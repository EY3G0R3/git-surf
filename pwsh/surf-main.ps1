# surf-main.ps1 — main pane (~70 %): real interactive shell
#
# This is a normal interactive PowerShell session — the user types here and
# sees output here, mirroring the Linux version's single main pane.
#
# The prompt function is wrapped to publish $PWD and a refresh signal to the
# state directory after each command, so the git-log pane redraws — the same
# role as the precmd hooks in surf-main.zsh.
#
# The user's own $PROFILE is sourced first so aliases, functions, and prompt
# themes (oh-my-posh, starship, posh-git, …) are active.  The existing prompt
# is captured and called from within the wrapper, so themes continue to work.
#
# IPC variables use $global: (not $script:) because the encoded-command's
# script scope is destroyed once it finishes; only global scope persists into
# the interactive REPL that follows.

param(
    [string]$StateDir,
    [string]$StartDir
)

Set-Location $StartDir

# Clear surf env vars so that if the user's $PROFILE still contains the old
# git-surf IPC hook it won't fire and double-initialize IPC.
Remove-Item Env:\SURF_STATE_DIR, Env:\SURF_START_DIR, Env:\SURF_SCRIPTS_DIR -ErrorAction SilentlyContinue

# Source the user's profiles so their environment is fully set up.
# Load both AllHosts and CurrentHost levels, same order PowerShell uses.
foreach ($p in @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost)) {
    if ($p -and (Test-Path -LiteralPath $p)) { . $p }
}

# ── IPC paths — must be $global: so they survive past this script scope ────
$global:_surf_PwdFile     = Join-Path $StateDir "pwd.txt"
$global:_surf_RefreshFile = Join-Path $StateDir "refresh.flag"

# ── Shared history (syncs with bot pane history path) ─────────────────────
Set-PSReadLineOption -HistorySavePath (Join-Path $StateDir "history.txt") `
                     -HistorySaveStyle SaveIncrementally

# ── Wrap the prompt to publish state after each command ───────────────────
# Capture whatever prompt the profile installed (or the PowerShell default).
$global:_surf_InnerPrompt = if ($function:prompt) { $function:prompt } else { $null }
# -1 so the very first prompt call always seeds pwd.txt (e.g. profile changed $PWD).
# After that, only update when Get-History shows a new entry — prevents prompt
# frameworks (oh-my-posh, posh-git, starship) from triggering bot redraws on
# their periodic idle-refresh calls.
$global:_surf_LastCmdId   = -1

function global:prompt {
    # Publish PWD / refresh signal only when the user ran a new command.
    $h  = Get-History -Count 1 -ErrorAction SilentlyContinue
    $id = if ($h) { $h.Id } else { 0 }
    if ($id -ne $global:_surf_LastCmdId) {
        $global:_surf_LastCmdId = $id
        $PWD.Path | Set-Content $global:_surf_PwdFile     -Encoding UTF8 -Force
        ""         | Set-Content $global:_surf_RefreshFile -Encoding UTF8 -Force
    }

    # Delegate to the user's original prompt, or use a minimal fallback
    if ($global:_surf_InnerPrompt) {
        return (& $global:_surf_InnerPrompt)
    }

    $loc = $PWD.Path -replace [regex]::Escape($HOME), "~"
    $b   = git rev-parse --abbrev-ref HEAD 2>$null
    Write-Host $loc -ForegroundColor Green -NoNewline
    if ($b) { Write-Host " ($b)" -ForegroundColor Cyan -NoNewline }
    return "`n❯ "
}
