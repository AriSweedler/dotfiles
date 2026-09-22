# dotfiles/lib/git.zsh — `dotfiles git`: git in one tier, arguments untouched.

# git in one tier, args untouched: `dotfiles git status`, `dotfiles --local git log -1`.
cmd_git() { repo_git "${GIT_TIER}" "${GIT_ARGS[@]}"; }
