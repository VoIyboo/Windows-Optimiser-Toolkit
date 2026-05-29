$repoRoot = Split-Path -Parent $PSScriptRoot
$ticketsModule = Import-Module (Join-Path $repoRoot "src\Core\Tickets.psm1") -Force -PassThru -ErrorAction Stop

Describe "Tickets body storage compaction" {
    BeforeEach {
        $global:QOTStorageTestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-ticket-storage-" + [guid]::NewGuid().ToString("N"))
        $global:QOTStorageStorePath = Join-Path $global:QOTStorageTestRoot "Tickets.json"
        $global:QOTStorageBackupPath = Join-Path $global:QOTStorageTestRoot "Backups"
        New-Item -ItemType Directory -Path $global:QOTStorageBackupPath -Force | Out-Null
        "[]" | Set-Content -LiteralPath $global:QOTStorageStorePath -Encoding UTF8
    }

    AfterEach {
        if (Test-Path -LiteralPath $global:QOTStorageTestRoot) {
            Remove-Item -LiteralPath $global:QOTStorageTestRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name QOTStorageTestRoot -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name QOTStorageStorePath -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name QOTStorageBackupPath -Scope Global -ErrorAction SilentlyContinue
    }

    It "offloads nested thread bodies during normal save optimization" {
        InModuleScope $ticketsModule.Name {
            $script:TicketStorePath = $global:QOTStorageStorePath
            $script:TicketBackupPath = $global:QOTStorageBackupPath

            $db = [pscustomobject]@{
                SchemaVersion = 1
                Tickets = @(
                    [pscustomobject]@{
                        Id = "ticket-body-storage"
                        EmailBody = ("P" * 3000)
                        IncomingMessages = @([pscustomobject]@{ Subject = "incoming"; Body = ("I" * 3000); CreatedAt = "2026-05-07 08:00:00" })
                        Replies = @([pscustomobject]@{ Subject = "reply"; Body = ("R" * 3000); CreatedAt = "2026-05-07 08:01:00" })
                        Notes = @([pscustomobject]@{ Body = ("N" * 3000); CreatedAt = "2026-05-07 08:02:00"; Author = "Tester" })
                    }
                )
            }

            Optimize-QOTicketBodyStorage -Database $db

            $ticket = $db.Tickets[0]
            $ticket.EmailBody | Should Be ""
            (Test-Path -LiteralPath $ticket.EmailBodyPath) | Should Be $true
            ([int]$ticket.EmailBodyPreview.Length -lt 605) | Should Be $true

            $incoming = $ticket.IncomingMessages[0]
            $incoming.Body | Should Be ""
            (Test-Path -LiteralPath $incoming.BodyPath) | Should Be $true
            ([int]$incoming.BodyPreview.Length -lt 605) | Should Be $true

            $reply = $ticket.Replies[0]
            $reply.Body | Should Be ""
            (Test-Path -LiteralPath $reply.BodyPath) | Should Be $true
            ([int]$reply.BodyPreview.Length -lt 605) | Should Be $true

            $note = $ticket.Notes[0]
            $note.Body | Should Be ""
            (Test-Path -LiteralPath $note.BodyPath) | Should Be $true
            ([int]$note.BodyPreview.Length -lt 605) | Should Be $true
        }
    }

    It "stream-compacts legacy oversized inline body lines before JSON parsing" {
        InModuleScope $ticketsModule.Name {
            $script:TicketStorePath = $global:QOTStorageStorePath
            $script:TicketBackupPath = $global:QOTStorageBackupPath

            $largeBody = "A" * 1600
            @"
[
  {
    "Id": "legacy-large-body",
    "IncomingMessages": [
      {
        "Subject": "reply",
        "Body": "$largeBody",
        "CreatedAt": "2026-05-07 08:00:00"
      }
    ],
    "Replies": [],
    "Notes": []
  }
]
"@ | Set-Content -LiteralPath $global:QOTStorageStorePath -Encoding UTF8

            $changed = Compress-QOTicketStoreLargeBodyLines -Path $global:QOTStorageStorePath -BackupDirectory $global:QOTStorageBackupPath -LineLengthThresholdChars 1000 -BodyFileMaxChars 120 -Quiet

            $changed | Should Be $true
            $db = Read-QOTicketStoreJsonText -Path $global:QOTStorageStorePath | ConvertFrom-Json
            $message = $db[0].IncomingMessages[0]
            $message.Body | Should Be ""
            ([string]::IsNullOrWhiteSpace([string]$message.BodyPath)) | Should Be $false
            $message.BodyPreview | Should Match "AAAAAAAAAA"
            (Test-Path -LiteralPath $message.BodyPath) | Should Be $true
            ([System.IO.File]::ReadAllText([string]$message.BodyPath)) | Should Match "Body compacted"
            (Get-ChildItem -LiteralPath $global:QOTStorageBackupPath -Filter "Tickets.json.compact-backup-*" | Measure-Object).Count | Should Be 1
        }
    }
}
