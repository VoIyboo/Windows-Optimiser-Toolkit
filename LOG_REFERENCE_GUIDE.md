# Reply Send Pipeline - Log Reference Guide

## Quick Diagnosis Using Logs

### Finding Logs
Location: `C:\ProgramData\QuinnOptimiserToolkit\Logs\`

Files:
- `ReplyRunner.log` - Individual send attempts (spawn a new process for each)
- `ReplyQueueRunner.log` - Queue processing and retries
- Other logs in this directory

### Searching for a Specific Reply

Use the **DraftId** as your search key. Every log message includes it.

Example: User says "I sent a reply to ticket 12345 at 2:30 PM"

```powershell
# Search for DraftId in logs
Select-String -Path "C:\ProgramData\QuinnOptimiserToolkit\Logs\*" -Pattern "TicketId='12345'"
```

---

## Log Levels Explained

- **[INFO]** - Normal operation, successful action
- **[WARN]** - Recoverable issue, will retry
- **[ERROR]** - Unrecoverable failure or critical issue requiring investigation

---

## Successful Send (Happy Path)

```
[INFO] Tickets: Pending reply queued. TicketId='T-001' DraftId='abc123' Subject='Re: Your Issue'
→ [INFO] Tickets: Pending reply persisted to disk. TicketId='T-001' DraftId='abc123'
→ [INFO] Setting reply state to Sending. TicketId='T-001' DraftId='abc123' RetryCount=0
→ [INFO] Tickets: Starting reply send. TicketId='T-001' Subject='Re: Your Issue'
→ [INFO] Tickets: Sending Outlook reply. TicketId='T-001' FromMailbox='user@company.com'
→ [INFO] Tickets: Reply sent successfully. TicketId='T-001' ResultNote='Reply sent.'
→ [INFO] Tickets: Reloading ticket to clean up pending replies. TicketId='T-001' DraftId='abc123'
→ [INFO] Tickets: Pending replies after filtering. TicketId='T-001' AfterCount=0
→ [INFO] Verified: Pending reply successfully removed from storage. TicketId='T-001' DraftId='abc123'
→ [INFO] Queued reply sent successfully and removed from queue. DraftId='abc123' TicketId='T-001'
```

**Total time**: Usually <5 seconds
**Outcome**: Reply sent, pending removed, UI updated

---

## Troubleshooting by Symptom

### "Reply seems stuck in queue"
Look for: `Picking up stale Sending state reply. DraftId='xyz' StaleSince=65s`
→ Normal recovery. Reply will be retried in 1 minute intervals.

### "Reply sent twice"
Look for: Two `Reply sent successfully` entries for same DraftId
→ Check if Outlook issue triggered retry, or user clicked Send twice

### "Reply never sent"
Look for: `marked failed. DraftId='xyz' Note='...'`
→ Read the Note field for reason. Max retries (5) exceeded.

### "Too many retries"
Look for: `NextAttemptIn=300s` (max backoff reached)
→ Persistent issue. Check Outlook health or ticket data.

---

## Key Log Patterns

| Pattern | Meaning | Action |
|---------|---------|--------|
| `successfully removed from storage` | Cleanup succeeded, no duplicate risk | None - working normally |
| `CRITICAL: Pending reply still exists` | Cleanup failed, duplicate risk possible | Report to support |
| `marked failed` | Permanent failure, no more retries | User must fix ticket data or support investigates |
| `Picking up stale Sending state` | Reply recovered from crash | Normal, will retry |
| `scheduling retry in 15s...60s...300s` | Exponential backoff retrying | Transient issue, will recover |
| `Classic Outlook is not running` | Outlook crashed during send | Start Outlook, retry auto-triggers |

---

## Log File Locations & Size

```
C:\ProgramData\QuinnOptimiserToolkit\Logs\
  ├── ReplyRunner.log (grows ~100KB per 100 replies)
  ├── ReplyQueueRunner.log (grows ~50KB per hour of activity)
  └── Other logs
```

Recommend log rotation if >100MB combined size or >1 week old.

---

## PowerShell Log Queries

```powershell
# Find all CRITICAL issues
Get-Content 'C:\ProgramData\QuinnOptimiserToolkit\Logs\*.log' | 
  Select-String 'CRITICAL'

# Find a specific ticket
Get-Content 'C:\ProgramData\QuinnOptimiserToolkit\Logs\*.log' | 
  Select-String "TicketId='T-001'"

# Show recent 50 lines
Get-Content 'C:\ProgramData\QuinnOptimiserToolkit\Logs\ReplyQueueRunner.log' -Tail 50

# Count errors by type
Get-Content 'C:\ProgramData\QuinnOptimiserToolkit\Logs\*.log' | 
  Select-String '\[ERROR\]' | 
  Group-Object -AsHashTable -AsString | 
  Sort-Object Count -Descending
```

---

## Quick Reference: Common Failure Messages

| Message | Recoverable? | Cause | Fix |
|---------|--------------|-------|-----|
| Classic Outlook is not running | YES | Outlook crashed | Start Outlook |
| Ticket has no customer email | NO | Missing email field | Add email to ticket |
| Timed out | YES | Network/COM lag | Auto-retries |
| Does not fall within range | YES | Rich text issue | Retry with plain text |
| Value does not fall within range | YES | Outlook COM issue | Auto-retries |
| Ticket not found | NO | Data deleted | Recreate ticket |

---

## When to Report to Support

1. **Seeing CRITICAL logs** → Immediate report
2. **Persistent permanent failures (NOT recoverable)** → Include logs and TicketId
3. **Reply sent twice** → Include logs and affected TicketId
4. **Stale replies stuck >10 minutes** → Include logs (should auto-recover in 1min)
5. **High retry rate (>20% of replies failing)** → Indicates systemic issue

Provide:
- TicketId or DraftId
- Timestamp of issue
- Relevant log section (full entry)
- What user saw in UI vs. what logs show
