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

## Workaround

Run `workmux remove` and `workmux merge` from the agent pane — the bare kitty
window in the tab — rather than from the surf pane. That path resolves the tab
and schedules the `kitten @ close-tab`.

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

## Upstream fix direction

workmux would need a fallback: when it is inside tmux but the tmux side has no
window matching the worktree handle, and `$KITTY_LISTEN_ON` is reachable, query
`kitten @ ls` and find the tab whose windows have the worktree path as their
`cwd`. That resolution is stale-proof in a way `KITTY_WINDOW_ID` is not, and it
is the only signal that survives the tmux boundary intact.

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
