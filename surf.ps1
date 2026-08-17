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
    [ValidateSet("adaptive-diamond", "arrow", "wide", "powerline",
        "row-yellow", "row-cyan", "arrow-hash", "hash")]
    [string]$Theme = "adaptive-diamond",
    [switch]$ListThemes,
    [switch]$SetTheme
)

$ErrorActionPreference = 'Stop'
$Themes = @("adaptive-diamond", "arrow", "wide", "powerline",
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
# Use Windows PowerShell (powershell.exe / PS5.1) — always present on Windows
# and resolves $PROFILE to Documents\WindowsPowerShell\, where most users keep
# their customisations.  PS7 (pwsh) uses a different profile path and misses them.
$PwshExe = (Get-Command powershell -ErrorAction Stop).Source

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

# ── Encode pane bootstraps ─────────────────────────────────────────────────
function ConvertTo-PwshEncoded ([string]$script) {
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    [Convert]::ToBase64String($bytes)
}

$rd = $SurfDir  -replace "'", "''"
$sd = $StateDir -replace "'", "''"
$st = $StartDir -replace "'", "''"

$mainEnc = ConvertTo-PwshEncoded ". '$rd\pwsh\surf-main.ps1' -StateDir '$sd' -StartDir '$st'"
$botEnc  = ConvertTo-PwshEncoded ". '$rd\pwsh\surf-bot.ps1'  -StateDir '$sd' -StartDir '$st'"

# ── Launch Windows Terminal ────────────────────────────────────────────────
# Layout (mirrors the Linux tmux layout):
#   main shell  (~70 %)  — top:    real interactive shell, input + output
#   git log     (~30 %)  — bottom: live git log, redraws after each command
#
# Both panes use -EncodedCommand so the state-dir path is embedded literally —
# no reliance on env-var inheritance through wt.exe.  surf-main.ps1 sources
# $PROFILE itself, so the user's full environment is active.
# move-focus up returns focus to the main pane after the split creates the bot.
wt.exe `
    new-tab --title "$Session" --startingDirectory "$StartDir" --tabColor "#555555" -- "$PwshExe" -NoLogo -NoExit -EncodedCommand $mainEnc `; `
    split-pane --horizontal --size 0.3 --title "git-log" -- "$PwshExe" -NoLogo -NoProfile -NoExit -EncodedCommand $botEnc `; `
    move-focus up
