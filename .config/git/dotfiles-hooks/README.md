# Dotfiles Hooks

Git hooks for the dotfiles bare repo (`~/dotfiles`).

These hooks are versioned in the dotfiles working tree but must be explicitly
wired up after a fresh clone, since `core.hooksPath` is a repo-local setting.

## Setup

After cloning the dotfiles bare repo:

```bash
git df config core.hooksPath ~/.config/git/dotfiles-hooks
```

## Hooks

- **pre-commit** — Ensures `karabiner.json` is sorted by key before committing.
  Run `bake` from `~/.config/karabiner` to fix.
