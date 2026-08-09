# Git log themes

Surf stores the bottom-pane theme per session. New sessions use
`adaptive-diamond` unless `SURF_GIT_THEME` names another theme.

List themes:

```sh
surf --themes
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
| `adaptive-diamond` | Strong pulse when HEAD moves, subtle refresh pulse, then `HEAD -> ◆` |
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
