# Reply Send Pipeline - Comprehensive Reliability Fixes

## Summary of Changes

This document outlines all reliability improvements made to the reply send pipeline to fix silent failures, state desynchronization, and stale queue entries.

---

## 1. COMPREHENSIVE LOGGING (CRITICAL FIX)

### Objective
Enable end-to-end tracing of every reply through the pipeline to diagnose failures.

### Changes Made

#### A. Core Module (`src/Core/Tickets.psm1`)

**Add-QOTTicketPendingReply (line ~3110)**
- Log when reply is queued: subject, draft ID, ticket ID
- Log when persistence succeeds
- Log errors with full context

**Set-QOTTicketPendingReplyState (line ~3187)**
- Log state transitions (e.g., Queued → Sending → Failed)
- Include retry count, failure note
- Log persistence confirmations

**Remove-QOTTicketPendingReply (line ~3240)**
- Log when removal is attempted
- Log success/failure
- Report remaining reply count

**Send-QOTicketReply (line ~3943-4160)**
- Log send initiation with subject, reply vs. email mode
- Log Outlook COM method calls (Reply vs. Email)
- Log recipient email and sender mailbox
- Log successful sends with conversation/entry IDs
- Log pending reply reload for cleanup
- Log filtering and removal of pending replies
- **CRITICAL**: Log verification that pending reply was actually removed from storage
- Log all failures with full exception messages

#### B. Queue Runner (`src/Tickets/Tickets.Email.ReplyQueueRunner.ps1`)

- Log when queue is empty
- Log state transition to "Sending"
- Log ticket reload
- Log payload extraction
- Log send attempt with retry count
- Log send result (success/failure and note)
- Log removal of successful replies
- Log retry scheduling with delay and reason
- Log permanent failure marking

#### C. Reply Runner (`src/Tickets/Tickets.Email.ReplyRunner.ps1`)

- Log payload file location
- Log payload size
- Log JSON deserialization (success and errors)
- Log extracted field values and lengths
- Log ticket lookup results
- Log Send-QOTicketReply invocation
- Log exceptions from send command
- Log result interpretation

### Expected Logs
Every reply will now produce a log trace like:
```
[2026-05-14 14:23:45] [INFO] Tickets: Pending reply queued. TicketId='T123' DraftId='abc' Subject='Re: Your Request'
[2026-05-14 14:23:45] [INFO] Tickets: Pending reply persisted to disk. TicketId='T123' DraftId='abc'
[2026-05-14 14:23:46] [INFO] Tickets: Starting reply send. TicketId='T123' Subject='Re: Your Request' HasReplyReference=True PreferOutbound=False
[2026-05-14 14:23:46] [INFO] Tickets: Sending Outlook reply. TicketId='T123' FromMailbox='user@company.com'
[2026-05-14 14:23:47] [INFO] Tickets: Reply sent successfully. TicketId='T123' ResultNote='Reply sent.'
[2026-05-14 14:23:47] [INFO] Tickets: Reloading ticket to clean up pending replies. TicketId='T123' DraftId='abc'
[2026-05-14 14:23:47] [INFO] Tickets: Loaded 1 pending replies from fresh ticket. TicketId='T123'
[2026-05-14 14:23:47] [INFO] Tickets: Filtering out DraftId from pending replies. TicketId='T123' DraftId='abc' BeforeCount=1
[2026-05-14 14:23:47] [INFO] Tickets: Pending replies after filtering. TicketId='T123' DraftId='abc' AfterCount=0
[2026-05-14 14:23:47] [INFO] Tickets: Saving updated ticket to storage. TicketId='T123' PendingReplyCount=0
[2026-05-14 14:23:47] [INFO] Tickets: Verified: Pending reply successfully removed from storage. TicketId='T123' DraftId='abc'
```

---

## 2. STALE STATE RECOVERY IMPROVEMENTS

### Objective
Prevent replies from getting stuck in "Sending" state when the app crashes.

### Changes Made

