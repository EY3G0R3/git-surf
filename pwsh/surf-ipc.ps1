# surf-ipc.ps1 — IPC hooks for the git-surf main pane
#
# Sourced from $PROFILE by the hook surf.ps1 installs, but only when
# $env:SURF_STATE_DIR is set (i.e. only inside a surf session).
#
# Loads the Windows PowerShell profile (Documents\WindowsPowerShell\) if
# present, so settings kept there are available even though surf runs PS7.
#
# Env vars are cleared immediately so nested `pwsh` processes spawned from
# this pane don't accidentally activate as surf panes.

# ── Capture and clear surf env vars ───────────────────────────────────────
$_surfStateDir = $env:SURF_STATE_DIR
$_surfStartDir = $env:SURF_START_DIR
Remove-Item Env:\SURF_STATE_DIR   -ErrorAction SilentlyContinue
Remove-Item Env:\SURF_START_DIR   -ErrorAction SilentlyContinue
Remove-Item Env:\SURF_SCRIPTS_DIR -ErrorAction SilentlyContinue

# ── Load the Windows PowerShell profile if present ────────────────────────
# PS7 auto-loads Documents\PowerShell\profile.ps1, but many users keep their
# settings in Documents\WindowsPowerShell\profile.ps1 (the PS5 location).
# Source it here so aliases, modules, and prompt themes are active.
$_winPSProfile = Join-Path ([Environment]::GetFolderPath('MyDocuments')) `
    'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
if (Test-Path -LiteralPath $_winPSProfile) { . $_winPSProfile }

# ── Navigate to the surf starting directory ────────────────────────────────
if ($_surfStartDir -and (Test-Path -LiteralPath $_surfStartDir)) {
    Set-Location $_surfStartDir
}

# ── IPC paths — $global: so they outlive this script's scope ──────────────
$global:_surf_PwdFile     = Join-Path $_surfStateDir "pwd.txt"
$global:_surf_RefreshFile = Join-Path $_surfStateDir "refresh.flag"

# ── Shared history ─────────────────────────────────────────────────────────
Set-PSReadLineOption -HistorySavePath (Join-Path $_surfStateDir "history.txt") `
                     -HistorySaveStyle SaveIncrementally

# ── Wrap the prompt to publish PWD after each command ─────────────────────
# $function:prompt here is the user's fully-configured prompt (oh-my-posh,
# starship, posh-git, …) because the entire profile has already run.
$global:_surf_InnerPrompt = if ($function:prompt) { $function:prompt } else { $null }

function global:prompt {
    $PWD.Path | Set-Content $global:_surf_PwdFile     -Encoding UTF8 -Force
    ""         | Set-Content $global:_surf_RefreshFile -Encoding UTF8 -Force

    if ($global:_surf_InnerPrompt) {
        return (& $global:_surf_InnerPrompt)
    }

    $loc = $PWD.Path -replace [regex]::Escape($HOME), '~'
    $b   = git rev-parse --abbrev-ref HEAD 2>$null
    Write-Host $loc -ForegroundColor Green -NoNewline
    if ($b) { Write-Host " ($b)" -ForegroundColor Cyan -NoNewline }
    return "`n❯ "
}
