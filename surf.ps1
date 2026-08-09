#!/usr/bin/env pwsh
# surf.ps1 — launch the git-surf Windows Terminal layout
#
# Usage: .\surf.ps1 [[-Session] <name>] [[-StartDir] <path>] [[-Theme] <name>]
#        .\surf.ps1 -ListThemes
#        .\surf.ps1 -SetTheme -Theme <name> [[-Session] <name>]
#   Session   defaults to "surf"
#   StartDir  defaults to current directory
#
# Requires: Windows Terminal (wt.exe) in PATH.

param(
    [string]$Session  = "surf",
    [string]$StartDir = $PWD.Path,
    [ValidateSet("adaptive-diamond", "pulse-arrow", "arrow", "wide", "powerline",
        "row-yellow", "row-cyan", "arrow-hash", "hash")]
    [string]$Theme = "adaptive-diamond",
    [switch]$ListThemes,
    [switch]$SetTheme
)

$ErrorActionPreference = 'Stop'
$Themes = @("adaptive-diamond", "pulse-arrow", "arrow", "wide", "powerline",
    "row-yellow", "row-cyan", "arrow-hash", "hash")

if ($ListThemes) {
    $Themes
    exit 0
}

$StateDir = Join-Path $env:TEMP "surf-$Session"
if ($SetTheme) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    $Theme | Set-Content (Join-Path $StateDir "theme.txt") -Encoding UTF8
    New-Item -ItemType File -Path (Join-Path $StateDir "refresh.flag") -Force | Out-Null
    exit 0
}

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    Write-Error "Windows Terminal (wt.exe) is required. Install from the Microsoft Store or https://aka.ms/terminal"
    exit 1
}

$SurfDir = $PSScriptRoot
$PwshExe = (Get-Command pwsh -ErrorAction Stop).Source

# ── Per-session IPC directory ──────────────────────────────────────────────
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

# Seed shared state
$StartDir | Set-Content (Join-Path $StateDir "pwd.txt") -Encoding UTF8
$Theme | Set-Content (Join-Path $StateDir "theme.txt") -Encoding UTF8

# ── Pass session state to child processes via env vars ─────────────────────
# wt.exe and the pwsh it spawns inherit these from the current process.
$env:SURF_STATE_DIR   = $StateDir
$env:SURF_START_DIR   = $StartDir
$env:SURF_SCRIPTS_DIR = $SurfDir

# ── Ensure $PROFILE has the surf IPC hook (added once, idempotent) ─────────
# The main pane is a real interactive shell; the hook fires when SURF_STATE_DIR
# is set, mirrors the `tmux send-keys` bootstrap the Linux version uses.
$hookTag  = '# git-surf IPC hook'
$hookLine = 'if ($env:SURF_STATE_DIR) { . (Join-Path $env:SURF_SCRIPTS_DIR "pwsh\surf-ipc.ps1") }'

# Ask the target pwsh for its own profile path — not $PROFILE here, which
# resolves to whichever host is running surf.ps1 (VSCode, git-bash, …).
$profilePath = & $PwshExe -NoProfile -Command '$PROFILE.CurrentUserCurrentHost'
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}
$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if ($profileContent -notlike "*$hookTag*") {
    Add-Content -Path $profilePath -Value "`n$hookTag`n$hookLine"
    Write-Host "surf: added IPC hook to $(Split-Path $profilePath -Leaf)" -ForegroundColor DarkGray
}

# ── Encode bot bootstrap (bot pane doesn't need $PROFILE) ─────────────────
function ConvertTo-PwshEncoded ([string]$script) {
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    [Convert]::ToBase64String($bytes)
}

$rd = $SurfDir  -replace "'", "''"
$sd = $StateDir -replace "'", "''"
$st = $StartDir -replace "'", "''"

$botEnc = ConvertTo-PwshEncoded ". '$rd\pwsh\surf-bot.ps1' -StateDir '$sd' -StartDir '$st'"

# ── Launch Windows Terminal ────────────────────────────────────────────────
# Layout (mirrors the Linux tmux layout):
#   main shell  (~70 %)  — top:    real interactive shell, input + output
#   git log     (~30 %)  — bottom: live git log, redraws after each command
#
# Main pane: bare `pwsh -NoExit` so $PROFILE auto-loads and the surf IPC hook
# fires naturally — no -EncodedCommand, no -NoProfile.
# Bot pane: encoded command for the git-log display; no profile needed.
wt.exe `
    new-tab --title "$Session" --startingDirectory "$StartDir" -- "$PwshExe" -NoLogo -NoExit `; `
    split-pane --horizontal --size 0.3 --title "git-log" -- "$PwshExe" -NoLogo -NoProfile -NoExit -EncodedCommand $botEnc
