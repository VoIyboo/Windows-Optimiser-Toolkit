# PowerShell Ticketing System - Reply Send Reliability Diagnostic

## Executive Summary

The reply send pipeline has multiple failure points where replies can silently fail, get stuck in queue, or desynchronize from UI. The root causes are:

1. **Insufficient Logging** — No structured trace of individual send attempts, state changes, or persistence operations
2. **Race Conditions** — State updates are not atomic; refreshes can overwrite queue data
3. **Incomplete Cleanup** — Successful sends don't always remove pending entries before the app can refresh
4. **Stale State Recovery** — Replies stuck in "Sending" state indefinitely due to app crashes
5. **Loose JSON Serialization** — Data can be lost in round-trips through temp files and cache

---

## Pipeline Architecture

```
User clicks "Send"
  ↓
UI queues reply (Add-QOTTicketPendingReply)
  → DraftId generated
  → State = "Queued"
  → Saved to disk
  ↓
UI starts background queue runner
  (Tickets.Email.ReplyQueueRunner.ps1)
  ↓
Queue runner gets next pending reply
  (Get-QOTNextPendingReply)
  ↓
Set state = "Sending"
  ↓
Load fresh ticket from storage
  ↓
Call Send-QOTicketReply
  → Calls Send-QOTicketOutlookReply (for replies)
  → OR Send-QOTicketOutlookEmail (for new emails)
  ↓
If success:
  → Add reply to ticket.Replies[]
  → Update FirstResponseAt, EmailConversationId, etc.
  → Save ticket to disk
  → Remove pending reply from PendingReplies[]
  → Save ticket to disk AGAIN
  ↓
If failure:
  → Determine if recoverable
  → Increment retry count
  → Calculate next attempt time (exponential backoff)
  → Set state back to "Queued"
  → Save to disk
```

---

## Critical Issues Identified

### 1. LOGGING GAPS (Most Critical)

**Problem**: Without end-to-end logging, we cannot determine WHERE a reply is failing.

**Affected Functions**:
- `Tickets.Email.ReplyRunner.ps1` — Only logs start/end, not intermediate failures
- `Tickets.Email.ReplyQueueRunner.ps1` — Logs queue events but missing COM details
- `Send-QOTicketReply` (Core module) — No logging of state transitions
- `Add-QOTTicketPendingReply` — No logging of queue additions
- `Set-QOTTicketPendingReplyState` — No logging of state changes
- `Remove-QOTTicketPendingReply` — Basic logging, but no tracing

**Impact**: If a reply fails, we have no trace of:
- Whether Outlook COM was unavailable
- Whether the send succeeded but persistence failed
- Whether the ticket couldn't be found
- Whether state was corrupted

**Fix Approach**:
1. Add structured logging to all state mutations
2. Log every Outlook COM call with method name and parameters
3. Log every persistence operation (Save, Remove)
4. Use correlation IDs (DraftId) to trace a single reply through the entire pipeline
5. Log failures with error codes and full exception text

---

### 2. RACE CONDITIONS - State Desynchronization

**Problem**: UI refreshes and queue processing operate on the same data without proper synchronization.

**Scenario A: Lost Pending Reply During Refresh**
```
1. UI sends reply → queues it with state "Queued"
2. Background refresh starts → loads ticket from disk
3. Queue runner picks up reply → sets state "Sending", saves
4. Refresh completes → reloads ticket, overwrites in-memory data
5. Refresh saves ticket to disk, clearing pending replies
   → Reply is now lost (state overwritten)
```

**Scenario B: Stale Queued Data After Send**
```
1. Queue runner sends reply successfully
2. Queue runner removes pending reply from storage
3. Meanwhile, refresh finishes → reloads ticket
4. Refresh had stale PendingReplies[] (loaded BEFORE removal)
5. Refresh saves, re-adds the removed pending reply
   → Zombie reply stays in queue
```

**Root Cause**: No locking around PendingReplies[] mutations.

**Fix Approach**:
1. Use mutex around all PendingReplies modifications (already partially done)
2. Verify refresh logic doesn't overwrite pending replies
3. Add validation: if removing a reply, verify it's actually gone after save
4. Add per-ticket versioning to detect stale loads

---

### 3. INCOMPLETE CLEANUP AFTER SUCCESS

**Problem**: Successful send doesn't fully clean up pending state before next save.

