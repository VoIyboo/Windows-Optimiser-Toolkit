$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$tempRoot = [IO.Path]::GetTempPath()
$fixture = Join-Path $tempRoot ('qot-settings-' + [guid]::NewGuid().ToString('N'))
$null = [IO.Directory]::CreateDirectory($fixture)
$oldPath = $env:QOT_SETTINGS_PATH
$path = Join-Path $fixture 'settings.json'
$env:QOT_SETTINGS_PATH = $path
$failures = [Collections.Generic.List[string]]::new()
function Check([string]$Name, [scriptblock]$Test) {
    try { & $Test; Write-Host "PASS $Name" }
    catch { $failures.Add("$Name - $($_.Exception.Message)"); Write-Host "FAIL $Name - $($_.Exception.Message)" }
    finally { [GC]::Collect(); [GC]::WaitForPendingFinalizers() }
}
try {
    Import-Module (Join-Path $repo 'src/Core/Settings.psm1') -Force
    Check 'a reader holding the old settings sees a complete snapshot across a save' {
        [IO.File]::WriteAllText($path, '{"Site":"before"}')
        $observer = [IO.File]::Open($path,'Open','Read',([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            Save-QOSettings -Settings ([pscustomobject]@{Site='after'})
            $reader = [IO.StreamReader]::new($observer)
            try { $snapshot = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        } finally { $observer.Dispose() }
        if ($snapshot.Site -ne 'before' -or (Get-QOSettings).Site -ne 'after') { throw 'The save overwrote the open snapshot' }
    }
    Check 'a read sharing violation cannot reset custom settings' {
        $original = '{"PreferredStartTab":"Tickets","Site":"keep"}'
        [IO.File]::WriteAllText($path,$original)
        $holder = [IO.File]::Open($path,'Open','Write','Write')
        $problem = $null
        try { try { $null = Get-QOSettings } catch { $problem = $_.Exception } }
        finally { $holder.Dispose(); [GC]::Collect(); [GC]::WaitForPendingFinalizers() }
        if (!$problem -or [IO.File]::ReadAllText($path) -cne $original) { throw 'A transient read error triggered default settings' }
    }
    Check 'a stale sync save preserves another process changing nested mailbox settings' {
        $sync = Get-QOSettings
        $worker = Join-Path $fixture 'set-mailboxes.ps1'
        @'
param($ModulePath)
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath
$null = Set-QOMonitoredMailboxAddresses -Addresses @('first@example.invalid','next@example.invalid')
'@ | Set-Content -LiteralPath $worker -Encoding UTF8
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker (Join-Path $repo 'src/Core/Settings.psm1')
        if ($LASTEXITCODE) { throw 'The separate settings writer failed' }
        $sync.Tickets.EmailIntegration.LastSyncUtc = '2026-01-01T05:04:03Z'
        Save-QOSettings $sync
        $result = Get-QOSettings
        if ($result.Tickets.EmailIntegration.MonitoredAddresses.Count -ne 2 -or !$result.Tickets.EmailIntegration.LastSyncUtc) { throw 'A worker reverted the mailbox configuration' }
        $sync.UiState.LastSelectedTab = 'TabTickets'
        Save-QOSettings $sync
        if ((Get-QOSettings).Tickets.EmailIntegration.MonitoredAddresses.Count -ne 2) { throw 'Reusing the saved object restored an old list' }
    }
    Check 'divergent writes to one settings value report conflict before replacing the file' {
        $null = Set-QOSetting -Name PreferredStartTab -Value 'Cleaning'
        $one = Get-QOSettings
        $two = Get-QOSettings
        $one.PreferredStartTab = 'Apps'
        $two.PreferredStartTab = 'Tickets'
        Save-QOSettings $one
        $before = [IO.File]::ReadAllText($path)
        $failed = $false
        try { Save-QOSettings $two } catch { $failed = $true }
        if (!$failed -or [IO.File]::ReadAllText($path) -cne $before) { throw 'A conflicting write replaced the previously committed value' }
    }
    Check 'a stale settings save cannot reset a damaged or switched settings file' {
        $old = Get-QOSettings
        $old.Site = 'edited after read'
        [IO.File]::WriteAllText($path, '{corrupt')
        $failed = $false
        try { Save-QOSettings $old } catch { $failed = $true }
        if (!$failed -or [IO.File]::ReadAllText($path) -cne '{corrupt') { throw 'A stale save replaced a damaged file' }
        $old = Get-QOSettings
        $other = Join-Path $fixture 'other.json'
        [IO.File]::WriteAllText($other, '{"Site":"second"}')
        $env:QOT_SETTINGS_PATH = $other
        $failed = $false
        try { try { Save-QOSettings $old } catch { $failed = $true } } finally { $env:QOT_SETTINGS_PATH = $path }
        if (!$failed -or [IO.File]::ReadAllText($other) -cne '{"Site":"second"}') { throw 'Settings leaked across profiles' }
    }
    Check 'a failed replacement retains the previous bytes and removes temporary files' {
        $original = '{"Site":"retain"}'
        [IO.File]::WriteAllText($path,$original)
        $holder = [IO.File]::Open($path,'Open','Read','Read')
        $failed = $false
        try { try { Save-QOSettings ([pscustomobject]@{Site='other'}) } catch { $failed = $true } }
        finally { $holder.Dispose() }
        if (!$failed -or [IO.File]::ReadAllText($path) -cne $original -or @(Get-ChildItem $fixture -Filter '*.tmp').Count) { throw 'Failed save changed the store or left a temporary file' }
    }
    Check 'unusable JSON roots are backed up before defaults are restored' {
        foreach ($contents in @('', '[{"Site":"invalid array root"}]', '{truncated')) {
            [IO.File]::WriteAllText($path,$contents)
            $defaults = Get-QOSettings
            $saved = Get-ChildItem $fixture -File -Filter 'settings.json.bak_*' | Where-Object { [IO.File]::ReadAllText($_.FullName) -ceq $contents }
            if (!$saved -or $defaults.PreferredStartTab -ne 'Cleaning' -or !(Get-QOSettings).UiState) { throw "Did not recover and preserve original JSON '$contents'" }
        }
    }
} finally {
    [Environment]::SetEnvironmentVariable('QOT_SETTINGS_PATH',$oldPath,'Process')
    $target = (Resolve-Path -LiteralPath $fixture).Path
    if ((Split-Path $target -Parent) -eq $tempRoot.TrimEnd('\') -and (Split-Path $target -Leaf) -match '^qot-settings-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}
if ($failures.Count) { throw ($failures -join [Environment]::NewLine) }
