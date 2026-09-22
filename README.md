# Intro

Hi! Welcome to my `dotfiles`

"dotfile" is a colloquial name for "configuration file". As they're hidden by
default (try running `ls` with and without out the `-a` flag), they're the
perfect place for applications to store configuration data that they don't want
users changing on accident.

With this git repo, any machine can feel like home with a simple `git pull`.
(Well, almost. I just need to get these dotfiles into my home directory. Read
[this](https://www.atlassian.com/git/tutorials/dotfiles) for full details).

## New machine

Open Terminal and paste:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/AriSweedler/dotfiles/main/.config/new-machine/bin/bootstrap.sh)"
```

(`git.io/.ari` lands on this page.) That is `~/.config/new-machine/bin/bootstrap.sh`:
the Command Line Tools if missing (click Install in the dialog), the bare clone into
`~/dotfiles.git` (https for fetch, ssh for push), the checkout into `~`, then
`new-machine setup`, which asks for your password once for Homebrew. Safe to re-run.
Flags pass through: `sh -c "$(curl …)" bootstrap --dry-run`. Pushing needs this
machine's ssh key on GitHub; `git_df_push` handles the rest. `DOTFILES_REMOTE=…`
clones from elsewhere.

By hand instead:

```zsh
git clone --bare git@github.com:AriSweedler/dotfiles.git ~/dotfiles.git
git --git-dir=~/dotfiles.git --work-tree=~ checkout
~/.config/new-machine/bin/new-machine setup   # --dry-run to preview
```

`new-machine setup` is idempotent: Homebrew, the packages in the shared
`~/.config/new-machine/Brewfile` plus this machine's
`~/.local/share/new-machine/Brewfile` (`brew bundle`), both dotfiles bare repos
and their hooks, neovim, Claude Code, and the one `dotfiles jobs` launchd job, whose
weekly `new-machine verify` plugin leaves one `~/Desktop/new-machine-FAILED.md` when
the machine drifts from this baseline.
`new-machine brew triage` lists brew packages no Brewfile declares;
`new-machine brew decree <name> --global|--local` settles each one. `vi_newmachbrew`
edits the shared Brewfile.

There are many ways to modify the behavior of a program. Per machine, per user,
per instance, etc. Dotfiles are generally per-user. 

1) Hard-code constants
2) Invoke program with parameters (--options)
3) Read configuration files (like these!)
4) Get user input during the program

I try to keep most of my configuration files in the `~/.config/<APP>` folder,
but older systems will still require you to use something like `~/.*<APP>*`.

## Fun facts
* The "dot" makes the file hidden:
  [link](https://linux-audit.com/linux-history-how-dot-files-became-hidden-files/).
  It seems reasonable to have these configuration files hidden, as you only
  wanna edit them when you wanna edit the system. The idea is: when you're being
  a regular user, you shouldn't even have to think about them.
* Referring to them as "hidden files" is too broad. Not all hidden files are
  config files. Referring to them as "config files" is totally reasonable.
  However, not all config files go in your home directory.

Many of these dotfiles have the `rc` suffix. Why?
* [answer](https://stackoverflow.com/a/11030607/7531823)