**Code Flow** (Send-QOTicketReply, line ~4084):
```powershell
if ($success) {
    # Add reply to Replies[]
    $ticketToUpdate.Replies = @($existingReplies) + @($replyEntry)
    
    # Then LATER (~line 4084):
    # Get fresh ticket from storage
    $latestPendingReplies = @($latestTicket.PendingReplies)
    
    # Remove this pending reply
    if (-not [string]::IsNullOrWhiteSpace([string]$PendingReplyDraftId)) {
        # ... filter out the draft ...
    }
    
    # Update the ticket with filtered pending replies
    $ticketToUpdate.PendingReplies = @($latestPendingReplies)
    
    # Save ticket
    $null = Update-QOTicket -Ticket $ticketToUpdate
}
```

**The Problem**:
- Between receiving success and removing the pending reply, there's a delay
- If the app crashes, the reply is marked sent but still in PendingReplies
- Next restart: queue runner sees stale pending reply, tries to send again
- Outlook might create a duplicate

**What Should Happen**:
1. Wait for Outlook to confirm send (ConversationId, EntryId received)
2. Remove pending reply from PendingReplies[] BEFORE updating the ticket
3. Save the cleaned ticket atomically
4. THEN update the Replies[] (or do both in same save)

---

### 4. STALE "SENDING" STATE NEVER RECOVERS

**Problem**: If app crashes while sending, reply stays in "Sending" state forever.

**Code** (ReplyQueueRunner.ps1, line ~3272):
```powershell
if ($stateValue -eq "Sending") {
    if ($lastAttemptUtc -eq [datetime]::MinValue) {
        $eligible = $true
    } else {
        $elapsedSeconds = ($nowUtc - $lastAttemptUtc).TotalSeconds
        if ($elapsedSeconds -ge $StaleSendingSeconds) {  # 600 seconds = 10 minutes
            $eligible = $true
        }
    }
}
```

**The Issue**:
- If LastAttemptAt is never set, the reply is NEVER picked up again
- If set but old, it only retries after 10 minutes
- If app crashes right after setting state to "Sending" (before LastAttemptAt), it's stuck

**Fix Approach**:
1. Always set LastAttemptAt BEFORE trying to send
2. Reduce StaleSendingSeconds to ~60 seconds (1 minute) instead of 600
3. Add a "MaxAge" for "Sending" state — if in this state for > 30 minutes, mark Failed
4. Log when transitioning from Sending to Queued

---

### 5. LOOSE JSON SERIALIZATION

**Problem**: Data can be corrupted when round-tripping through JSON and temp files.

**Points of Loss**:
- ReplyRunner.ps1 loads JSON from temp file (line 81):
  ```powershell
  $payload = $payloadRaw | ConvertFrom-Json
  ```
  If JSON is malformed or incomplete, the entire send fails silently.

- Subject and Body might have escape sequences that don't round-trip
- Carriage returns or special chars might be lost
- No validation that Subject/Body are actually present in the deserialized object

**Fix Approach**:
1. Validate JSON schema before deserializing
2. Escape subject/body properly
3. Use -Encoding UTF8 consistently
4. Log the actual content of payloads (redacted if sensitive)

---

## Summary of Root Causes

| Issue | Impact | Severity | Root Cause |
|-------|--------|----------|-----------|
| No end-to-end logging | Cannot diagnose failures | CRITICAL | Missing logging instrumentation |
| Race conditions on state | Replies lost or duplicated | CRITICAL | No atomic updates or versioning |
| Incomplete cleanup after send | Duplicate sends possible | HIGH | Cleanup not atomic with send |
| Stale "Sending" state | Stuck replies | HIGH | Poor recovery from crashes |
| Loose JSON serialization | Data corruption | MEDIUM | No validation or escaping |

---

## Recommended Fixes (In Order)

1. **Add Comprehensive Logging** ← START HERE
   - Every state change
   - Every Outlook COM call
   - Every persistence operation
   - Every error with full exception text

2. **Fix State Cleanup Order**
   - Remove pending reply BEFORE updating Replies[]
   - Make removal idempotent
   - Validate removal succeeded before proceeding

3. **Improve Crash Recovery**
   - Reduce StaleSendingSeconds
   - Add MaxAge for Sending state
   - Always set LastAttemptAt before send

4. **Add Defensive Validation**
   - Validate JSON before deserializing
   - Verify ticket exists before sending
   - Verify DraftId extraction worked

5. **Test Everything**
   - Unit tests for state transitions
   - Integration tests for full pipeline
   - Crash recovery scenarios
