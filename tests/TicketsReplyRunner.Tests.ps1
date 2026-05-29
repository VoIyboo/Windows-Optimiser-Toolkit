$repoRoot = Split-Path -Parent $PSScriptRoot
$replyRunnerPath = Join-Path $repoRoot "src\Tickets\Tickets.Email.ReplyRunner.ps1"
$ticketsUiPath = Join-Path $repoRoot "src\Tickets\Tickets.UI.psm1"

Describe "Tickets reply runner" {
    It "writes reply results to the requested result file" {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("qot-reply-runner-" + [guid]::NewGuid().ToString("N"))
        $payloadPath = Join-Path $tempRoot "payload.json"
        $resultPath = Join-Path $tempRoot "result.json"
        $coreDir = Join-Path $tempRoot "src\Core"
        $coreModulePath = Join-Path $coreDir "Tickets.psm1"

        try {
            $null = New-Item -ItemType Directory -Path $coreDir -Force

            @'
function Get-QOTickets {
    param([switch]$Quiet)

    return [pscustomobject]@{
        Tickets = @(
            [pscustomobject]@{
                Id = "ticket-1"
            }
        )
    }
}

function Send-QOTicketReply {
    param(
        [Parameter(Mandatory)]$Ticket,
        [Parameter(Mandatory)][string]$Subject,
        [Parameter(Mandatory)][string]$Body
    )

    return [pscustomobject]@{
        Success = $true
        Note = ("reply sent for " + [string]$Ticket.Id + " / " + $Subject + " / " + $Body)
    }
}

Export-ModuleMember -Function Get-QOTickets, Send-QOTicketReply
'@ | Set-Content -LiteralPath $coreModulePath -Encoding UTF8

            '{"TicketId":"ticket-1","Subject":"Subject","Body":"Body"}' | Set-Content -LiteralPath $payloadPath -Encoding UTF8

            $powershellExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
            $arguments = @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $replyRunnerPath,
                "-ToolkitRoot", $tempRoot,
                "-PayloadPath", $payloadPath,
                "-ResultPath", $resultPath
            )

            & $powershellExe @arguments | Out-Null

            $LASTEXITCODE | Should Be 0
            Test-Path -LiteralPath $resultPath | Should Be $true

            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            $result.Success | Should Be $true
            $result.Note | Should Match "reply sent for ticket-1"
        } finally {
            if (Test-Path -LiteralPath $tempRoot) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It "no longer keeps the direct in-process reply branch ahead of the async runner" {
        $uiSource = Get-Content -LiteralPath $ticketsUiPath -Raw

        $uiSource | Should Not Match "Starting direct reply send"
        $uiSource | Should Match "Async reply send started"
    }
}
