#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/surf-lifecycle.XXXXXX")
REAL_TMUX=$(command -v tmux)
TMUX_SOCKET="surf-lifecycle-$$"
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/worktree"
printf '#!/usr/bin/env bash\nexec %q -L %q "$@"\n' \
    "$REAL_TMUX" "$TMUX_SOCKET" > "$TEST_TMP/bin/tmux"
chmod +x "$TEST_TMP/bin/tmux"
export PATH="$TEST_TMP/bin:$PATH"

cleanup() {
    tmux kill-server >/dev/null 2>&1 || true
    rm -rf -- "$TEST_TMP"
}
trap cleanup EXIT

fail() {
    printf 'lifecycle test failed: %s\n' "$1" >&2
    if [[ -s "$TEST_TMP/client.log" ]]; then
        sed -n '/error\|failed\|denied\|not found\|no server\|duplicate/ip' \
            "$TEST_TMP/client.log" | tail -n 5 >&2
    fi
    exit 1
}

wait_for_attached_session() {
    local session="$1" attached attempt
    for ((attempt = 0; attempt < 100; attempt++)); do
        if tmux has-session -t "$session" 2>/dev/null; then
            attached=$(tmux display-message -t "$session" -p '#{session_attached}')
            [[ "$attached" -gt 0 ]] && return 0
        fi
        sleep 0.05
    done
    return 1
}

wait_for_absent_session() {
    local session="$1" attempt
    for ((attempt = 0; attempt < 100; attempt++)); do
        tmux has-session -t "$session" 2>/dev/null || return 0
        sleep 0.05
    done
    return 1
}

# Seed an unarmed legacy Surf session, an unrelated tmux session, and a Surf
# session that is still in its pre-attach construction window. Normal startup
# must reap only the legacy session.
tmux new-session -d -s automatic-legacy
tmux set-environment -t automatic-legacy SURF_START_DIR "$TEST_TMP/automatic-old"
tmux set-environment -t automatic-legacy SURF_DIR "$ROOT"
tmux new-session -d -s concurrent-launch
tmux set-environment -t concurrent-launch SURF_START_DIR "$TEST_TMP/concurrent"
tmux set-environment -t concurrent-launch SURF_DIR "$ROOT"
concurrent_id=$(tmux display-message -t concurrent-launch -p '#{session_id}')
tmux set-hook -t concurrent-launch client-attached \
    "set-option -t '$concurrent_id' destroy-unattached on"
tmux new-session -d -s unrelated

# Run the real launcher under a pseudo-terminal so tmux gets a client. The
# first attach must arm destroy-unattached, and the last detach must reap the
# complete session rather than leave its polling panes behind.
TERM=xterm-256color script -qefc \
    "$ROOT/surf lifecycle-probe $TEST_TMP/worktree" /dev/null \
    >"$TEST_TMP/client.log" 2>&1 &
client_pid=$!

wait_for_attached_session lifecycle-probe \
    || fail 'Surf session never attached'

tmux has-session -t automatic-legacy 2>/dev/null \
    && fail 'normal startup left a detached legacy Surf session alive'
tmux has-session -t concurrent-launch \
    || fail 'normal startup reaped a Surf session before its first attach'
tmux has-session -t unrelated \
    || fail 'normal startup reaped an unrelated tmux session'

hook=$(tmux show-hooks -t lifecycle-probe client-attached)
[[ "$hook" == *'destroy-unattached on'* ]] \
    || fail 'client-attached hook did not arm destroy-unattached'

tmux detach-client -s lifecycle-probe
wait_for_absent_session lifecycle-probe \
    || fail 'Surf session survived its last client detaching'
wait "$client_pid" || true

# Pruning is a dry run by default and only recognizes sessions carrying Surf's
# environment markers. --force removes those sessions without touching other
# detached tmux work.
tmux new-session -d -s legacy-surf
tmux set-environment -t legacy-surf SURF_START_DIR "$TEST_TMP/old-worktree"
tmux set-environment -t legacy-surf SURF_DIR "$ROOT"

dry_run=$("$ROOT/surf" --prune)
[[ "$dry_run" == *'legacy-surf'* ]] || fail 'dry run omitted legacy Surf session'
[[ "$dry_run" != *'unrelated'* ]] || fail 'dry run included unrelated tmux session'
[[ "$dry_run" != *'concurrent-launch'* ]] \
    || fail 'dry run included a lifecycle-armed Surf session'
tmux has-session -t legacy-surf || fail 'dry run removed a Surf session'
tmux has-session -t unrelated || fail 'dry run removed an unrelated session'

"$ROOT/surf" --prune --force >"$TEST_TMP/prune.log"
tmux has-session -t legacy-surf 2>/dev/null \
    && fail '--force left the legacy Surf session alive'
tmux has-session -t unrelated \
    || fail '--force removed an unrelated tmux session'

printf 'lifecycle tests passed\n'
