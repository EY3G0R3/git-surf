# Surf's tmux session shadows workmux's kitty backend

Investigated 2026-08-07 against workmux 0.1.234 and kitty 0.x with
`allow_remote_control yes` / `listen_on unix:/tmp/kitty-{kitty_pid}`.

## Symptom

`workmux remove` (and the cleanup phase of `workmux merge`) succeeds — worktree
gone, branch deleted, `pre_remove` hooks run — but the kitty tab that held the
worktree stays open. It has to be closed by hand. The same command used to close
its container automatically.

## Cause

workmux picks its multiplexer backend by sniffing environment variables, and
**session-scoped variables are checked before terminal-scoped ones**: `$TMUX`
wins over `$KITTY_WINDOW_ID`. This is deliberate upstream — it is what makes
plain tmux-inside-kitty resolve to the tmux backend.

Surf creates a per-worktree tmux session (`surf-<handle>-<cksum>`) and that
session's pane is a natural place to type `workmux remove` from. But it is a
tmux session workmux does not own: its windows are named `zsh` / `workmux`, not
`<prefix><handle>`. So workmux takes the tmux path, searches for a tmux window
matching the worktree handle, finds none, concludes it is not running inside the
target, and tears the worktree down without closing anything. The kitty tab is
never consulted, because no kitty connection is ever opened.

The two outcomes are distinguishable in `~/.local/state/workmux/workmux.log`.
Kitty pane ids are bare integers; tmux pane ids carry a `%` sigil.

Run from the agent pane (a bare kitty window) — closes the tab:

```
cleanup:mux focus context  current_pane_id=Some("33")
    current_matching_target=Some("\u{f418} feat-koban-outage-durations")
    running_inside_target=true
cleanup:scheduled target close
    script="sleep 0.300; kitten @ close-tab --match 'window_id:33' && mv …"
```

Run from the surf pane (tmux) — closes nothing:

```
cleanup:mux focus context  current_pane_id=Some("%21")
    current_matching_target=None  running_inside_target=false
    active_session=Some("surf-feat-koban-outage-durations-2725742374")
navigate_to_target_and_close:entry
    window_to_close=None  window_target_to_close=None  target_id_to_close=None
```

## Why it used to work

Nothing regressed in workmux; the surrounding layout changed. Under the earlier
setup the worktrees *were* tmux windows inside a single session named `work`:

```
2026-08-03  current_pane_id=Some("%24")
    current_matching_target=Some(("\u{f418} fix-merge-queue-comms", Some("@10")))
    active_session=Some("work")  running_inside_target=true
```

There, the pane you typed in and the thing workmux wanted to close were the same
object, so the tmux backend killed it and the cleanup looked automatic. Once the
worktree container became a kitty tab and the pane became a surf tmux session,
that identity broke. Across one log, all six tmux-launched removals from the
`work`-session era matched a target; all eight from the surf era matched none.

## Second symptom: orphaned sessions

Because nothing tore the surf session down either, every removal left a detached
tmux session behind for a worktree that no longer existed. On the machine where
this was investigated, 8 of 10 live `surf-*` sessions pointed at deleted
worktrees. Surf's own `pane-exited` hook does not catch this: it fires when the
main pane's process exits, and closing a kitty tab kills the *client*, leaving
the server-side panes untouched.

Surf now arms tmux's session-scoped `destroy-unattached` option from a
`client-attached` hook. Deferring it until the first attachment is important:
enabling the option while Surf is still constructing its initially detached
session would destroy the session immediately. After attachment, losing the
last client destroys the complete session and its status and Git-log workers.
Multiple simultaneous clients remain supported; the session survives until the
last one detaches.

Normal Surf startup automatically removes detached sessions created by older
versions. A session that is concurrently being constructed already carries the
new first-attach hook, so startup cleanup recognizes it and leaves it alone.
The pruning commands remain available for inspection or immediate cleanup:

```sh
surf --prune
surf --prune --force
```

Pruning identifies Surf sessions by their published `SURF_START_DIR` and
`SURF_DIR` environment values and excludes sessions carrying the new lifecycle
hook. Unrelated detached tmux sessions and in-progress Surf launches are left
alone.

## The fix

`surf --close <worktree-dir>` tears down both, and a workmux `pre_remove` hook
invokes it. In `~/.config/workmux/config.yaml`:

