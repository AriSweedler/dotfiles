# Local-dotfiles Hooks

Git hooks for the per-machine local-dotfiles bare repo (`~/.local/local-dotfiles.git`,
worktree `~/.local`, driven by `git local-dotfiles` / `git ldf`).

Versioned in the shared dotfiles tree; `core.hooksPath` is repo-local, so wire
them up once per machine after bootstrapping the repo.

## Setup

`~/.config/new-machine/bin/setup-new-machine` bootstraps the repo, its
`info/exclude` allowlist, and this hooks path. By hand:

```bash
git ldf config core.hooksPath ~/.config/git/local-dotfiles-hooks
```

## Hooks

- **pre-commit** — Refuses to commit any path containing `.secret.` and any
  staged content matching a known token shape (Airtable PAT, Buildkite token,
  GitHub PAT, AWS key id, `*_SECRET=`/`*_TOKEN=` literals). Secrets live in
  `*.secret.zsh` beside the plugin that needs them and are never tracked.
