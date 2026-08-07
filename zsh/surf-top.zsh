# surf-top.zsh — top pane (2–10 rows): live Git/yadm worktree status

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

_surf_status_paint() {
    local bg="$1" fg="$2"
    shift 2
    local -a lines=("$@")
    local rows cols line i

    rows=$(tmux display-message -t "$SURF_TOP_PANE" -p "#{pane_height}" 2>/dev/null)
    cols=$(tmux display-message -t "$SURF_TOP_PANE" -p "#{pane_width}" 2>/dev/null)
    [[ -z "$rows" || "$rows" -lt 2 ]] && rows=2
    [[ -z "$cols" || "$cols" -lt 10 ]] && cols=80

    printf '\033[H\033[2J\033[48;5;%sm\033[38;5;%sm' "$bg" "$fg"
    for (( i = 1; i <= rows; i++ )); do
        line="${lines[$i]:-}"
        line="${line[1,$cols]}"
        printf '%-*s' "$cols" "$line"
        (( i < rows )) && printf '\n'
    done
    printf '\033[0m'
}

_surf_draw_status() {
    local dir="$1"
    local -a reply status_lines shown lines cmd
    local branch desired total visible remaining

    if ! _surf_status_command "$dir"; then
        tmux resize-pane -t "$SURF_TOP_PANE" -y 2 2>/dev/null
        _surf_status_paint "$SURF_STATUS_DIRTY_BG" "$SURF_STATUS_DIRTY_FG" \
            "  ?  not a Git repository · $dir"
        return
    fi

    cmd=("${reply[@]}")
    _surf_status_branch
    branch="$REPLY"
    status_lines=("${(@f)$("${cmd[@]}" status --short 2>/dev/null)}")
    [[ ${#status_lines} -eq 1 && -z "$status_lines[1]" ]] && status_lines=()

    if (( ${#status_lines} == 0 )); then
        tmux resize-pane -t "$SURF_TOP_PANE" -y 2 2>/dev/null
        _surf_status_paint "$SURF_STATUS_CLEAN_BG" "$SURF_STATUS_CLEAN_FG" \
            "  ✓  working tree is clean · $branch"
        return
    fi

    total=${#status_lines}
    desired=$(( total + 1 ))
    (( desired < 2 )) && desired=2
    (( desired > 10 )) && desired=10
    visible=$(( desired - 1 ))

    if (( total > visible )); then
        visible=$(( visible - 1 ))
        shown=("${status_lines[@]:0:$visible}")
        remaining=$(( total - visible ))
        shown+=(" …  $remaining more changed file(s)")
    else
        shown=("${status_lines[@]}")
    fi

    lines=("  ●  working tree has changes · $branch" "${shown[@]}")
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
