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

_surf_current_head_oid() {
    local dir="$1"
    if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        REPLY=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
    elif [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]] \
         && (( $+commands[yadm] )) \
         && yadm rev-parse --is-inside-work-tree &>/dev/null; then
        REPLY=$(yadm rev-parse HEAD 2>/dev/null)
    else
        REPLY=''
    fi
}

_surf_draw_log() {
    local dir="$1"
    local theme="${2:-adaptive-diamond}"
    local pulse="${3:-none}"
    local -a log_cmd
    local head_oid head_short main_oid
    local separator=$'\x1f'
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

    head_oid=$("${log_cmd[@]}" rev-parse HEAD 2>/dev/null)
    head_short=$("${log_cmd[@]}" rev-parse --short HEAD 2>/dev/null)
    main_oid=$("${log_cmd[@]}" rev-parse --verify refs/heads/main 2>/dev/null) \
        || main_oid=$("${log_cmd[@]}" rev-parse --verify refs/remotes/origin/main 2>/dev/null)

    "${log_cmd[@]}" \
        log --pretty=format:'%H%x1f%C(yellow)%h%C(reset) %C(green)%>|(25)%cr%C(reset) %s %C(bold blue)<%cl>%C(reset) %C(auto)%D%C(reset)' \
        --graph --all -n "$rows" \
        --color=always \
        2>/dev/null \
    | head -n "$rows" \
    | while IFS= read -r line; do
        if [[ "$line" == *"$separator"* ]]; then
            local graph_and_oid="${line%%$separator*}"
            local rendered="${line#*$separator}"
            local oid="${graph_and_oid[-${#head_oid},-1]}"
            local graph="${graph_and_oid[1,-$(( ${#head_oid} + 1 ))]}"
            local head_node=$'\033[1;96m◆\033[0m'
            local main_node=$'\033[1;32m◆\033[0m'
            local head_graph="${graph/\*/$head_node}"
            local main_graph="${graph/\*/$main_node}"
            local is_head=false is_main=false label=HEAD arrow=' -> '
            [[ "$oid" == "$head_oid" ]] && is_head=true
            [[ -n "$main_oid" && "$oid" == "$main_oid" ]] && is_main=true
            if [[ "$is_head" == true && "$is_main" == true ]]; then
                label=H+M
                arrow=' ->  '
            fi

            if [[ "$is_head" == true ]]; then
                local plain='' padding='' cyan_reset=$'\033[0;48;5;23m'
                local hash_badge=$'\033[1;97;44m'"${head_short}"$'\033[0m'
                case "$theme" in
                    adaptive-diamond)
                        if [[ "$pulse" == strong ]]; then
                            plain=$(printf '%s' "${label}${arrow}${graph/\*/◆}${rendered}" | sed $'s/\033\\[[0-9;]*m//g')
                            printf -v padding '%*s' "$cols" ''
                            line=$'\033[1;30;46m'"${plain}${padding}"
                        elif [[ "$pulse" == subtle ]]; then
                            line=$'\033[1;30;46m'"${label}"$'\033[0;97m'"${arrow}"$'\033[0m'"${head_graph}${rendered}"
                        else
                            line=$'\033[1;96m'"${label}"$'\033[0;97m'"${arrow}"$'\033[0m'"${head_graph}${rendered}"
                        fi
                        ;;
                    pulse-arrow)
                        if [[ "$pulse" == strong ]]; then
                            plain=$(printf '%s' "${label}${arrow}${graph}${rendered}" | sed $'s/\033\\[[0-9;]*m//g')
                            printf -v padding '%*s' "$cols" ''
                            line=$'\033[1;30;46m'"${plain}${padding}"
                        else
                            line=$'\033[1;96m'"${label}"$'\033[0;97m'"${arrow}"$'\033[0m'"${graph}${rendered}"
                        fi
                        ;;
                    arrow)
                        line=$'\033[1;96m'"${label}"$'\033[0;97m'"${arrow}"$'\033[0m'"${graph}${rendered}"
                        ;;
                    powerline)
                        if [[ "$label" == H+M ]]; then
                            line=$'\033[1;30;43m H+M  \033[0;33m\033[0m '"${graph}${rendered}"
                        else
                            line=$'\033[1;30;46m HEAD \033[0;36m\033[0m '"${graph}${rendered}"
                        fi
                        ;;
                    row-yellow)
                        plain=$(printf '%s' "${label}${arrow}${graph}${rendered}" | sed $'s/\033\\[[0-9;]*m//g')
                        printf -v padding '%*s' "$cols" ''
                        line=$'\033[1;30;103m'"${plain}${padding}"
                        ;;
                    row-cyan)
                        line=$'\033[48;5;23m\033[1;97m'"${label}"$'\033[22m'"${arrow}${graph}${rendered}"
                        line="${line//$'\033[0m'/$cyan_reset}"
                        line="${line//$'\033[m'/$cyan_reset}"
                        printf -v padding '%*s' "$cols" ''
                        line+="$padding"
                        ;;
                    arrow-hash)
                        rendered="${rendered/$head_short/$hash_badge}"
                        line=$'\033[1;96m'"${label}"$'\033[0;97m'"${arrow}"$'\033[0m'"${graph}${rendered}"
                        ;;
                    hash)
                        rendered="${rendered/$head_short/$hash_badge}"
                        line="${graph}${rendered}"
                        ;;
                esac
            elif [[ -n "$main_oid" && "$oid" == "$main_oid" ]]; then
                case "$theme" in
                    hash) line="${graph}${rendered}" ;;
                    powerline) line=$'\033[1;30;42m MAIN \033[0;32m\033[0m '"${graph}${rendered}" ;;
                    adaptive-diamond) line=$'\033[1;32mMAIN\033[0;97m -> \033[0m'"${main_graph}${rendered}" ;;
                    *) line=$'\033[1;32mMAIN\033[0;97m -> \033[0m'"${graph}${rendered}" ;;
                esac
            else
                [[ "$theme" == hash ]] && line="${graph}${rendered}" \
                    || line="        ${graph}${rendered}"
            fi
        else
            # Graph connector-only rows need the same gutter to preserve the
            # shape and alignment of merge lines.
            [[ "$theme" == hash ]] || line="        ${line}"
        fi
        _surf_truncate_ansi "$line" "$cols"
        printf '%s\n' "$REPLY"
      done
}

