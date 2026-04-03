# surf-bot.zsh — bottom pane (30 %): live git log
#
# Redraws the git log whenever SURF_PWD or SURF_REFRESH changes.
# SURF_REFRESH is bumped by the top pane after each command completes,
# so the bottom pane only redraws on real activity — no timer-driven blink.

# No interactive prompt needed
setopt no_prompt_cr

_surf_draw_log() {
    local dir="$1"
    # Query actual pane height each draw so resizes and rounding never mismatch
    local rows cols
    rows=$(tmux display-message -t "$SURF_BOT_PANE" -p "#{pane_height}" 2>/dev/null)
    cols=$(tmux display-message -t "$SURF_BOT_PANE" -p "#{pane_width}"  2>/dev/null)
    [[ -z "$rows" || "$rows" -lt 2 ]] && rows="${SURF_GIT_LINES:-10}"
    [[ -z "$cols" || "$cols" -lt 10 ]] && cols=80
    (( rows-- ))   # leave one line at the bottom to avoid scroll

    # Move to top of pane, clear it
    tput cup 0 0
    tput ed

    if ! git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        printf '%s\n' "$(tput setaf 3)not a git repository: $dir$(tput sgr0)"
        return
    fi

    git -C "$dir" \
        log --oneline --graph --decorate --all -n "$rows" \
        --color=always \
        2>/dev/null \
    | head -n "$rows" \
    | cut -c1-"$cols"
}

# ── Main refresh loop ─────────────────────────────────────────────────────
tput civis          # hide cursor in this pane
trap 'tput cnorm; exit' INT TERM EXIT

last_pwd=''
last_refresh=''

while true; do
    # Read current working dir and refresh signal from tmux session env
    cur_pwd=$(tmux show-environment -t "$SURF_SESSION" SURF_PWD 2>/dev/null \
              | sed 's/^SURF_PWD=//')
    [[ -z "$cur_pwd" ]] && cur_pwd="$HOME"

    cur_refresh=$(tmux show-environment -t "$SURF_SESSION" SURF_REFRESH 2>/dev/null \
                  | sed 's/^SURF_REFRESH=//')

    # Redraw only when PWD changes or a command has completed
    if [[ "$cur_pwd" != "$last_pwd" ]] \
       || [[ -n "$cur_refresh" && "$cur_refresh" != "$last_refresh" ]]; then
        _surf_draw_log "$cur_pwd"
        last_pwd="$cur_pwd"
        last_refresh="$cur_refresh"
    fi

    sleep 0.5
done
