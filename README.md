# dotfiles

This repo is the shared tier: `~/.config` and the files beside it, a bare
repo whose work tree is `~` (`git df`). The local tier is one private repo per
machine for `~/.local` (`git ldf`).

## New machine

On a fresh Mac, paste this into Terminal:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/AriSweedler/dotfiles/main/.config/new-machine/bin/bootstrap.sh)"
```

`git.io/.ari` lands on this page. [`bootstrap.sh`](.config/new-machine/bin/bootstrap.sh)
installs the Command Line Tools if they are missing and clones the bare repo
into `~/dotfiles.git`. Then it checks the files out into `~` and hands off to
`dotfiles setup`. `dotfiles setup` installs Homebrew, the packages in the
Brewfiles, and the tools, one step each under [`steps/`](.config/dotfiles/steps).
It asks for your password once, for Homebrew. `bootstrap.sh` and
`dotfiles setup` are both safe to run again.

---

# The `dotfiles` command

Past bootstrap, one command manages the machine: [`dotfiles`](.config/bin/dotfiles).
Its program is [`.config/dotfiles/`](.config/dotfiles/), laid out in
[`lib/README.md`](.config/dotfiles/lib/README.md). `dotfiles --help` lists the
verbs, and each verb answers `--help`.

| Verb | What it does |
|---|---|
| `init` | Sets up the dotfiles themselves: both bare repos and their hooks, the submodules, the Claude skills, the ssh key, the launchd job behind [`dotfiles jobs`](.config/dotfiles/jobs/README.md). Idempotent. Ends in `status`. |
| `push` | Pushes the submodules and records their new commits in the shared tier. Then it pushes the shared tier and the local tier. |
| `pull` | Fast-forwards the shared tier from origin, then runs `init`, so pulled steps, skills and jobs take effect. |

Day to day: edit, commit with `git df` or `git ldf`, then `dotfiles push`. On
another machine, `dotfiles pull`. A step left by hand is printed by the verb
that needs it: the local tier's remote by `setup`, the `gh` login by `push`.
