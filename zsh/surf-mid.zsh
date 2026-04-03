# surf-mid.zsh — middle pane (~10 %): input-only prompt
#
# The user types here. On Enter, the command is sent to the top pane via
# tmux send-keys rather than executed locally.  PWD is kept in sync by
# reading the SURF_PWD tmux env var that the top pane publishes.

# ── Source user's config for completions / aliases ────────────────────────
[[ -z "$SURF_SOURCED" && -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

# ── Suppress the top pane's own prompt from interfering ───────────────────
# (the top pane's shell is responsible for display; we just drive it)

# ── Prompt ────────────────────────────────────────────────────────────────
autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats       '%F{cyan}(%b)%f'
zstyle ':vcs_info:git:*' actionformats '%F{yellow}(%b|%a)%f'

_surf_mid_precmd() {
    # Sync PWD from top pane
    local top_pwd
    top_pwd=$(tmux show-environment -t "$SURF_SESSION" SURF_PWD 2>/dev/null \
              | sed 's/^SURF_PWD=//')
    if [[ -n "$top_pwd" && "$top_pwd" != "$PWD" && -d "$top_pwd" ]]; then
        builtin cd "$top_pwd"
    fi

    vcs_info
}
add-zsh-hook precmd _surf_mid_precmd

setopt prompt_subst
PROMPT='%F{green}%~%f ${vcs_info_msg_0_} %F{yellow}❯%f '
RPROMPT='%F{240}%D{%H:%M}%f'

# ── ZLE widget: send command to top pane instead of running it locally ────
_surf_send_to_top() {
    local cmd="$BUFFER"
    BUFFER=''

    if [[ -z "${cmd// }" ]]; then
        # Empty line — just redraw prompt
        zle reset-prompt
        return
    fi

    # Add to local history so up-arrow works in the prompt pane too
    print -s "$cmd"

    # Send to top pane
    tmux send-keys -t "$SURF_TOP_PANE" "$cmd" Enter

    # If the command is a plain `cd`, mirror it locally right away so the
    # next prompt render doesn't flicker with the wrong directory.
    if [[ "$cmd" =~ ^[[:space:]]*cd([[:space:]]|$) ]]; then
        eval "$cmd" 2>/dev/null
        tmux set-environment -t "$SURF_SESSION" SURF_PWD "$PWD"
    fi

    zle reset-prompt
}
zle -N _surf_send_to_top
bindkey "^M"  _surf_send_to_top   # Enter
bindkey "^J"  _surf_send_to_top   # Ctrl-J (also Enter on some setups)

# ── Ctrl-C: forward interrupt to top pane ────────────────────────────────
_surf_interrupt() {
    tmux send-keys -t "$SURF_TOP_PANE" C-c
    BUFFER=''
    zle reset-prompt
}
zle -N _surf_interrupt
bindkey "^C" _surf_interrupt

# ── Ctrl-L: clear top pane ────────────────────────────────────────────────
_surf_clear_top() {
    tmux send-keys -t "$SURF_TOP_PANE" "clear" Enter
    zle reset-prompt
}
zle -N _surf_clear_top
bindkey "^L" _surf_clear_top

# ── Shared history with top pane ──────────────────────────────────────────
HISTFILE="${SURF_DIR}/.surf_history"
HISTSIZE=10000
SAVEHIST=10000
setopt share_history inc_append_history

# ── Pane title ────────────────────────────────────────────────────────────
printf '\033]2;prompt\033\\'
