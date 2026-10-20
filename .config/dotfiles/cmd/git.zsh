# dotfiles/cmd/git.zsh — `dotfiles git`: git in one tier, arguments untouched; `--local git
# --edit` edits the local tier's allowlist. Also its documentation rule
# (git_allowlist_undocumented), which the local_dotfiles_repo step runs.

help_git() {
  cat <<EOF
git in a tier's bare repo (what 'git df' and 'git ldf' do)

${c_bold}Usage${c_rst}
  ${DF} [--local] git <args…>
  ${DF} [--local] --dir
  ${DF} --local git --edit [--no-commit]

  Everything after 'git' goes to git untouched, --help included, with one
  exception: '--edit' as the first word (git itself takes no such option;
  'git commit --edit' still reaches git). The shared tier is
  $(help::tilde "${TIER_GIT_DIR[shared]}") with work tree ~; the local tier is
  $(help::tilde "${TIER_GIT_DIR[local]}") with work tree ~/.local.

  The local tier tracks only what its allowlist admits: info/exclude, a
  copy of the template $(help::tilde "${LDF_EXCLUDE_TEMPLATE}") (shared
  tier). It starts '/*' (nothing), and each '!' entry admits a path; every
  '!' entry has a '# why' comment on the line above it, or above the run of
  '!' lines it belongs to. An entry without one fails local_dotfiles_repo.

  '--local git --edit' opens the template in \$EDITOR (vi when unset) as a
  draft. It refuses up front when this machine's info/exclude has rules the
  template does not (it shows the diff: make them agree first). On save the
  draft must start with '/*', keep every '*.secret.zsh' out of every
  admitted directory, and give each '!' entry its why; a draft that fails is
  kept (offered for another edit on a terminal, else exit 1; the same
  command resumes it). One that passes replaces the template and is
  installed as info/exclude; 'git ldf status --short -uall' then shows what
  it admits, and the template is committed in the shared tier.

${c_bold}Flags${c_rst}
  --local       act on the local tier, not the shared one (before the verb)
  --dir         print the tier's bare repo path and exit (in place of a verb)
  --edit        with --local: edit the local tier's allowlist (first word only)
  --no-commit   --edit: install it, leave the template uncommitted

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_DF_GIT_DIR)
      the shared tier's bare repo (default $(help::tilde "${ARI_DOTFILES_DF_GIT_DIR}"))
  $(ENV ARI_DOTFILES_LDF_GIT_DIR)
      the local tier's bare repo (default $(help::tilde "${ARI_DOTFILES_LDF_GIT_DIR}"))
EOF
}

cmd_git() {
  # Only a leading --edit is ours; anything else, `git commit --edit` included, is git's.
  if [[ "${1:-}" == --edit ]]; then
    shift
    [[ "${GIT_TIER}" == local ]] || usage_error "git --edit edits the local tier's allowlist | fix='${CLI_NAME} --local git --edit'"
    local commit=1
    while (( $# )); do
      case "${1}" in
        -h|--help) help_verb git; return 0 ;;
        --no-commit) commit=0 ;;
        *) usage_error "git --edit: unknown argument | arg='${1}'" ;;
      esac
      shift
    done
    need_lib "${ARI_DOTFILES_CMD}/git/edit.zsh" || return 3
    git_edit "${commit}"
    return
  fi
  repo_git "${GIT_TIER}" "$@"
}

# git_allowlist_undocumented FILE: reply = each '!' entry of an allowlist with no '# why' comment
# on the line above it, or above the run of '!' lines it belongs to. Pure zsh.
git_allowlist_undocumented() {
  setopt localoptions extendedglob
  zmodload zsh/mapfile
  local line prev=""
  local -i documented=0
  reply=()
  for line in "${(@f)mapfile[${1}]-}"; do
    if [[ "${line}" == '!'* ]]; then
      if [[ "${prev}" != '!'* ]]; then
        documented=0
        [[ "${prev}" == '#'[[:space:]]#[^[:space:]]* ]] && documented=1
      fi
      (( documented )) || reply+=("${line}")
    fi
    prev="${line}"
  done
  return 0
}
