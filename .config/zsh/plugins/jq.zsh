function jq::drill::help() {
  cat <<HELP
Usage: jq::drill [options]
HELP
}

function jq::drill() {
  # Parse args
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) jq::drill::help; return ;;
      *) log::err "Unknown argument in ${funcstack[1]}: ${1}"; return 1;;
    esac
  done

  # If there is no stdin, then just quit
  if [ -t 0 ]; then
    log::err "No input"
    return 1
  fi
  local original_json
  original_json=$(cat - | jq)

  # Initialize global values and start drilling
  local histstack_filt=() histstack_json=()
  local generated_filter="" cur_json="${original_json}"
  jq::_drill

  # Put results on clipboard
  pbcopy < <(jq::_drill::selection)
}

function jq::_drill::selection() {
  # Validate
  JQ_DRILL_SELECTION="${JQ_DRILL_SELECTION:-result}"
  case "${JQ_DRILL_SELECTION}" in
    filter | result) ;;
    *)
      log::err "Unknown selection: ${JQ_DRILL_SELECTION} - selecting 'result'"
      JQ_DRILL_SELECTION="result"
      ;;
  esac

  # Implement
  case "${JQ_DRILL_SELECTION}" in
    result) echo -n "${cur_json}" ;;
    filter) echo -n "${generated_filter}" ;;
  esac
  log::INFO "Putting selection on clipboard: selection='${JQ_DRILL_SELECTION:-}'
|    generated_filter='${generated_filter}'
|    result='${cur_json}'"
}

function jq::_drill() {
  # Find the type of the current JSON & dispatch
  local type
  if ! type=$(jq -r 'type' <<< "${cur_json}"); then
    log::err "Failed to get type"
    return 1
  fi

  # Type check
  case "${type}" in
    string | number | null) return ;;
    object | array) ;;
    *)
      log::err "Unknown type | type='${type}' filter='${generated_filter}' cur_json='${cur_json}'"
      return 1
      ;;
  esac

  # Let the user select a key with fzf.
  local fzf_opts=(
    --height=20
    --layout=reverse
    --border
    --ansi
  )
  "jq::_drill::${type}::_append_fzf_opts"

  local keys
  if ! keys=($(jq -r 'keys[]' <<< "${cur_json}" 2>/dev/null)); then
    log::info "Drilling complete | filter='${generated_filter}'"
    return
  fi

  # Newline separated string. Options are:
  # 1. no-op
  # 2. all the keys
  # 3. Go to prev filter
  # TODO: Give user an escape sequence to add non-drill filters - a pipe or a
  # function
  local fzf_input=$(
    echo
    echo -e "${(j.\n.)keys[@]}"
    echo ".."
  )
  local user_selection
  if ! user_selection=$(fzf "${fzf_opts[@]}" <<< "${fzf_input}"); then
    log::warn "No key selected - drilling done"
    return
  fi
  log::debug "Selected filter | user_selection='${user_selection}'"

  # Implement the selection
  case "${user_selection}" in
    "") ;;
    ..)
      # Set state to top of stack
      generated_filter="${histstack_filt[@]: -1}"
      cur_json="${histstack_json[@]: -1}"

      # Pop from history stack
      histstack_filt=("${histstack_filt[@]:0:$((${#histstack_filt[@]}-1))}")
      histstack_json=("${histstack_json[@]:0:$((${#histstack_json[@]}-1))}")
      ;;
    *)
      # Push to history stack
      histstack_filt+=("${generated_filter}")
      histstack_json+=("${cur_json}")
      "jq::_drill::${type}::_update_cur_json_and_generated_filter"
      ;;
  esac

  jq::_drill
}

function jq::_drill::object::_append_fzf_opts() {
  fzf_opts+=(
    --header="Generated filter: '${generated_filter}'"
    --prompt="Key> "
    --preview="echo '${cur_json}' | jq -r '.{}'"
  )
}

function jq::_drill::object::_update_cur_json_and_generated_filter() {
  generated_filter="${generated_filter:-}.${user_selection}"
  cur_json=$(echo "${cur_json}" | jq -r ".${user_selection}")
}

function jq::_drill::array::_append_fzf_opts() {
  fzf_opts+=(
    --header="Generated filter: '${generated_filter}'"
    --prompt="Index> "
    --preview="echo '${cur_json}' | jq -r '.[{}]'"
  )
}

function jq::_drill::array::_update_cur_json_and_generated_filter() {
  generated_filter="${generated_filter:-}[${user_selection}]"
  cur_json=$(echo "${cur_json}" | jq -r ".[${user_selection}]")
}

function jq::drill::resource() {
  source /Users/ari.sweedler/.config/zsh/plugins/jq.zsh
}

function jq::drill::example::1() {
  jq::drill::resource
  jq::drill <<< '
{
  "a": 1,
  "b": 2,
  "c": { "d": 3, "e": 4 }
}
'
}

function jq::drill::example::2() {
  jq::drill::resource
  jq::drill <<< '
{
  "a": 1,
  "b": 2,
  "c": { "d": 3, "e": 4 },
  "f": [
    { "x0": 0, "x1": 1 },
    { "y0": 0, "y1": 1 },
    { "z0": 0, "z1": 1 }
  ]
}
'
}
