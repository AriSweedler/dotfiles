function fzfdb::help() {
  cat << EOF
Helper utility to make "fuzzy-findable databases" (ilo_env, tenants, etc.)

This is a really common concept - I have a list of objects that I wanna
fuzzy-find through. The easiest way for me to implement this is to define a
folder and save key-value pairs. The key is the filename, the value is anything.

CLI:
  fzfdb [options] [fzf options]

$(fzfdb::help_common)

USAGE
  Create a file and define the entrypoint. Have it forward to fzfdb. For
  example, if you want each entry to be a set of environment variables to
  source, you may have an entrypoint like so:

      function my_env() {
        fzfdb --fzfdb_dir "/some/absolute/dir" -- "\$@"
      }

  Then, you can override stuff, like what to do when you select a key:

      # Input: env key
      # No output. Sets environment variables
      function fzfdb::key::_handle_selection() {
        local key="\${1:?}"
        local keypath
        keypath="\$(fzfdb::key::_path "\${key}")"
        eval "\$(cat "\${keypath}")"
      }
EOF
}

function fzfdb::help_common() {
  cat << EOF
DETAILS:
  * name: ${fzfdb_name:?}
  * dir: ${fzfdb_dir:?}

ACTIONS:
  --help
    Print this help message

  --dir
    Print the directory where the fzfdb is stored

  --list
    List the items in the fzfdb

  --edit
    Edit the fzfdb directory or a specific fzfdb file
    * optional 1st arg is the fzfdb file to edit

PRESEARCH
  -g|--grep
    * Grep the list of items to filter it down
    * Takes a single grep pattern; quote it if it contains spaces
  -q|--query
    * Start fzf with this query

KEYS
  --key::value|--key::menuitem
    * Get the value or the menuitem for a key
EOF
}