# ── Main refresh loop ─────────────────────────────────────────────────────
tput civis          # hide cursor in this pane
trap 'tput cnorm; exit' INT TERM EXIT

last_pwd=''
last_refresh=''
last_head_oid=''
last_theme=''

while true; do
    tmux display-message -t "$SURF_MAIN_PANE" -p '#{pane_id}' &>/dev/null \
        || exit

    # Read current working dir and refresh signal from tmux session env
    cur_pwd=$(tmux show-environment -t "$SURF_SESSION" SURF_PWD 2>/dev/null \
              | sed 's/^SURF_PWD=//')
    [[ -z "$cur_pwd" ]] && cur_pwd="${SURF_START_DIR:-$HOME}"

    cur_refresh=$(tmux show-environment -t "$SURF_SESSION" SURF_REFRESH 2>/dev/null \
                  | sed 's/^SURF_REFRESH=//')
    cur_theme=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_THEME 2>/dev/null \
                | sed 's/^SURF_GIT_THEME=//')
    [[ -z "$cur_theme" ]] && cur_theme=adaptive-diamond
    case "$cur_theme" in
        adaptive-diamond|pulse-arrow|arrow|powerline|row-yellow|row-cyan|arrow-hash|hash) ;;
        *) cur_theme=adaptive-diamond ;;
    esac

    # Redraw only when PWD changes or a command has completed
    if [[ "$cur_pwd" != "$last_pwd" ]] \
       || [[ -n "$cur_refresh" && "$cur_refresh" != "$last_refresh" ]] \
       || [[ "$cur_theme" != "$last_theme" ]]; then
        _surf_current_head_oid "$cur_pwd"
        current_head_oid="$REPLY"
        pulse=none
        case "$cur_theme" in
            adaptive-diamond)
                if [[ -n "$current_head_oid" && "$current_head_oid" != "$last_head_oid" ]]; then
                    pulse=strong; pulse_delay=0.2
                else
                    pulse=subtle; pulse_delay=0.08
                fi
                ;;
            pulse-arrow) pulse=strong; pulse_delay=0.2 ;;
        esac
        if [[ "$pulse" != none ]]; then
            _surf_draw_log "$cur_pwd" "$cur_theme" "$pulse"
            sleep "$pulse_delay"
        fi
        _surf_draw_log "$cur_pwd" "$cur_theme"
        last_pwd="$cur_pwd"
        last_refresh="$cur_refresh"
        last_head_oid="$current_head_oid"
        last_theme="$cur_theme"
    fi

    sleep 0.5
done
