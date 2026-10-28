# dotfiles/lib/machine_name.zsh — every machine's everyday name: one word in a local-tier file
# (ARI_DOTFILES_MACHINE_NAME_FILE). The machine_name step writes a random one; `dotfiles
# machine-name` reads and sets it, and so does editing the file. One source of truth: anything
# that labels a host reads it through `dotfiles machine-name`, never the path.

typeset -ga MACHINE_NAME_ADJECTIVES=(amber brisk calm dusky eager fern gentle hazel ivory jolly keen lunar misty nimble olive plucky quiet russet sunny tidy umber vivid windy young zesty)
typeset -ga MACHINE_NAME_NOUNS=(otter heron maple comet badger willow falcon pebble lantern thistle walrus juniper marten cobalt finch acorn harbor quill sparrow tundra)

# machine_name::is_valid NAME: one word of letters, digits, _ or -.
machine_name::is_valid() {
  [[ -n "${1}" && "${1}" != *[^A-Za-z0-9_-]* ]]
}

# machine_name::trim TEXT: REPLY is TEXT without leading or trailing whitespace; inner
# whitespace stays, so "two words" is still refused.
machine_name::trim() {
  setopt localoptions extendedglob
  REPLY="${${1##[[:space:]]#}%%[[:space:]]#}"
}

# machine_name::read: REPLY is the name, trimmed. 1 when the file is missing or empty, 2 when
# what it holds is not a valid name (REPLY then holds it, for the message).
machine_name::read() {
  REPLY=""
  [[ -s "${ARI_DOTFILES_MACHINE_NAME_FILE}" ]] || return 1
  machine_name::trim "$(<"${ARI_DOTFILES_MACHINE_NAME_FILE}")"
  machine_name::is_valid "${REPLY}" || return 2
}

# machine_name::random: REPLY is a fresh adjective-noun name.
machine_name::random() {
  REPLY="${MACHINE_NAME_ADJECTIVES[RANDOM % ${#MACHINE_NAME_ADJECTIVES} + 1]}-${MACHINE_NAME_NOUNS[RANDOM % ${#MACHINE_NAME_NOUNS} + 1]}"
}

# machine_name::write NAME: the file holds NAME; 64 for an invalid one.
machine_name::write() {
  machine_name::is_valid "${1}" || return 64
  run_mut zsh -c 'mkdir -p "${1:h}" && print -r -- "${2}" > "${1}"' _ "${ARI_DOTFILES_MACHINE_NAME_FILE}" "${1}"
}