function fzfdb() {
  # Parse args to the framework
  local fzfdb_name fzfdb_dir
  while (( $# > 0 )); do
    case "${1}" in
      -h|--help) fzfdb::help; return 0;;
      --fzfdb_name) fzfdb_name="${2}"; shift 2;;
      --fzfdb_dir) fzfdb_dir="${2}"; shift 2;;
      --) shift; break;;
      *)
        log::err "Unknown option | option='${1}'"
        return 1
        ;;
    esac
  done

  # Massage and validate args
  [ -z "${fzfdb_name}" ] && fzfdb_name="${funcstack[2]}"
  [ -z "${fzfdb_dir}" ] && log::err "fzfdb_dir is required" && return 1

  # Parse args to the application
  local fzf_args=(--select-1)
  local grep_pat='.'
  while (( $# > 0 )); do
    case "${1}" in
      --dir|--list|--edit|--help) fzfdb::_dispatch "action::${1#--}" "$@"; return 0;;
      --key::value|--key::menuitem) fzfdb::_dispatch "${1#--}" "${2:?}"; return 0;;
      # Menuitem -> key -> value in one action, so the fzf preview goes through
      # the client's own (dispatched) menuitem::key instead of the default.
      --preview::menuitem)
        local fzfdb_pk
        if ! fzfdb_pk="$(fzfdb::_dispatch menuitem::key "${2:?}")"; then
          log::err "Could not recover key from menuitem | menuitem='${2}'"
          return 1
        fi
        fzfdb::_dispatch key::value "${fzfdb_pk}"
        return $?
        ;;
      -g|--grep) grep_pat="${2}"; shift 2;;
      -q|--query) fzf_args+=(--query "${2}"); shift 2;;
      *) break;;
    esac
  done

  # Make it easier to "log with"
  local logw="fzfdb_name='${fzfdb_name}' fzfdb_dir='${fzfdb_dir}'"

  # If there are positional parameters, take the first one as the selection &
  # exit early.
  if (( $# > 0 )); then
    local fzfdb_k="${1}"

    # Make sure the key is valid
    if ! fzfdb::key::_validate "${fzfdb_k}" &>/dev/null; then
      log::err "The key you provided does not exist | key='${fzfdb_k}' ${logw}"
      return 1
    fi

    # Run the "I have selected a key" action
    fzfdb::_dispatch key::_handle_selection "${fzfdb_k}"
    return $?
  fi

  # Make sure there are elements in fzfdb_ks
  # The inner substitution MUST be quoted: zsh IFS-splits unquoted $(...)
  # even inside ${(@f)...}, shattering keys that contain spaces.
  local fzfdb_ks=(${(@f)"$(fzfdb::_dispatch action::list | grep -- "${grep_pat}")"})
  if (( ${#fzfdb_ks[@]} == 0 )); then
    log::err "No fzfdb items found | ${logw}"
    return 1
  fi

  # Generate the fzf menu
  local tmpdir="$(mktemp -d "/tmp/fzfdb.${fzfdb_name}.XXXXX")"
  # Function-local EXIT trap: cleans up even when fzf is cancelled or we error out.
  trap "rm -rf '${tmpdir}'" EXIT
  setopt LOCAL_OPTIONS NO_MONITOR
  for fzfdb_k in "${fzfdb_ks[@]}"; do
    fzfdb::_dispatch key::menuitem "${fzfdb_k}" > "${tmpdir}/${fzfdb_k}" &
  done
  wait
  local fzfdb_m_items=()
  local fzfdb_k
  for fzfdb_k in "${fzfdb_ks[@]}"; do
    fzfdb_m_items+=("$(cat "${tmpdir}/${fzfdb_k}")")
  done

  # Pad keys to a common width so the " | " separators line up across the
  # menu. fzfdb::menuitem::key strips this padding when recovering the key.
  local fzfdb_m_item max_key_len=0
  for fzfdb_m_item in "${fzfdb_m_items[@]}"; do
    local item_key="${fzfdb_m_item%% | *}"
    (( ${#item_key} > max_key_len )) && max_key_len=${#item_key}
  done
  local fzfdb_m_aligned=()
  for fzfdb_m_item in "${fzfdb_m_items[@]}"; do
    if [[ "${fzfdb_m_item}" != *" | "* ]]; then
      fzfdb_m_aligned+=("${fzfdb_m_item}")
      continue
    fi
    local item_key="${fzfdb_m_item%% | *}"
    fzfdb_m_aligned+=("${(r:${max_key_len}:)item_key} | ${fzfdb_m_item#* | }")
  done
  fzfdb_m_items=("${fzfdb_m_aligned[@]}")

  # Generate the fzf command
  local preview_cmd=(
    source ${funcsourcetrace[1]%:*} \;
    source ${funcsourcetrace[2]%:*} \;
    source ~/.config/zsh/plugins/log.zsh \;
    source ~/.config/zsh/plugins/arr.zsh \;
    fzfdb
    --fzfdb_name "${fzfdb_name}"
    --fzfdb_dir "${fzfdb_dir}"
    --
    --preview::menuitem {}
  )
  fzf_args+=(
    --preview "${preview_cmd[*]}"
    --preview-window=up:3:wrap
  )

  # Get a selection from the user
  local fzfdb_m_selected
  fzfdb_m_selected=$(printf "%s\n" "${fzfdb_m_items[@]}" |\
    fzf "${fzf_args[@]}")
  if [ -z "${fzfdb_m_selected}" ]; then
    log::warn "No fzfdb item selected | ${logw}"
    return 1
  fi

  # Find the selected key from the menuitem
  fzfdb_k="$(fzfdb::_dispatch menuitem::key "${fzfdb_m_selected}")"
  if ! fzfdb::key::_validate "${fzfdb_k}" &>/dev/null; then
    log::err "Failed to recover valid key from selected menuitem | menuitem='${fzfdb_m_selected}' invalid_key='${fzfdb_k}' ${logw}"
    return 1
  fi

  # Run the "I have selected a key" action
  fzfdb::_dispatch key::_handle_selection "${fzfdb_k}"
}

############################### Helper functions ################################

function fzfdb::_dispatch() {
  local fxn="${1:?}"
  shift

  local cmd="${fzfdb_name}::${fxn}"
  if type "${cmd}" &>/dev/null; then
    log::debug "Dispatching to user-overriden fxn | fxn='${fxn}' ${logw}"
  else
    log::debug "Dispatching to default cmd for fxn. Override this with 'override_cmd' | override_cmd='${cmd}' fxn='${fxn}' ${logw}"
    cmd="fzfdb::${fxn}"
  fi
  "${cmd}" "$@"
}

function fzfdb::key::_validate() {
  local key="${1:?}"
  shift

  # Dispatch so clients that override action::list (non-file-backed keys,
  # e.g. tmux-oneshot's JSON list) validate against their own key set. The
  # inner quotes keep zsh from IFS-splitting keys that contain spaces.
  local keys=(${(@f)"$(fzfdb::_dispatch action::list)"})
  if ! arr::contains "${key}" "${keys[@]}"; then
    log::err "Key not found | key='${key}' ${logw}"
    return 1
  fi

  echo "${key}"
}

function fzfdb::key::_path() {
  local key="${1:?}"
  shift

  local path="$(fzfdb::action::dir)/${key}"
  echo "${path}"
}

##################### Actions common to all fzfdb utilities #####################

function fzfdb::action::edit() {
  shift
  if (( $# > 0 )); then
    log::info "Editing fzfdb file | ${logw} file='${1}'"
    "${EDITOR}" "$(fzfdb::action::dir)/${1}"
  else
    log::info "Editing fzfdb dir | ${logw}"
    "${EDITOR}" "$(fzfdb::action::dir)"
  fi
}

function fzfdb::action::dir() {
  local dir="${fzfdb_dir:?}/${fzfdb_name:?}"
  mkdir -p "${dir}"
  echo "${dir}"
}

function fzfdb::action::list() {
  local dir
  dir="$(fzfdb::action::dir)"
  # Keys are plain files; subdirectories (e.g. go_aws/profiles/) are not keys.
  local keys=("${dir}"/*(N-.))
  (( ${#keys[@]} == 0 )) && return 0
  printf '%s\n' "${keys[@]:t}" | sort
}

############## Clients are encouraged to override these functions. ##############

# Input: fzfdb key
# Output: the line you want to show up in fzf
function fzfdb::key::menuitem() {
  local key="$(fzfdb::key::_validate "${1:?}")"
  shift

  local value="$(fzfdb::key::value "${key}")"
  local transformed_value="$(tr -s '\n' ';' <<< "${value}")"
  echo "${key} | ${transformed_value}"
}

# Input: the line you want to show up in fzf
# Output: The fzfdb key that was used to generate this
function fzfdb::menuitem::key() {
  local menuitem="${1:?}"
  shift

  # Strip column-alignment padding appended to the key.
  setopt LOCAL_OPTIONS EXTENDED_GLOB
  echo "${${menuitem%% | *}%%\ #}"
}

# Input: fzfdb key
# Output: The value you want to show up in the fzf preview window
function fzfdb::key::value() {
  local key="$(fzfdb::key::_validate "${1:?}")"
  shift

  local keypath
  keypath="$(fzfdb::key::_path "${key}")"
  cat "${keypath}"
}

# Input: fzfdb key
# No output. But this function should have desirable side effects
function fzfdb::key::_handle_selection() {
  local key="${1:?}"
  shift

  log::info "You have selected a key | key='${key}' ${logw}"
}
