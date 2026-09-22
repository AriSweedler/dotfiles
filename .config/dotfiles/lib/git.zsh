# dotfiles/lib/git.zsh — `dotfiles git`: git in one tier, arguments untouched.
# Sourced by ~/.config/bin/dotfiles in no particular order: this file defines functions and
# nothing runs when it is sourced, so it needs no other module first (see README.md).

# git in one tier, args untouched: `dotfiles git status`, `dotfiles --local git log -1`.
cmd_git() { repo_git "${GIT_TIER}" "${GIT_ARGS[@]}"; }