**Get-QOTNextPendingReply** (`src/Core/Tickets.psm1`, line ~3265)

1. **Reduced StaleSendingSeconds from 600 to 60 seconds**
   - Previous: 10 minutes waiting for detection
   - New: 1 minute for faster recovery
   - Reason: 10 minutes is too long for user frustration

2. **Added MaxAge threshold (7200 seconds = 2 hours)**
   - Prevents ancient replies from staying in queue indefinitely
   - Logs when skipping old replies

3. **Added recovery logging**
   - Log when picking up reply stuck in "Sending" with no LastAttemptAt
   - Log how long reply has been stale

4. **LastAttemptAt is always set when transitioning to "Sending"**
   - Ensures no "Sending" state replies can have MinValue timestamp
   - Even if app crashes, the timestamp shows when it failed

### Impact
- Stuck "Sending" replies recovered within 1 minute
- No ancient replies lingering in queue
- Clear diagnostic logs for each recovery

---

## 3. STATE PERSISTENCE VALIDATION

### Objective
Ensure state changes actually persist before proceeding.

### Changes Made

**ReplyQueueRunner** (`src/Tickets/Tickets.Email.ReplyQueueRunner.ps1`)

When transitioning to "Sending" state:
1. Call Set-QOTTicketPendingReplyState
2. Validate the returned state update result is not null
3. Only proceed with send if state update succeeded
4. Skip to next reply if state update failed

**Send-QOTicketReply** (`src/Core/Tickets.psm1`)

After successful send and pending reply removal:
1. Reload ticket from fresh storage
2. Verify pending reply is actually gone
3. Log verification result (success or CRITICAL error if still present)
4. Alerts to logs if cleanup didn't work (potential data corruption)

### Impact
- Prevents sending same reply twice if state update failed
- Detects and logs data corruption issues
- Automatic recovery mechanism built in

---

## 4. IMPROVED FAILURE DETECTION

### Objective
Catch failures that were previously silent.

### Changes Made

**ReplyRunner.ps1** (`src/Tickets/Tickets.Email.ReplyRunner.ps1`)

1. **JSON Deserialization Validation**
   - Log JSON parsing errors with full exception
   - Validate each required field is present
   - Log field lengths (detect truncation)

2. **Send Command Validation**
   - Log if Send-QOTicketReply throws exception
   - Log if command returns null
   - Log if Success property is missing

3. **Payload Content Validation**
   - Log payload size
   - Detect empty or missing critical fields

### Impact
- JSON parsing errors no longer silent
- Malformed payloads detected and logged
- Command crashes captured and reported

---

## 5. FAILURE CLASSIFICATION IMPROVEMENT

### Objective
Better distinguish recoverable vs. permanent failures.

### Changes Made

**ReplyQueueRunner** - Enhanced `Test-QOTReplyQueueFailureRecoverable`

The function already had good detection of recoverable errors:
- "Classic Outlook is not running"
- "Timed out"
- "Busy"
- etc.

Added logging to show:
- Whether error is classified as recoverable
- Retry count before marking as permanent
- Delay before next retry attempt

### Impact
- Transient Outlook issues auto-retry
- Permanent failures marked quickly
- No silent retries on permanent errors

---

## 6. RACE CONDITION MITIGATION

### Objective
Reduce (not eliminate) race conditions between refresh and queue processing.

### Notes
- Full elimination requires locking improvements (out of scope)
- These changes reduce the impact window

**Set-QOTTicketPendingReplyState**
- Already saves immediately after state change
- Uses Save-QOTickets with persistence

**Remove-QOTTicketPendingReply**
- Filters pending replies array
- Saves immediately
- Now validated by verification check

**Send-QOTicketReply**
- Reloads fresh ticket before cleanup
- Removes pending reply from fresh data
- Verifies removal succeeded
- Saves with filtered array

### Still Possible (But Logged)
- Refresh could overwrite a send in progress (both log and notify)
- Very narrow window after success but before removal completion

