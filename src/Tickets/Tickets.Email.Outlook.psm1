# src\Tickets\Tickets.Email.Outlook.psm1
# Outlook COM sync for QOT tickets (NO UI CODE)

$ErrorActionPreference = "Stop"

# Import settings directly. This module reads/writes email-sync watermark and cutoff settings.
try {
    Import-Module (Join-Path $PSScriptRoot "..\Core\Settings.psm1") -Global -ErrorAction Stop
} catch {
    throw ("Failed to import Core Settings module: " + $_.Exception.Message)
}

function Write-QOTOutlookSyncLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )

    try {
        if (Get-Command Write-QLog -ErrorAction SilentlyContinue) {
            Write-QLog ("[OutlookSync] " + $Message) $Level
        }
    } catch { }

    $line = ("[{0}] [{1}] [OutlookSync] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message)
    try {
        $fallbackDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $fallbackDir "QuinnOptimiserToolkit.log") -Value $line -Encoding UTF8
    } catch { }
    try {
        $fallbackDir = Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"
        New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $fallbackDir "OutlookSync.log") -Value $line -Encoding UTF8
    } catch { }
}

function Convert-QOTPlainTextToHtml {
    param(
        [AllowNull()][string]$Text
    )

    $plain = ""
    try { $plain = [string]($Text + "") } catch { $plain = "" }
    $plain = $plain -replace "`r`n", "`n"
    $plain = $plain -replace "`r", "`n"

    $escaped = ""
    try {
        $escaped = [System.Security.SecurityElement]::Escape($plain)
    } catch {
        $escaped = $plain
    }
    if ($null -eq $escaped) { $escaped = "" }

    $escaped = ($escaped -replace "`n", "<br/>")
    return ("<div style=""font-family:Segoe UI, Arial, sans-serif;font-size:11pt;"">{0}</div>" -f $escaped)
}

function Convert-QOTHtmlToPlainText {
    param([AllowNull()][string]$Html)

    $value = [string]($Html + "")
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }

    try {
        $value = $value -replace '(?is)<(script|style)\b[^>]*>.*?</\1>', ' '
        $value = $value -replace '(?i)<br\s*/?>', "`r`n"
        $value = $value -replace '(?i)</(p|div|li|tr|table|section|article|blockquote|h[1-6])\s*>', "`r`n"
        $value = $value -replace '(?i)<li\b[^>]*>', ' - '
        $value = $value -replace '(?s)<[^>]+>', ' '
        $value = [System.Net.WebUtility]::HtmlDecode($value)
        $value = $value -replace "[\u00A0\u2007\u202F]", " "
        $value = $value -replace '\r?\n[ \t]+', "`r`n"
        $value = $value -replace '[ \t]{2,}', ' '
        $value = $value -replace '(\r?\n){3,}', "`r`n`r`n"
        return $value.Trim()
    } catch {
        return ([string]($Html + "")).Trim()
    }
}

function Test-QOTBodyLooksUnreadable {
    param([AllowNull()][string]$Text)

    $value = [string]($Text + "")
    if ([string]::IsNullOrWhiteSpace($value)) { return $true }

    $sample = $value
    if ($sample.Length -gt 4000) {
        $sample = $sample.Substring(0, 4000)
    }

    $letterCount = ([regex]::Matches($sample, '\p{L}')).Count
    $wordCount = ([regex]::Matches($sample, '(?<!\p{L})\p{L}{2,}')).Count
    $mojibakePattern = (([string][char]0x00C3) + '|' + ([string][char]0x00C2) + '|' + ([string][char]0x00E2))
    $mojibakeCount = ([regex]::Matches($sample, $mojibakePattern)).Count
    if ($letterCount -eq 0) { return $true }
    if ($mojibakeCount -ge 20 -and $wordCount -lt 20) { return $true }
    return $false
}

function Get-QOTPreferredMailItemBodyText {
    param([AllowNull()]$MailItem)

    $plainBody = ""
    $htmlBody = ""
    try { $plainBody = [string]($MailItem.Body + "") } catch { $plainBody = "" }
    try { $htmlBody = [string]($MailItem.HTMLBody + "") } catch { $htmlBody = "" }

    $plainBody = ([string]($plainBody + "")).Trim()
    $htmlText = Convert-QOTHtmlToPlainText -Html $htmlBody

    $selectedBody = $plainBody
    $selectedSource = "PlainBody"

    if ([string]::IsNullOrWhiteSpace($selectedBody) -and -not [string]::IsNullOrWhiteSpace($htmlText)) {
        $selectedBody = $htmlText
        $selectedSource = "HtmlBodyConverted"
    } elseif ((Test-QOTBodyLooksUnreadable -Text $selectedBody) -and -not [string]::IsNullOrWhiteSpace($htmlText)) {
        $selectedBody = $htmlText
        $selectedSource = "HtmlBodyPreferred"
    }

    return [pscustomobject]@{
        BodyText     = ([string]($selectedBody + "")).Trim()
        BodySource   = $selectedSource
        PlainLength  = $plainBody.Length
        HtmlLength   = $htmlBody.Length
        ChosenLength = ([string]($selectedBody + "")).Trim().Length
    }
}

function Initialize-QOTicketsCoreApi {
    $requiredCommands = @(
        "Get-QOTMonitoredMailboxAddresses",
        "Get-QOTickets",
        "Save-QOTickets"
    )

    $missing = @(
        $requiredCommands |
            Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
    )

    if ($missing.Count -eq 0) {
        return
    }

    $coreModulePath = Join-Path $PSScriptRoot "..\Core\Tickets.psm1"
    if (-not (Test-Path -LiteralPath $coreModulePath)) {
        throw ("Core Tickets module not found: " + $coreModulePath)
    }

    Import-Module $coreModulePath -Global -ErrorAction Stop

    $missingAfterImport = @(
        $requiredCommands |
            Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
    )
    if ($missingAfterImport.Count -gt 0) {
        throw ("Missing required ticket core command(s): " + ($missingAfterImport -join ", "))
    }
}

function Test-QOTCurrentProcessElevated {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity) { return $false }
        $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
        return [bool]$principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function New-QOTOutlookComApplication {
    param(
        [int]$RetryCount = 1,
        [int]$RetryDelayMilliseconds = 1000
    )

    if ($RetryCount -lt 1) { $RetryCount = 1 }
    if ($RetryDelayMilliseconds -lt 0) { $RetryDelayMilliseconds = 0 }

    $lastError = $null
    for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            $outlookApp = New-Object -ComObject Outlook.Application

            # Minimize Outlook window to prevent focus-stealing
            try {
                $outlookApp.ActiveExplorer().WindowState = 1  # 1 = olMinimized
            } catch {
                # If minimizing fails, that's OK - Outlook is still running in background
            }

            return $outlookApp
        } catch {
            $lastError = $_.Exception
            $message = ""
            try { $message = [string]$lastError.Message } catch { $message = "" }
            if ($message -match '(?i)class not registered|invalid class string') {
                throw $lastError
            }
            if ($attempt -lt $RetryCount) {
                Start-Sleep -Milliseconds $RetryDelayMilliseconds
            }
        }
    }

    if ($lastError) { throw $lastError }
    throw "Unable to create Outlook COM application."
}

function Get-QOTOutlookNamespace {
    param(
        [switch]$AllowStartOutlook
    )

    if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
        throw "PowerShell is not running in STA mode. Launch with: powershell.exe -STA"
    }

    $tryResolveNamespace = {
        $activeOutlook = $null
        try {
            $activeOutlook = [System.Runtime.InteropServices.Marshal]::GetActiveObject("Outlook.Application")
        } catch { $activeOutlook = $null }
        if ($activeOutlook) {
            try { return $activeOutlook.GetNamespace("MAPI") } catch { }
        }
        return $null
    }.GetNewClosure()

    # Fast path: attach to an already running classic Outlook instance.
    $existingNamespace = & $tryResolveNamespace
    if ($existingNamespace) { return $existingNamespace }

    if (-not $AllowStartOutlook) {
        throw "Classic Outlook is not running. Open Outlook and retry."
    }

    # Start classic Outlook explicitly, then attach via the running instance.
    # Direct COM startup can block for a long time on some machines when Outlook is cold.
    $candidateExePaths = @()
    try {
        foreach ($regPath in @(
                "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE",
                "HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE",
                "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE")) {
            try {
                $value = (Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue).'(default)'
                $exe = ([string]($value + "")).Trim()
                if (-not [string]::IsNullOrWhiteSpace($exe)) { $candidateExePaths += @($exe) }
            } catch { }
        }
    } catch { }
    try {
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
            foreach ($rel in @(
                    "Microsoft Office\root\Office16\OUTLOOK.EXE",
                    "Microsoft Office\Office16\OUTLOOK.EXE",
                    "Microsoft Office\root\Office15\OUTLOOK.EXE",
                    "Microsoft Office\Office15\OUTLOOK.EXE")) {
                $candidateExePaths += @(Join-Path $root $rel)
            }
        }
    } catch { }
    $candidateExePaths += @("OUTLOOK.EXE")

    $started = $false
    $lastStartError = ""
    foreach ($candidate in @($candidateExePaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        try {
            if ($candidate -ne "OUTLOOK.EXE" -and -not (Test-Path -LiteralPath $candidate)) { continue }
            $startedProcess = Start-Process -FilePath $candidate -ArgumentList "/recycle" -WindowStyle Minimized -PassThru -ErrorAction Stop
            try { $null = $startedProcess.WaitForInputIdle(12000) } catch { }
            Write-QOTOutlookSyncLog ("Started Outlook process for COM attach using: " + $candidate)
            $started = $true
            break
        } catch {
            $lastStartError = [string]$_.Exception.Message
        }
    }

    if ($started) {
        $maxAttempts = 24  # ~12 seconds
        for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
            Start-Sleep -Milliseconds 500

            $attachedNamespace = & $tryResolveNamespace
            if ($attachedNamespace) { return $attachedNamespace }
        }
    }

    $details = @()
    try {
        $createdOutlook = New-QOTOutlookComApplication -RetryCount 3 -RetryDelayMilliseconds 1500
        if ($createdOutlook) {
            $createdNamespace = $createdOutlook.GetNamespace("MAPI")
            if ($createdNamespace) {
                Write-QOTOutlookSyncLog "Attached to Classic Outlook by creating a COM application instance after active-object attach failed." "WARN"
                return $createdNamespace
            }
        }
    } catch {
        $fallbackMessage = ""
        try { $fallbackMessage = ([string]$_.Exception.Message).Trim() } catch { $fallbackMessage = "" }
        if (-not [string]::IsNullOrWhiteSpace($fallbackMessage)) {
            $details += @("COM: " + $fallbackMessage)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($lastStartError)) {
        $details += @("Start: " + $lastStartError)
    }
    $detailSuffix = ""
    if ($details.Count -gt 0) {
        $detailSuffix = " (" + ($details -join " | ") + ")"
    }

    $elevatedHint = ""
    try {
        if (Test-QOTCurrentProcessElevated) {
            $elevatedHint = " If this toolkit is running as Administrator, close it and run it normally (same level as Outlook)."
        }
    } catch { }

    Write-QOTOutlookSyncLog "Outlook COM attach/startup failed after retries." "WARN"

    throw ("Outlook COM unavailable: could not attach to Classic Outlook. Ensure Classic Outlook (not New Outlook) is installed/running and fully opened, then retry." + $elevatedHint + $detailSuffix)
}

