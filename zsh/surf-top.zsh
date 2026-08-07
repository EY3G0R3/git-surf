# surf-top.zsh — top pane (4–10 rows): live Git/yadm worktree status

setopt no_prompt_cr

typeset -gr SURF_STATUS_CLEAN_BG=22
typeset -gr SURF_STATUS_DIRTY_BG=58
typeset -gr SURF_STATUS_CLEAN_FG=157
typeset -gr SURF_STATUS_DIRTY_FG=229
# Available layouts: split, file-centered
typeset -gr SURF_STATUS_LAYOUT=split

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

_surf_status_action() {
    case "$1" in
        M) REPLY='modified' ;;
        A) REPLY='added' ;;
        D) REPLY='deleted' ;;
        R) REPLY='renamed' ;;
        C) REPLY='copied' ;;
        T) REPLY='type change' ;;
        *) REPLY='' ;;
    esac
}

_surf_parse_status_line() {
    local entry="$1"
    local code="${entry[1,2]}"
    local index="${code[1]}" worktree="${code[2]}"
    local staged='' unstaged=''

    case "$code" in
        '??') unstaged='untracked' ;;
        *U*|'AA'|'DD') staged='conflict'; unstaged='conflict' ;;
        *)
            _surf_status_action "$index"
            staged="$REPLY"
            _surf_status_action "$worktree"
            unstaged="$REPLY"
            ;;
    esac

    reply=("$staged" "$unstaged" "${entry[4,-1]}")
}

_surf_color_action() {
    local line="$1"
    local forced_color="${2:-}"
    local label color colored

    case "$line" in
        *'type change'*) label='type change'; color=33 ;;
        *'modified'*)    label='modified';    color=33 ;;
        *'added'*)       label='added';       color=32 ;;
        *'copied'*)      label='copied';      color=32 ;;
        *'renamed'*)     label='renamed';     color=36 ;;
        *'deleted'*)     label='deleted';     color=31 ;;
        *'untracked'*)   label='untracked';   color=31 ;;
        *'conflict'*)    label='conflict';    color=31 ;;
        *)
            REPLY="$line"
            return
            ;;
    esac
    [[ -n "$forced_color" ]] && color="$forced_color"

    printf -v colored '\033[%sm%s\033[38;5;%sm' \
        "$color" "$label" "$SURF_STATUS_DIRTY_FG"
    REPLY="${line/$label/$colored}"
}

_surf_color_status_row() {
    local line="$1"
    local left middle right

    [[ "$line" == *' │ '* ]] || {
        REPLY="$line"
        return
    }

    left="${line%%' │ '*}"
    right="${line#*' │ '}"
    if [[ "$right" == *' │ '* ]]; then
        middle="${right%%' │ '*}"
        right="${right#*' │ '}"
        _surf_color_action "$left" 32
        left="$REPLY"
        _surf_color_action "$right"
        right="$REPLY"
        REPLY="$left │ $middle │ $right"
    else
        _surf_color_action "$left" 32
        left="$REPLY"
        _surf_color_action "$right"
        right="$REPLY"
        REPLY="$left │ $right"
    fi
}

