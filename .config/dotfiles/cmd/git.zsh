# dotfiles/cmd/git.zsh — `dotfiles git`: git in one tier, arguments untouched.

help_git() {
  cat <<EOF
git in a tier's bare repo (what 'git df' and 'git ldf' do)

${c_bold}Usage${c_rst}
  ${DF} [--local] git <args…>
  ${DF} [--local] --dir

  Everything after 'git' goes to git untouched, --help included. The shared
  tier is $(help::tilde "${TIER_GIT_DIR[shared]}") with work tree ~; the local tier is
  $(help::tilde "${TIER_GIT_DIR[local]}") with work tree ~/.local.

${c_bold}Flags${c_rst}
  --local   act on the local tier instead of the shared one (before the verb)
  --dir     print the tier's bare repo path and exit (in place of a verb)

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_DF_GIT_DIR)
      the shared tier's bare repo (default $(help::tilde "${ARI_DOTFILES_DF_GIT_DIR}"))
  $(ENV ARI_DOTFILES_LDF_GIT_DIR)
      the local tier's bare repo (default $(help::tilde "${ARI_DOTFILES_LDF_GIT_DIR}"))
EOF
}

cmd_git() { repo_git "${GIT_TIER}" "$@"; }