---

## Testing Recommendations

### 1. Successful Send
```
Expected Log Pattern:
- Pending reply queued
- Pending reply persisted
- Starting reply send
- Sending Outlook reply (or email)
- Reply sent successfully
- Reloading ticket to clean up
- Filtering out draft ID
- Pending replies after filtering (count should be 0)
- Saving updated ticket
- Verified: Pending reply successfully removed
```

### 2. Outlook Unavailable (Recoverable)
```
Expected Behavior:
- Set state to "Sending"
- Attempt send → fails with "Classic Outlook is not running"
- Classified as recoverable
- Schedule retry in exponential backoff (15s, 30s, 60s...)
- Retry on next queue runner cycle
```

### 3. Invalid Email (Permanent)
```
Expected Behavior:
- Set state to "Sending"
- Attempt send → fails with "Ticket has no customer email"
- Classified as non-recoverable
- Mark state as "Failed"
- Log permanent failure
- Do not retry
```

### 4. Stale Sending State Recovery
```
Expected Behavior:
- Reply stuck in "Sending" for > 60 seconds
- Queue runner picks it up
- Log: "Picking up stale Sending state reply"
- Retry send
```

### 5. Ancient Pending Reply (> 2 hours)
```
Expected Behavior:
- Reply in queue for > 2 hours
- Queue runner skips it
- Log: "Skipping reply that exceeded max age"
```

---

## Operational Impact

### Log File Growth
- Adds ~10-15 log lines per successful reply
- Adds ~5-20 lines per failed/retried reply
- Recommend log rotation for >100 daily replies

### Performance
- Minimal impact (logging is async via Write-QOTicketsCoreLog)
- Extra ticket reload for verification is negligible
- No network calls added

### Debugging Ease
- **Before**: "Reply didn't send" with no diagnostic info
- **After**: Full trace showing exactly where and why it failed

---

## Known Limitations

### Still Not Fixed (Requires Larger Refactor)
1. **True atomicity between add-reply and remove-pending**
   - Window still exists (now logged and validated)
   - Full fix requires DB transactions

2. **Outlook COM reliability**
   - Outlook API itself can fail unpredictably
   - Improved retry logic and logging, but not foolproof

3. **Duplicate prevention if crash between success and removal**
   - Now validated and logged
   - Could re-send if verification fails

4. **UI state during background operations**
   - Refresh can still desync UI
   - Separate issue from send reliability

---

## Verification Checklist

- [ ] Logs directory exists: `ProgramData\QuinnOptimiserToolkit\Logs\`
- [ ] ReplyRunner.log file grows with reply attempts
- [ ] ReplyQueueRunner.log shows queue processing
- [ ] Tickets.log (core module) shows detailed state transitions
- [ ] Each successful reply has verification log line
- [ ] Failed replies show full exception messages
- [ ] Retries show exponential backoff delay calculation
- [ ] Stale replies (> 60s in Sending) are picked up and retried
- [ ] Pending replies removed from UI after send completes

---

## Summary of Reliability Improvements

| Issue | Before | After | Severity |
|-------|--------|-------|----------|
| Silent failures | No logs | Full trace | CRITICAL |
| Stuck Sending state | 10 min recovery | 1 min recovery | HIGH |
| Stale queue entries | Never cleaned | 2 hour max age | MEDIUM |
| Unvalidated persistence | No check | Validated | HIGH |
| Undetected cleanup failures | Silent | CRITICAL log | HIGH |
| Recoverable errors | Unclear | Clear classification | MEDIUM |
| Crash between send/cleanup | No detection | Verified and logged | HIGH |

---

## Next Steps (If Needed)

1. **Monitor logs** for 1-2 weeks to identify any new patterns
2. **Reduce max age** if ancient replies are still problematic
3. **Add metrics** to track send success rates
4. **Implement locking** if race conditions cause issues (requires larger refactor)
5. **Add user notification** for persistent failures after 3+ retries
