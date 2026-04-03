# surf-bot.ps1 — bottom pane (30 %): live git log viewer
#
# Redraws the git log when pwd.txt changes or refresh.flag is written.
# refresh.flag is created by the top pane after each command completes,
# so there are no timer-driven redraws (and no blinking).

param(
    [string]$StateDir,
    [string]$StartDir
)

$PwdFile     = Join-Path $StateDir "pwd.txt"
$RefreshFile = Join-Path $StateDir "refresh.flag"
$MaxLines    = $Host.UI.RawUI.WindowSize.Height - 2
if ($MaxLines -lt 5) { $MaxLines = 5 }

[Console]::CursorVisible = $false
# Restore cursor on exit
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    [Console]::CursorVisible = $true
}

function Draw-GitLog {
    param([string]$Dir)

    # Move to top-left of this pane's virtual screen and clear
    [Console]::SetCursorPosition(0, 0)
    # Clear screen without flicker: overwrite each line
    $blank = ' ' * $Host.UI.RawUI.WindowSize.Width
    for ($i = 0; $i -lt $Host.UI.RawUI.WindowSize.Height; $i++) {
        [Console]::SetCursorPosition(0, $i)
        Write-Host $blank -NoNewline
    }
    [Console]::SetCursorPosition(0, 0)

    $isRepo = git -C $Dir rev-parse --is-inside-work-tree 2>$null
    if (-not $isRepo) {
        Write-Host "not a git repository: $Dir" -ForegroundColor Yellow
        return
    }

    $lines = git -C $Dir log --oneline --graph --decorate --all -n $MaxLines --color=never 2>$null
    if (-not $lines) {
        Write-Host "(no commits)" -ForegroundColor DarkGray
        return
    }

    # Colour the output manually (--color=always would emit ANSI codes that
    # Write-Host can handle on modern Windows terminals, but let's keep it
    # simple and colour entire lines based on content)
    foreach ($l in ($lines | Select-Object -First $MaxLines)) {
        if     ($l -match '\*')          { Write-Host $l -ForegroundColor Cyan }
        elseif ($l -match '\(HEAD')      { Write-Host $l -ForegroundColor Green }
        elseif ($l -match 'origin/')     { Write-Host $l -ForegroundColor Yellow }
        else                             { Write-Host $l -ForegroundColor Gray }
    }
}

# ── Main loop ──────────────────────────────────────────────────────────────
$lastPwd = ""

while ($true) {
    $curPwd = $StartDir
    if (Test-Path $PwdFile) {
        $r = (Get-Content $PwdFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($r) { $curPwd = $r.Trim() }
    }

    $needsRefresh = Test-Path $RefreshFile

    if ($curPwd -ne $lastPwd -or $needsRefresh) {
        if ($needsRefresh) {
            Remove-Item $RefreshFile -Force -ErrorAction SilentlyContinue
        }
        Draw-GitLog -Dir $curPwd
        $lastPwd = $curPwd
    }

    Start-Sleep -Milliseconds 500
}