function Get-QOTOutlookApplication {
    param(
        [AllowNull()]$MAPI
    )

    try {
        $app = $null
        if ($MAPI) { $app = $MAPI.Application }
        if ($app) { return $app }
    } catch { }

    try {
        $activeOutlook = [System.Runtime.InteropServices.Marshal]::GetActiveObject("Outlook.Application")
        if ($activeOutlook) { return $activeOutlook }
    } catch { }

    return (New-QOTOutlookComApplication -RetryCount 3 -RetryDelayMilliseconds 1200)
}

function Get-QOTConfiguredMailboxAddresses {
    try {
        return @(
            @(Get-QOTMonitoredMailboxAddresses) |
                ForEach-Object { ([string]($_ + "")).Trim() } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
    } catch {
        return @()
    }
}

function Save-QOTConfiguredMailboxAddresses {
    param(
        [string[]]$Addresses
    )

    $clean = @(
        @($Addresses) |
            ForEach-Object { Normalize-QOTEmailAddress -Value ([string]($_ + "")) } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    if ($clean.Count -eq 0) { return @() }

    $setCmd = $null
    try { $setCmd = Get-Command Set-QOMonitoredMailboxAddresses -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $setCmd = $null }
    if (-not $setCmd) {
        try { $setCmd = Get-Command Set-QOMonitoredAddresses -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $setCmd = $null }
    }

    if (-not $setCmd) { return $clean }

    try {
        $saved = @(& $setCmd -Addresses $clean)
        if ($saved.Count -gt 0) {
            return @(
                @($saved) |
                    ForEach-Object { Normalize-QOTEmailAddress -Value ([string]($_ + "")) } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Sort-Object -Unique
            )
        }
    } catch {
        try { Write-QOTOutlookSyncLog ("Failed to persist auto-discovered mailbox settings: " + $_.Exception.Message) "WARN" } catch { }
    }

    return $clean
}

function Get-QOTOutlookAccountMailboxAddresses {
    param(
        [AllowNull()]$MAPI
    )

    if (-not $MAPI) { return @() }

    $addresses = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        for ($i = 1; $i -le $MAPI.Accounts.Count; $i++) {
            $account = $null
            try { $account = $MAPI.Accounts.Item($i) } catch { $account = $null }
            if (-not $account) { continue }

            $candidates = @()
            try { $candidates += @(([string]($account.SmtpAddress + "")).Trim()) } catch { }
            try { $candidates += @(([string]($account.DisplayName + "")).Trim()) } catch { }
            try { $candidates += @(([string]($account.UserName + "")).Trim()) } catch { }

            foreach ($candidate in @($candidates)) {
                $email = Normalize-QOTEmailAddress -Value ([string]($candidate + ""))
                if (-not [string]::IsNullOrWhiteSpace($email)) {
                    [void]$addresses.Add($email)
                }
            }
        }
    } catch { }

    return @($addresses)
}

function Get-QOTHistoricalMonitoredMailboxAddresses {
    $getTicketsCmd = $null
    try { $getTicketsCmd = Get-Command Get-QOTickets -ErrorAction SilentlyContinue | Select-Object -First 1 } catch { $getTicketsCmd = $null }
    if (-not $getTicketsCmd) { return @() }

    try {
        $database = & $getTicketsCmd
        if (-not $database) { return @() }

        return @(
            @($database.Tickets) |
                ForEach-Object {
                    if ($null -eq $_) { return }
                    $rawMailbox = ""
                    try {
                        if ($_.PSObject.Properties.Name -contains "SourceMailbox") {
                            $rawMailbox = [string]($_.SourceMailbox + "")
                        }
                    } catch { $rawMailbox = "" }
                    Normalize-QOTEmailAddress -Value $rawMailbox
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Sort-Object -Unique
        )
    } catch {
        try { Write-QOTOutlookSyncLog ("Failed to recover monitored mailbox from ticket history: " + $_.Exception.Message) "WARN" } catch { }
        return @()
    }
}

function Get-QOTEffectiveMonitoredMailboxAddresses {
    param(
        [AllowNull()]$MAPI,
        [switch]$AllowStartOutlook,
        [switch]$PersistWhenSingle
    )

    $configured = @(Get-QOTConfiguredMailboxAddresses)
    if ($configured.Count -gt 0) {
        return $configured
    }

    $historical = @(Get-QOTHistoricalMonitoredMailboxAddresses)
    if ($historical.Count -eq 1) {
        $mailbox = [string]$historical[0]
        if ($PersistWhenSingle) {
            $historical = @(Save-QOTConfiguredMailboxAddresses -Addresses $historical)
            if ($historical.Count -gt 0) {
                $mailbox = [string]$historical[0]
            }
        }
        try { Write-QOTOutlookSyncLog ("Using historical mailbox '{0}' because monitored mailbox settings are empty." -f $mailbox) "WARN" } catch { }
        return @($mailbox)
    }

    $resolvedMAPI = $MAPI
    if (-not $resolvedMAPI) {
        try {
            $resolvedMAPI = Get-QOTOutlookNamespace -AllowStartOutlook:$AllowStartOutlook
        } catch {
            $resolvedMAPI = $null
        }
    }

    $discovered = @(Get-QOTOutlookAccountMailboxAddresses -MAPI $resolvedMAPI)
    if ($discovered.Count -eq 1) {
        $mailbox = [string]$discovered[0]
        if ($PersistWhenSingle) {
            $discovered = @(Save-QOTConfiguredMailboxAddresses -Addresses $discovered)
            if ($discovered.Count -gt 0) {
                $mailbox = [string]$discovered[0]
            }
        }
        try { Write-QOTOutlookSyncLog ("Using Outlook mailbox '{0}' because monitored mailbox settings are empty." -f $mailbox) "WARN" } catch { }
        return @($mailbox)
    }

    return @()
}

function Test-QOTConfiguredMailboxAddress {
    param(
        [AllowNull()][string]$MailboxAddress
    )

    $target = ([string]($MailboxAddress + "")).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($target)) { return $false }

    foreach ($candidate in @(Get-QOTConfiguredMailboxAddresses)) {
        $value = ([string]($candidate + "")).Trim().ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -eq $target) {
            return $true
        }
    }

    return $false
}

function Get-QOTPreferredSenderMailbox {
    param(
        [AllowNull()]$Ticket,
        [AllowNull()][string]$FromMailbox
    )

    $candidate = ([string]($FromMailbox + "")).Trim()
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        return $candidate
    }

    try {
        if ($Ticket -and ($Ticket.PSObject.Properties.Name -contains "SourceMailbox")) {
            $candidate = ([string]($Ticket.SourceMailbox + "")).Trim()
        }
    } catch { $candidate = "" }
    if (-not [string]::IsNullOrWhiteSpace($candidate)) {
        return $candidate
    }

    $configured = @(Get-QOTConfiguredMailboxAddresses)
    if ($configured.Count -eq 1) {
        return ([string]$configured[0]).Trim()
    }

    return ""
}

function Get-QOTOutlookAccountForMailbox {
    param(
        [Parameter(Mandatory)]
        [object]$MAPI,
        [Parameter(Mandatory)]
        [string]$MailboxAddress
    )

    $target = ([string]($MailboxAddress + "")).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($target)) { return $null }

    try {
        for ($i = 1; $i -le $MAPI.Accounts.Count; $i++) {
            $account = $MAPI.Accounts.Item($i)
            if (-not $account) { continue }

            $candidates = @()
            try { $candidates += @(([string]($account.SmtpAddress + "")).Trim()) } catch { }
            try { $candidates += @(([string]($account.DisplayName + "")).Trim()) } catch { }
            try { $candidates += @(([string]($account.UserName + "")).Trim()) } catch { }

            foreach ($candidate in @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
                if (([string]$candidate).Trim().ToLowerInvariant() -eq $target) {
                    return $account
                }
            }
        }
    } catch { }

    return $null
}

