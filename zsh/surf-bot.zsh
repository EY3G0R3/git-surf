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

_surf_current_primary_oid() {
    local dir="$1"
    local -a cmd
    local configured primary_ref candidate oid=''
    if git -C "$dir" rev-parse --is-inside-work-tree &>/dev/null; then
        cmd=(git -C "$dir")
    elif [[ "$dir" == "$HOME" || "$dir" == "$HOME"/* ]] \
         && (( $+commands[yadm] )) \
         && yadm rev-parse --is-inside-work-tree &>/dev/null; then
        cmd=(yadm)
    else
        REPLY=''
        return
    fi

    configured=$("${cmd[@]}" config --get surf.primaryBranch 2>/dev/null)
    if [[ -n "$configured" ]]; then
        for candidate in "refs/heads/$configured" \
                         "refs/remotes/origin/$configured" "$configured"; do
            oid=$("${cmd[@]}" rev-parse --verify "$candidate" 2>/dev/null) || continue
            break
        done
    fi
    if [[ -z "$oid" ]]; then
        primary_ref=$("${cmd[@]}" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
        if [[ -n "$primary_ref" ]]; then
            local name="${primary_ref#refs/remotes/origin/}"
            oid=$("${cmd[@]}" rev-parse --verify "refs/heads/$name" 2>/dev/null) \
                || oid=$("${cmd[@]}" rev-parse --verify "$primary_ref" 2>/dev/null) \
                || oid=''
        fi
    fi
    if [[ -z "$oid" ]]; then
        for candidate in refs/heads/main refs/heads/master \
                         refs/remotes/origin/main refs/remotes/origin/master; do
            oid=$("${cmd[@]}" rev-parse --verify "$candidate" 2>/dev/null) || continue
            break
        done
    fi
    REPLY="$oid"
}

_surf_repo_signature() {
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
              refs/heads refs/remotes refs/tags 2>/dev/null
        } | cksum | awk '{print $1 ":" $2}'
    )
}

_surf_render_config_signature() {
    local theme="$1"
    local name value signature="$theme"
    local -a names=(
        SURF_GIT_REF_STYLE
        SURF_GIT_SEPARATOR
        SURF_GIT_RIGHT_SEPARATOR
        SURF_GIT_NODE
        SURF_GIT_HEAD_NODE
        SURF_GIT_SHOW_DATE
        SURF_GIT_SHOW_AUTHOR
        SURF_GIT_HIGHLIGHT_ROW
    )

    if [[ "$theme" == custom ]]; then
        for name in "${names[@]}"; do
            value=$(tmux show-environment -t "$SURF_SESSION" "$name" 2>/dev/null \
                    | sed -n "s/^${name}=//p")
            signature+=$'\n'"${name}=${value}"
        done
    fi
    REPLY="$signature"
}

_surf_draw_log() {
    local dir="$1"
    local theme="${2:-adaptive-diamond}"
    local pulse="${3:-none}"
    local -a log_cmd
    local -a log_lines decoration_args
    local -A wide_branches custom_remotes
    local head_oid head_short primary_oid='' primary_name=''
    local ref_style=text configured_separator=arrow configured_right_separator=arrow
    local configured_node=star configured_head_node=star
    local show_date=yes show_author=yes highlight_row=no pretty
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

    if [[ "$theme" == custom ]]; then
        ref_style=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_REF_STYLE 2>/dev/null \
                    | sed -n 's/^SURF_GIT_REF_STYLE=//p')
        configured_separator=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_SEPARATOR 2>/dev/null \
                               | sed -n 's/^SURF_GIT_SEPARATOR=//p')
        configured_right_separator=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_RIGHT_SEPARATOR 2>/dev/null \
                                     | sed -n 's/^SURF_GIT_RIGHT_SEPARATOR=//p')
        configured_node=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_NODE 2>/dev/null \
                      | sed -n 's/^SURF_GIT_NODE=//p')
        configured_head_node=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_HEAD_NODE 2>/dev/null \
                               | sed -n 's/^SURF_GIT_HEAD_NODE=//p')
        show_date=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_SHOW_DATE 2>/dev/null \
                    | sed -n 's/^SURF_GIT_SHOW_DATE=//p')
        show_author=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_SHOW_AUTHOR 2>/dev/null \
                      | sed -n 's/^SURF_GIT_SHOW_AUTHOR=//p')
        highlight_row=$(tmux show-environment -t "$SURF_SESSION" SURF_GIT_HIGHLIGHT_ROW 2>/dev/null \
                        | sed -n 's/^SURF_GIT_HIGHLIGHT_ROW=//p')
        [[ "$ref_style" == powerline ]] || ref_style=text
        [[ "$configured_separator" == none ]] || configured_separator=arrow
        [[ "$configured_right_separator" == none ]] || configured_right_separator=arrow
        [[ "$configured_node" == diamond || "$configured_node" == none ]] || configured_node=star
        [[ "$configured_head_node" == diamond || "$configured_head_node" == none ]] || configured_head_node=star
        [[ "$show_date" == no ]] || show_date=yes
        [[ "$show_author" == no ]] || show_author=yes
        [[ "$highlight_row" == yes ]] || highlight_row=no
    fi

    head_oid=$("${log_cmd[@]}" rev-parse HEAD 2>/dev/null)
    head_short=$("${log_cmd[@]}" rev-parse --short HEAD 2>/dev/null)
    local configured_primary primary_ref candidate
    configured_primary=$("${log_cmd[@]}" config --get surf.primaryBranch 2>/dev/null)
    if [[ -n "$configured_primary" ]]; then
        for candidate in "refs/heads/$configured_primary" \
                         "refs/remotes/origin/$configured_primary" \
                         "$configured_primary"; do
            primary_oid=$("${log_cmd[@]}" rev-parse --verify "$candidate" 2>/dev/null) || continue
            primary_name="${configured_primary#refs/heads/}"
            primary_name="${primary_name#refs/remotes/origin/}"
            break
        done
    fi
    if [[ -z "$primary_oid" ]]; then
        primary_ref=$("${log_cmd[@]}" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)
        if [[ -n "$primary_ref" ]]; then
            primary_name="${primary_ref#refs/remotes/origin/}"
            # origin/HEAD identifies the primary branch by name, but its
            # remote-tracking commit may lag a local branch that is ahead.
            # Prefer the local branch position when that branch exists.
            primary_oid=$("${log_cmd[@]}" rev-parse --verify \
                "refs/heads/$primary_name" 2>/dev/null) \
                || primary_oid=$("${log_cmd[@]}" rev-parse --verify \
                    "$primary_ref" 2>/dev/null) \
                || primary_oid=''
            [[ -n "$primary_oid" ]] || primary_name=''
        fi
    fi
    if [[ -z "$primary_oid" ]]; then
        for candidate in refs/heads/main refs/heads/master \
                         refs/remotes/origin/main refs/remotes/origin/master; do
            primary_oid=$("${log_cmd[@]}" rev-parse --verify "$candidate" 2>/dev/null) || continue
            primary_name="${candidate##*/}"
            break
        done
    fi

    if [[ "$theme" == wide ]]; then
        decoration_args=(--decorate-refs=refs/remotes --decorate-refs=refs/tags)
    elif [[ "$theme" == custom ]]; then
        # Remote refs are rendered separately so they can use a mirrored,
        # independently configurable separator. Git still owns tag decoration.
        decoration_args=(--decorate-refs=refs/tags)
    fi
    pretty='%H%x1f%C(yellow)%h%C(reset)'
    [[ "$theme" != custom || "$show_date" == yes ]] \
        && pretty+=' %C(green)%>|(25)%cr%C(reset)'
    pretty+=' %s'
    [[ "$theme" != custom || "$show_author" == yes ]] \
        && pretty+=' %C(bold blue)<%cl>%C(reset)'
    pretty+=' %C(auto)%D%C(reset)'
    log_lines=("${(@f)$("${log_cmd[@]}" \
        log "--pretty=format:${pretty}" \
        --graph --all --date-order -n "$rows" \
        --color=always "${decoration_args[@]}" \
        2>/dev/null)}")
    log_lines=("${log_lines[@]:0:$rows}")

    local gutter_width=8 gutter='        '
    if [[ -n "$primary_name" ]]; then
        (( ${#primary_name} + 4 > gutter_width )) && gutter_width=$(( ${#primary_name} + 4 ))
    fi
    if [[ "$theme" == wide || "$theme" == custom ]]; then
        gutter_width=1
        local ref_line ref_oid ref_name visible_line
        while IFS= read -r ref_line; do
            ref_oid="${ref_line%% *}"
            ref_name="${ref_line#* }"
            for visible_line in "${log_lines[@]}"; do
                [[ "$visible_line" == *"${ref_oid}${separator}"* ]] || continue
                if [[ -n "${wide_branches[$ref_oid]}" ]]; then
                    wide_branches[$ref_oid]+=$'\n'"${ref_name}"
                else
                    wide_branches[$ref_oid]="$ref_name"
                fi
                break
            done
        done < <("${log_cmd[@]}" for-each-ref --format='%(objectname) %(refname:short)' refs/heads 2>/dev/null)

        if [[ "$theme" == custom ]]; then
            while IFS= read -r ref_line; do
                ref_oid="${ref_line%% *}"
                ref_name="${ref_line#* }"
                ref_name="${ref_name#refs/remotes/}"
                for visible_line in "${log_lines[@]}"; do
                    [[ "$visible_line" == *"${ref_oid}${separator}"* ]] || continue
                    if [[ -n "${custom_remotes[$ref_oid]}" ]]; then
                        custom_remotes[$ref_oid]+=$'\n'"${ref_name}"
                    else
                        custom_remotes[$ref_oid]="$ref_name"
                    fi
                    break
                done
            done < <("${log_cmd[@]}" for-each-ref \
                --format='%(objectname) %(refname)' refs/remotes 2>/dev/null)
        fi

        local wide_oid wide_names wide_width wide_name
        for wide_oid wide_names in "${(@kv)wide_branches}"; do
            wide_width=0
            if [[ "$theme" == custom && "$ref_style" == powerline ]]; then
                local -i powerline_separator_width=1
                [[ "$configured_separator" == none ]] && powerline_separator_width=0
                [[ "$wide_oid" == "$head_oid" ]] && (( wide_width += 6 + powerline_separator_width ))
                for wide_name in "${(f)wide_names}"; do
                    (( wide_width += ${#wide_name} + 2 + powerline_separator_width ))
                done
                [[ "$configured_separator" == none ]] && (( wide_width += 1 ))
            else
                local -i separator_width=4
                [[ "$theme" == custom && "$configured_separator" == none ]] && separator_width=1
                [[ "$wide_oid" == "$head_oid" ]] && (( wide_width += 4 + separator_width ))
                for wide_name in "${(f)wide_names}"; do
                    (( wide_width += ${#wide_name} + separator_width ))
                done
            fi
            (( wide_width + 1 > gutter_width )) && gutter_width=$(( wide_width + 1 ))
        done
    fi
    if [[ -n "$primary_oid" && "$head_oid" == "$primary_oid" ]]; then
        if [[ "$theme" == powerline ]]; then
            gutter_width=$(( ${#primary_name} + 11 ))
        elif [[ "$theme" == wide || "$theme" == custom ]]; then
            : # already sized from every visible local branch above
        else
            gutter_width=$(( ${#primary_name} + 9 ))
        fi
    fi
    printf -v gutter '%*s' "$gutter_width" ''
    [[ "$theme" == hash ]] && gutter=''

    printf '%s\n' "${log_lines[@]}" | while IFS= read -r line; do
        local is_head=false is_primary=false
        if [[ "$line" == *"$separator"* ]]; then
            local graph_and_oid="${line%%$separator*}"
            local rendered="${line#*$separator}"
            local oid="${graph_and_oid[-${#head_oid},-1]}"
            local graph="${graph_and_oid[1,-$(( ${#head_oid} + 1 ))]}"
            local head_node=$'\033[1;96m◆\033[0m'
            local primary_node=$'\033[1;32m◆\033[0m'
            local head_graph="${graph/\*/$head_node}"
            local primary_graph="${graph/\*/$primary_node}"
            local label=HEAD arrow=' -> '
            [[ "$oid" == "$head_oid" ]] && is_head=true
            [[ -n "$primary_oid" && "$oid" == "$primary_oid" ]] && is_primary=true
            local selected_node="$configured_node"
            [[ "$is_head" == true ]] && selected_node="$configured_head_node"
            if [[ "$theme" == custom && "$selected_node" == diamond ]]; then
                local configured_graph_node=$'\033[1;97m◆\033[0m'
                [[ -n "${wide_branches[$oid]}" ]] && configured_graph_node=$'\033[1;32m◆\033[0m'
                [[ "$is_head" == true ]] && configured_graph_node=$'\033[1;96m◆\033[0m'
                graph="${graph/\*/$configured_graph_node}"
            elif [[ "$theme" == custom && "$selected_node" == none ]]; then
                graph="${graph/\* /}"
                graph="${graph% }"
            fi
            if [[ "$theme" == custom && -n "${custom_remotes[$oid]}" ]]; then
                local remote_name='' right_separator_text=' <- '
                [[ "$configured_right_separator" == none ]] && right_separator_text=' '
                for remote_name in "${(f)custom_remotes[$oid]}"; do
                    rendered+=$'\033[97m'"${right_separator_text}"$'\033[1;31m'"${remote_name}"$'\033[0m'
                done
            fi
            if [[ "$is_head" == true && "$is_primary" == true ]]; then
                label="HEAD+${primary_name}"
            fi

            if [[ ( "$theme" == wide || "$theme" == custom ) \
                  && ( "$is_head" == true || -n "${wide_branches[$oid]}" ) ]]; then
                local wide_prefix='' wide_visible=0 wide_branch=''
                if [[ "$theme" == custom && "$ref_style" == powerline ]]; then
                    local head_powerline_end=$'\033[0;36m\033[0m'
                    local branch_powerline_end=$'\033[0;32m\033[0m'
                    local -i powerline_separator_width=1
                    if [[ "$configured_separator" == none ]]; then
                        head_powerline_end=$'\033[0m'
                        branch_powerline_end=$'\033[0m'
                        powerline_separator_width=0
                    fi
                    if [[ "$is_head" == true ]]; then
                        wide_prefix=$'\033[1;30;46m HEAD '"${head_powerline_end}"
                        (( wide_visible += 6 + powerline_separator_width ))
                    fi
                    for wide_branch in "${(f)wide_branches[$oid]}"; do
                        [[ -n "$wide_branch" ]] || continue
                        wide_prefix+=$'\033[1;30;42m '"${wide_branch}"$' '"${branch_powerline_end}"
                        (( wide_visible += ${#wide_branch} + 2 + powerline_separator_width ))
                    done
                    if [[ "$configured_separator" == none ]]; then
                        wide_prefix+=' '
                        (( wide_visible += 1 ))
                    fi
                else
                    local configured_arrow=' -> ' configured_arrow_width=4
                    if [[ "$theme" == custom && "$configured_separator" == none ]]; then
                        configured_arrow=' '
                        configured_arrow_width=1
                    fi
                    if [[ "$is_head" == true ]]; then
                        wide_prefix=$'\033[1;96mHEAD\033[0;97m'"${configured_arrow}"
                        (( wide_visible += 4 + configured_arrow_width ))
                    fi
                    for wide_branch in "${(f)wide_branches[$oid]}"; do
                        [[ -n "$wide_branch" ]] || continue
                        wide_prefix+=$'\033[1;32m'"${wide_branch}"$'\033[0;97m'"${configured_arrow}"
                        (( wide_visible += ${#wide_branch} + configured_arrow_width ))
                    done
                fi
                printf -v padding '%*s' "$(( gutter_width - wide_visible ))" ''
                line="${padding}${wide_prefix}"$'\033[0m'"${graph}${rendered}"
            elif [[ "$is_head" == true ]]; then
                local plain='' padding='' cyan_reset=$'\033[0;48;5;23m'
                local label_padding=''
                printf -v label_padding '%*s' "$(( gutter_width - ${#label} - 4 ))" ''
                local hash_badge=$'\033[1;97;44m'"${head_short}"$'\033[0m'
                local styled_label=$'\033[1;96mHEAD\033[0m'
                local pulsed_label=$'\033[1;30;46mHEAD\033[0m'
                if [[ "$is_primary" == true ]]; then
                    styled_label+=$'\033[97m+\033[1;32m'"${primary_name}"$'\033[0m'
                    pulsed_label+=$'\033[97m+\033[1;32m'"${primary_name}"$'\033[0m'
                fi
                case "$theme" in
                    adaptive-diamond)
                        if [[ "$pulse" == strong ]]; then
                            plain=$(printf '%s' "${label}${arrow}${label_padding}${graph/\*/◆}${rendered}" | sed $'s/\033\\[[0-9;]*m//g')
                            printf -v padding '%*s' "$cols" ''
                            line=$'\033[1;30;46m'"${plain}${padding}"
                        elif [[ "$pulse" == subtle ]]; then
                            line="${pulsed_label}"$'\033[97m'"${arrow}${label_padding}"$'\033[0m'"${head_graph}${rendered}"
                        else
                            line="${styled_label}"$'\033[97m'"${arrow}${label_padding}"$'\033[0m'"${head_graph}${rendered}"
                        fi
                        ;;
                    pulse-arrow)
                        if [[ "$pulse" == strong ]]; then
                            plain=$(printf '%s' "${label}${arrow}${label_padding}${graph}${rendered}" | sed $'s/\033\\[[0-9;]*m//g')
                            printf -v padding '%*s' "$cols" ''
                            line=$'\033[1;30;46m'"${plain}${padding}"
                        else
                            line="${styled_label}"$'\033[97m'"${arrow}${label_padding}"$'\033[0m'"${graph}${rendered}"
                        fi
                        ;;
                    arrow)
                        line="${styled_label}"$'\033[97m'"${arrow}${label_padding}"$'\033[0m'"${graph}${rendered}"
                        ;;
                    powerline)
                        if [[ "$is_primary" == true ]]; then
                            line=$'\033[1;30;46m HEAD \033[36;42m\033[30m '"${primary_name}"$' \033[0;32m\033[0m '"${graph}${rendered}"
                        else
                            line=$'\033[1;30;46m HEAD \033[0;36m\033[0m '"${label_padding}${graph}${rendered}"
                        fi
                        ;;
                    row-yellow)
                        plain=$(printf '%s' "${label}${arrow}${label_padding}${graph}${rendered}" | sed $'s/\033\\[[0-9;]*m//g')
                        printf -v padding '%*s' "$cols" ''
                        line=$'\033[1;30;103m'"${plain}${padding}"
                        ;;
                    row-cyan)
                        line=$'\033[48;5;23m'"${styled_label}"$'\033[22;97m'"${arrow}${label_padding}${graph}${rendered}"
                        line="${line//$'\033[0m'/$cyan_reset}"
                        line="${line//$'\033[m'/$cyan_reset}"
                        printf -v padding '%*s' "$cols" ''
                        line+="$padding"
                        ;;
                    arrow-hash)
                        rendered="${rendered/$head_short/$hash_badge}"
                        line="${styled_label}"$'\033[97m'"${arrow}${label_padding}"$'\033[0m'"${graph}${rendered}"
                        ;;
                    hash)
                        rendered="${rendered/$head_short/$hash_badge}"
                        line="${graph}${rendered}"
                        ;;
                esac
            elif [[ -n "$primary_oid" && "$oid" == "$primary_oid" ]]; then
                local primary_padding=''
                printf -v primary_padding '%*s' "$(( gutter_width - ${#primary_name} - 4 ))" ''
                case "$theme" in
                    hash|wide|custom) line="${graph}${rendered}" ;;
                    powerline) line=$'\033[1;30;42m '"${primary_name}"$' \033[0;32m\033[0m '"${primary_padding}${graph}${rendered}" ;;
                    adaptive-diamond) line=$'\033[1;32m'"${primary_name}"$'\033[0;97m -> \033[0m'"${primary_padding}${primary_graph}${rendered}" ;;
                    *) line=$'\033[1;32m'"${primary_name}"$'\033[0;97m -> \033[0m'"${primary_padding}${graph}${rendered}" ;;
                esac
            else
                line="${gutter}${graph}${rendered}"
            fi
        else
            # Graph connector-only rows need the same gutter to preserve the
            # shape and alignment of merge lines.
            line="${gutter}${line}"
        fi
        if [[ "$theme" == custom && "$highlight_row" == yes \
              && "${is_head:-false}" == true ]]; then
            line=$'\033[48;5;23m'"${line}"
            line=$(printf '%s' "$line" \
                   | sed $'s/\033\\[[0-9;]*m/&\033[48;5;23m/g')
            printf -v padding '%*s' "$cols" ''
            line+="$padding"
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
last_primary_oid=''
last_repo_signature=''
last_render_config_signature=''
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
        adaptive-diamond|pulse-arrow|arrow|wide|custom|powerline|row-yellow|row-cyan|arrow-hash|hash) ;;
        *) cur_theme=adaptive-diamond ;;
    esac

    # A command completion is only a prompt to inspect Git state. Avoid
    # clearing the pane when none of the displayed refs actually changed.
    if [[ "$cur_pwd" != "$last_pwd" ]] \
       || [[ -n "$cur_refresh" && "$cur_refresh" != "$last_refresh" ]] \
       || [[ "$cur_theme" != "$last_theme" ]]; then
        _surf_current_head_oid "$cur_pwd"
        current_head_oid="$REPLY"
        _surf_current_primary_oid "$cur_pwd"
        current_primary_oid="$REPLY"
        _surf_repo_signature "$cur_pwd"
        current_repo_signature="$REPLY"
        _surf_render_config_signature "$cur_theme"
        current_render_config_signature="$REPLY"

        should_draw=false
        pulse=none
        if [[ "$cur_pwd" != "$last_pwd" || "$cur_theme" != "$last_theme" \
           || "$current_repo_signature" != "$last_repo_signature" \
           || "$current_render_config_signature" != "$last_render_config_signature" ]]; then
            should_draw=true
        fi
        # pulse-arrow is the deliberately animated alternative; unlike the
        # adaptive default it continues to pulse after every command.
        [[ "$cur_theme" == pulse-arrow && "$cur_refresh" != "$last_refresh" ]] \
            && should_draw=true
        if [[ -n "$last_repo_signature" \
           && ( "$current_head_oid" != "$last_head_oid" \
             || "$current_primary_oid" != "$last_primary_oid" ) ]]; then
            case "$cur_theme" in
                adaptive-diamond|pulse-arrow) pulse=strong; pulse_delay=0.2 ;;
            esac
        elif [[ "$should_draw" == true && "$cur_theme" == pulse-arrow ]]; then
            pulse=strong; pulse_delay=0.2
        fi
        if [[ "$should_draw" == true && "$pulse" != none ]]; then
            _surf_draw_log "$cur_pwd" "$cur_theme" "$pulse"
            sleep "$pulse_delay"
        fi
        [[ "$should_draw" == true ]] && _surf_draw_log "$cur_pwd" "$cur_theme"
        last_pwd="$cur_pwd"
        last_refresh="$cur_refresh"
        last_head_oid="$current_head_oid"
        last_primary_oid="$current_primary_oid"
        last_repo_signature="$current_repo_signature"
        last_render_config_signature="$current_render_config_signature"
        last_theme="$cur_theme"
    fi

    sleep 0.5
done
