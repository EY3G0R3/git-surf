# surf-bot.zsh — bottom pane (30 %): live git log
#
# Redraws the git log whenever SURF_PWD or SURF_REFRESH changes.
# SURF_REFRESH is bumped by the top pane after each command completes,
# so the bottom pane only redraws on real activity — no timer-driven blink.

# No interactive prompt needed
setopt no_prompt_cr

_surf_truncate_ansi() {
    local input="$1"
    local limit="$2"
    local output='' sequence='' char
    local -i index=1 visible=0 length=${#input}

    while (( index <= length && visible < limit )); do
        char="${input[$index]}"
        if [[ "$char" == $'\033' && "${input[$(( index + 1 ))]}" == '[' ]]; then
            # Consume the CSI introducer together.  '[' is in the CSI final-byte
            # range, so examining it in the loop below would end the sequence
            # immediately and count its parameters (for example, "31m") as
            # visible text.
            sequence=$'\033['
            (( index += 2 ))
            while (( index <= length )); do
                char="${input[$index]}"
                sequence+="$char"
                (( index += 1 ))
                [[ "$char" == [@-~] ]] && break
            done
            output+="$sequence"
            sequence=''
            continue
        fi

        output+="$char"
        (( visible += 1 ))
        (( index += 1 ))
    done

    REPLY="$output"$'\033[0m'
}

_surf_draw_log() {
    local dir="$1"
    local -a log_cmd
    # Query actual pane height each draw so resizes and rounding never mismatch
    local rows cols
    rows=$(tmux display-message -t "$SURF_BOT_PANE" -p "#{pane_height}" 2>/dev/null)
    cols=$(tmux display-message -t "$SURF_BOT_PANE" -p "#{pane_width}" 2>/dev/null)
    [[ -z "$rows" || "$rows" -lt 2 ]] && rows="${SURF_GIT_LINES:-10}"
    [[ -z "$cols" || "$cols" -lt 10 ]] && cols=80
    (( rows-- ))   # leave one line at the bottom to avoid scroll

    # Move to top of pane, clear it
    tput cup 0 0
    tput ed

    if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        log_cmd=(git -C "$dir")
    elif [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]] \
         && (( $+commands[yadm] )) \
         && yadm rev-parse --is-inside-work-tree &>/dev/null; then
        # yadm's work tree is $HOME, so every directory below it is covered.
        # Prefer a regular repository above when one is nested in that tree.
        log_cmd=(yadm)
    else
        printf '%s\n' "$(tput setaf 3)not a git repository: $dir$(tput sgr0)"
        return
    fi

    "${log_cmd[@]}" \
        log --oneline --graph --decorate --all -n "$rows" \
        --color=always \
        2>/dev/null \
    | head -n "$rows" \
    | while IFS= read -r line; do
        _surf_truncate_ansi "$line" "$cols"
        printf '%s\n' "$REPLY"
      done
}

# ── Main refresh loop ─────────────────────────────────────────────────────
tput civis          # hide cursor in this pane
trap 'tput cnorm; exit' INT TERM EXIT

last_pwd=''
last_refresh=''

while true; do
    tmux display-message -t "$SURF_MAIN_PANE" -p '#{pane_id}' &>/dev/null \
        || exit

    # Read current working dir and refresh signal from tmux session env
    cur_pwd=$(tmux show-environment -t "$SURF_SESSION" SURF_PWD 2>/dev/null \
              | sed 's/^SURF_PWD=//')
    [[ -z "$cur_pwd" ]] && cur_pwd="${SURF_START_DIR:-$HOME}"

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
