# surf-ipc.ps1 — IPC hooks for the git-surf main pane
#
# Sourced from $PROFILE by the hook surf.ps1 installs, but only when
# $env:SURF_STATE_DIR is set (i.e. only inside a surf session).
#
# Because the profile has already finished loading before this runs,
# the user's full environment (aliases, prompt theme, modules, …) is in
# place.  We just layer the IPC on top.
#
# Env vars are cleared immediately so nested `pwsh` processes spawned from
# this pane don't accidentally activate as surf panes.

# ── Capture and clear surf env vars ───────────────────────────────────────
$_surfStateDir = $env:SURF_STATE_DIR
$_surfStartDir = $env:SURF_START_DIR
Remove-Item Env:\SURF_STATE_DIR   -ErrorAction SilentlyContinue
Remove-Item Env:\SURF_START_DIR   -ErrorAction SilentlyContinue
Remove-Item Env:\SURF_SCRIPTS_DIR -ErrorAction SilentlyContinue

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
