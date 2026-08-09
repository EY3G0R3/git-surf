# Surf session identity

tmux mirrors every client attached to the same session. To prevent two
independent terminal windows from unexpectedly controlling the same Surf
layout, Surf gives implicit non-workmux sessions a terminal-scoped name.

The identity source is selected in this order:

1. Kitty's `KITTY_WINDOW_ID`.
2. iTerm2's `ITERM_SESSION_ID`.
3. `TERM_SESSION_ID`, including Apple Terminal.
4. WezTerm's `WEZTERM_PANE`.
5. The controlling TTY, which works as a portable fallback on macOS and Linux.
6. The historical session name `surf` when no terminal identity is available.

Opaque IDs and TTY paths are hashed before they become tmux names. Kitty's
normally numeric window ID stays readable, producing names such as
`surf-kitty-17`. Re-running Surf in that terminal attaches to its existing
session, while another terminal receives an independent name and layout.

TTY identity is stable for the lifetime of a terminal but can eventually be
reused by the operating system. Dedicated IDs are preferred when the terminal
provides them. An explicit session name remains the strongest override:

```sh
surf my-session /path/to/start
```

workmux behavior is unchanged. Its sessions remain stable per worktree so its
hooks can find and manage them independently of the terminal that launched
them.
