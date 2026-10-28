# step machine_name — this machine has an everyday name: one word in a local-tier file, read and
# set with `dotfiles machine-name`, which tools show where a machine must be told apart.
step::declare machine_name --group repo \
  --desc "this machine's everyday name is set: one word in ~/.local/share/dotfiles/machine-name ('dotfiles machine-name NAME' or an edit renames it)" \
  --apply "writes a random adjective-noun name to ~/.local/share/dotfiles/machine-name; 'dotfiles machine-name NAME' renames it"
step::watches machine_name --none "reads only the local-tier name file, which no repo tracks"

check::machine_name() {
  local -i rc=0
  machine_name::read || rc=$?
  case "${rc}" in
    0) verdict ok named -d "name='${REPLY}' file='${ARI_DOTFILES_MACHINE_NAME_FILE}'" ;;
    1) verdict fail name_missing -d "no machine name | file='${ARI_DOTFILES_MACHINE_NAME_FILE}'" -f "${CLI_NAME} apply machine_name" ;;
    *) verdict fail name_malformed -d "machine name must be one word of letters, digits, _ or - | file='${ARI_DOTFILES_MACHINE_NAME_FILE}' name='${REPLY}'" -f "${CLI_NAME} machine-name NAME" ;;
  esac
}

apply::machine_name() {
  if [[ -s "${ARI_DOTFILES_MACHINE_NAME_FILE}" ]]; then
    log::info "Keeping the existing machine name | file='${ARI_DOTFILES_MACHINE_NAME_FILE}'"
    return 0
  fi
  machine_name::random
  log::info "Naming this machine; '${CLI_NAME} machine-name NAME' renames it | name='${REPLY}' file='${ARI_DOTFILES_MACHINE_NAME_FILE}'"
  machine_name::write "${REPLY}"
}
