# dotfiles/cmd/machine-name.zsh — `dotfiles machine-name`: this machine's everyday name.

verb::define machine-name "this machine's everyday name: print it, or set it"
verb::usage machine-name 'machine-name' 'machine-name NAME [--no-commit]'
verb::about machine-name <<'EOF'
Every machine has one everyday name: one word of letters, digits, _ or -
in $(help::tilde "${ARI_DOTFILES_MACHINE_NAME_FILE}"), a local-tier file. The
machine_name step writes a random adjective-noun there when it is missing.
'machine-name NAME' renames the machine; so does editing the file, by hand
or with 'machine-name edit', which checks the name on save. Either way the
file is committed in the local tier.

Anything that labels a host reads the name through 'dotfiles machine-name',
never the path; for another machine, run it there over ssh.
EOF
verb::edit machine-name machine_name::edit_cmd '[--no-commit]' 'the name file in \$EDITOR as a draft, checked on save, then put in place and committed in the local tier'
verb::flag machine-name '--no-commit' 'put the name in place, leave it uncommitted'
verb::env machine-name ARI_DOTFILES_MACHINE_NAME_FILE 'the name file' '$(help::tilde "${ARI_DOTFILES_MACHINE_NAME_FILE}")'
verb::section machine-name 'Exit codes' <<'EOF'
0   printed, set, or no change
1   no name yet (run 'dotfiles apply machine_name'), the file holds no valid name, or the commit failed
64  usage, or NAME is not one word of letters, digits, _ or -
EOF

cmd_machine-name() {
  local -A opts; local -a args
  verb::parse machine-name "$@"
  (( ${#args} <= 1 )) || usage_error "machine-name takes at most one NAME | args='${args[*]}'"
  if (( ${#args} == 0 )); then
    (( ! ${+opts[--no-commit]} )) || usage_error "--no-commit goes with machine-name NAME"
    machine_name::print
    return
  fi
  local name="${args[1]}"
  machine_name::is_valid "${name}" || usage_error "a machine name is one word of letters, digits, _ or - | name='${name}'"
  local REPLY
  if machine_name::read && [[ "${REPLY}" == "${name}" ]]; then
    print -r -- "machine-name: no change | name=${name}"
    return 0
  fi
  machine_name::write "${name}" || return 1
  print -r -- "machine-name: set | name=${name} file=$(ui::paths "${ARI_DOTFILES_MACHINE_NAME_FILE}")"
  machine_name::commit "${name}"
}

# machine_name::print: the name on stdout and nothing else, for scripts and prompts.
machine_name::print() {
  local REPLY
  local -i rc=0
  machine_name::read || rc=$?
  case "${rc}" in
    0) print -r -- "${REPLY}" ;;
    1) log::err "no machine name yet | file='${ARI_DOTFILES_MACHINE_NAME_FILE}' fix='${CLI_NAME} apply machine_name'"; return 1 ;;
    *) log::err "the name file holds no valid name | file='${ARI_DOTFILES_MACHINE_NAME_FILE}' name='${REPLY}' fix='${CLI_NAME} machine-name NAME'"; return 1 ;;
  esac
}

# machine_name::commit NAME: the name file committed in the local tier, unless the caller's opts
# carry --no-commit.
machine_name::commit() {
  if (( ${+opts[--no-commit]} )); then
    print -r -- "not committed | file=$(ui::paths "${ARI_DOTFILES_MACHINE_NAME_FILE}")"
    return 0
  fi
  tier::commit local "machine-name: ${1}" "${ARI_DOTFILES_MACHINE_NAME_FILE}"
}

# machine_name::edit_cmd [--no-commit]: the name file through a draft, checked on save.
machine_name::edit_cmd() {
  local -A opts; local -a args
  verb::parse machine-name "$@"
  (( ${#args} == 0 )) || usage_error "machine-name edit takes no NAME | args='${args[*]}'"
  local file="${ARI_DOTFILES_MACHINE_NAME_FILE}" draft
  local -i rc=0
  edit::draft "${file}" "${ARI_DOTFILES_STATE_DIR}/drafts" machine_name::_edit_template || return 1
  draft="${REPLY}"
  edit::session "${draft}" --check machine_name::_edit_check --what "the machine name" ${${EDIT_RESUMED:#0}:+--changed} \
    --resume "${CLI_NAME} machine-name edit" || rc=$?
  if (( rc == 2 )) || { (( rc == 0 )) && [[ -f "${file}" ]] && edit::same "${draft}" "${file}"; }; then
    rm -f -- "${draft}"
    print -r -- "machine-name: no change | file=$(ui::paths "${file}")"
    return 0
  fi
  (( rc == 0 )) || return 1
  mkdir -p "${file:h}"
  edit::install "${draft}" "${file}" 644 || return 1
  local REPLY
  machine_name::read
  print -r -- "machine-name: set | name=${REPLY} file=$(ui::paths "${file}")"
  machine_name::commit "${REPLY}"
}

# A missing name file starts from a fresh random name.
machine_name::_edit_template() {
  local REPLY
  machine_name::random
  print -r -- "${REPLY}"
}

machine_name::_edit_check() {
  local REPLY
  machine_name::trim "$(<"${1}")"
  machine_name::is_valid "${REPLY}" && return 0
  print -u2 -r -- "a machine name is one word of letters, digits, _ or - | name='${REPLY}'"
  return 1
}
