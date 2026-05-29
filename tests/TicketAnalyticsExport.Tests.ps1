$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsModule = Import-Module (Join-Path $repoRoot "src\Core\Settings.psm1") -Force -PassThru -ErrorAction Stop
$ticketsModule = Import-Module (Join-Path $repoRoot "src\Core\Tickets.psm1") -Force -PassThru -ErrorAction Stop

Describe "Ticket analytics and export" {
    BeforeEach {
        $global:QOTAnalyticsSettingsPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-analytics-settings-" + [guid]::NewGuid().ToString("N") + ".json")
        $global:QOTAnalyticsStorePath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-analytics-store-" + [guid]::NewGuid().ToString("N") + ".json")
        $global:QOTAnalyticsBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-analytics-backup-" + [guid]::NewGuid().ToString("N"))
        $global:QOTAnalyticsExportPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-analytics-export-" + [guid]::NewGuid().ToString("N") + ".csv")
    }

    AfterEach {
        foreach ($path in @($global:QOTAnalyticsSettingsPath, $global:QOTAnalyticsStorePath, $global:QOTAnalyticsExportPath)) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
        if ($global:QOTAnalyticsBackupPath -and (Test-Path -LiteralPath $global:QOTAnalyticsBackupPath)) {
            Remove-Item -LiteralPath $global:QOTAnalyticsBackupPath -Recurse -Force -ErrorAction SilentlyContinue
        }

        Remove-Variable -Name QOTAnalyticsSettingsPath -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name QOTAnalyticsStorePath -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name QOTAnalyticsBackupPath -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name QOTAnalyticsExportPath -Scope Global -ErrorAction SilentlyContinue
    }

    It "keeps open, waiting, and closed counts as distinct buckets" {
        $now = Get-Date
        $todayOne = $now.Date.AddHours(1)
        $todayTwo = $now.Date.AddHours(2)
        $oldClosed = $now.Date.AddDays(-40).AddHours(9)

        InModuleScope $settingsModule.Name {
            $script:SettingsPath = $global:QOTAnalyticsSettingsPath
            $settings = New-QODefaultSettings -NoSave
            $settings.TicketStorePath = $global:QOTAnalyticsStorePath
            $settings.LocalTicketBackupPath = $global:QOTAnalyticsBackupPath
            Save-QOSettings -Settings $settings
        }

        @(
            [pscustomobject]@{
                Id = "t-open"
                Subject = "Open ticket"
                Status = "In Progress"
                AssignedTo = "Aaron"
                CreatedAt = $todayOne.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @([pscustomobject]@{ CreatedAt = $todayOne.AddMinutes(30).ToString("yyyy-MM-dd HH:mm:ss") })
                Notes = @()
                IsDeleted = $false
            }
            [pscustomobject]@{
                Id = "t-pending"
                Subject = "Waiting ticket"
                Status = "Pending"
                AssignedTo = "Jamie"
                CreatedAt = $todayTwo.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @()
                Notes = @()
                IsDeleted = $false
            }
            [pscustomobject]@{
                Id = "t-closed"
                Subject = "Closed ticket"
                Status = "Closed"
                AssignedTo = "Aaron"
                CreatedAt = $oldClosed.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $oldClosed.AddHours(4).ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @([pscustomobject]@{ CreatedAt = $oldClosed.AddHours(2).ToString("yyyy-MM-dd HH:mm:ss") })
                Notes = @()
                IsDeleted = $false
            }
            [pscustomobject]@{
                Id = "t-deleted"
                Subject = "Deleted ticket"
                Status = "Closed"
                AssignedTo = "Aaron"
                CreatedAt = $todayOne.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $todayOne.AddHours(1).ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @()
                Notes = @()
                IsDeleted = $true
                DeletedAt = $todayOne.AddHours(2).ToString("yyyy-MM-dd HH:mm:ss")
            }
        ) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $global:QOTAnalyticsStorePath -Encoding UTF8

        InModuleScope $ticketsModule.Name {
            $script:TicketStorePath = $null
            $script:TicketBackupPath = $null

            $snapshotAll = Get-QOTicketAnalyticsSnapshot -Range "All"
            $snapshotDay = Get-QOTicketAnalyticsSnapshot -Range "Day"

            $snapshotAll.TotalTickets | Should Be 3
            $snapshotAll.OpenTickets | Should Be 1
            $snapshotAll.PendingTickets | Should Be 1
            $snapshotAll.ClosedTickets | Should Be 1
            $snapshotAll.FirstReplySamples | Should Be 2

            $snapshotDay.TotalTickets | Should Be 2
            $snapshotDay.OpenTickets | Should Be 1
            $snapshotDay.PendingTickets | Should Be 1
            $snapshotDay.ClosedTickets | Should Be 0
        }
    }

    It "exports only the selected active range and preserves subject-backed title fields" {
        $now = Get-Date
        $todayOne = $now.Date.AddHours(1)
        $todayTwo = $now.Date.AddHours(2)
        $oldClosed = $now.Date.AddDays(-30).AddHours(9)

        InModuleScope $settingsModule.Name {
            $script:SettingsPath = $global:QOTAnalyticsSettingsPath
            $settings = New-QODefaultSettings -NoSave
            $settings.TicketStorePath = $global:QOTAnalyticsStorePath
            $settings.LocalTicketBackupPath = $global:QOTAnalyticsBackupPath
            Save-QOSettings -Settings $settings
        }

        @(
            [pscustomobject]@{
                Id = "t1"
                Subject = "Today open"
                Status = "In Progress"
                AssignedTo = "Aaron"
                CreatedAt = $todayOne.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @([pscustomobject]@{ CreatedAt = $todayOne.AddMinutes(60).ToString("yyyy-MM-dd HH:mm:ss") })
                Notes = @()
                IsDeleted = $false
            }
            [pscustomobject]@{
                Id = "t2"
                Subject = "Today waiting"
                Status = "Pending"
                AssignedTo = "Jamie"
                CreatedAt = $todayTwo.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $now.ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @()
                Notes = @()
                IsDeleted = $false
            }
            [pscustomobject]@{
                Id = "t3"
                Subject = "Old closed"
                Status = "Closed"
                AssignedTo = "Aaron"
                CreatedAt = $oldClosed.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $oldClosed.AddHours(6).ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @()
                Notes = @()
                IsDeleted = $false
            }
            [pscustomobject]@{
                Id = "t4"
                Subject = "Deleted today"
                Status = "Closed"
                AssignedTo = "Aaron"
                CreatedAt = $todayOne.ToString("yyyy-MM-dd HH:mm:ss")
                UpdatedAt = $todayOne.AddHours(1).ToString("yyyy-MM-dd HH:mm:ss")
                Replies = @()
                Notes = @()
                IsDeleted = $true
                DeletedAt = $todayOne.AddHours(2).ToString("yyyy-MM-dd HH:mm:ss")
            }
        ) | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $global:QOTAnalyticsStorePath -Encoding UTF8

        InModuleScope $ticketsModule.Name {
            $script:TicketStorePath = $null
            $script:TicketBackupPath = $null

            $result = Export-QOTicketsToExcelSpreadsheet -Path $global:QOTAnalyticsExportPath -Range "Day"
            $result.Success | Should Be $true
            $result.Count | Should Be 2
        }

        $rows = @(Import-Csv -LiteralPath $global:QOTAnalyticsExportPath)
        $rows.Count | Should Be 2
        (@($rows | Where-Object { $_.Id -eq "t4" })).Count | Should Be 0

        $first = @($rows | Where-Object { $_.Id -eq "t1" } | Select-Object -First 1)
        $first.Subject | Should Be "Today open"
        $first.Title | Should Be "Today open"
        $first.TicketName | Should Be "Today open"
    }
}
