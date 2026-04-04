#!/usr/bin/env pwsh
# surf.ps1 — launch the git-surf Windows Terminal layout
#
# Usage: .\surf.ps1 [[-Session] <name>] [[-StartDir] <path>]
#   Session   defaults to "surf"
#   StartDir  defaults to current directory
#
# Requires: Windows Terminal (wt.exe) in PATH.

param(
    [string]$Session  = "surf",
    [string]$StartDir = $PWD.Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    Write-Error "Windows Terminal (wt.exe) is required. Install from the Microsoft Store or https://aka.ms/terminal"
    exit 1
}

$SurfDir = $PSScriptRoot
$PwshExe = (Get-Command pwsh -ErrorAction Stop).Source

# ── Per-session IPC directory ──────────────────────────────────────────────
$StateDir = Join-Path $env:TEMP "surf-$Session"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

# Seed shared state
$StartDir | Set-Content (Join-Path $StateDir "pwd.txt") -Encoding UTF8

# ── Encode bootstrap scripts as Base64 (avoids quoting issues in wt.exe args) ──
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
# --horizontal means the split line is horizontal (panes stacked top/bottom).
# --size 0.3 carves 30 % off the bottom of the focused (full-height) tab.
wt.exe `
    new-tab --title "$Session" -- "$PwshExe" -NoLogo -NoExit -EncodedCommand $mainEnc `; `
    split-pane --horizontal --size 0.3 --title "git-log" -- "$PwshExe" -NoLogo -NoExit -EncodedCommand $botEnc
