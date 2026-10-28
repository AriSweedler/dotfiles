# step machine_name — this machine has an everyday name: one word in a local-tier file, which
# tools show where a machine must be told apart (ari-driving labels a remote pane machine=<name>).
step::declare machine_name --group repo \
  --desc "this machine's everyday name is set: one word in ~/.local/share/dotfiles/machine-name (edit it any time)" \
  --apply "writes a random adjective-noun name to ~/.local/share/dotfiles/machine-name; rename by editing the file"
step::watches machine_name --none "reads only the local-tier name file, which no repo tracks"

readonly MACHINE_NAME_FILE="${XDG_DATA_HOME:-${HOME}/.local/share}/dotfiles/machine-name"
readonly -a MACHINE_NAME_ADJECTIVES=(amber brisk calm dusky eager fern gentle hazel ivory jolly keen lunar misty nimble olive plucky quiet russet sunny tidy umber vivid windy young zesty)
readonly -a MACHINE_NAME_NOUNS=(otter heron maple comet badger willow falcon pebble lantern thistle walrus juniper marten cobalt finch acorn harbor quill sparrow tundra)

check::machine_name() {
  if [[ ! -s "${MACHINE_NAME_FILE}" ]]; then
    verdict fail name_missing -d "no machine name | file='${MACHINE_NAME_FILE}'" -f "${CLI_NAME} apply machine_name"
    return 0
  fi
  local name
  name="$(<"${MACHINE_NAME_FILE}")"
  name="${name//[[:space:]]/}"
  if [[ -z "${name}" || "${name}" == *[^A-Za-z0-9_-]* ]]; then
    verdict fail name_malformed -d "machine name must be one word of letters, digits, _ or - | file='${MACHINE_NAME_FILE}' name='${name}'"
    return 0
  fi
  verdict ok named -d "name='${name}' file='${MACHINE_NAME_FILE}'"
}

apply::machine_name() {
  if [[ -s "${MACHINE_NAME_FILE}" ]]; then
    log::info "Keeping the existing machine name | file='${MACHINE_NAME_FILE}'"
    return 0
  fi
  local name="${MACHINE_NAME_ADJECTIVES[RANDOM % ${#MACHINE_NAME_ADJECTIVES} + 1]}-${MACHINE_NAME_NOUNS[RANDOM % ${#MACHINE_NAME_NOUNS} + 1]}"
  log::info "Naming this machine; edit the file to rename it | name='${name}' file='${MACHINE_NAME_FILE}'"
  run_mut zsh -c 'mkdir -p "${1:h}" && print -r -- "${2}" > "${1}"' _ "${MACHINE_NAME_FILE}" "${name}"
}
