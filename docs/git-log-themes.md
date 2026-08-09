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
| `powerline` | Padded ` HEAD ` block and matching `` pointer |
| `row-yellow` | Bright yellow full-row highlight |
| `row-cyan` | Dark cyan full-row highlight that retains field colors |
| `arrow-hash` | `HEAD -> *` gutter plus a dark-blue hash badge |
| `hash` | Dark-blue HEAD hash badge without a gutter |

PowerShell exposes the same names:

```powershell
.\surf.ps1 -ListThemes
.\surf.ps1 -SetTheme -Theme powerline -Session surf
```

The PowerShell selection is stored in that session's IPC directory and its
bottom pane redraws immediately.
