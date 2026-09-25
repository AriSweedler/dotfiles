# dotfiles/cmd/git.zsh — `dotfiles git`: git in one tier, arguments untouched.

help_git() {
  cat <<EOF
dotfiles [--local] git <args…>   git in the shared tier (what 'git df' does); with --local, the local tier ('git ldf')

  Everything after 'git' goes to git untouched, --help included. --dir prints the tier's bare
  repo path instead: ${TIER_GIT_DIR[shared]}, or ${TIER_GIT_DIR[local]} with --local.
EOF
}

cmd_git() { repo_git "${GIT_TIER}" "$@"; }
