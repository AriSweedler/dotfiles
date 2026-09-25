# dotfiles

The program behind `~/.config/bin/dotfiles`, which is only the entrypoint: it sources every
`lib/*.zsh` (the kernel) and `cmd/*.zsh` (the verbs) and calls `main`. Three directories, three
rules:

| Directory | Holds | To add one |
|---|---|---|
| `lib/` | the kernel: `env.zsh` (constants, seams, flags), `logging.zsh`, `run.zsh` (is_dry_run, run_mut, timed, with_timeout, need_lib), `verdict.zsh`, `lock.zsh`, `notify.zsh`, `tiers.zsh` (repo_git, tier::commit), `steps.zsh` (the registry and the one runner), `dispatch.zsh` (main, help) | a module is one concern; a new global belongs in `env.zsh` |
| `cmd/` | one verb per file: `cmd_<verb>` parses its own arguments (zparseopts; flags after the verb belong to the verb) and `help_<verb>` prints its help, first line the one-line synopsis `dotfiles --help` lists | add `cmd/<verb>.zsh` with those two functions; nothing else to register |
| `steps/` | one step per file: `step::declare <name> [--group repo\|brew\|tools] [--needs a,b] [--tools t] [--desc D] [--abort]`, then `check::<name>` (pure, one verdict line on stdout) and optionally `apply::<name>` (mutates only through `run_mut`) | add `steps/<name>.zsh`; `steps::load` validates the registry and orders it by group, then --needs, then name |

Domain libraries load on demand with `need_lib`: `cmd/brew/{brew,decree}.zsh` (the Homebrew
model), `cmd/verify/report.zsh` (the weekly report). Every check and apply runs in a fresh zsh
that sources `lib/` and the step's file, so only exported environment reaches a step
(`ARI_DOTFILES_DRY_RUN`, `ARI_DOTFILES_MODE`, `STEP`, `RUN_DIR`, the `ARI_DOTFILES_*` seams).

Rules that keep the entrypoint trivial:

- **Modules are independent at source time.** A module defines functions, and nothing else runs
  when it is sourced, so a test can source one alone and no file name carries a number to force
  an order. `env.zsh` sets constants from `$HOME` and the environment only; `logging.zsh` loads
  the shared log lib by a path it derives from the checkout.
- **Functions call across modules freely at run time**; by then everything is loaded.
- **A file sourced from inside a function declares its globals with `typeset -g`**: `need_lib`
  sources the domain libraries from a function, where a bare `readonly X=` would be local.
- **Predicates are `is_*`**: `is_dry_run`, `is_repo_present`, `tier::is_no_push`, `step::is_fixable`.
- **Never name a variable after one of zsh's own.** `path` is tied to `PATH` (a local by that
  name made `mkdir` vanish), `status` is `$?`; also `argv`, `options`, `fpath`, `cdpath`,
  `manpath`, `prompt`, `reply`, `watch`, `signals`, `histchars`.

Check independence after a change:

```zsh
for f in ~/.config/dotfiles/lib/*.zsh ~/.config/dotfiles/cmd/*.zsh; do zsh -f -c "set -euo pipefail; source '$f'" && echo "ok  ${f:t}"; done
```

The hermetic suite (`dotfiles test`, `tests/`) runs every verb in a fake HOME with
brew/launchctl/curl shims; `dotfiles test <plugin>` runs one zsh plugin suite.
`~/.config/new-machine/` holds only data: the two tier files, the local-dotfiles exclude
template, and `bin/bootstrap.sh` at the URL the README gives a fresh Mac.
