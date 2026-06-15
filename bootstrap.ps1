param(
    [string]$Branch = "main",
    [switch]$VerboseStartup,
    [switch]$ForceRemote,
    [switch]$ForceRefresh
)

# bootstrap.ps1
# Remote bootstrap for:
#   irm "https://raw.githubusercontent.com/VoIyboo/Windows-Optimiser-Toolkit/main/bootstrap.ps1" | iex
#
# Behaviour:
# - If a local installed copy exists, check GitHub for updates, then run it.
# - If no local installed copy exists, download the current GitHub copy, install it, then run it.
# - If GitHub cannot be reached but a local installed copy exists, run the installed copy anyway.

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$originalLocation = Get-Location

function Invoke-QOTWebRequestToFile {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$OutFile
    )

    $requestParams = @{
        Uri     = $Uri
        OutFile = $OutFile
        Headers = @{
            "User-Agent" = "QuinnOptimiserToolkit-Bootstrap/2.0"
            "Accept"     = "application/octet-stream,*/*"
        }
    }

    $iwrCommand = Get-Command Invoke-WebRequest -ErrorAction Stop
    if ($iwrCommand.Parameters.ContainsKey("UseBasicParsing")) {
        $requestParams.UseBasicParsing = $true
    }

    try {
        Invoke-WebRequest @requestParams | Out-Null
        return
    }
    catch {
        $iwrMessage = $_.Exception.Message
        $webClient = $null
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "QuinnOptimiserToolkit-Bootstrap/2.0")
            $webClient.Headers.Add("Accept", "application/octet-stream,*/*")
            $webClient.DownloadFile($Uri, $OutFile)
            return
        }
        catch {
            $wcMessage = $_.Exception.Message
            throw "Invoke-WebRequest failed: $iwrMessage | WebClient fallback failed: $wcMessage"
        }
        finally {
            if ($webClient) { $webClient.Dispose() }
        }
    }
}

function Invoke-QOTWebRequestText {
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [string]$Accept = "application/json"
    )

    $requestParams = @{
        Uri     = $Uri
        Headers = @{
            "User-Agent" = "QuinnOptimiserToolkit-Bootstrap/2.0"
            "Accept"     = $Accept
        }
    }

    $iwrCommand = Get-Command Invoke-WebRequest -ErrorAction Stop
    if ($iwrCommand.Parameters.ContainsKey("UseBasicParsing")) {
        $requestParams.UseBasicParsing = $true
    }

    try {
        $response = Invoke-WebRequest @requestParams
        return [string]$response.Content
    }
    catch {
        $iwrMessage = $_.Exception.Message
        $webClient = $null
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.Headers.Add("User-Agent", "QuinnOptimiserToolkit-Bootstrap/2.0")
            $webClient.Headers.Add("Accept", $Accept)
            return [string]$webClient.DownloadString($Uri)
        }
        catch {
            $wcMessage = $_.Exception.Message
            throw "Invoke-WebRequest failed: $iwrMessage | WebClient fallback failed: $wcMessage"
        }
        finally {
            if ($webClient) { $webClient.Dispose() }
        }
    }
}

function Test-QOTPathWritable {
    param(
        [AllowNull()][string]$Path
    )

    $candidatePath = ([string]($Path + "")).Trim()
    if ([string]::IsNullOrWhiteSpace($candidatePath)) { return $false }

    try {
        if (-not (Test-Path -LiteralPath $candidatePath)) {
            New-Item -ItemType Directory -Path $candidatePath -Force | Out-Null
        }

        $probePath = Join-Path $candidatePath (".qot-write-test-{0}.tmp" -f [guid]::NewGuid().ToString("N"))
        [System.IO.File]::WriteAllText($probePath, "")
        Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
        return $true
    }
    catch {
        return $false
    }
}

