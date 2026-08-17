# surf-bot.zsh — tmux adapter for the standalone fancylog renderer

setopt no_prompt_cr

_surf_fancylog_value() {
    local name="$1" fallback="$2" value
    value=$(tmux show-environment -t "$SURF_SESSION" "$name" 2>/dev/null \
            | sed -n "s/^${name}=//p")
    printf '%s' "${value:-$fallback}"
}

_surf_fancylog_find() {
    local candidate
    if [[ -n "${SURF_FANCYLOG:-}" && -x "$SURF_FANCYLOG" ]]; then
        REPLY="$SURF_FANCYLOG"
        return
    fi
    if (( $+commands[fancylog] )); then
        REPLY="${commands[fancylog]}"
        return
    fi
    for candidate in \
        "$SURF_DIR/../fancylog/target/release/fancylog" \
        "$HOME/src/fancylog/target/release/fancylog"; do
        if [[ -x "$candidate" ]]; then
            REPLY="$candidate"
            return
        fi
    done
    REPLY=''
}

_surf_fancylog_repo_signature() {
    local dir="$1"
    local -a cmd
    if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        cmd=(git -C "$dir")
    elif [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]] \
         && (( $+commands[yadm] )) \
         && yadm rev-parse --is-inside-work-tree &>/dev/null; then
        cmd=(yadm)
    else
        REPLY="not-repo:$dir"
        return
    fi

    REPLY=$(
        { "${cmd[@]}" rev-parse HEAD 2>/dev/null
          "${cmd[@]}" for-each-ref \
              --format='%(refname):%(objectname)' \
              refs/heads refs/remotes refs/tags refs/backup 2>/dev/null
        } | cksum | awk '{print $1 ":" $2}'
    )
}

_surf_fancylog_config_signature() {
    local theme="$1" name value signature="$theme"
    local -a names=(
        SURF_GIT_REF_STYLE
        SURF_GIT_HEAD_PLACEMENT
        SURF_GIT_MAIN_PLACEMENT
        SURF_GIT_CURRENT_BRANCH_PLACEMENT
        SURF_GIT_OTHER_LOCAL_BRANCHES_PLACEMENT
        SURF_GIT_REMOTE_MAIN_PLACEMENT
        SURF_GIT_REMOTE_HEAD_PLACEMENT
        SURF_GIT_OTHER_REMOTE_BRANCHES_PLACEMENT
        SURF_GIT_SEPARATOR
        SURF_GIT_LEFT_SPACING
        SURF_GIT_RIGHT_SEPARATOR
        SURF_GIT_RIGHT_SPACING
        SURF_GIT_NODE
        SURF_GIT_HEAD_NODE
        SURF_GIT_SHOW_DATE
        SURF_GIT_SHOW_AUTHOR
        SURF_GIT_HIGHLIGHT_ROW
    )

    if [[ "$theme" == custom ]]; then
        for name in "${names[@]}"; do
            value=$(_surf_fancylog_value "$name" '')
            signature+=$'\n'"${name}=${value}"
        done
    fi
    REPLY="$signature"
}