```yaml
pre_remove:
  - surf --close "$WM_WORKTREE_PATH"
```

Three details make this work where forcing the backend does not.

**The tab is identified by a kitty user var, not a window id.** At launch —
where the surf script is still a direct child of kitty and its
`$KITTY_WINDOW_ID` is therefore real — surf stamps its window with
`surf_worktree=<start-dir>`, and teardown matches
`close-tab --match "var:surf_worktree=^<escaped-dir>$"`. The pattern is anchored
and regex-escaped because kitty searches rather than anchors, so an unanchored
`…/foo` would also match the tab for `…/foo-bar`. Panes cannot do this stamping
themselves; see the section below.

**Teardown is deferred until the removal completes.** `pre_remove` runs *before*
the worktree is deleted, typically from inside the very session and tab being
closed, so acting synchronously would kill workmux mid-removal. `surf --close`
resolves its targets, hands them to a watcher detached onto init with `SIGHUP`
ignored, and returns in ~0.1s. The watcher waits for the worktree directory to
disappear — the observable end of the destructive phase, whether workmux deleted
the directory or renamed it to a trash path — then acts. On a 60s timeout it
does nothing, which is the right outcome when the removal aborted.

**The tab closes before the sessions are killed.** The reverse order races:
killing the session takes down the kitty window carrying the `surf_worktree`
var, leaving `close-tab` nothing to match. A tmux session outlives its client,
so it can still be reaped afterwards.

`$KITTY_LISTEN_ON` is what makes any of this reachable from inside tmux. Unlike
`$KITTY_WINDOW_ID` it stays correct in every pane; surf also stashes a copy in
the session environment for callers that have no kitty in their environment at
all.

Running `workmux remove` from the agent pane — the bare kitty window — was the
manual workaround before this existed, and still works: that path is inside
kitty, so workmux resolves and closes the tab itself.

## Do not force the kitty backend from a surf pane

`WORKMUX_BACKEND=kitty` looks like the obvious override and is actively unsafe
here. `KITTY_WINDOW_ID` inside a tmux pane is whatever the kitty window that
started the **tmux server** had, and tmux hands that same stale value to every
later session. Observed on this machine: every live surf pane carried
`KITTY_WINDOW_ID=5` while the actual live kitty windows were 8, 9, 28, 29, 35 —
window 5 having closed long before. Forcing the kitty backend would issue
`close-tab --match window_id:5` against an id that no longer identifies the tab
you are in, or identifies someone else's.

Any real fix has to resolve the tab by working directory, not by an inherited
window id.

## Hooking it up per project

A project's `.workmux.yaml` **replaces** the global hook list rather than
extending it. quiver's `pre_remove` originally read:

```yaml
pre_remove:
  - bun run scripts/cleanup.ts
```

which silently shadowed the global entry, so the hook never fired in the one
repository it was needed in. Projects have to opt in explicitly, the same way
that file's `post_create` already did:

```yaml
pre_remove:
  - "<global>"
  - bun run scripts/cleanup.ts
```

workmux logs the resolved count as `cleanup:running pre-remove hooks … count=N`,
which is the quickest way to confirm `<global>` expanded.

Note also that setting `pre_remove` in the global config replaces workmux's
built-in default, which fast-deletes `node_modules` before removal. Projects
that want both should list them together.

## Upstream fix direction

Nothing above needs workmux to change, but the tidier home for it is upstream:
when workmux is inside tmux and the tmux side has no window matching the
worktree handle, it could fall back to `$KITTY_LISTEN_ON` and resolve the tab by
working directory. That resolution is stale-proof in a way `KITTY_WINDOW_ID` is
not, and it is the only signal that survives the tmux boundary intact.

## Side observation, not confirmed

On the working kitty path the deferred script chains the tab close and the
worktree move with `&&`:

```
kitten @ close-tab --match 'window_id:4' && mv <worktree> <trash> ; git worktree prune ; …
```

After one such scheduled close the tab did disappear but the worktree directory
was still on disk half an hour later and needed a second manual `workmux rm`.
That is consistent with the detached script being killed along with the tab it
just closed, before reaching the `mv`. Not reproduced deliberately — recorded
only so that "tab closed, worktree still present" is recognized as one failure
rather than two.

`surf --close` avoids the shape entirely: it waits for the removal to finish
before touching anything, so its own survival is never a precondition for the
worktree being cleaned up.