function Set-QOTOutlookMailSender {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]$MailItem,
        [Parameter(Mandatory)]
        [object]$MAPI,
        [AllowNull()][string]$MailboxAddress
    )

    $senderMailbox = ([string]($MailboxAddress + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($senderMailbox)) {
        return ""
    }

    $account = $null
    try { $account = Get-QOTOutlookAccountForMailbox -MAPI $MAPI -MailboxAddress $senderMailbox } catch { $account = $null }
    $effectiveMailboxes = @(Get-QOTEffectiveMonitoredMailboxAddresses -MAPI $MAPI -PersistWhenSingle)
    $mailboxAllowed = $false
    foreach ($candidate in @($effectiveMailboxes)) {
        if (([string]($candidate + "")).Trim().ToLowerInvariant() -eq $senderMailbox.ToLowerInvariant()) {
            $mailboxAllowed = $true
            break
        }
    }

    if (-not $mailboxAllowed -and -not $account) {
        throw ("The sender mailbox '{0}' is not available. Add it in Settings > Monitored mailbox addresses or add the mailbox to Outlook." -f $senderMailbox)
    }

    if ($account) {
        try {
            $MailItem.SendUsingAccount = $account
            Write-QOTOutlookSyncLog ("Prepared outgoing mail to send using Outlook account: " + $senderMailbox)
            return $senderMailbox
        } catch { }
    }

    try { $MailItem.SentOnBehalfOfName = $senderMailbox } catch { }

    $appliedMailbox = ""
    try { $appliedMailbox = ([string]($MailItem.SentOnBehalfOfName + "")).Trim() } catch { $appliedMailbox = "" }

    if (-not [string]::IsNullOrWhiteSpace($appliedMailbox)) {
        Write-QOTOutlookSyncLog ("Prepared outgoing mail to send from mailbox: " + $senderMailbox)
        return $senderMailbox
    }

    throw ("Unable to use sender mailbox '{0}'. Ensure the mailbox is added to Outlook and you have Send As or Send on Behalf permission." -f $senderMailbox)
}

function Get-QOTMailboxInboxFolder {
    param(
        [Parameter(Mandatory)]
        [object]$MAPI,
        [Parameter(Mandatory)]
        [string]$MailboxAddress
    )

    $olFolderInbox = 6

    try {
        $recipient = $MAPI.CreateRecipient($MailboxAddress)
        $recipient.Resolve() | Out-Null

        if (-not $recipient.Resolved) {
            throw "Recipient not resolved: $MailboxAddress"
        }

        return $MAPI.GetSharedDefaultFolder($recipient, $olFolderInbox)
    } catch { }

    # Fallback 1: if mailbox matches a signed-in account, use default inbox
    try {
        $target = ([string]$MailboxAddress).Trim().ToLowerInvariant()
        for ($i = 1; $i -le $MAPI.Accounts.Count; $i++) {
            $acct = $MAPI.Accounts.Item($i)
            $smtp = ""
            try { $smtp = ([string]$acct.SmtpAddress).Trim().ToLowerInvariant() } catch { $smtp = "" }
            if ($smtp -and ($smtp -eq $target)) {
                return $MAPI.GetDefaultFolder($olFolderInbox)
            }
        }
    } catch { }

    # Fallback 2: scan stores by name and open Inbox under matching root
    try {
        $target = ([string]$MailboxAddress).Trim().ToLowerInvariant()
        $local = $target
        if ($target -like "*@*") {
            $local = $target.Split('@')[0]
        }

        for ($s = 1; $s -le $MAPI.Stores.Count; $s++) {
            $store = $MAPI.Stores.Item($s)
            $display = ""
            try { $display = ([string]$store.DisplayName).Trim().ToLowerInvariant() } catch { $display = "" }

            $matches = $false
            if ($display) {
                if ($display -eq $target -or $display -eq $local) { $matches = $true }
                elseif ($target -and $display -like ("*" + $target + "*")) { $matches = $true }
                elseif ($local -and $display -like ("*" + $local + "*")) { $matches = $true }
            }
            if (-not $matches) { continue }

            $root = $store.GetRootFolder()
            if (-not $root) { continue }
            try {
                $inbox = $root.Folders.Item("Inbox")
                if ($inbox) { return $inbox }
            } catch { }
        }
    } catch { }

    throw "Cannot open Inbox for $MailboxAddress. Check Outlook permissions and that the mailbox exists in your profile."
}

function Get-QOTOutlookItemsSnapshot {
    param(
        [Parameter(Mandatory)]
        [object]$Items,
        [int]$MaxItems = 5000
    )

    $list = @()
    $count = 0
    try { $count = [int]$Items.Count } catch { $count = 0 }
    if ($count -le 0) { return @() }

    $limit = [Math]::Min($count, [Math]::Max(1, $MaxItems))
    for ($i = 1; $i -le $limit; $i++) {
        try {
            $item = $Items.Item($i)
            if ($null -ne $item) { $list += @($item) }
        } catch { }
    }

    return @($list)
}

function Normalize-QOTInternetMessageId {
    param([AllowNull()][string]$Value)

    $text = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    $text = $text.Trim('<', '>', '"', "'")
    $text = ($text -replace '\s+', '')
    return $text.ToLowerInvariant()
}

function Normalize-QOTEmailAddress {
    param([AllowNull()][string]$Value)

    $text = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }

    $match = [regex]::Match($text, '(?i)([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})')
    if ($match.Success) {
        return ([string]$match.Groups[1].Value).Trim().ToLowerInvariant()
    }

    if ($text -like "*@*") {
        return $text.ToLowerInvariant()
    }

    return ""
}

function Get-QOTNormalizedEmailThreadSubject {
    param([AllowNull()][string]$Subject)

    $value = ([string]($Subject + "")).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($value)) { return "" }

    $changed = $true
    while ($changed) {
        $before = $value
        $value = ($value -replace '^\s*(re|fw|fwd)\s*:\s*', '').Trim()
        $changed = ($value -ne $before)
    }

    $value = ($value -replace '\s+', ' ').Trim()
    return $value
}

function Limit-QOTOutlookText {
    param(
        [AllowNull()][string]$Value,
        [int]$MaxLength = 260
    )

    $text = ([string]($Value + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    if ($MaxLength -lt 32) { $MaxLength = 32 }
    $text = ($text -replace '\s+', ' ').Trim()
    if ($text.Length -gt $MaxLength) {
        $text = $text.Substring(0, $MaxLength).Trim()
    }
    return $text
}

function Get-QOTOutlookInternetMessageId {
    param([Parameter(Mandatory)][object]$MailItem)

    $candidates = @(
        # Preferred canonical MAPI proptag for Internet Message-ID
        "http://schemas.microsoft.com/mapi/proptag/0x1035001F",
        # Legacy schema string fallback used by older builds
        "http://schemas.microsoft.com/mapi/string/{00020386-0000-0000-C000-000000000046}/InternetMessageId"
    )

    foreach ($prop in $candidates) {
        try {
            $raw = [string]$MailItem.PropertyAccessor.GetProperty($prop)
            $normalized = Normalize-QOTInternetMessageId -Value $raw
            if (-not [string]::IsNullOrWhiteSpace($normalized)) {
                return $normalized
            }
        } catch { }
    }

    return ""
}

function Get-QOTOutlookConversationId {
    param([Parameter(Mandatory)][object]$MailItem)

    try {
        $conversationId = ([string]($MailItem.ConversationID + "")).Trim()
        if (-not [string]::IsNullOrWhiteSpace($conversationId)) {
            return $conversationId.ToLowerInvariant()
        }
    } catch { }

    return ""
}

function Get-QOTOutlookSenderInfo {
    param([Parameter(Mandatory)][object]$MailItem)

    $senderName = ""
    $senderEmail = ""

    try { $senderName = ([string]$MailItem.SenderName).Trim() } catch { $senderName = "" }
    try { $senderEmail = ([string]$MailItem.SenderEmailAddress).Trim() } catch { $senderEmail = "" }

    $senderEmailType = ""
    try { $senderEmailType = ([string]$MailItem.SenderEmailType).Trim() } catch { $senderEmailType = "" }

    $addressEntry = $null
    try { $addressEntry = $MailItem.Sender } catch { $addressEntry = $null }

    if ($addressEntry) {
        if ([string]::IsNullOrWhiteSpace($senderName)) {
            try { $senderName = ([string]$addressEntry.Name).Trim() } catch { $senderName = "" }
        }

        if ([string]::IsNullOrWhiteSpace($senderEmail) -or $senderEmailType -eq "EX" -or ($senderEmail -notlike "*@*")) {
            try {
                $exchangeUser = $addressEntry.GetExchangeUser()
                if ($exchangeUser) {
                    $smtp = ([string]$exchangeUser.PrimarySmtpAddress).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($smtp)) {
                        $senderEmail = $smtp
                    }
                }
            } catch { }

            if ([string]::IsNullOrWhiteSpace($senderEmail) -or ($senderEmail -notlike "*@*")) {
                try {
                    $smtpProp = "http://schemas.microsoft.com/mapi/proptag/0x39FE001E"
                    $smtpValue = ([string]$addressEntry.PropertyAccessor.GetProperty($smtpProp)).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($smtpValue)) {
                        $senderEmail = $smtpValue
                    }
                } catch { }
            }
        }
    }

    $displayFrom = ""
    if (-not [string]::IsNullOrWhiteSpace($senderName) -and -not [string]::IsNullOrWhiteSpace($senderEmail)) {
        $displayFrom = ("{0} <{1}>" -f $senderName, $senderEmail)
    } elseif (-not [string]::IsNullOrWhiteSpace($senderEmail)) {
        $displayFrom = $senderEmail
    } elseif (-not [string]::IsNullOrWhiteSpace($senderName)) {
        $displayFrom = $senderName
    }

    return [pscustomobject]@{
        SenderName  = $senderName
        SenderEmail = $senderEmail
        DisplayFrom = $displayFrom
    }
}

