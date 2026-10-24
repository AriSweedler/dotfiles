# Shortcuts for the dotfiles harness (~/.config/bin/dotfiles): `df` is the harness,
# `dfp` its push — the one command that publishes the submodules, the shared tier's
# pointer bumps, the shared tier and the local tier together.
#
# df shadows df(1); `command df -h` still reaches the disk-free one. The tier-specific
# git aliases are git's, not the shell's (git df / git ldf, in
# ~/.config/git/plugin/dotfiles.gitconfig), and the harness's init parameters are the
# local tier's (~/.local/share/zsh/plugins/dotfiles.zsh).
alias df='dotfiles'
alias dfp='dotfiles push'
