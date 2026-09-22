# dotfiles/lib

The program behind `~/.config/bin/dotfiles`, which is only the entrypoint: it sources every
`*.zsh` here and calls `main`. Two rules keep that trivial:

- **Modules are independent at source time.** A module defines functions, and nothing else
  runs when it is sourced, so the entrypoint sources them in any order, a test can source one
  alone, and no file name carries a number to force an order. Two modules do source-time work
  and are self-contained: `env.zsh` sets the constants and flag defaults from `$HOME` and the
  environment only; `logging.zsh` loads the shared logging library by paths it derives from
  `$HOME`.
- **Functions call across modules freely at run time**; by then everything is loaded. A new
  global belongs in `env.zsh`, never beside the function that first needs it.

One concern per file, named for it:

| Module | Holds |
|---|---|
| `env.zsh` | environment variables, constants (tiers, paths, submodules), flag defaults |
| `logging.zsh` | the shared logging lib, `log_rotate`, `strip_ansi` |
| `help.zsh` | `help()` |
| `repos.zsh` | `repo_git`, `repo_present`, `log_file` |
| `run.zsh` | `run_mut`, `step`, `elapsed`, `check_prerequisites` |
| `init.zsh` | the `init_*` steps, `cmd_init`, `cmd_pull` |
| `push.zsh` | `load_token`, `push_*`, `bump_pointer`, `cmd_push` |
| `status.zsh` | `tier_line`, `submodule_lines`, `cmd_status`, `cmd_logs` |
| `git.zsh` | `cmd_git` |
| `main.zsh` | `main`: parse, massage, validate, dispatch |

Check independence after a change:

```zsh
for f in ~/.config/dotfiles/lib/*.zsh; do zsh -f -c "set -euo pipefail; source '$f'" && echo "ok  ${f:t}"; done
```