function Get-QOTBootstrapLogDir {
    $candidates = @(
        (Join-Path $env:ProgramData "QuinnOptimiserToolkit\Logs"),
        (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit\Logs"),
        (Join-Path $env:TEMP "QuinnOptimiserToolkit\Logs")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (Test-QOTPathWritable -Path $candidate) {
            return $candidate
        }
    }

    throw "Unable to create a writable log directory for bootstrap."
}

function Get-QOTInstallLayout {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "StudioVoly\QuinnToolkit"),
        (Join-Path $env:APPDATA "StudioVoly\QuinnToolkit"),
        (Join-Path $env:USERPROFILE "StudioVoly\QuinnToolkit"),
        (Join-Path $env:TEMP "QuinnOptimiserToolkit")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($candidate in $candidates) {
        if (-not (Test-QOTPathWritable -Path $candidate)) { continue }

        return [pscustomobject]@{
            RootPath       = $candidate
            AppRoot        = Join-Path $candidate "App"
            CurrentRoot    = Join-Path $candidate "App\Current"
            PreviousRoot   = Join-Path $candidate "App\Previous"
            StagingRoot    = Join-Path $candidate "App\Staging"
            DownloadRoot   = Join-Path $candidate "Bootstrap"
            StatePath      = Join-Path $candidate "Bootstrap\install-state.json"
            BootstrapLog   = Join-Path $candidate "Bootstrap"
        }
    }

    throw "Unable to find a writable install root for Quinn Optimiser Toolkit."
}

