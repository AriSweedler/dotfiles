function _pk::help() {
  cat <<EOF
Usage: pubkey [OPTIONS] [PUBKEY]

Options:
  -h, --help  Show this help message and exit
  --edit      Edit pubkey file
  --copy      Copy pubkey to clipboard
  --dir       Show the directory where pubkeys are stored
  --list      List all pubkeys in your database
  --compare   Use 'rg' to check if a pattern shows up in your pubkey database
EOF
}

function pubkey() {
  local action=copy
  local epp=1 pp=() # [expected] positional parameters

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) _pk::help; return 0;;
      --edit) action=edit; epp=1; shift;;
      --copy) action=copy; epp=1; shift;;
      --list) action=list; epp=0; shift;;
      --dir) action=dir; epp=0; shift;;
      --compare) action=compare; epp=1; shift;;
      *)
        pp+=( "$1" ) && shift
        if (( ${#pp[@]} > epp )); then
          log::err "Expected only N positional parameters | N='${epp}'"
          return 1
        fi
        ;;
    esac
  done

  if (( ${#pp[@]} != epp )); then
    log::err "Expected N positional parameters | N='${epp}' #pp='${#pp[@]}'"
    return 1
  fi

  "_pk::action::$action" "${pp[@]}"
}

function validate::pubkey() {
  local pk="${1:?}"
  local pk_abs
  pk_abs="$(_pk::dir)/$pk"
  [ -r "$pk_abs" ]
}

function _pk::dir() {
  echo "$XDG_DATA_HOME/ssh/pubkeys_of_friends"
}

function _pk::file() {
  local pk="${1:?}"
  validate::pubkey "$pk" || fatal::_pk::invalid

  echo "$(_pk::dir)/$pk"
}

function _pk::action::copy() (
  local pk="${1:?}"
  validate::pubkey "$pk" || fatal::_pk::invalid
  local pk_abs
  pk_abs="$(_pk::file "$pk")"

  pbcopy < "$pk_abs"
  log::INFO "Copied friend's pubkey to clipboard
friend='${c_cyan}${pk}${c_rst}'
pubkey='${c_green}$(pbpaste)${c_rst}'"
)

function _pk::action::edit() (
  if (( $# == 0 )); then
    "$EDITOR" "$(_pk::dir)"
    return
  fi

  local pk="${1:-}"
  local pk_abs
  pk_abs="$(_pk::dir)/$pk"

  run_cmd "$EDITOR" "$pk_abs"
  pubkey --copy "$pk"
)

function _pk::action::list() {
  ls -1 "$(_pk::dir)"
}

function _pk::action::dir() {
  _pk::dir
}

function _pk::action::compare() {
  local pk_contents="${1:?}"
  local files_with_matches
  files_with_matches=($(
    cd "$(_pk::dir)"
    rg "${pk_contents}" --files-with-matches
  ))
  log::info "Found N matches | N='${#files_with_matches[@]}'"
  case "${#files_with_matches[@]}" in
    0) return 1;;
    *) log::INFO "${(F)files_with_matches}" ;;
  esac
}

function fatal::_pk::invalid() {
  log::err "Invalid pubkey | pk='${pk}'"
  exit 1
}
