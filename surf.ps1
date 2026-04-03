#!/usr/bin/env pwsh
# surf.ps1 — launch the git-surf Windows Terminal layout
#
# Usage: .\surf.ps1 [-StartDir <path>]
#
# Requires: Windows Terminal (wt.exe) in PATH.

param(
    [string]$StartDir = $PWD.Path
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    Write-Error "Windows Terminal (wt.exe) is required. Install from the Microsoft Store or https://aka.ms/terminal"
    exit 1
}

$RiderDir = $PSScriptRoot
$PwshExe  = (Get-Command pwsh -ErrorAction Stop).Source

# ── Per-session IPC directory ──────────────────────────────────────────────
$SessionId = (New-Guid).ToString("N").Substring(0, 8)
$StateDir  = Join-Path $env:TEMP "surf-$SessionId"
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

# Seed shared state files
$StartDir | Set-Content (Join-Path $StateDir "pwd.txt") -Encoding UTF8
""         | Set-Content (Join-Path $StateDir "cmd.txt") -Encoding UTF8

# ── Encode each pane's bootstrap as Base64 (pwsh -EncodedCommand) ─────────
# This sidesteps all quoting/escaping issues when paths land in wt.exe args.
# Single quotes inside $RiderDir / $StateDir / $StartDir are escaped for PS.

function ConvertTo-PwshEncoded ([string]$script) {
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($script)
    [Convert]::ToBase64String($bytes)
}

$rd = $RiderDir  -replace "'", "''"
$sd = $StateDir  -replace "'", "''"
$st = $StartDir  -replace "'", "''"

$topEnc = ConvertTo-PwshEncoded ". '$rd\pwsh\surf-top.ps1' -StateDir '$sd' -StartDir '$st'"
$midEnc = ConvertTo-PwshEncoded ". '$rd\pwsh\surf-mid.ps1' -StateDir '$sd' -StartDir '$st'"
$botEnc = ConvertTo-PwshEncoded ". '$rd\pwsh\surf-bot.ps1' -StateDir '$sd' -StartDir '$st'"

# ── Launch Windows Terminal ────────────────────────────────────────────────
# Backtick-semicolons (`;) prevent PowerShell from treating ; as a statement
# separator; wt.exe receives them as literal semicolons and uses them to
# delimit sub-commands.
#
# Split math (--horizontal = divider is horizontal = panes stacked top/bottom):
#   new-tab                → top    60 % (full height)
#   split-pane --size 0.4  → bottom 40 %; original top shrinks to 60 %
#   split-pane --size 0.75 → focused pane (40 %) splits:
#                              new bottom = 75 % × 40 % = 30 %
#                              remaining  = 25 % × 40 % = 10 %  ← middle/prompt

wt.exe `
    new-tab --title output -- "$PwshExe" -NoLogo -NoExit -EncodedCommand $topEnc `; `
    split-pane --horizontal --size 0.4 --title prompt -- "$PwshExe" -NoLogo -NoExit -EncodedCommand $midEnc `; `
    split-pane --horizontal --size 0.75 --title git-log -- "$PwshExe" -NoLogo -NoExit -EncodedCommand $botEnc
