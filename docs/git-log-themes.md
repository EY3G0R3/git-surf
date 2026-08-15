# Git log themes

Surf stores the bottom-pane theme per session. New sessions use
`adaptive-diamond` unless `SURF_GIT_THEME` names another theme.

List themes:

```sh
surf --themes
```

Configure a live Surf session interactively:

```sh
surf --configure
```

The configuration screen previews independent bottom-panel options immediately:
placement of seven independent ref-marker categories, HEAD/branch label style,
left and mirrored right-side separators and spacing, separate regular and HEAD
node characters, date and author visibility, and full-row HEAD highlighting.
Every marker placement cycles through `left`, `hidden`, and `right`, in that
order. Left markers appear in the graph gutter; right markers appear as inline
decorations. In text mode, spacing is applied on both sides of its separator;
in powerline mode, it is applied outside the separator so labels can be
separated without adding padding before the powerline glyph. Press Enter to
save the settings as defaults and keep them in the current session, or
`q`/Escape to restore the previous display without writing.
Each row shows every available value; use up/down to choose a setting and
left/right to move the highlighted value.

Persistent settings live in
`${XDG_CONFIG_HOME:-$HOME/.config}/git-surf/config`. Surf validates known values
rather than sourcing the file as shell code, preserves unknown keys when the
TUI updates it, and writes changes atomically. New sessions use the saved
bottom-panel configuration unless explicit `SURF_GIT_*` environment values
override it. Named `surf --theme` changes remain session-scoped.

The marker placement keys and defaults are:

| Marker category | Config key | Default |
| --- | --- | --- |
| `HEAD` marker | `bottom.head_placement` | `left` |
| Primary (`main`) marker | `bottom.main_placement` | `left` |
| Current local branch | `bottom.current_branch_placement` | `left` |
| Other local branches | `bottom.other_local_branches_placement` | `left` |
| Remote primary branch | `bottom.remote_main_placement` | `right` |
| Remote `HEAD` refs | `bottom.remote_head_placement` | `right` |
| Other remote branches | `bottom.other_remote_branches_placement` | `right` |

The primary marker uses Surf's detected primary-branch name, so it also works
for repositories that use `master`, `trunk`, or another configured name. A ref
is rendered in exactly one category: local primary takes precedence over
current local, and remote `HEAD` takes precedence over remote primary. This
prevents duplicate labels when the current branch is also `main`.

For example, this keeps only `HEAD` and the current non-primary branch in the
gutter, hides remote `HEAD`, and moves everything else to the right:

```ini
bottom.head_placement=left
bottom.main_placement=right
bottom.current_branch_placement=left
bottom.other_local_branches_placement=right
bottom.remote_main_placement=right
bottom.remote_head_placement=hidden
bottom.other_remote_branches_placement=right
```

Switch every live Surf session for a worktree:

```sh
surf --theme powerline /path/to/worktree
```

Inside a workmux worktree, the path can be omitted because Surf uses
`WM_WORKTREE_PATH`. Changing themes triggers an immediate redraw and does not
restart the interactive shell.

| Theme | HEAD treatment |
| --- | --- |
| `adaptive-diamond` | Strong pulse when HEAD or the primary branch moves, then `HEAD -> ◆`; unchanged commands do not redraw |
| `pulse-arrow` | Full-row pulse on every refresh, then `HEAD -> *` |
| `arrow` | Static `HEAD -> *` gutter |
| `wide` | Right-aligned gutter sized for visible local branches, such as `HEAD -> main -> topic -> *` |
| `powerline` | Padded ` HEAD ` block and matching `` pointer |
| `row-yellow` | Bright yellow full-row highlight |
| `row-cyan` | Dark cyan full-row highlight that retains field colors |
| `arrow-hash` | `HEAD -> *` gutter plus a dark-blue hash badge |
| `hash` | Dark-blue HEAD hash badge without a gutter |

Themes use the repository's actual primary-branch name. When HEAD and that
branch point to the same commit, compact gutter themes show labels such as
`HEAD+main` or `HEAD+master`. The `wide` theme keeps the refs separate as
`HEAD -> main ->`; it expands to fit all local branch tips visible on screen
with one space at the left edge, aligns shorter labels to the right, and leaves
remote branches and tags in the decorations on the right. Powerline renders
adjacent `HEAD` and branch-name chips.

The commit graph prefers topology order, which keeps short side branches close
to their fork point. If that ordering would place `HEAD` below the visible pane,
Surf retries with date order. If newer branches still fill the pane, Surf draws
a graph anchored at `HEAD`, guaranteeing that a worktree checked out in the
middle of busy history remains visible. The fallback is selected before the
pane is drawn.

Git includes nonstandard refs in `--all` traversal but omits them from its
default decorations. Surf renders `refs/backup/*` as muted amber, right-side
markers such as `← backup:pre-rewrite`, so recovery points are identified
instead of appearing as unlabeled side histories.

Surf resolves the primary branch in this order:

1. The repository's `surf.primaryBranch` Git configuration.
2. The default branch name from `refs/remotes/origin/HEAD`, using its local
   branch commit when present and the remote-tracking commit otherwise.
3. Local `main`, then local `master`.
4. Remote `origin/main`, then `origin/master`.

For an unusual default such as `trunk`, override detection with:

```sh
git config surf.primaryBranch trunk
```

PowerShell exposes the same names:

```powershell
.\surf.ps1 -ListThemes
.\surf.ps1 -SetTheme -Theme powerline -Session surf
```

The PowerShell selection is stored in that session's IPC directory and its
bottom pane redraws immediately.
