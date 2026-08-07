# surf-top.zsh — top pane (4–10 rows): live Git/yadm worktree status

setopt no_prompt_cr

typeset -gr SURF_STATUS_CLEAN_BG=22
typeset -gr SURF_STATUS_DIRTY_BG=58
typeset -gr SURF_STATUS_CLEAN_FG=157
typeset -gr SURF_STATUS_DIRTY_FG=229

_surf_status_command() {
    local dir="$1"

    if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        reply=(git -C "$dir")
        return 0
    fi

    if [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]] \
       && (( $+commands[yadm] )) \
       && yadm rev-parse --is-inside-work-tree &>/dev/null; then
        reply=(yadm)
        return 0
    fi

    return 1
}

_surf_status_branch() {
    local -a cmd=("${reply[@]}")
    local branch
    branch=$("${cmd[@]}" symbolic-ref --quiet --short HEAD 2>/dev/null) \
        || branch=$("${cmd[@]}" rev-parse --short HEAD 2>/dev/null) \
        || branch='unknown'
    REPLY="$branch"
}

_surf_format_status_line() {
    local entry="$1"
    local code="${entry[1,2]}"
    local path="${entry[4,-1]}"
    local label

    case "$code" in
        '??') label='untracked' ;;
        *U*|'AA'|'DD') label='conflict' ;;
        R*) label='renamed' ;;
        C*) label='copied' ;;
        A*) label='added' ;;
        *D*|D*) label='deleted' ;;
        *T*|T*) label='type change' ;;
        *) label='modified' ;;
    esac

    printf -v REPLY '%11s  %s' "$label" "$path"
}

_surf_status_paint() {
    local bg="$1" fg="$2"
    shift 2
    local -a lines=("$@")
    local rows cols line i padding block_width=0 block_padding=0

    rows=$(tmux display-message -t "$SURF_TOP_PANE" -p "#{pane_height}" 2>/dev/null)
    cols=$(tmux display-message -t "$SURF_TOP_PANE" -p "#{pane_width}" 2>/dev/null)
    [[ -z "$rows" || "$rows" -lt 4 ]] && rows=4
    [[ -z "$cols" || "$cols" -lt 10 ]] && cols=80

    for (( i = 5; i <= ${#lines}; i++ )); do
        (( ${#lines[$i]} > block_width )) && block_width=${#lines[$i]}
    done
    (( block_width < cols )) && block_padding=$(( (cols - block_width) / 2 ))

    printf '\033[H\033[2J\033[48;5;%sm\033[38;5;%sm' "$bg" "$fg"
    for (( i = 1; i <= rows; i++ )); do
        line="${lines[$i]:-}"
        if (( i <= 4 && ${#line} < cols )); then
            padding=$(( (cols - ${#line}) / 2 ))
            printf -v line '%*s%s' "$padding" '' "$line"
        elif (( i >= 5 && block_padding > 0 && ${#line} > 0 )); then
            printf -v line '%*s%s' "$block_padding" '' "$line"
        fi
        line="${line[1,$cols]}"
        printf '%-*s' "$cols" "$line"
        (( i < rows )) && printf '\n'
    done
    printf '\033[0m'
}

_surf_draw_status() {
    local dir="$1"
    local -a reply status_lines shown lines cmd
    local branch display_dir desired total visible remaining
    local -i i

    if [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]]; then
        display_dir="~${dir#$HOME}"
    else
        display_dir="$dir"
    fi

    if ! _surf_status_command "$dir"; then
        tmux resize-pane -t "$SURF_TOP_PANE" -y 4 2>/dev/null
        _surf_status_paint "$SURF_STATUS_DIRTY_BG" "$SURF_STATUS_DIRTY_FG" \
            "  no repository" \
            "  $display_dir" \
            "" \
            "?  not a Git or yadm working tree"
        return
    fi

    cmd=("${reply[@]}")
    _surf_status_branch
    branch="$REPLY"
    status_lines=("${(@f)$("${cmd[@]}" status --short 2>/dev/null)}")
    [[ ${#status_lines} -eq 1 && -z "$status_lines[1]" ]] && status_lines=()

    if (( ${#status_lines} == 0 )); then
        tmux resize-pane -t "$SURF_TOP_PANE" -y 4 2>/dev/null
        _surf_status_paint "$SURF_STATUS_CLEAN_BG" "$SURF_STATUS_CLEAN_FG" \
            "  $branch" \
            "  $display_dir" \
            "" \
            "✓  working tree is clean"
        return
    fi

    total=${#status_lines}
    desired=$(( total + 4 ))
    (( desired < 4 )) && desired=4
    (( desired > 10 )) && desired=10
    visible=$(( desired - 4 ))

    if (( total > visible )); then
        visible=$(( visible - 1 ))
        shown=("${status_lines[@]:0:$visible}")
        remaining=$(( total - visible ))
        shown+=(" …  $remaining more changed file(s)")
    else
        shown=("${status_lines[@]}")
    fi

    for (( i = 1; i <= ${#shown}; i++ )); do
        [[ "${shown[$i]}" == ' … '* ]] && continue
        _surf_format_status_line "${shown[$i]}"
        shown[$i]="$REPLY"
    done

    lines=(
        "  $branch"
        "  $display_dir"
        ""
        "──  Working tree has changes  ──"
        "${shown[@]}"
    )
    tmux resize-pane -t "$SURF_TOP_PANE" -y "$desired" 2>/dev/null
    _surf_status_paint "$SURF_STATUS_DIRTY_BG" "$SURF_STATUS_DIRTY_FG" \
        "${lines[@]}"
}

tput civis
trap 'printf "\033[0m"; tput cnorm; exit' INT TERM EXIT

last_pwd=''
last_refresh=''
last_size=''

while true; do
    cur_pwd=$(tmux show-environment -t "$SURF_SESSION" SURF_PWD 2>/dev/null \
              | sed 's/^SURF_PWD=//')
    [[ -z "$cur_pwd" ]] && cur_pwd="${SURF_START_DIR:-$HOME}"

    cur_refresh=$(tmux show-environment -t "$SURF_SESSION" SURF_REFRESH 2>/dev/null \
                  | sed 's/^SURF_REFRESH=//')
    cur_size=$(tmux display-message -t "$SURF_TOP_PANE" \
               -p "#{pane_width}x#{pane_height}" 2>/dev/null)

    if [[ "$cur_pwd" != "$last_pwd" ]] \
       || [[ -n "$cur_refresh" && "$cur_refresh" != "$last_refresh" ]] \
       || [[ "$cur_size" != "$last_size" ]]; then
        _surf_draw_status "$cur_pwd"
        last_pwd="$cur_pwd"
        last_refresh="$cur_refresh"
        last_size=$(tmux display-message -t "$SURF_TOP_PANE" \
                    -p "#{pane_width}x#{pane_height}" 2>/dev/null)
    fi

    sleep 0.5
done