function Get-QOTTicketIdentityKeys {
    param(
        [AllowNull()]$Ticket
    )

    if ($null -eq $Ticket) { return @() }

    $keys = New-Object 'System.Collections.Generic.List[string]'

    $sourceId = ""
    $storeId = ""
    $emailMessageId = ""
    $conversationId = ""
    $emailFrom = ""
    $emailTo = ""
    $senderEmail = ""
    $subject = ""
    $emailReceived = ""

    try { if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") { $sourceId = ([string]($Ticket.SourceMessageId + "")).Trim() } } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "SourceStoreId") { $storeId = ([string]($Ticket.SourceStoreId + "")).Trim() } } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") {
            $emailMessageId = Normalize-QOTInternetMessageId -Value ([string]$Ticket.EmailMessageId)
        }
    } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailConversationId") {
            $conversationId = ([string]($Ticket.EmailConversationId + "")).Trim().ToLowerInvariant()
        } elseif ($Ticket.PSObject.Properties.Name -contains "ConversationId") {
            $conversationId = ([string]($Ticket.ConversationId + "")).Trim().ToLowerInvariant()
        }
    } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "EmailFrom") { $emailFrom = ([string]($Ticket.EmailFrom + "")).Trim().ToLowerInvariant() } } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "EmailTo") { $emailTo = ([string]($Ticket.EmailTo + "")).Trim().ToLowerInvariant() } } catch { }
    try { if ($Ticket.PSObject.Properties.Name -contains "SenderEmail") { $senderEmail = ([string]($Ticket.SenderEmail + "")).Trim().ToLowerInvariant() } } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "Subject") {
            $subject = ([string]($Ticket.Subject + "")).Trim().ToLowerInvariant()
        } elseif ($Ticket.PSObject.Properties.Name -contains "Title") {
            $subject = ([string]($Ticket.Title + "")).Trim().ToLowerInvariant()
        }
    } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "EmailReceived") {
            $emailReceived = ([string]($Ticket.EmailReceived + "")).Trim()
        } elseif ($Ticket.PSObject.Properties.Name -contains "CreatedAt") {
            $emailReceived = ([string]($Ticket.CreatedAt + "")).Trim()
        }
    } catch { }

    if (-not [string]::IsNullOrWhiteSpace($emailMessageId)) {
        $keys.Add("internet:$emailMessageId") | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($conversationId)) {
        $keys.Add("conversation:$conversationId") | Out-Null
    }

    if (-not [string]::IsNullOrWhiteSpace($sourceId)) {
        $normalizedSourceInternet = Normalize-QOTInternetMessageId -Value $sourceId
        if (($sourceId -match '@') -and (-not [string]::IsNullOrWhiteSpace($normalizedSourceInternet))) {
            $keys.Add("internet:$normalizedSourceInternet") | Out-Null
        } else {
            $entryKey = if (-not [string]::IsNullOrWhiteSpace($storeId)) {
                "entry:$($storeId.ToLowerInvariant())|$($sourceId.ToLowerInvariant())"
            } else {
                "entry:$($sourceId.ToLowerInvariant())"
            }
            $keys.Add($entryKey) | Out-Null
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($subject) -and
        -not [string]::IsNullOrWhiteSpace($emailFrom) -and
        -not [string]::IsNullOrWhiteSpace($emailReceived)) {
        $keys.Add(("fallback:{0}|{1}|{2}" -f $emailFrom, $subject, $emailReceived.ToLowerInvariant())) | Out-Null
    }

    $threadSubject = Get-QOTNormalizedEmailThreadSubject -Subject $subject
    if (-not [string]::IsNullOrWhiteSpace($threadSubject)) {
        $participants = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($candidate in @($emailFrom, $emailTo, $senderEmail)) {
            $email = Normalize-QOTEmailAddress -Value $candidate
            if (-not [string]::IsNullOrWhiteSpace($email)) {
                [void]$participants.Add($email)
            }
        }

        foreach ($email in $participants) {
            $keys.Add(("thread:{0}|{1}" -f $email, $threadSubject)) | Out-Null
        }
    }

    $unique = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $keys) {
        if (-not [string]::IsNullOrWhiteSpace([string]$k)) {
            [void]$unique.Add([string]$k)
        }
    }
    return @($unique)
}

# ---------------------------------------------------------------------
# Watermark: only sync emails newer than last successful sync
# Stored in Settings: Tickets.EmailIntegration.LastSyncUtc
# ---------------------------------------------------------------------
function Get-QOTLastEmailSyncUtc {
    try {
        $s = Get-QOSettings
        if ($s -and $s.PSObject.Properties.Name -contains "Tickets") {
            $t = $s.Tickets
            if ($t -and $t.PSObject.Properties.Name -contains "EmailIntegration") {
                $ei = $t.EmailIntegration
                if ($ei -and $ei.PSObject.Properties.Name -contains "LastSyncUtc") {
                    $v = [string]$ei.LastSyncUtc
                    if (-not [string]::IsNullOrWhiteSpace($v)) {
                        return ([datetime]::Parse($v)).ToUniversalTime()
                    }
                }
            }
        }
    } catch { }

    return [datetime]"1970-01-01T00:00:00Z"
}

