# surf-mid.ps1 — middle pane (~10 %): interactive prompt
#
# PSReadLine's Enter key is overridden: instead of executing locally,
# the command is written to a shared file and the top pane runs it.
# PWD is kept in sync by reading the shared pwd.txt on every prompt.

param(
    [string]$StateDir,
    [string]$StartDir
)

Set-Location $StartDir

$script:CmdFile  = Join-Path $StateDir "cmd.txt"
$script:FlagFile = Join-Path $StateDir "cmd_ready.flag"
$script:BusyFile = Join-Path $StateDir "busy.flag"
$script:PwdFile  = Join-Path $StateDir "pwd.txt"

# ── Shared history file ────────────────────────────────────────────────────
$HistFile = Join-Path $StateDir "history.txt"
Set-PSReadLineOption -HistorySavePath $HistFile -HistorySaveStyle SaveIncrementally

# ── PSReadLine: intercept Enter ────────────────────────────────────────────
Set-PSReadLineKeyHandler -Key Enter -ScriptBlock {
    $line   = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ([string]::IsNullOrWhiteSpace($line)) {
        # Empty Enter: just get a new prompt
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        return
    }

    # Save to history
    [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($line)

    # Forward to top pane
    [System.IO.File]::WriteAllText($script:CmdFile, $line, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($script:FlagFile, "", [System.Text.Encoding]::UTF8)

    # Mirror cd locally so the prompt updates immediately
    if ($line -match '^\s*(?:cd|Set-Location|sl|Push-Location|pushd)\s+(.+)') {
        try { Set-Location $Matches[1] } catch {}
        $PWD.Path | Set-Content $script:PwdFile -Encoding UTF8 -Force
    }

    # Clear the buffer and return to prompt (accept an empty line)
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# ── PSReadLine: Ctrl-C forwards interrupt to top pane ─────────────────────
# We can't send a real SIGINT to the other pane, but we can write a
# synthetic interrupt command.  For simple cases this works; for complex
# interactive processes in the top pane the user can click the top pane.
Set-PSReadLineKeyHandler -Key Ctrl+c -ScriptBlock {
    [System.IO.File]::WriteAllText($script:CmdFile, "", [System.Text.Encoding]::UTF8)
    Remove-Item $script:FlagFile -Force -ErrorAction SilentlyContinue
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

# ── PWD sync + git branch in prompt ───────────────────────────────────────
function Get-GitBranch {
    $b = git rev-parse --abbrev-ref HEAD 2>$null
    if ($b) { return "($b)" }
    return ""
}

function global:prompt {
    # Sync PWD from top pane
    if (Test-Path $script:PwdFile) {
        $topPwd = (Get-Content $script:PwdFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue).Trim()
        if ($topPwd -and $topPwd -ne $PWD.Path -and (Test-Path $topPwd)) {
            Set-Location $topPwd
        }
    }

    # Busy indicator
    $busy = Test-Path $script:BusyFile
    $busyMark = if ($busy) { " …" } else { "" }

    $branch = Get-GitBranch

    $loc    = $PWD.Path -replace [regex]::Escape($HOME), "~"
    $time   = Get-Date -Format "HH:mm"

    Write-Host $loc    -ForegroundColor Green  -NoNewline
    if ($branch) {
        Write-Host " $branch" -ForegroundColor Cyan -NoNewline
    }
    Write-Host "$busyMark" -ForegroundColor Yellow -NoNewline
    Write-Host "  $time"   -ForegroundColor DarkGray -NoNewline

    # The actual prompt character — returned as string (not written)
    return "`n❯ "
}