_surf_fancylog_draw() {
    local dir="$1" theme="$2" rows cols
    local -a args
    rows=$(tmux display-message -t "$SURF_BOT_PANE" -p '#{pane_height}' 2>/dev/null)
    cols=$(tmux display-message -t "$SURF_BOT_PANE" -p '#{pane_width}' 2>/dev/null)
    [[ -z "$rows" || "$rows" -lt 2 ]] && rows="${SURF_GIT_LINES:-10}"
    [[ -z "$cols" || "$cols" -lt 10 ]] && cols=80
    (( rows-- ))

    args=(--no-config --color always --clear --theme "$theme" \
          --width "$cols" --height "$rows")
    if [[ "$theme" == custom ]]; then
        args+=(
            --ref-style "$(_surf_fancylog_value SURF_GIT_REF_STYLE text)"
            --head-placement "$(_surf_fancylog_value SURF_GIT_HEAD_PLACEMENT left)"
            --main-placement "$(_surf_fancylog_value SURF_GIT_MAIN_PLACEMENT left)"
            --current-branch-placement "$(_surf_fancylog_value SURF_GIT_CURRENT_BRANCH_PLACEMENT left)"
            --other-local-branches-placement "$(_surf_fancylog_value SURF_GIT_OTHER_LOCAL_BRANCHES_PLACEMENT left)"
            --remote-main-placement "$(_surf_fancylog_value SURF_GIT_REMOTE_MAIN_PLACEMENT right)"
            --remote-head-placement "$(_surf_fancylog_value SURF_GIT_REMOTE_HEAD_PLACEMENT right)"
            --other-remote-branches-placement "$(_surf_fancylog_value SURF_GIT_OTHER_REMOTE_BRANCHES_PLACEMENT right)"
            --left-separator "$(_surf_fancylog_value SURF_GIT_SEPARATOR arrow)"
            --left-spacing "$(_surf_fancylog_value SURF_GIT_LEFT_SPACING single)"
            --right-separator "$(_surf_fancylog_value SURF_GIT_RIGHT_SEPARATOR arrow)"
            --right-spacing "$(_surf_fancylog_value SURF_GIT_RIGHT_SPACING single)"
            --regular-node "$(_surf_fancylog_value SURF_GIT_NODE star)"
            --head-node "$(_surf_fancylog_value SURF_GIT_HEAD_NODE star)"
            --show-date "$(_surf_fancylog_value SURF_GIT_SHOW_DATE yes)"
            --show-author "$(_surf_fancylog_value SURF_GIT_SHOW_AUTHOR yes)"
            --highlight-head-row "$(_surf_fancylog_value SURF_GIT_HIGHLIGHT_ROW no)"
        )
    fi
    "$FANCYLOG_BIN" "${args[@]}" -- "$dir"
}

_surf_fancylog_find
FANCYLOG_BIN="$REPLY"
if [[ -z "$FANCYLOG_BIN" ]]; then
    printf '\033[H\033[2J\033[33mfancylog not found\033[0m\n'
    printf 'Build ~/src/fancylog with: cargo build --release\n'
    return 127
fi

tput civis
trap 'tput cnorm; exit' INT TERM EXIT

last_pwd=''
last_refresh=''
last_repo_signature=''
last_config_signature=''
last_dimensions=''

while true; do
    tmux display-message -t "$SURF_MAIN_PANE" -p '#{pane_id}' &>/dev/null || exit

    cur_pwd=$(_surf_fancylog_value SURF_PWD "${SURF_START_DIR:-$HOME}")
    cur_refresh=$(_surf_fancylog_value SURF_REFRESH '')
    cur_theme=$(_surf_fancylog_value SURF_GIT_THEME adaptive-diamond)
    case "$cur_theme" in
        adaptive-diamond|arrow|wide|custom|powerline|row-yellow|row-cyan|arrow-hash|hash) ;;
        *) cur_theme=adaptive-diamond ;;
    esac
    cur_dimensions=$(tmux display-message -t "$SURF_BOT_PANE" \
                     -p '#{pane_width}x#{pane_height}' 2>/dev/null)

    if [[ "$cur_pwd" != "$last_pwd" \
       || "$cur_refresh" != "$last_refresh" \
       || "$cur_dimensions" != "$last_dimensions" ]]; then
        _surf_fancylog_repo_signature "$cur_pwd"
        cur_repo_signature="$REPLY"
        _surf_fancylog_config_signature "$cur_theme"
        cur_config_signature="$REPLY"
        if [[ "$cur_pwd" != "$last_pwd" \
           || "$cur_refresh" != "$last_refresh" \
           || "$cur_repo_signature" != "$last_repo_signature" \
           || "$cur_config_signature" != "$last_config_signature" \
           || "$cur_dimensions" != "$last_dimensions" ]]; then
            _surf_fancylog_draw "$cur_pwd" "$cur_theme"
        fi
        last_pwd="$cur_pwd"
        last_refresh="$cur_refresh"
        last_repo_signature="$cur_repo_signature"
        last_config_signature="$cur_config_signature"
        last_dimensions="$cur_dimensions"
    fi
    sleep 0.5
done
