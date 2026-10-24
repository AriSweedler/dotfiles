function pubkey() {
  fzfdb --fzfdb_dir "${XDG_DATA_HOME}/ssh" -- "$@"
}

function pubkey::action::help() {
  cat << EOF
USAGE: pubkey [pubkey]
 
Put a pubkey on your clipboard. Use fzf to search through all possible
pubkeys that have been saved
 
$(fzfdb::help_common)
EOF
}

# Input: pubkey
# Output: the line you want to show up in fzf
function pubkey::key::menuitem() {
  local pubkey="${1:?}"
  local pubkey_file="$(fzfdb::key::_path "${pubkey}")"

  local pubkey_body
  pubkey_body=$(awk '{print $1 " " $3}' "${pubkey_file}" | tr -s '\n' ';')
  echo "${pubkey} | ${pubkey_body}"
}

# Input: pubkey
# Put the pubkey on the system clipboard & log
function pubkey::key::_handle_selection() {
  local pubkey="${1:?}"
  local pubkey_file="$(fzfdb::key::_path "${pubkey}")"

  pbcopy < "${pubkey_file}"
  log::INFO "Copied friend's pubkey to clipboard
friend='${c_cyan}${pubkey}${c_rst}'
pubkey='${c_green}$(pbpaste)${c_rst}'"
}