_surf_render_split() {
    local cols="$1"
    shift
    local -a entries=("$@") staged_lines unstaged_lines rendered
    local -a parsed
    local entry staged unstaged path text left right rule
    local -i block_width cell_width path_width total visible desired remaining i

    block_width=$cols
    (( block_width > 110 )) && block_width=110
    cell_width=$(( (block_width - 3) / 2 ))
    path_width=$(( cell_width - 13 ))
    (( path_width < 1 )) && path_width=1

    for entry in "${entries[@]}"; do
        _surf_parse_status_line "$entry"
        parsed=("${reply[@]}")
        staged="${parsed[1]}"
        unstaged="${parsed[2]}"
        path="${parsed[3]}"
        if [[ -n "$staged" ]]; then
            printf -v text '%s  %s' "${path[1,$path_width]}" "$staged"
            staged_lines+=("$text")
        fi
        if [[ -n "$unstaged" ]]; then
            printf -v text '%11s  %s' "$unstaged" "${path[1,$path_width]}"
            unstaged_lines+=("$text")
        fi
    done

    total=${#staged_lines}
    (( ${#unstaged_lines} > total )) && total=${#unstaged_lines}
    desired=$(( total + 5 ))
    (( desired > 10 )) && desired=10
    visible=$(( desired - 5 ))

    printf -v left '%*s' "$cell_width" 'STAGED CHANGES'
    printf -v right '%-*s' "$cell_width" 'UNSTAGED CHANGES'
    rendered+=("$left │ $right")
    rule="${(l:$cell_width::─:)}─┼─${(l:$cell_width::─:)}"
    rendered+=("$rule")

    for (( i = 1; i <= visible; i++ )); do
        if (( i == visible && ${#staged_lines} > visible )); then
            remaining=$(( ${#staged_lines} - visible + 1 ))
            left="… $remaining more staged"
        else
            left="${staged_lines[$i]:-}"
        fi
        if (( i == visible && ${#unstaged_lines} > visible )); then
            remaining=$(( ${#unstaged_lines} - visible + 1 ))
            right="… $remaining more unstaged"
        else
            right="${unstaged_lines[$i]:-}"
        fi
        left="${left[1,$cell_width]}"
        right="${right[1,$cell_width]}"
        printf -v left '%*s' "$cell_width" "$left"
        printf -v right '%-*s' "$cell_width" "$right"
        rendered+=("$left │ $right")
    done

    SURF_DIRTY_HEIGHT=$desired
    SURF_DIRTY_LINES=("${rendered[@]}")
}

_surf_render_file_centered() {
    local cols="$1"
    shift
    local -a entries=("$@") rendered parsed
    local entry staged unstaged path left middle right rule
    local -i block_width status_width=16 file_width total visible desired remaining i

    block_width=$cols
    (( block_width > 110 )) && block_width=110
    file_width=$(( block_width - status_width * 2 - 6 ))
    (( file_width < 12 )) && file_width=12

    printf -v left '%*s' "$status_width" 'STAGED CHANGES'
    printf -v middle '%-*s' "$file_width" 'FILE'
    printf -v right '%-*s' "$status_width" 'UNSTAGED CHANGES'
    rendered+=("$left │ $middle │ $right")
    rule="${(l:$status_width::─:)}─┼─${(l:$file_width::─:)}─┼─${(l:$status_width::─:)}"
    rendered+=("$rule")

    total=${#entries}
    desired=$(( total + 5 ))
    (( desired > 10 )) && desired=10
    visible=$(( desired - 5 ))

    for (( i = 1; i <= visible; i++ )); do
        if (( i == visible && total > visible )); then
            remaining=$(( total - visible + 1 ))
            printf -v middle '%-*s' "$file_width" "… $remaining more changed files"
            printf -v left '%*s' "$status_width" ''
            printf -v right '%-*s' "$status_width" ''
        else
            _surf_parse_status_line "${entries[$i]}"
            parsed=("${reply[@]}")
            staged="${parsed[1]}"
            unstaged="${parsed[2]}"
            path="${parsed[3][1,$file_width]}"
            printf -v left '%*s' "$status_width" "$staged"
            printf -v middle '%-*s' "$file_width" "$path"
            printf -v right '%-*s' "$status_width" "$unstaged"
        fi
        rendered+=("$left │ $middle │ $right")
    done

    SURF_DIRTY_HEIGHT=$desired
    SURF_DIRTY_LINES=("${rendered[@]}")
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
        if (( i >= 5 )); then
            _surf_color_status_row "$line"
            line="$REPLY"
        fi
        # Paint the complete row first. ANSI sequences in colored labels do
        # not consume terminal columns, but printf counts them when applying a
        # field width and would otherwise leave the right side unpainted.
        printf '%*s\r%s' "$cols" '' "$line"
        (( i < rows )) && printf '\n'
    done
    printf '\033[0m'
}

_surf_draw_status() {
    local dir="$1"
    local -a reply status_lines lines cmd
    local branch display_dir cols

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

    cols=$(tmux display-message -t "$SURF_TOP_PANE" -p '#{pane_width}' 2>/dev/null)
    [[ -z "$cols" || "$cols" -lt 40 ]] && cols=80
    case "$SURF_STATUS_LAYOUT" in
        split)
            _surf_render_split "$cols" "${status_lines[@]}"
            ;;
        file-centered)
            _surf_render_file_centered "$cols" "${status_lines[@]}"
            ;;
        *)
            _surf_render_split "$cols" "${status_lines[@]}"
            ;;
    esac

    lines=(
        "  $branch"
        "  $display_dir"
        ""
        "${SURF_DIRTY_LINES[@]}"
    )
    tmux resize-pane -t "$SURF_TOP_PANE" -y "$SURF_DIRTY_HEIGHT" 2>/dev/null
    _surf_status_paint "$SURF_STATUS_DIRTY_BG" "$SURF_STATUS_DIRTY_FG" \
        "${lines[@]}"
}

tput civis
trap 'printf "\033[0m"; tput cnorm; exit' INT TERM EXIT

last_pwd=''
last_refresh=''
last_size=''

while true; do
    tmux display-message -t "$SURF_MAIN_PANE" -p '#{pane_id}' &>/dev/null \
        || exit

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
