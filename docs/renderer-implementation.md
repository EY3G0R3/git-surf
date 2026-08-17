# Bottom-pane renderer implementation

Surf's bottom-pane renderer is the standalone `fancylog` application in the
sibling `~/src/fancylog` repository. Surf retains a thin zsh adapter for tmux
session state; the Git query, commit/ref model, layout, ANSI rendering, config
validation, and terminal sizing belong to `fancylog`.

## Process boundary

```text
Surf bottom pane
    └── surf-bot.zsh (tmux adapter)
          ├── read SURF_PWD, refresh, theme, config, and pane dimensions
          ├── skip redraw when repository/config state is unchanged
          └── fancylog --clear --width … --height … REPOSITORY
                ├── query Git
                ├── build the visible commit/ref model
                └── write one ANSI frame to stdout
```

The renderer itself does not query tmux or Kitty. A host can run it as a
one-shot subprocess and own refresh timing, as Surf does, or use
`fancylog --watch` for a panel tied to a fixed repository.

Surf resolves the binary in this order:

1. Executable path in `SURF_FANCYLOG`.
2. `fancylog` on `PATH`.
3. A release build in `../fancylog/target/release/fancylog`.
4. A release build in `~/src/fancylog/target/release/fancylog`.

This supports installed releases, side-by-side development, and explicit host
configuration without coupling either repository to one filesystem layout.

## Standalone and embedded use

Render one composable snapshot:

```sh
fancylog [repository]
```

Run a self-updating fixed panel:

```sh
fancylog --watch --width 72 --height 18 --color always [repository]
```

Snapshot mode does not clear the screen. Watch mode clears by default and
redraws only when refs or terminal dimensions change. Explicit width, height,
color, clear, and polling flags make the stdout protocol usable in other
window and panel layouts.

## Configuration compatibility

`fancylog` reads `${XDG_CONFIG_HOME:-$HOME/.config}/git-surf/config` and
understands every `bottom.*` setting written by `surf --configure`. Each of the
17 settings also has a long CLI option, such as `--head-placement`,
`--right-separator`, `--regular-node`, and `--show-author`. CLI values override
the file.

Surf passes its live tmux environment as CLI values when the selected theme is
`custom`, so the existing configuration TUI continues to preview changes
without restarting the pane.

## Implementation choice

`fancylog` is a Rust binary with no third-party runtime dependencies. Release
builds enable full LTO, one codegen unit, abort-on-panic, and symbol stripping.
The native binary minimizes startup and resident memory for repeated snapshot
embedding while keeping deployment to a single executable.

Git subprocesses remain the largest rendering cost. The adapter avoids
launching the renderer after commands that did not change refs, and watch mode
does not redraw unchanged frames.
