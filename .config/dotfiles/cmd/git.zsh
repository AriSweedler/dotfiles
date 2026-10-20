# dotfiles/cmd/git.zsh — `dotfiles git`: git in one tier, arguments untouched; `--local git
# edit` edits the local tier's allowlist. Also its documentation rule
# (git_allowlist_undocumented), which the local_dotfiles_repo step runs.
#
# cmd_git parses nothing: its words are git's. The dispatcher sends a first word of edit or --edit
# to git::edit_cmd, the only parser here (verb::parse); main() takes --local and --dir before the
# verb, and leaves --help on a git line to git.

verb::define git "git in a tier's bare repo (what 'git df' and 'git ldf' do)"
verb::usage git '[--local] git <args…>' '[--local] --dir'
verb::about git <<'EOF'
Everything after 'git' goes to git untouched, --help included, with one
exception: 'edit' or '--edit' as the first word (git has no such command
or option; 'git commit --edit' still reaches git). The shared tier is
$(help::tilde "${TIER_GIT_DIR[shared]}") with work tree ~; the local tier is
$(help::tilde "${TIER_GIT_DIR[local]}") with work tree ~/.local.
EOF
verb::section git 'The local allowlist' <<'EOF'
The local tier tracks only what its allowlist admits: info/exclude, a
copy of the template $(help::tilde "${LDF_EXCLUDE_TEMPLATE}") (shared
tier). It starts '/*' (nothing), and each '!' entry admits a path; every
'!' entry has a '# why' comment on the line above it, or above the run of
'!' lines it belongs to. An entry without one fails local_dotfiles_repo.
EOF
verb::edit git git::edit_cmd '[--no-commit]' \
  "with --local only ('dotfiles --local git edit'): the allowlist template in \\\$EDITOR (vi when unset) as a draft. It refuses up front when this machine's info/exclude has rules the template does not (it shows the diff: make them agree first). On save the draft must start with '/*', keep every '*.secret.zsh' out of every admitted directory, and give each '!' entry its why; a draft that fails is kept (offered for another edit on a terminal, else exit 1; the same command resumes it). One that passes replaces the template and is installed as info/exclude; 'git ldf status --short -uall' then shows what it admits, and the template is committed in the shared tier"
verb::flag git '--local' 'act on the local tier, not the shared one (before the verb)'
verb::flag git '--dir' "print the tier's bare repo path and exit (in place of a verb)"
verb::flag git '--no-commit' 'edit: install it, leave the template uncommitted'
verb::env git ARI_DOTFILES_DF_GIT_DIR "the shared tier's bare repo" '$(help::tilde "${ARI_DOTFILES_DF_GIT_DIR}")'
verb::env git ARI_DOTFILES_LDF_GIT_DIR "the local tier's bare repo" '$(help::tilde "${ARI_DOTFILES_LDF_GIT_DIR}")'

cmd_git() { repo_git "${GIT_TIER}" "$@"; }

# git::edit_cmd [--no-commit]: `--local git edit`; main() leaves --help to it, as to git.
git::edit_cmd() {
  local -A opts; local -a args
  verb::parse git "$@"
  (( ${+opts[--help]} )) && { help_verb git; return 0; }
  [[ "${GIT_TIER}" == local ]] || usage_error "git --edit edits the local tier's allowlist | fix='${CLI_NAME} --local git --edit'"
  (( ${#args} == 0 )) || usage_error "git --edit: unknown argument | arg='${args[1]}'"
  (( ${+opts[--local]} + ${+opts[--dir]} == 0 )) || usage_error "git --edit: --local and --dir go before the verb | fix='${CLI_NAME} --local git --edit'"
  need_lib "${ARI_DOTFILES_CMD}/git/edit.zsh" || return 3
  git_edit "$(( ! ${+opts[--no-commit]} ))"
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
