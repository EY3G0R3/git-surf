# surf-main.zsh — main pane: normal interactive shell (input + output)
#
# No prompt override — the user's own zsh config is already active.
# We only add hooks to keep SURF_PWD in sync so the bot pane follows cd.

# ── Push prompt to the bottom of the pane on startup ──────────────────────
local _h
_h=$(tput lines)
printf '\n%.0s' {1..$_h}
unset _h

# ── After each command, publish PWD and signal the bot pane to redraw ─────
_surf_main_precmd() {
    tmux set-environment -t "$SURF_SESSION" SURF_PWD "$PWD"
    tmux set-environment -t "$SURF_SESSION" SURF_REFRESH "$(date +%s%N)"
}
add-zsh-hook precmd _surf_main_precmd

# ── After a cd, publish immediately ───────────────────────────────────────
_surf_main_chpwd() {
    tmux set-environment -t "$SURF_SESSION" SURF_PWD "$PWD"
}
add-zsh-hook chpwd _surf_main_chpwd
