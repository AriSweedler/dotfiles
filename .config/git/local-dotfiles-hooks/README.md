# Local-dotfiles Hooks

Git hooks for the per-machine local-dotfiles bare repo (`~/.local/local-dotfiles.git`,
worktree `~/.local`, driven by `git local-dotfiles` / `git ldf`).

Versioned in the shared dotfiles tree; `core.hooksPath` is repo-local, so wire
them up once per machine after bootstrapping the repo.

## Setup

`new-machine setup` bootstraps the repo, its
`info/exclude` allowlist, and this hooks path. By hand:

```bash
git ldf config core.hooksPath ~/.config/git/local-dotfiles-hooks
```

## Hooks

- **pre-commit** — Refuses to commit any path containing `.secret.` and any
  staged content matching a known token shape (`pat…`, `bkua_`, `ghp_` prefixes,
  AWS key id, `*_SECRET=`/`*_TOKEN=` literals). Secrets live in
  `*.secret.zsh` beside the plugin that needs them and are never tracked.
- **pre-push** — When the push touches `share/chrome-exoskeleton/` (this
  machine's private Chrome Exoskeleton plugins), runs the framework's full
  check (`exo check --e2e`: lint, format, tsc, vitest, build, Playwright) over
  the framework and both plugin tiers. Prints `[EXO-PREPUSH] passed|failed`;
  `dotfiles::commit` treats a failed verdict as fatal. `EXO_PUSH_E2E=0` skips
  the browser suite.
