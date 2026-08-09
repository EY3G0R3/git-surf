# Bottom-pane renderer implementation

The bottom pane does not inherently require zsh. tmux gives the pane a normal
terminal, so any long-running process that emits ANSI control sequences can
occupy it. The launcher could source `surf-bot.zsh`, run `python3 surf-bot.py`,
or execute a compiled `surf-bot` binary without changing the pane layout.

## Current performance

The zsh renderer is likely fast enough for the current workload. Most redraw
cost comes from spawning Git and tmux commands, not from styling strings in the
shell. Surf redraws after user activity and otherwise polls session state every
500 ms, so renderer CPU time is not currently a demonstrated bottleneck.

A rewrite should therefore be justified primarily by maintainability and
testability, not expected rendering speed.

## TODO: extract a standalone smartlog tool

Separate the Git query, commit/ref model, layout, and ANSI rendering currently
embedded in `surf-bot.zsh` into a standalone configurable command—effectively a
Surf-flavored wrapper around `git log --graph`, or "smartlog" tool. A tentative
name is `surf-smartlog`.

The command should be useful without tmux or Kitty:

```sh
surf-smartlog [--config path] [--width columns] [repository]
surf-smartlog --watch [repository]
```

The default mode should render one snapshot to standard output so it composes
with ordinary terminal workflows. Watch mode should redraw on repository
changes or an explicit refresh signal and serve as the process Surf launches in
its bottom pane. The core renderer must not query tmux directly; a thin Surf
adapter should translate pane dimensions and session state into command options
or environment values.

Reuse the persistent `bottom.*` configuration keys for ref styles, separators,
nodes, metadata fields, and row highlighting. Command-line flags should override
the config file, making the tool independently scriptable while preserving the
same output users configured through `surf --configure`.

Extraction should precede any Python or Rust rewrite. First establish the CLI
and testable renderer boundary while behavior is still defined by the existing
zsh implementation; the implementation language can then change without
coupling the smartlog interface to Surf's pane orchestration.

## Python

Python is the preferred next implementation if the renderer outgrows zsh. It
would provide natural commit/ref data structures, simpler ANSI-aware width and
truncation code, and straightforward unit and snapshot tests. A persistent
Python process would make startup cost irrelevant and could eventually replace
the duplicated zsh and PowerShell rendering logic.

The tradeoffs are a Python runtime dependency and a larger resident process.
Windows terminal and process integration would still need explicit testing
before replacing the PowerShell implementation.

## Rust

Rust could produce a fast, low-memory, self-contained executable with strong
data modeling. It becomes attractive if Surf is distributed as a standalone
application or needs substantially more interactive and event-driven behavior.

For the current project it would add disproportionate build, packaging, and
cross-platform release work. Visual experiments would also take longer to
iterate on, while Git subprocesses would remain the dominant redraw cost.

## Suggested migration boundary

Keep the launcher and shell hooks unchanged initially. Replace only the
long-running bottom renderer behind the existing session variables:

```text
surf launcher
    └── persistent renderer
          ├── read tmux/session state
          ├── invoke Git
          ├── build a commit/ref model
          ├── render the selected theme
          └── write ANSI output to the pane
```

Preserve `SURF_PWD`, `SURF_REFRESH`, `SURF_GIT_THEME`, and the pane/session IDs
as the compatibility boundary. This permits an incremental Python prototype
and side-by-side output tests without redesigning the rest of Surf.

The display configuration UI should likewise remain renderer-independent: it
writes session configuration, while each pane observes the settings relevant
to it. That leaves room for top- and middle-panel options without coupling the
UI to the current zsh renderer.
