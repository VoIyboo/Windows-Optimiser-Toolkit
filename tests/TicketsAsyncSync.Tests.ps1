$repoRoot = Split-Path -Parent $PSScriptRoot
$ticketsUiModule = Import-Module (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Force -PassThru -ErrorAction Stop

Describe "Tickets async sync helpers" {
    BeforeEach {
        $global:QOTSyncResultPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-sync-" + [guid]::NewGuid().ToString("N") + ".result.json")
        $global:QOTSyncStdOutPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-sync-" + [guid]::NewGuid().ToString("N") + ".json")
        $global:QOTSyncStdErrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-sync-" + [guid]::NewGuid().ToString("N") + ".err")
    }

    AfterEach {
        foreach ($path in @($global:QOTSyncResultPath, $global:QOTSyncStdOutPath, $global:QOTSyncStdErrPath)) {
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
            }
        }
        Remove-Variable -Name QOTSyncResultPath -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name QOTSyncStdOutPath -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name QOTSyncStdErrPath -Scope Global -ErrorAction SilentlyContinue
    }

    It "parses child-process runner output into a normalized result object" {
        '{"Success":true,"Added":2,"Updated":1,"Note":"ok","AddedTickets":[{"Id":"abc"}]}' | Set-Content -LiteralPath $global:QOTSyncStdOutPath -Encoding UTF8
        "" | Set-Content -LiteralPath $global:QOTSyncStdErrPath -Encoding UTF8

        InModuleScope $ticketsUiModule.Name {
            $result = Read-QOTicketsSyncRunnerResult -ResultPath $global:QOTSyncResultPath -StdOutPath $global:QOTSyncStdOutPath -StdErrPath $global:QOTSyncStdErrPath
            $result.Success | Should Be $true
            $result.Added | Should Be 2
            $result.Updated | Should Be 1
            @($result.AddedTickets).Count | Should Be 1
        }
    }

    It "parses runner JSON even when stdout has a Windows PowerShell banner prefix" {
        @'
Windows PowerShell
Copyright (C) Microsoft Corporation. All rights reserved.

{"Success":true,"Added":1,"Updated":0,"Note":"ok","AddedTickets":[]}
'@ | Set-Content -LiteralPath $global:QOTSyncStdOutPath -Encoding UTF8
        "" | Set-Content -LiteralPath $global:QOTSyncStdErrPath -Encoding UTF8

        InModuleScope $ticketsUiModule.Name {
            $result = Read-QOTicketsSyncRunnerResult -ResultPath $global:QOTSyncResultPath -StdOutPath $global:QOTSyncStdOutPath -StdErrPath $global:QOTSyncStdErrPath
            $result.Success | Should Be $true
            $result.Added | Should Be 1
            $result.Updated | Should Be 0
        }
    }

    It "builds a Start-Process argument string that can launch a script from a spaced path" {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qot spaced path " + [guid]::NewGuid().ToString("N"))
        $scriptPath = Join-Path $tempRoot "runner script.ps1"
        $resultPath = Join-Path $tempRoot "result.json"

        try {
            $null = New-Item -ItemType Directory -Path $tempRoot -Force
            @'
param([string]$ResultPath)
[pscustomobject]@{ Ok = $true } | ConvertTo-Json -Compress | Set-Content -LiteralPath $ResultPath -Encoding UTF8
'@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8

            & $ticketsUiModule {
                param($scriptPath, $resultPath)
                $exePath = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
                $argumentString = ConvertTo-QOTProcessArgumentString -Arguments @(
                    "-NoLogo",
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", $scriptPath,
                    "-ResultPath", $resultPath
                )

                $proc = Start-Process -FilePath $exePath -ArgumentList $argumentString -PassThru -WindowStyle Hidden
                $completed = $proc.WaitForExit(10000)

                $completed | Should Be $true
                $proc.ExitCode | Should Be 0
                (Test-Path -LiteralPath $resultPath) | Should Be $true
            } $scriptPath $resultPath
        }
        finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It "uses a limited scheduled task for elevated Outlook runner bridges" {
        $moduleSource = Get-Content (Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1") -Raw

        $moduleSource | Should Match 'function Start-QOTLimitedScheduledProcess'
        $moduleSource | Should Match '\$taskDefinition\.Principal\.LogonType = 3'
        $moduleSource | Should Match '\$taskDefinition\.Principal\.RunLevel = 0'
        $moduleSource | Should Match 'Elevated sync run #\{0\} launched as limited scheduled task for Outlook COM access\.'
        $moduleSource | Should Not Match 'Elevated sync run #\{0\} launched through unelevated shell'
    }

    It "detects completion for both child-process and runspace sync operations" {
        InModuleScope $ticketsUiModule.Name {
            (Test-QOTicketsSyncOperationCompleted -Mode "child-process" -Process ([pscustomobject]@{ HasExited = $true })) | Should Be $true
            (Test-QOTicketsSyncOperationCompleted -Mode "child-process" -Process ([pscustomobject]@{ HasExited = $false })) | Should Be $false
            (Test-QOTicketsSyncOperationCompleted -Mode "runspace" -AsyncResult ([pscustomobject]@{ IsCompleted = $true })) | Should Be $true
            (Test-QOTicketsSyncOperationCompleted -Mode "runspace" -AsyncResult ([pscustomobject]@{ IsCompleted = $false })) | Should Be $false
            (Test-QOTicketsSyncOperationCompleted -Mode "result-file" -ResultPath $global:QOTSyncResultPath) | Should Be $false
            '{"Success":true,"Added":0,"Updated":0,"Note":"ok","AddedTickets":[]}' | Set-Content -LiteralPath $global:QOTSyncResultPath -Encoding UTF8
            (Test-QOTicketsSyncOperationCompleted -Mode "result-file" -ResultPath $global:QOTSyncResultPath) | Should Be $true
        }
    }

    It "does not start a background sync before the next scheduled attempt" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $grid = [System.Windows.Controls.DataGrid]::new()
            $script:TicketsEmailSyncInProgress = $false
            $script:TicketsSyncNextAttemptUtc = (Get-Date).ToUniversalTime().AddMinutes(5)
            $script:TicketsSyncRunCounter = 42

            Start-TicketsEmailSyncAsync -Grid $grid -GetTicketsCmd "Get-QOTickets" -SyncCmd ([scriptblock]{ throw "should not run" }) -StatusText $null -RespectNextAttempt

            $script:TicketsSyncRunCounter | Should Be 42
            $script:TicketsEmailSyncInProgress | Should Be $false
        }
    }

    It "schedules the next automatic sync five minutes after a successful run" {
        '{"Success":true,"Added":0,"Updated":0,"Note":"ok","AddedTickets":[]}' | Set-Content -LiteralPath $global:QOTSyncStdOutPath -Encoding UTF8
        "" | Set-Content -LiteralPath $global:QOTSyncStdErrPath -Encoding UTF8

        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $grid = [System.Windows.Controls.DataGrid]::new()
            $statusText = [System.Windows.Controls.TextBlock]::new()
            $script:TicketsEmailSyncInProgress = $true
            $script:TicketsSyncActiveRunId = 7
            $script:TicketsSyncMode = "child-process"
            $script:TicketsSyncProcess = [pscustomobject]@{ HasExited = $true }
            $script:TicketsSyncRunnerResultPath = $global:QOTSyncResultPath
            $script:TicketsSyncRunnerStdOutPath = $global:QOTSyncStdOutPath
            $script:TicketsSyncRunnerStdErrPath = $global:QOTSyncStdErrPath
            $script:TicketsSyncFailureCount = 3
            $script:TicketsLastSuccessfulSyncUtc = $null
            $script:TicketsSyncLastStartUtc = (Get-Date).ToUniversalTime().AddSeconds(-5)

            $completed = Complete-TicketsEmailSyncAsyncRun -Grid $grid -GetTicketsCmd "Get-QOTickets" -StatusText $statusText -RunId 7

            $completed | Should Be $true
            $script:TicketsEmailSyncInProgress | Should Be $false
            $script:TicketsSyncFailureCount | Should Be 0
            [math]::Round(($script:TicketsSyncNextAttemptUtc - $script:TicketsLastSuccessfulSyncUtc).TotalSeconds) | Should Be 300
            $statusText.Text | Should Match "Last successful email sync:"
        }
    }

    It "uses a short reconnect retry for recoverable Outlook failures" {
        '{"Success":false,"Added":0,"Updated":0,"Note":"Outlook COM unavailable: could not attach to Classic Outlook","AddedTickets":[]}' | Set-Content -LiteralPath $global:QOTSyncResultPath -Encoding UTF8

        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $grid = [System.Windows.Controls.DataGrid]::new()
            $statusText = [System.Windows.Controls.TextBlock]::new()
            $script:TicketsEmailSyncInProgress = $true
            $script:TicketsSyncActiveRunId = 9
            $script:TicketsSyncMode = "result-file"
            $script:TicketsSyncProcess = $null
            $script:TicketsSyncRunnerResultPath = $global:QOTSyncResultPath
            $script:TicketsSyncRunnerStdOutPath = $global:QOTSyncStdOutPath
            $script:TicketsSyncRunnerStdErrPath = $global:QOTSyncStdErrPath
            $script:TicketsSyncFailureCount = 0
            $script:TicketsLastSuccessfulSyncUtc = $null
            $script:TicketsSyncLastStartUtc = (Get-Date).ToUniversalTime().AddSeconds(-2)

            $completed = Complete-TicketsEmailSyncAsyncRun -Grid $grid -GetTicketsCmd "Get-QOTickets" -StatusText $statusText -RunId 9

            $completed | Should Be $true
            $script:TicketsEmailSyncInProgress | Should Be $false
            $script:TicketsSyncFailureCount | Should Be 1
            $statusText.Text | Should Match "Outlook reconnecting"
            $statusText.Text | Should Not Match "Sync failed"
            (($script:TicketsSyncNextAttemptUtc - (Get-Date).ToUniversalTime()).TotalSeconds -le 20) | Should Be $true
        }
    }

    It "backs off reconnect attempts without waiting five minutes first" {
        InModuleScope $ticketsUiModule.Name {
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 0) | Should Be 300
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 1) | Should Be 15
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 2) | Should Be 30
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 3) | Should Be 60
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 4) | Should Be 60
            (Get-QOTicketsSyncBackoffSeconds -FailureCount 5) | Should Be 60
        }
    }

    It "keeps the reconnect countdown in seconds up to the one-minute cap" {
        InModuleScope $ticketsUiModule.Name {
            $label = Get-QOTicketsSyncRetryDelayLabel -NextAttemptUtc ((Get-Date).ToUniversalTime().AddSeconds(60))
            $label | Should Match '^[5-6][0-9]s$'
        }
    }

    It "checks for reconnects every second" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $grid = [System.Windows.Controls.DataGrid]::new()
            $statusText = [System.Windows.Controls.TextBlock]::new()
            $script:TicketsSyncWorkerStarted = $false
            $script:TicketsSyncTimer = $null
            $script:TicketsSyncNextAttemptUtc = [datetime]::MinValue
            $script:TicketsSyncFailureCount = 0
            $script:TicketsEmailSyncInProgress = $false

            try {
                Start-QOTicketsAutoSyncWorker -Grid $grid -GetTicketsCmd "Get-QOTickets" -SyncCmd $null -StatusText $statusText

                [int][math]::Round($script:TicketsSyncTimer.Interval.TotalSeconds) | Should Be 1
            }
            finally {
                if ($script:TicketsSyncTimer) {
                    try { $script:TicketsSyncTimer.Stop() } catch { }
                }
                $script:TicketsSyncWorkerStarted = $false
                $script:TicketsSyncTimer = $null
            }
        }
    }

    It "completes incremental merge timer callbacks without losing helper functions" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $grid = [System.Windows.Controls.DataGrid]::new()
            $grid.ItemsSource = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
            $statusText = [System.Windows.Controls.TextBlock]::new()
            $script:TicketsShowSyncStatus = $true
            $script:AllTickets = @()
            $script:ShowOpen = $true
            $script:ShowClosed = $true
            $script:ShowDeleted = $false
            $script:TicketsSortMode = "Priority"
            $script:TicketsIncrementalMergeTimer = $null
            $script:TicketsIncrementalMergeTickHandler = $null
            $script:TicketsLastSuccessfulSyncUtc = [datetime]"2026-05-07T03:10:00Z"

            $ticket = [pscustomobject]@{
                Id        = "incremental-1"
                Subject   = "Incremental merge"
                CreatedAt = "2026-05-07T03:10:00Z"
                Status    = "New"
                IsDeleted = $false
            }

            try {
                $queued = Start-QOTicketsIncrementalMerge -Grid $grid -IncomingTickets @($ticket) -StatusText $statusText

                $queued | Should Be 1
                $handler = $script:TicketsIncrementalMergeTickHandler
                if ($script:TicketsIncrementalMergeTimer) {
                    try { $script:TicketsIncrementalMergeTimer.Stop() } catch { }
                }
                & $handler
                & $handler

                $statusText.Text | Should Match "Last successful email sync:"
                $script:TicketsIncrementalMergeTimer | Should Be $null
            }
            finally {
                if ($script:TicketsIncrementalMergeTimer) {
                    try { $script:TicketsIncrementalMergeTimer.Stop() } catch { }
                }
                $script:TicketsIncrementalMergeTimer = $null
                $script:TicketsIncrementalMergeTickHandler = $null
            }
        }
    }

    It "finalises result-file sync operations launched without a process handle" {
        '{"Success":true,"Added":0,"Updated":0,"Note":"ok","AddedTickets":[]}' | Set-Content -LiteralPath $global:QOTSyncResultPath -Encoding UTF8

        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $grid = [System.Windows.Controls.DataGrid]::new()
            $statusText = [System.Windows.Controls.TextBlock]::new()
            $script:TicketsEmailSyncInProgress = $true
            $script:TicketsSyncActiveRunId = 8
            $script:TicketsSyncMode = "result-file"
            $script:TicketsSyncProcess = $null
            $script:TicketsSyncRunnerResultPath = $global:QOTSyncResultPath
            $script:TicketsSyncRunnerStdOutPath = $global:QOTSyncStdOutPath
            $script:TicketsSyncRunnerStdErrPath = $global:QOTSyncStdErrPath
            $script:TicketsSyncFailureCount = 2
            $script:TicketsLastSuccessfulSyncUtc = $null
            $script:TicketsSyncLastStartUtc = (Get-Date).ToUniversalTime().AddSeconds(-5)

            $completed = Complete-TicketsEmailSyncAsyncRun -Grid $grid -GetTicketsCmd "Get-QOTickets" -StatusText $statusText -RunId 8

            $completed | Should Be $true
            $script:TicketsEmailSyncInProgress | Should Be $false
            $script:TicketsSyncFailureCount | Should Be 0
            $statusText.Text | Should Match "Last successful email sync:"
        }
    }

    It "manual sync requests start an immediate sync pass" {
        InModuleScope $ticketsUiModule.Name {
            Add-Type -AssemblyName PresentationFramework | Out-Null
            $grid = [System.Windows.Controls.DataGrid]::new()
            $statusText = [System.Windows.Controls.TextBlock]::new()
            $script:TicketsEmailSyncInProgress = $false
            $script:TicketsBackgroundBatchSize = 17
            $script:TicketsLastSuccessfulSyncUtc = $null
            $script:ManualSyncInvocation = $null

            $invokeSyncCmd = {
                param($Grid, $GetTicketsCmd, $SyncCmd, $StatusText, $MaxPerMailbox)
                $script:ManualSyncInvocation = [pscustomobject]@{
                    Grid          = $Grid
                    GetTicketsCmd = $GetTicketsCmd
                    SyncCmd       = $SyncCmd
                    StatusText    = $StatusText
                    MaxPerMailbox = $MaxPerMailbox
                }
            }

            $started = Invoke-QOTicketsManualSyncRequest -Grid $grid -GetTicketsCmd "Get-QOTickets" -SyncCmd "Sync-QOTicketsFromEmail" -StatusText $statusText -InvokeSyncCmd $invokeSyncCmd

            $started | Should Be $true
            $script:ManualSyncInvocation | Should Not Be $null
            $script:ManualSyncInvocation.MaxPerMailbox | Should Be 17
            $statusText.Text | Should Be "Manual sync requested..."
        }
    }
}
