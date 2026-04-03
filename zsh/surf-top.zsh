# surf-top.zsh — top pane (~60 %): runs commands, owns the working directory
#
# This pane is the real shell. The middle pane sends keystrokes here.
# After every command, we publish $PWD so the middle pane can follow.

# ── Source user's existing zsh config so aliases/functions are available ──
[[ -z "$SURF_SOURCED" && -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

# ── No prompt — this pane is output-only ──────────────────────────────────
# Enforced in precmd so theme hooks (p10k, starship, etc.) can't override it.
PROMPT=''
RPROMPT=''

# ── Pager: open in *this* pane (we are the output pane) ───────────────────
export PAGER=less
export GIT_PAGER=less
export LESS="-RFX"

# ── After each prompt, publish PWD and signal the bottom pane to redraw ──
_surf_top_precmd() {
    PROMPT=''
    RPROMPT=''
    tmux set-environment -t "$SURF_SESSION" SURF_PWD "$PWD"
    tmux set-environment -t "$SURF_SESSION" SURF_REFRESH "$(date +%s%N)"
}
add-zsh-hook precmd _surf_top_precmd

# ── After a cd, publish immediately (chpwd fires before precmd) ───────────
_surf_top_chpwd() {
    tmux set-environment -t "$SURF_SESSION" SURF_PWD "$PWD"
}
add-zsh-hook chpwd _surf_top_chpwd

# ── Keep this pane's title clean ──────────────────────────────────────────
printf '\033]2;output\033\\'