function Read-QOTInstallState {
    param(
        [Parameter(Mandatory)]
        [string]$StatePath
    )

    if (-not (Test-Path -LiteralPath $StatePath)) { return $null }

    try {
        return (Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
    }
    catch {
        return $null
    }
}

function Write-QOTInstallState {
    param(
        [Parameter(Mandatory)]
        [string]$StatePath,

        [Parameter(Mandatory)]
        $State
    )

    $dir = Split-Path -Parent $StatePath
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $json = $State | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $StatePath -Value $json -Encoding UTF8
}

function Get-QOTLatestRemoteInfo {
    param(
        [Parameter(Mandatory)]
        [string[]]$Owners,

        [Parameter(Mandatory)]
        [string]$RepoName,

        [Parameter(Mandatory)]
        [string]$Branch
    )

    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($owner in $Owners) {
        $apiUrl = "https://api.github.com/repos/$owner/$RepoName/commits/$Branch"
        try {
            $payload = Invoke-QOTWebRequestText -Uri $apiUrl -Accept "application/vnd.github+json"
            $data = $payload | ConvertFrom-Json -ErrorAction Stop

            if (-not $data.sha) {
                throw "GitHub API response did not include a commit SHA."
            }

            return [pscustomobject]@{
                Owner      = $owner
                RepoName   = $RepoName
                Branch     = $Branch
                CommitSha  = [string]$data.sha
                CommitDate = [string]$data.commit.committer.date
                HtmlUrl    = [string]$data.html_url
            }
        }
        catch {
            $errors.Add("$apiUrl => $($_.Exception.Message)") | Out-Null
        }
    }

    throw "Unable to query the latest GitHub commit metadata. Errors: $($errors -join '; ')"
}

function Invoke-QOTDownloadRepoZip {
    param(
        [Parameter(Mandatory)]
        [string[]]$Urls,

        [Parameter(Mandatory)]
        [string]$OutFile,

        [int]$MaxAttemptsPerUrl = 2
    )

    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($url in $Urls) {
        for ($attempt = 1; $attempt -le $MaxAttemptsPerUrl; $attempt++) {
            try {
                if (Test-Path -LiteralPath $OutFile) {
                    Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
                }

                Write-Host ("Trying ({0}/{1}): {2}" -f $attempt, $MaxAttemptsPerUrl, $url)
                Invoke-QOTWebRequestToFile -Uri $url -OutFile $OutFile

                if (-not (Test-Path -LiteralPath $OutFile)) {
                    throw "Download completed but zip file was not created."
                }

                $fileInfo = Get-Item -LiteralPath $OutFile
                if ($fileInfo.Length -lt 1024) {
                    throw "Downloaded file is unexpectedly small ($($fileInfo.Length) bytes)."
                }

                return
            }
            catch {
                $errors.Add("$url (attempt $attempt): $($_.Exception.Message)") | Out-Null
                if ($attempt -lt $MaxAttemptsPerUrl) {
                    Start-Sleep -Milliseconds 500
                }
            }
        }
    }

    throw "Failed to download repository zip. Errors: $($errors -join '; ')"
}

function Find-QOTToolkitRoot {
    param(
        [Parameter(Mandatory)]
        [string]$SearchRoot
    )

    $candidateRoots = New-Object System.Collections.Generic.List[string]
    $candidateRoots.Add($SearchRoot) | Out-Null

    foreach ($directory in (Get-ChildItem -Path $SearchRoot -Directory -Recurse -ErrorAction SilentlyContinue)) {
        $candidateRoots.Add($directory.FullName) | Out-Null
    }

    foreach ($candidateRoot in ($candidateRoots | Select-Object -Unique)) {
        $candidateIntro = Join-Path $candidateRoot "src\Intro\Intro.ps1"
        if (Test-Path -LiteralPath $candidateIntro) {
            return $candidateRoot
        }
    }

    return $null
}

function Install-QOTFromGitHub {
    param(
        [Parameter(Mandatory)]
        $Layout,

        [Parameter(Mandatory)]
        [string[]]$Owners,

        [Parameter(Mandatory)]
        [string]$RepoName,

        [Parameter(Mandatory)]
        [string]$Branch,

        [AllowNull()]
        $RemoteInfo
    )

    foreach ($dir in @($Layout.AppRoot, $Layout.DownloadRoot)) {
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }

    $zipPath = Join-Path $Layout.DownloadRoot "repo.zip"
    $extractRoot = Join-Path $Layout.DownloadRoot "extract"
    $stagingCurrent = Join-Path $Layout.StagingRoot "Current"

    foreach ($path in @($extractRoot, $Layout.StagingRoot, $zipPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    New-Item -ItemType Directory -Path $extractRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $Layout.StagingRoot -Force | Out-Null

    $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $downloadUrls = New-Object System.Collections.Generic.List[string]
    foreach ($owner in $Owners) {
        $downloadUrls.Add("https://github.com/$owner/$RepoName/archive/refs/heads/$Branch.zip?cb=$cacheBust") | Out-Null
        $downloadUrls.Add("https://codeload.github.com/$owner/$RepoName/zip/refs/heads/$Branch?cb=$cacheBust") | Out-Null
    }

    Write-Host "Downloading Quinn Optimiser Toolkit..."
    Write-Host "Branch: $Branch"
    Invoke-QOTDownloadRepoZip -Urls $downloadUrls -OutFile $zipPath
    Expand-Archive -Path $zipPath -DestinationPath $extractRoot -Force

    $resolvedRoot = Find-QOTToolkitRoot -SearchRoot $extractRoot
    if (-not $resolvedRoot) {
        throw "Could not locate downloaded toolkit root after extraction (missing src\Intro\Intro.ps1)."
    }

    Copy-Item -LiteralPath $resolvedRoot -Destination $stagingCurrent -Recurse -Force

    $stagedIntro = Join-Path $stagingCurrent "src\Intro\Intro.ps1"
    if (-not (Test-Path -LiteralPath $stagedIntro)) {
        throw "Staged toolkit is invalid: missing $stagedIntro"
    }

    if (Test-Path -LiteralPath $Layout.PreviousRoot) {
        Remove-Item -LiteralPath $Layout.PreviousRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $Layout.CurrentRoot) {
        Move-Item -LiteralPath $Layout.CurrentRoot -Destination $Layout.PreviousRoot -Force
    }

    Move-Item -LiteralPath $stagingCurrent -Destination $Layout.CurrentRoot -Force

    if (Test-Path -LiteralPath $Layout.StagingRoot) {
        Remove-Item -LiteralPath $Layout.StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    $installedState = [pscustomobject]@{
        InstalledAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        Owner          = if ($RemoteInfo) { [string]$RemoteInfo.Owner } else { [string]$Owners[0] }
        RepoName       = $RepoName
        Branch         = $Branch
        CommitSha      = if ($RemoteInfo) { [string]$RemoteInfo.CommitSha } else { "" }
        CommitDate     = if ($RemoteInfo) { [string]$RemoteInfo.CommitDate } else { "" }
        InstallRoot    = $Layout.CurrentRoot
    }
    Write-QOTInstallState -StatePath $Layout.StatePath -State $installedState

    return $installedState
}

function Start-QOTInstalledCopy {
    param(
        [Parameter(Mandatory)]
        [string]$ToolkitRoot,

        [Parameter(Mandatory)]
        [string]$LogDir,

        [switch]$VerboseStartup
    )

    $runLocalPath = Join-Path $ToolkitRoot "run-local.ps1"
    $introPath = Join-Path $ToolkitRoot "src\Intro\Intro.ps1"

    if (-not (Test-Path -LiteralPath $runLocalPath) -and -not (Test-Path -LiteralPath $introPath)) {
        throw "Installed toolkit copy is incomplete. Missing run-local.ps1 and src\Intro\Intro.ps1 under: $ToolkitRoot"
    }

    $psExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $psExe)) {
        throw "Windows PowerShell executable was not found at: $psExe"
    }

    if (Test-Path -LiteralPath $runLocalPath) {
        $psArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $runLocalPath
        )

        if ($VerboseStartup) {
            $psArgs += "-VerboseStartup"
        }
    }
    else {
        $introLog = Join-Path $LogDir ("Intro_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
        $psArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-STA",
            "-File", $introPath,
            "-LogPath", $introLog
        )

        if (-not $VerboseStartup) {
            $psArgs += "-Quiet"
        }
    }

    Write-Host ""
    Write-Host "Toolkit root: $ToolkitRoot"
    Write-Host "Data folder:  $env:LOCALAPPDATA\StudioVoly\QuinnToolkit"
    Write-Host ""

    Set-Location $ToolkitRoot
    & $psExe @psArgs
}

$logDir = Get-QOTBootstrapLogDir
$bootstrapLog = Join-Path $logDir ("Bootstrap_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
Start-Transcript -Path $bootstrapLog | Out-Null

try {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    }
    catch { }

    $repoOwners = @(
        "VoIyboo",
        "Volyboo"
    )
    $repoName = "Windows-Optimiser-Toolkit"

    if ([string]::IsNullOrWhiteSpace($Branch)) {
        $Branch = "main"
    }

    $layout = Get-QOTInstallLayout
    $state = Read-QOTInstallState -StatePath $layout.StatePath

    $toolkitRoot = $null
    $localRoot = $PSScriptRoot
    $localIntro = $null
    if (-not [string]::IsNullOrWhiteSpace($localRoot)) {
        $localIntro = Join-Path $localRoot "src\Intro\Intro.ps1"
    }

    if ((-not $ForceRemote) -and $localIntro -and (Test-Path -LiteralPath $localIntro)) {
        Write-Host "Using local toolkit source (developer/local checkout)."
        Start-QOTInstalledCopy -ToolkitRoot $localRoot -LogDir $logDir -VerboseStartup:$VerboseStartup
        return
    }

    $installedIntro = Join-Path $layout.CurrentRoot "src\Intro\Intro.ps1"
    $hasInstalledCopy = Test-Path -LiteralPath $installedIntro

    $remoteInfo = $null
    $remoteLookupError = $null
    try {
        $remoteInfo = Get-QOTLatestRemoteInfo -Owners $repoOwners -RepoName $repoName -Branch $Branch
        Write-Host ("Latest GitHub commit: {0}" -f $remoteInfo.CommitSha)
    }
    catch {
        $remoteLookupError = $_.Exception.Message
        Write-Host ("Warning: could not query GitHub for the latest version. {0}" -f $remoteLookupError)
    }

    $shouldInstallOrUpdate = $ForceRefresh.IsPresent -or (-not $hasInstalledCopy)
    if (-not $shouldInstallOrUpdate -and $remoteInfo) {
        $installedSha = ""
        try { $installedSha = ([string]($state.CommitSha + "")).Trim() } catch { $installedSha = "" }
        if ([string]::IsNullOrWhiteSpace($installedSha)) {
            $shouldInstallOrUpdate = $true
        }
        elseif ($installedSha -ne $remoteInfo.CommitSha) {
            $shouldInstallOrUpdate = $true
        }
    }

    if ($shouldInstallOrUpdate) {
        $actionLabel = if ($hasInstalledCopy) { "Updating installed copy..." } else { "No installed copy found. Downloading current GitHub version..." }
        Write-Host $actionLabel
        $state = Install-QOTFromGitHub -Layout $layout -Owners $repoOwners -RepoName $repoName -Branch $Branch -RemoteInfo $remoteInfo
        $hasInstalledCopy = $true
    }
    elseif ($hasInstalledCopy) {
        Write-Host "Installed copy is up to date. Launching local copy."
    }

    if (-not $hasInstalledCopy) {
        if ($remoteLookupError) {
            throw "Toolkit is not installed yet, and GitHub could not be reached to download it. $remoteLookupError"
        }
        throw "Toolkit is not installed yet, and the download step did not complete."
    }

    Start-QOTInstalledCopy -ToolkitRoot $layout.CurrentRoot -LogDir $logDir -VerboseStartup:$VerboseStartup
}
catch {
    try {
        Add-Type -AssemblyName PresentationFramework | Out-Null
        [System.Windows.MessageBox]::Show(
            "Bootstrap failed.`r`n$($_.Exception.Message)`r`n`r`nBootstrap log:`r`n$bootstrapLog",
            "Quinn Optimiser Toolkit"
        ) | Out-Null
    }
    catch { }
    throw
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
    Set-Location $originalLocation
}