function Set-QOTLastEmailSyncUtc {
    param(
        [Parameter(Mandatory)]
        [datetime]$UtcTime
    )

    try {
        $s = Get-QOSettings
        if (-not $s) { return }

        if ($s.PSObject.Properties.Name -notcontains "Tickets") {
            $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        if ($s.Tickets.PSObject.Properties.Name -notcontains "EmailIntegration") {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        if ($s.Tickets.EmailIntegration.PSObject.Properties.Name -notcontains "LastSyncUtc") {
            $s.Tickets.EmailIntegration | Add-Member -NotePropertyName LastSyncUtc -NotePropertyValue $null -Force
        }

        $s.Tickets.EmailIntegration.LastSyncUtc = $UtcTime.ToUniversalTime().ToString("o")
        Save-QOSettings -Settings $s
    } catch { }
}

function Get-QOTLastSuccessfulEmailSyncUtc {
    try {
        $s = Get-QOSettings
        if ($s -and $s.PSObject.Properties.Name -contains "Tickets") {
            $t = $s.Tickets
            if ($t -and $t.PSObject.Properties.Name -contains "EmailIntegration") {
                $ei = $t.EmailIntegration
                if ($ei -and $ei.PSObject.Properties.Name -contains "LastSuccessfulSyncUtc") {
                    $v = [string]$ei.LastSuccessfulSyncUtc
                    if (-not [string]::IsNullOrWhiteSpace($v)) {
                        return ([datetime]::Parse($v)).ToUniversalTime()
                    }
                }
            }
        }
    } catch { }

    return $null
}

function Set-QOTLastSuccessfulEmailSyncUtc {
    param(
        [Parameter(Mandatory)]
        [datetime]$UtcTime
    )

    try {
        $s = Get-QOSettings
        if (-not $s) { return }

        if ($s.PSObject.Properties.Name -notcontains "Tickets") {
            $s | Add-Member -NotePropertyName Tickets -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        if ($s.Tickets.PSObject.Properties.Name -notcontains "EmailIntegration") {
            $s.Tickets | Add-Member -NotePropertyName EmailIntegration -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        if ($s.Tickets.EmailIntegration.PSObject.Properties.Name -notcontains "LastSuccessfulSyncUtc") {
            $s.Tickets.EmailIntegration | Add-Member -NotePropertyName LastSuccessfulSyncUtc -NotePropertyValue $null -Force
        }

        $s.Tickets.EmailIntegration.LastSuccessfulSyncUtc = $UtcTime.ToUniversalTime().ToString("o")
        Save-QOSettings -Settings $s
    } catch { }
}

# ---------------------------------------------------------------------
# Decide cutoff:
# - If never synced before (LastSyncUtc is default), use pinned start date.
# - If never synced and not pinned, follow today (today at midnight local).
# - Otherwise use LastSyncUtc for incremental sync (clamped to pinned date if needed).
# ---------------------------------------------------------------------
function Get-QOTEffectiveEmailCutoffUtc {
    param(
        [Parameter(Mandatory)]
        [datetime]$LastSyncUtc
    )

    $pinned = $null
    try {
        # If user pinned a start date, always sync from that day -> now.
        $pinned = Get-QOEmailSyncStartDatePinned
    } catch { }

    $neverSynced = ($LastSyncUtc -le [datetime]"1970-01-02T00:00:00Z")
    if ($neverSynced) {
        if ($pinned) {
            $localStart = ([datetime]$pinned).Date
            return $localStart.ToUniversalTime()
        }

        # Follow today: use start of today (local), then convert to UTC
        return (Get-Date).Date.ToUniversalTime()
    }

    # After first successful sync, always move incrementally from watermark.
    # Safety: if watermark is behind pinned date, clamp to pinned date once.
    if ($pinned) {
        $pinnedUtc = ([datetime]$pinned).Date.ToUniversalTime()
        if ($LastSyncUtc -lt $pinnedUtc) {
            return $pinnedUtc
        }
    }

    return $LastSyncUtc
}

function Convert-QOTMailItemToTicket {
    param(
        [Parameter(Mandatory)] [string]$MailboxAddress,
        [Parameter(Mandatory)] [object]$MailItem
    )

    $senderInfo = $null
    try { $senderInfo = Get-QOTOutlookSenderInfo -MailItem $MailItem } catch { $senderInfo = $null }
    $from = ""
    $senderName = ""
    $senderEmail = ""
    if ($senderInfo) {
        try { $from = ([string]$senderInfo.DisplayFrom).Trim() } catch { $from = "" }
        try { $senderName = ([string]$senderInfo.SenderName).Trim() } catch { $senderName = "" }
        try { $senderEmail = ([string]$senderInfo.SenderEmail).Trim() } catch { $senderEmail = "" }
    }
    if ([string]::IsNullOrWhiteSpace($from)) {
        if (-not [string]::IsNullOrWhiteSpace($senderEmail)) {
            $from = $senderEmail
        } elseif (-not [string]::IsNullOrWhiteSpace($senderName)) {
            $from = $senderName
        }
    }

    $subject = ""
    try { $subject = [string]$MailItem.Subject } catch { }
    $subject = Limit-QOTOutlookText -Value $subject -MaxLength 320

    $received = $null
    try { $received = [datetime]$MailItem.ReceivedTime } catch { $received = Get-Date }

    $body = ""
    $bodySource = "PlainBody"
    $plainBodyLength = 0
    $htmlBodyLength = 0
    try {
        $bodyInfo = Get-QOTPreferredMailItemBodyText -MailItem $MailItem
        if ($bodyInfo) {
            $body = [string]$bodyInfo.BodyText
            $bodySource = [string]$bodyInfo.BodySource
            $plainBodyLength = [int]$bodyInfo.PlainLength
            $htmlBodyLength = [int]$bodyInfo.HtmlLength
        }
    } catch {
        try { $body = [string]$MailItem.Body } catch { $body = "" }
    }

    $entryId = ""
    try { $entryId = [string]$MailItem.EntryID } catch { }

    $storeId = ""
    try { $storeId = [string]$MailItem.Parent.StoreID } catch { }

    $internetId = ""
    try { $internetId = Get-QOTOutlookInternetMessageId -MailItem $MailItem } catch { }
    $conversationId = ""
    try { $conversationId = Get-QOTOutlookConversationId -MailItem $MailItem } catch { }

    # Clean up noisy subjects
    $cleanTitle = ($subject + "").Trim()
    if ($cleanTitle) {
        $cleanTitle = $cleanTitle -replace '^(RE|FW|FWD):\s*', ''
        $cleanTitle = $cleanTitle -replace '\*\*DO NOT REPLY\*\*', ''
        $cleanTitle = $cleanTitle.Trim()
    }
    $cleanTitle = Limit-QOTOutlookText -Value $cleanTitle -MaxLength 220
    if ([string]::IsNullOrWhiteSpace($cleanTitle)) {
        $cleanTitle = "(No subject)"
    }

    # Optional: basic priority hints
    $priority = "Medium"
    try {
        if ($cleanTitle -match '(?i)\b(critical|sev[\s\-]?1|p1|outage|system down|major incident)\b') { $priority = "Critical" }
        elseif ($cleanTitle -match '(?i)\b(high|urgent|asap|immediately|sev[\s\-]?2|p2|password|login|access|mfa|2fa|locked)\b') { $priority = "High" }
        elseif ($cleanTitle -match '(?i)\b(low|minor|info|question|sev[\s\-]?4|p4)\b') { $priority = "Low" }
    } catch { }
    try {
        $importance = [int]$MailItem.Importance
        if ($importance -ge 2 -and $priority -ne "Critical") { $priority = "High" }
        elseif ($importance -le 0 -and $priority -eq "Medium") { $priority = "Low" }
    } catch { }

    $createdStr = $received.ToString("yyyy-MM-dd HH:mm:ss")
    try {
        Write-QOTOutlookSyncLog ("Email import body detected. Subject='{0}'; PlainLength={1}; HtmlLength={2}; ChosenLength={3}; Source={4}" -f `
            $cleanTitle, `
            $plainBodyLength, `
            $htmlBodyLength, `
            ([string]($body + "")).Length, `
            $bodySource)
    } catch { }

    return [pscustomobject]@{
        Id              = ([guid]::NewGuid().ToString())

        Title           = $cleanTitle
        TicketName      = $cleanTitle
        Subject         = $subject
        Created         = $createdStr
        CreatedAt       = $createdStr
        UpdatedAt       = $createdStr
        Status          = "New"
        Priority        = $priority

        Source          = "Outlook"
        SourceMailbox   = $MailboxAddress
        SourceMessageId = $entryId
        SourceStoreId   = $storeId
        EmailMessageId  = $internetId
        EmailConversationId = $conversationId

        EmailFrom       = if ($from) { $from } else { "Unknown sender" }
        SenderName      = $senderName
        SenderEmail     = $senderEmail
        EmailTo         = $MailboxAddress
        EmailReceived   = $createdStr
        EmailBody       = $body
        IncomingMessages = @()
        Notes           = @()
        Replies         = @()
    }
}

function Update-QOTExistingTicketFromMailItem {
    param(
        [Parameter(Mandatory)][AllowNull()]$ExistingTicket,
        [Parameter(Mandatory)][AllowNull()]$IncomingTicket
    )

    if (-not $ExistingTicket -or -not $IncomingTicket) { return $false }

    $changed = $false
    $incomingUpdatedAt = ""
    try { $incomingUpdatedAt = ([string]($IncomingTicket.UpdatedAt + "")).Trim() } catch { $incomingUpdatedAt = "" }

    $setValue = {
        param(
            [string]$PropertyName,
            [AllowNull()]$NewValue,
            [switch]$ReplaceIfBlank,
            [switch]$AlwaysReplace
        )

        $existingValue = $null
        $hasProperty = $ExistingTicket.PSObject.Properties.Name -contains $PropertyName
        if ($hasProperty) {
            try { $existingValue = $ExistingTicket.$PropertyName } catch { $existingValue = $null }
        }

        $existingText = ([string]($existingValue + "")).Trim()
        $newText = ([string]($NewValue + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($newText)) { return }

        $shouldApply = $false
        if ($AlwaysReplace) {
            if ($existingText -ne $newText) { $shouldApply = $true }
        } elseif ($ReplaceIfBlank) {
            if ([string]::IsNullOrWhiteSpace($existingText)) { $shouldApply = $true }
        }

        if (-not $shouldApply) { return }

        if ($hasProperty) {
            try { $ExistingTicket.$PropertyName = $NewValue } catch { return }
        } else {
            try { $ExistingTicket | Add-Member -NotePropertyName $PropertyName -NotePropertyValue $NewValue -Force } catch { return }
        }
        $script:__qotExistingTicketUpdated = $true
    }.GetNewClosure()

    $script:__qotExistingTicketUpdated = $false

    & $setValue -PropertyName "Source" -NewValue "Outlook" -ReplaceIfBlank
    & $setValue -PropertyName "SourceMailbox" -NewValue $IncomingTicket.SourceMailbox -ReplaceIfBlank
    & $setValue -PropertyName "SourceMessageId" -NewValue $IncomingTicket.SourceMessageId -ReplaceIfBlank
    & $setValue -PropertyName "SourceStoreId" -NewValue $IncomingTicket.SourceStoreId -ReplaceIfBlank
    & $setValue -PropertyName "EmailMessageId" -NewValue $IncomingTicket.EmailMessageId -ReplaceIfBlank
    & $setValue -PropertyName "EmailConversationId" -NewValue $IncomingTicket.EmailConversationId -ReplaceIfBlank
    & $setValue -PropertyName "SenderName" -NewValue $IncomingTicket.SenderName -AlwaysReplace
    & $setValue -PropertyName "SenderEmail" -NewValue $IncomingTicket.SenderEmail -AlwaysReplace
    & $setValue -PropertyName "EmailFrom" -NewValue $IncomingTicket.EmailFrom -AlwaysReplace
    & $setValue -PropertyName "EmailReceived" -NewValue $IncomingTicket.EmailReceived -ReplaceIfBlank
    & $setValue -PropertyName "Subject" -NewValue $IncomingTicket.Subject -ReplaceIfBlank
    & $setValue -PropertyName "Created" -NewValue $IncomingTicket.Created -ReplaceIfBlank
    & $setValue -PropertyName "CreatedAt" -NewValue $IncomingTicket.CreatedAt -ReplaceIfBlank
    & $setValue -PropertyName "EmailBodyPreview" -NewValue $IncomingTicket.EmailBodyPreview -ReplaceIfBlank

    $existingBodyPath = ""
    try {
        if ($ExistingTicket.PSObject.Properties.Name -contains "EmailBodyPath") {
            $existingBodyPath = ([string]($ExistingTicket.EmailBodyPath + "")).Trim()
        }
    } catch { $existingBodyPath = "" }
    if (-not [string]::IsNullOrWhiteSpace($existingBodyPath)) {
        try {
            if (-not (Test-Path -LiteralPath $existingBodyPath)) {
                $existingBodyPath = ""
            }
        } catch { $existingBodyPath = "" }
    }

    $existingBody = ""
    try {
        if ($ExistingTicket.PSObject.Properties.Name -contains "EmailBody") {
            $existingBody = [string]$ExistingTicket.EmailBody
        }
    } catch { $existingBody = "" }

    $incomingBody = ""
    try {
        if ($IncomingTicket.PSObject.Properties.Name -contains "EmailBody") {
            $incomingBody = [string]$IncomingTicket.EmailBody
        }
    } catch { $incomingBody = "" }

    if (-not [string]::IsNullOrWhiteSpace($incomingBody) -and
        [string]::IsNullOrWhiteSpace($existingBody) -and
        [string]::IsNullOrWhiteSpace($existingBodyPath)) {
        if ($ExistingTicket.PSObject.Properties.Name -contains "EmailBody") {
            try { $ExistingTicket.EmailBody = $incomingBody; $script:__qotExistingTicketUpdated = $true } catch { }
        } else {
            try { $ExistingTicket | Add-Member -NotePropertyName EmailBody -NotePropertyValue $incomingBody -Force; $script:__qotExistingTicketUpdated = $true } catch { }
        }
    }

    $incomingMessageId = ""
    $incomingSourceId = ""
    $existingMainMessageId = ""
    $existingMainSourceId = ""
    try { if ($IncomingTicket.PSObject.Properties.Name -contains "EmailMessageId") { $incomingMessageId = Normalize-QOTInternetMessageId -Value ([string]$IncomingTicket.EmailMessageId) } } catch { }
    try { if ($IncomingTicket.PSObject.Properties.Name -contains "SourceMessageId") { $incomingSourceId = ([string]($IncomingTicket.SourceMessageId + "")).Trim().ToLowerInvariant() } } catch { }
    try { if ($ExistingTicket.PSObject.Properties.Name -contains "EmailMessageId") { $existingMainMessageId = Normalize-QOTInternetMessageId -Value ([string]$ExistingTicket.EmailMessageId) } } catch { }
    try { if ($ExistingTicket.PSObject.Properties.Name -contains "SourceMessageId") { $existingMainSourceId = ([string]($ExistingTicket.SourceMessageId + "")).Trim().ToLowerInvariant() } } catch { }

    $isExistingMainEmail = $false
    if (-not [string]::IsNullOrWhiteSpace($incomingMessageId) -and $incomingMessageId -eq $existingMainMessageId) { $isExistingMainEmail = $true }
    if (-not [string]::IsNullOrWhiteSpace($incomingSourceId) -and $incomingSourceId -eq $existingMainSourceId) { $isExistingMainEmail = $true }

    if (-not $isExistingMainEmail -and -not [string]::IsNullOrWhiteSpace($incomingBody)) {
        $incomingMessages = @()
        try {
            if ($ExistingTicket.PSObject.Properties.Name -contains "IncomingMessages") {
                $incomingMessages = @($ExistingTicket.IncomingMessages)
            }
        } catch { $incomingMessages = @() }

        $alreadyAttached = $false
        foreach ($message in $incomingMessages) {
            if (-not $message) { continue }
            $existingMessageId = ""
            $existingSourceId = ""
            try { if ($message.PSObject.Properties.Name -contains "EmailMessageId") { $existingMessageId = Normalize-QOTInternetMessageId -Value ([string]$message.EmailMessageId) } } catch { }
            try { if ($message.PSObject.Properties.Name -contains "SourceMessageId") { $existingSourceId = ([string]($message.SourceMessageId + "")).Trim().ToLowerInvariant() } } catch { }

            if (-not [string]::IsNullOrWhiteSpace($incomingMessageId) -and $incomingMessageId -eq $existingMessageId) {
                $alreadyAttached = $true
                break
            }
            if (-not [string]::IsNullOrWhiteSpace($incomingSourceId) -and $incomingSourceId -eq $existingSourceId) {
                $alreadyAttached = $true
                break
            }
        }

        if (-not $alreadyAttached) {
            $incomingMessages = @($incomingMessages) + @([pscustomobject]@{
                Subject             = $IncomingTicket.Subject
                Body                = $incomingBody
                CreatedAt           = $IncomingTicket.CreatedAt
                From                = $IncomingTicket.EmailFrom
                SenderName          = $IncomingTicket.SenderName
                SenderEmail         = $IncomingTicket.SenderEmail
                SourceMailbox       = $IncomingTicket.SourceMailbox
                SourceMessageId     = $IncomingTicket.SourceMessageId
                SourceStoreId       = $IncomingTicket.SourceStoreId
                EmailMessageId      = $IncomingTicket.EmailMessageId
                EmailConversationId = $IncomingTicket.EmailConversationId
            })

            if ($ExistingTicket.PSObject.Properties.Name -contains "IncomingMessages") {
                try { $ExistingTicket.IncomingMessages = @($incomingMessages); $script:__qotExistingTicketUpdated = $true } catch { }
            } else {
                try { $ExistingTicket | Add-Member -NotePropertyName IncomingMessages -NotePropertyValue @($incomingMessages) -Force; $script:__qotExistingTicketUpdated = $true } catch { }
            }
        }
    }

    $changed = [bool]$script:__qotExistingTicketUpdated
    Remove-Variable -Scope Script -Name __qotExistingTicketUpdated -ErrorAction SilentlyContinue

    if ($changed -and -not [string]::IsNullOrWhiteSpace($incomingUpdatedAt)) {
        if ($ExistingTicket.PSObject.Properties.Name -contains "UpdatedAt") {
            try { $ExistingTicket.UpdatedAt = $incomingUpdatedAt } catch { }
        } else {
            try { $ExistingTicket | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue $incomingUpdatedAt -Force } catch { }
        }
    }

    try {
        $bodyLengthForLog = 0
        $bodyPathForLog = ""
        $previewLengthForLog = 0
        try { if ($ExistingTicket.PSObject.Properties.Name -contains "EmailBody") { $bodyLengthForLog = ([string]($ExistingTicket.EmailBody + "")).Length } } catch { $bodyLengthForLog = 0 }
        try { if ($ExistingTicket.PSObject.Properties.Name -contains "EmailBodyPath") { $bodyPathForLog = ([string]($ExistingTicket.EmailBodyPath + "")).Trim() } } catch { $bodyPathForLog = "" }
        try { if ($ExistingTicket.PSObject.Properties.Name -contains "EmailBodyPreview") { $previewLengthForLog = ([string]($ExistingTicket.EmailBodyPreview + "")).Length } } catch { $previewLengthForLog = 0 }
        Write-QOTOutlookSyncLog ("Ticket save body prepared. TicketId={0}; Subject='{1}'; InlineLength={2}; PreviewLength={3}; HasBodyPath={4}; Updated={5}" -f `
            ([string]($ExistingTicket.Id + "")).Trim(), `
            ([string]($ExistingTicket.Subject + "")).Trim(), `
            $bodyLengthForLog, `
            $previewLengthForLog, `
            $(if (-not [string]::IsNullOrWhiteSpace($bodyPathForLog)) { "Yes" } else { "No" }), `
            $changed)
    } catch { }

    return $changed
}

function Resolve-QOTOutlookContactInfoForTicket {
    param(
        [Parameter(Mandatory)][AllowNull()]$Ticket
    )

    if (-not $Ticket) { return $null }

    $mapi = $null
    try { $mapi = Get-QOTOutlookNamespace -AllowStartOutlook:$false } catch { $mapi = $null }
    if (-not $mapi) { return $null }

    $sourceId = ""
    $storeId = ""
    $internetId = ""
    try { if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") { $sourceId = ([string]($Ticket.SourceMessageId + "")).Trim() } } catch { $sourceId = "" }
    try { if ($Ticket.PSObject.Properties.Name -contains "SourceStoreId") { $storeId = ([string]($Ticket.SourceStoreId + "")).Trim() } } catch { $storeId = "" }
    try { if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") { $internetId = Normalize-QOTInternetMessageId -Value ([string]$Ticket.EmailMessageId) } } catch { $internetId = "" }

    $mailItem = $null

    if (-not [string]::IsNullOrWhiteSpace($sourceId) -and ($sourceId -notmatch '@')) {
        try {
            if (-not [string]::IsNullOrWhiteSpace($storeId)) {
                $mailItem = $mapi.GetItemFromID($sourceId, $storeId)
            } else {
                $mailItem = $mapi.GetItemFromID($sourceId)
            }
        } catch { $mailItem = $null }
    }

    if (-not $mailItem -and -not [string]::IsNullOrWhiteSpace($internetId)) {
        try { $mailItem = Find-QOTOutlookMessageByInternetId -MAPI $mapi -InternetMessageId $internetId -MaxScan 250 } catch { $mailItem = $null }
    }

    if (-not $mailItem) { return $null }

    try {
        $senderInfo = Get-QOTOutlookSenderInfo -MailItem $mailItem
        if ($senderInfo -and (
                -not [string]::IsNullOrWhiteSpace([string]$senderInfo.SenderName) -or
                -not [string]::IsNullOrWhiteSpace([string]$senderInfo.SenderEmail) -or
                -not [string]::IsNullOrWhiteSpace([string]$senderInfo.DisplayFrom)
            )) {
            return $senderInfo
        }
    } catch { }

    return $null
}

function Sync-QOTicketsFromOutlook {
    param(
        [int]$MaxPerMailbox = 200,
        [switch]$MarkAsRead,
        [switch]$AllowStartOutlook,
        [string]$ProcessedCategory = "QOT Imported"
    )

    Initialize-QOTicketsCoreApi
    $mailboxes = @(Get-QOTEffectiveMonitoredMailboxAddresses -AllowStartOutlook:$AllowStartOutlook -PersistWhenSingle)
    if (-not $mailboxes -or $mailboxes.Count -eq 0) {
        $note = "No monitored mailbox addresses set. Add one in Settings, or sign in to a single Outlook mailbox so QOT can auto-detect it."
        Write-QOTOutlookSyncLog $note "WARN"
        return [pscustomobject]@{ Success = $false; Added = 0; Note = $note }
    }

    Write-QOTOutlookSyncLog ("Starting sync. Mailboxes={0}; MaxPerMailbox={1}; AllowStartOutlook={2}" -f @($mailboxes).Count, $MaxPerMailbox, [bool]$AllowStartOutlook)

    $existingDb  = Get-QOTickets
    $existingIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $existingTicketByIdentity = @{}

    foreach ($t in @($existingDb.Tickets)) {
        try {
            foreach ($identityKey in @(Get-QOTTicketIdentityKeys -Ticket $t)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$identityKey)) {
                    [void]$existingIds.Add([string]$identityKey)
                    if (-not $existingTicketByIdentity.ContainsKey([string]$identityKey)) {
                        $existingTicketByIdentity[[string]$identityKey] = $t
                    }
                }
            }
        } catch { }
    }

    $lastSyncUtc  = Get-QOTLastEmailSyncUtc
    $cutoffUtc    = Get-QOTEffectiveEmailCutoffUtc -LastSyncUtc $lastSyncUtc
    $syncStartedAtUtc = (Get-Date).ToUniversalTime()

    # Background sync keeps this disabled so periodic polls fail fast.
    # Startup paths can opt in to launch Outlook and hydrate tickets before the UI opens.
    $mapi  = Get-QOTOutlookNamespace -AllowStartOutlook:$AllowStartOutlook
    Write-QOTOutlookSyncLog "Outlook namespace resolved."
    $added = 0
    $addedTickets = @()
    $mailboxNotes = @()
    $canAdvanceWatermark = $true
    $mailboxSuccessCount = 0
    $mailboxFailureCount = 0
    $updated = 0
    
    foreach ($mb in $mailboxes) {
        $mbValue = ([string]($mb + "")).Trim()
        if ([string]::IsNullOrWhiteSpace($mbValue)) { continue }
        $inbox = $null
        try {
            $inbox = Get-QOTMailboxInboxFolder -MAPI $mapi -MailboxAddress $mbValue
        } catch {
            $mailboxNotes += @("Mailbox '$mbValue' failed: $($_.Exception.Message)")
            $canAdvanceWatermark = $false
            $mailboxFailureCount++
            continue
        }

        $items = $inbox.Items
        try { $items.Sort("[ReceivedTime]", $true) } catch { }

        # We intentionally avoid Outlook Restrict date strings (locale-sensitive).
        # Filter by ReceivedTime in PowerShell after sorting newest-first.

        $count = 0
        $scanned = 0
        $skippedExisting = 0
        # Large cap so backlog imports from pinned start date can progress reliably
        # even when newest items are already imported.
        $scanLimit = 100000
        $hitMailboxCap = $false
        $reachedCutoff = $false
        $hitScanLimit = $true

        for ($idx = 1; $idx -le $scanLimit; $idx++) {
            if ($count -ge $MaxPerMailbox) {
                $hitMailboxCap = $true
                break
            }

            $item = $null
            try { $item = $items.Item($idx) } catch { $item = $null }
            if ($null -eq $item) {
                $hitScanLimit = $false
                $reachedCutoff = $true
                break
            }

            $scanned++

            $isMail = $false
            try { $isMail = ($item.MessageClass -like "IPM.Note*") } catch { }
            if (-not $isMail) { continue }

            # Items are sorted newest-first; once below cutoff we can stop.
            $receivedUtc = $null
            try {
                $receivedUtc = ([datetime]$item.ReceivedTime).ToUniversalTime()
            } catch { $receivedUtc = $null }

            if ($receivedUtc -and ($receivedUtc -lt $cutoffUtc)) {
                $hitScanLimit = $false
                $reachedCutoff = $true
                break
            }

            $categories = ""
            try { $categories = [string]$item.Categories } catch { }

            $ticket = Convert-QOTMailItemToTicket -MailboxAddress $mbValue -MailItem $item
            $ticketIdentityKeys = @(Get-QOTTicketIdentityKeys -Ticket $ticket)
            if ($ticketIdentityKeys.Count -eq 0) { continue }

            $alreadyImported = $false
            $matchedTicket = $null
            foreach ($k in $ticketIdentityKeys) {
                if ($existingIds.Contains([string]$k)) {
                    $alreadyImported = $true
                    if (-not $matchedTicket -and $existingTicketByIdentity.ContainsKey([string]$k)) {
                        $matchedTicket = $existingTicketByIdentity[[string]$k]
                    }
                    break
                }
            }

            if ($alreadyImported) {
                if ($matchedTicket) {
                    try {
                        if (Update-QOTExistingTicketFromMailItem -ExistingTicket $matchedTicket -IncomingTicket $ticket) {
                            $updated++
                        }
                        foreach ($k in $ticketIdentityKeys) {
                            if (-not [string]::IsNullOrWhiteSpace([string]$k)) {
                                [void]$existingIds.Add([string]$k)
                                if (-not $existingTicketByIdentity.ContainsKey([string]$k)) {
                                    $existingTicketByIdentity[[string]$k] = $matchedTicket
                                }
                            }
                        }
                    } catch {
                        Write-QOTOutlookSyncLog ("Existing ticket refresh failed for mailbox '{0}': {1}" -f $mbValue, $_.Exception.Message) "WARN"
                    }
                }
                $skippedExisting++
                continue
            }

            $addedTickets += @($ticket)
            foreach ($k in $ticketIdentityKeys) {
                if (-not [string]::IsNullOrWhiteSpace([string]$k)) {
                    [void]$existingIds.Add([string]$k)
                    if (-not $existingTicketByIdentity.ContainsKey([string]$k)) {
                        $existingTicketByIdentity[[string]$k] = $ticket
                    }
                }
            }

            try {
                if ($ProcessedCategory) {
                    if ($categories) { $item.Categories = ($categories + "; " + $ProcessedCategory) } else { $item.Categories = $ProcessedCategory }
                }
                if ($MarkAsRead) { $item.UnRead = $false }
                $item.Save() | Out-Null
            } catch { }

            $added++
            $count++
        }

        $mailboxNotes += @("Mailbox '$mbValue': scanned=$scanned added=$count updated=$updated skippedExisting=$skippedExisting")
        $mailboxSuccessCount++

        if ($hitMailboxCap) {
            $canAdvanceWatermark = $false
            $mailboxNotes += @("Mailbox '$mbValue': holding watermark (batch cap reached).")
        } elseif ($hitScanLimit -and (-not $reachedCutoff)) {
            $canAdvanceWatermark = $false
            $mailboxNotes += @("Mailbox '$mbValue': holding watermark (scan limit reached).")
        }
    }

    if ($addedTickets.Count -gt 0 -or $updated -gt 0) {
        $existingDb.Tickets = @($existingDb.Tickets) + @($addedTickets)
        Save-QOTickets -Database $existingDb
    }
    
    $overallSuccess = $true
    if (($mailboxSuccessCount -le 0) -and ($mailboxFailureCount -gt 0)) {
        $overallSuccess = $false
    }

    $completedAtUtc = (Get-Date).ToUniversalTime()
    $nextWatermarkUtc = $syncStartedAtUtc.AddSeconds(-30)
    if ($nextWatermarkUtc -lt $cutoffUtc) {
        $nextWatermarkUtc = $cutoffUtc
    }

    # Persist a real "last successful run" timestamp even when the watermark is intentionally held.
    if ($overallSuccess) {
        Set-QOTLastSuccessfulEmailSyncUtc -UtcTime $completedAtUtc
    }

    # Only update watermark when all mailboxes fully progressed past cutoff in this pass.
    if ($canAdvanceWatermark) {
        Set-QOTLastEmailSyncUtc -UtcTime $nextWatermarkUtc
    }

    $summaryNote = ("Sync complete. Success=" + [string][bool]$overallSuccess + " WatermarkAdvanced=" + [string][bool]$canAdvanceWatermark + " CutoffUtc=" + $cutoffUtc.ToString("o") + " LastSyncUtcWas=" + $lastSyncUtc.ToString("o") + " NextWatermarkUtc=" + $nextWatermarkUtc.ToString("o") + " MailboxesOk=" + $mailboxSuccessCount + " MailboxesFailed=" + $mailboxFailureCount + " | " + ($mailboxNotes -join " ; "))
    $summaryLevel = if ($overallSuccess) { "INFO" } else { "WARN" }
    Write-QOTOutlookSyncLog ("Finished sync. Added={0} Updated={1}. {2}" -f $added, $updated, $summaryNote) $summaryLevel

    return [pscustomobject]@{
        Success     = [bool]$overallSuccess
        Added       = $added
        Updated     = $updated
        AddedTickets = @($addedTickets)
        WatermarkAdvanced = [bool]$canAdvanceWatermark
        Note        = $summaryNote
    }
}

function Find-QOTOutlookMessageByInternetId {
    param(
        [Parameter(Mandatory)][object]$MAPI,
        [Parameter(Mandatory)][string]$InternetMessageId,
        [int]$MaxScan = 250
    )

    $mailboxes = Get-QOTMonitoredMailboxAddresses
    if (-not $mailboxes -or $mailboxes.Count -eq 0) { return $null }

    foreach ($mb in $mailboxes) {
        $inbox = $null
        try { $inbox = Get-QOTMailboxInboxFolder -MAPI $MAPI -MailboxAddress $mb } catch { $inbox = $null }
        if (-not $inbox) { continue }

        $items = $inbox.Items
        try { $items.Sort("[ReceivedTime]", $true) } catch { }

        $count = 0
        foreach ($item in @($items)) {
            if ($count -ge $MaxScan) { break }
            $isMail = $false
            try { $isMail = ($item.MessageClass -like "IPM.Note*") } catch { }
            if (-not $isMail) { continue }

            $internetId = ""
            try {
                $internetId = [string]$item.PropertyAccessor.GetProperty(
                    "http://schemas.microsoft.com/mapi/string/{00020386-0000-0000-C000-000000000046}/InternetMessageId"
                )
            } catch { }

            if ($internetId -and ($internetId -eq $InternetMessageId)) {
                return $item
            }

            $count++
        }
    }

    return $null
}

function Send-QOTicketOutlookEmail {
    param(
        [Parameter(Mandatory)][string]$To,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [AllowNull()][string]$FromMailbox,
        [AllowNull()][string]$TicketId
    )

    Initialize-QOTicketsCoreApi

    $toValue = ([string]$To).Trim()
    $subjectValue = ([string]$Subject).Trim()
    $bodyValue = ([string]$Body).Trim()
    $senderMailbox = ([string]($FromMailbox + "")).Trim()

    if ([string]::IsNullOrWhiteSpace($toValue)) {
        return [pscustomobject]@{ Success = $false; Note = "Recipient email address required." }
    }
    if ([string]::IsNullOrWhiteSpace($subjectValue)) {
        return [pscustomobject]@{ Success = $false; Note = "Email subject required." }
    }
    if ([string]::IsNullOrWhiteSpace($bodyValue)) {
        return [pscustomobject]@{ Success = $false; Note = "Email body required." }
    }

    $mapi = $null
    try {
        $mapi = Get-QOTOutlookNamespace -AllowStartOutlook:$false
    } catch {
        $firstFailureNote = ([string]$_.Exception.Message).Trim()
        try {
            Write-QOTOutlookSyncLog ("New email attach failed without startup assist, retrying with Outlook launch enabled. " + $firstFailureNote) "WARN"
        } catch { }

        try {
            $mapi = Get-QOTOutlookNamespace -AllowStartOutlook:$true
        } catch {
            $note = ([string]$_.Exception.Message).Trim()
            if ([string]::IsNullOrWhiteSpace($note)) {
                $note = $firstFailureNote
            }
            if ([string]::IsNullOrWhiteSpace($note)) {
                $note = "Unable to access Classic Outlook."
            }
            return [pscustomobject]@{
                Success = $false
                Note    = ("Unable to send email: {0}" -f $note)
            }
        }
    }

    $outlook = $null
    try {
        $outlook = Get-QOTOutlookApplication -MAPI $mapi
    } catch {
        return [pscustomobject]@{
            Success = $false
            Note    = ("Unable to create Outlook email item: " + $_.Exception.Message)
        }
    }

    if ([string]::IsNullOrWhiteSpace($senderMailbox)) {
        $effectiveMailboxes = @(Get-QOTEffectiveMonitoredMailboxAddresses -MAPI $mapi -PersistWhenSingle)
        if ($effectiveMailboxes.Count -eq 1) {
            $senderMailbox = ([string]$effectiveMailboxes[0]).Trim()
        }
    }

    try {
        Write-QOTOutlookSyncLog ("Preparing new Outlook email to " + $toValue)
        $mail = $outlook.CreateItem(0)
        $mail.To = $toValue
        $mail.Subject = $subjectValue

        if (-not [string]::IsNullOrWhiteSpace($senderMailbox)) {
            $null = Set-QOTOutlookMailSender -MailItem $mail -MAPI $mapi -MailboxAddress $senderMailbox
        }

        $sentConversationId = ""
        $sentEntryId = ""
        $sentStoreId = ""
        try { $mail.BodyFormat = 1 } catch { }
        $mail.Body = $bodyValue

        Write-QOTOutlookSyncLog "Sending new Outlook email item."
        $mail.Send()
        try { $sentConversationId = Get-QOTOutlookConversationId -MailItem $mail } catch { }
        try { $sentEntryId = ([string]($mail.EntryID + "")).Trim() } catch { }
        try { $sentStoreId = ([string]($mail.Parent.StoreID + "")).Trim() } catch { }
        Write-QOTOutlookSyncLog "Outlook email Send() returned control to toolkit."
    } catch {
        return [pscustomobject]@{
            Success = $false
            Note    = ("Email send failed: " + $_.Exception.Message)
        }
    }

    return [pscustomobject]@{
        Success        = $true
        Note           = "Email sent."
        ConversationId = $sentConversationId
        SentEntryId    = $sentEntryId
        SentStoreId    = $sentStoreId
        TicketId       = ([string]($TicketId + "")).Trim()
    }
}

function Invoke-QOTOutlookReplySendAttempt {
    param(
        [Parameter(Mandatory)]$MailItem,
        [Parameter(Mandatory)][object]$MAPI,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [AllowNull()][string]$SenderMailbox,
        [switch]$PlainTextOnly
    )

    $reply = $MailItem.Reply()
    if (-not $reply) {
        throw "Outlook did not return a reply item."
    }

    if (-not [string]::IsNullOrWhiteSpace($Subject)) {
        try { $reply.Subject = $Subject } catch { }
    }

    $usedHtml = $false
    if (-not $PlainTextOnly) {
        try { $reply.BodyFormat = 2 } catch { }

        $existingReplyHtml = ""
        try { $existingReplyHtml = [string]($reply.HTMLBody + "") } catch { $existingReplyHtml = "" }

        if (-not [string]::IsNullOrWhiteSpace($existingReplyHtml)) {
            $newReplyHtml = Convert-QOTPlainTextToHtml -Text $Body
            $reply.HTMLBody = ($newReplyHtml + "<br/>" + $existingReplyHtml)
            $usedHtml = $true
            Write-QOTOutlookSyncLog "Reply composed in HTML mode (preserving Outlook signature/thread)."
        }
    }

    if (-not $usedHtml) {
        $existingReplyBody = ""
        try { $existingReplyBody = [string]($reply.Body + "") } catch { $existingReplyBody = "" }
        $reply.Body = $Body + "`r`n`r`n" + $existingReplyBody
        if ($PlainTextOnly) {
            Write-QOTOutlookSyncLog "Reply composed in plain-text retry mode."
        } else {
            Write-QOTOutlookSyncLog "Reply composed in plain-text fallback mode."
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($SenderMailbox)) {
        $null = Set-QOTOutlookMailSender -MailItem $reply -MAPI $MAPI -MailboxAddress $SenderMailbox
    }

    Write-QOTOutlookSyncLog "Sending Outlook reply item."
    $reply.Send()
    Write-QOTOutlookSyncLog "Outlook reply Send() returned control to toolkit."

    $sentConversationId = ""
    $sentEntryId = ""
    $sentStoreId = ""
    try { $sentConversationId = Get-QOTOutlookConversationId -MailItem $reply } catch { }
    try { $sentEntryId = ([string]($reply.EntryID + "")).Trim() } catch { }
    try { $sentStoreId = ([string]($reply.Parent.StoreID + "")).Trim() } catch { }

    return [pscustomobject]@{
        ConversationId = $sentConversationId
        SentEntryId    = $sentEntryId
        SentStoreId    = $sentStoreId
    }
}

function Send-QOTicketOutlookReply {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body,
        [AllowNull()][string]$FromMailbox,
        [AllowNull()][string]$TicketId
    )

    Initialize-QOTicketsCoreApi

    $subjectValue = ([string]$Subject).Trim()
    $bodyValue = ([string]$Body).Trim()
    $senderMailbox = Get-QOTPreferredSenderMailbox -Ticket $Ticket -FromMailbox $FromMailbox

    if ([string]::IsNullOrWhiteSpace($subjectValue)) {
        return [pscustomobject]@{ Success = $false; Note = "Reply subject required." }
    }
    if ([string]::IsNullOrWhiteSpace($bodyValue)) {
        return [pscustomobject]@{ Success = $false; Note = "Reply body required." }
    }

    $mapi = $null
    try {
        # Prefer an already-running Outlook instance first so replies feel instant when COM is warm.
        $mapi = Get-QOTOutlookNamespace -AllowStartOutlook:$false
    } catch {
        $firstFailureNote = ([string]$_.Exception.Message).Trim()
        try {
            Write-QOTOutlookSyncLog ("Reply attach failed without startup assist, retrying with Outlook launch enabled. " + $firstFailureNote) "WARN"
        } catch { }

        try {
            $mapi = Get-QOTOutlookNamespace -AllowStartOutlook:$true
        } catch {
            $note = ([string]$_.Exception.Message).Trim()
            if ([string]::IsNullOrWhiteSpace($note)) {
                $note = $firstFailureNote
            }
            if ([string]::IsNullOrWhiteSpace($note)) {
                $note = "Unable to access Classic Outlook."
            }
            return [pscustomobject]@{
                Success = $false
                Note    = ("Unable to send reply: {0}" -f $note)
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($senderMailbox)) {
        $effectiveMailboxes = @(Get-QOTEffectiveMonitoredMailboxAddresses -MAPI $mapi -PersistWhenSingle)
        if ($effectiveMailboxes.Count -eq 1) {
            $senderMailbox = ([string]$effectiveMailboxes[0]).Trim()
        }
    }

    $sourceId = ""
    $storeId = ""
    try {
        if ($Ticket.PSObject.Properties.Name -contains "SourceMessageId") {
            $sourceId = [string]$Ticket.SourceMessageId
        }
    } catch { }
    try {
        if ($Ticket.PSObject.Properties.Name -contains "SourceStoreId") {
            $storeId = [string]$Ticket.SourceStoreId
        }
    } catch { }

    $mailItem = $null
    if ($sourceId) {
        try {
            if ($storeId) {
                $mailItem = $mapi.GetItemFromID($sourceId, $storeId)
            } else {
                $mailItem = $mapi.GetItemFromID($sourceId)
            }
        } catch { $mailItem = $null }
    }

    if (-not $mailItem) {
        $internetId = ""
        try {
            if ($Ticket.PSObject.Properties.Name -contains "EmailMessageId") {
                $internetId = [string]$Ticket.EmailMessageId
            }
        } catch { }

        if ($internetId) {
            $mailItem = Find-QOTOutlookMessageByInternetId -MAPI $mapi -InternetMessageId $internetId
        }
    }

    if (-not $mailItem) {
        return [pscustomobject]@{
            Success = $false
            Note    = "Original email not found in Outlook."
        }
    }

    try {
        Write-QOTOutlookSyncLog "Preparing Outlook reply item."
        $sendResult = Invoke-QOTOutlookReplySendAttempt -MailItem $mailItem -MAPI $mapi -Subject $subjectValue -Body $bodyValue -SenderMailbox $senderMailbox
        $sentConversationId = $sendResult.ConversationId
        $sentEntryId = $sendResult.SentEntryId
        $sentStoreId = $sendResult.SentStoreId
    } catch {
        $primaryFailureNote = ([string]$_.Exception.Message).Trim()
        $shouldRetryPlainText = $false
        if (-not [string]::IsNullOrWhiteSpace($primaryFailureNote)) {
            $shouldRetryPlainText = ($primaryFailureNote -match "Value does not fall within the expected range")
        }

        if ($shouldRetryPlainText) {
            try {
                Write-QOTOutlookSyncLog ("Reply send failed in rich mode, retrying with a simpler draft. " + $primaryFailureNote) "WARN"
            } catch { }

            try {
                $sendResult = Invoke-QOTOutlookReplySendAttempt -MailItem $mailItem -MAPI $mapi -Subject $subjectValue -Body $bodyValue -SenderMailbox $senderMailbox -PlainTextOnly
                $sentConversationId = $sendResult.ConversationId
                $sentEntryId = $sendResult.SentEntryId
                $sentStoreId = $sendResult.SentStoreId
            } catch {
                $retryFailureNote = ([string]$_.Exception.Message).Trim()
                if ([string]::IsNullOrWhiteSpace($retryFailureNote)) {
                    $retryFailureNote = $primaryFailureNote
                }
                return [pscustomobject]@{
                    Success = $false
                    Note    = ("Reply failed: " + $retryFailureNote)
                }
            }
        } else {
            return [pscustomobject]@{
                Success = $false
                Note    = ("Reply failed: " + $primaryFailureNote)
            }
        }
    }

    return [pscustomobject]@{
        Success        = $true
        Note           = "Reply sent."
        ConversationId = $sentConversationId
        SentEntryId    = $sentEntryId
        SentStoreId    = $sentStoreId
        TicketId       = ([string]($TicketId + "")).Trim()
    }
}

Export-ModuleMember -Function Sync-QOTicketsFromOutlook, Send-QOTicketOutlookReply, Send-QOTicketOutlookEmail, Resolve-QOTOutlookContactInfoForTicket

