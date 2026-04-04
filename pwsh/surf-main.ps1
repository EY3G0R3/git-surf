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

param(
    [string]$StateDir,
    [string]$StartDir
)

Set-Location $StartDir

# Source the user's profile so their environment is fully set up
if (Test-Path $PROFILE) { . $PROFILE }

# ── IPC paths ─────────────────────────────────────────────────────────────
$script:PwdFile     = Join-Path $StateDir "pwd.txt"
$script:RefreshFile = Join-Path $StateDir "refresh.flag"

# ── Shared history (syncs with bot pane history path) ─────────────────────
Set-PSReadLineOption -HistorySavePath (Join-Path $StateDir "history.txt") `
                     -HistorySaveStyle SaveIncrementally

# ── Wrap the prompt to publish state after each command ───────────────────
# Capture whatever prompt the profile installed (or the PowerShell default).
$script:_innerPrompt = if ($function:prompt) { $function:prompt } else { $null }

function global:prompt {
    # Publish PWD and signal the git-log pane to redraw
    $PWD.Path | Set-Content $script:PwdFile     -Encoding UTF8 -Force
    ""         | Set-Content $script:RefreshFile -Encoding UTF8 -Force

    # Delegate to the user's original prompt, or use a minimal fallback
    if ($script:_innerPrompt) {
        return (& $script:_innerPrompt)
    }

    $loc = $PWD.Path -replace [regex]::Escape($HOME), "~"
    $b   = git rev-parse --abbrev-ref HEAD 2>$null
    Write-Host $loc -ForegroundColor Green -NoNewline
    if ($b) { Write-Host " ($b)" -ForegroundColor Cyan -NoNewline }
    return "`n❯ "
}
