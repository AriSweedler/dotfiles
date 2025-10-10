# Help text storage
typeset -gA GIT_WRAPPER_HELP

git_wrapper::_help() {
  if (( $# == 2 )); then
    # Register help: git_wrapper::_help <option> "description"
    GIT_WRAPPER_HELP[$1]=$2
    return
  fi

  # Retrieve help: git_wrapper::_help <option>
  # If no help text, try to follow the alias
  if [[ -n "${GIT_WRAPPER_HELP[$1]}" ]]; then
    echo "${GIT_WRAPPER_HELP[$1]}"
    return
  fi

  # Try to find what this function calls
  local func_body=$(typeset -f "git_wrapper::$1" 2>/dev/null)
  # Match the function call inside the body (not the definition line)
  # Look for git_wrapper::something that's not the function name itself
  if [[ $func_body =~ $'\n'[[:space:]]*'git_wrapper::'([a-z-]+) ]]; then
    local target="${match[1]}"
    if [[ -n "${GIT_WRAPPER_HELP[$target]}" ]]; then
      echo "${GIT_WRAPPER_HELP[$target]}"
      return
    fi
  fi

  # Unhappy path: no help found
  log::err "No help text found for option: $1"
}

# Define all -cc option handlers (and their aliases)
git_wrapper::side-by-side() { echo "delta.features=side-by-side"; }
git_wrapper::sbs()          { git_wrapper::side-by-side; }
git_wrapper::_help side-by-side "Enable side-by-side diff view"

# https://github.com/dandavison/delta/issues/680#issuecomment-897794121
git_wrapper::files-only() { echo "delta.navigate-regex=^Δ"; }
git_wrapper::files()      { git_wrapper::files-only; }
git_wrapper::no-hunks()   { git_wrapper::files-only; }
git_wrapper::nh()         { git_wrapper::files-only; }
git_wrapper::_help files-only "Navigate files only (skip hunks)"

git_wrapper::hunks-only() { echo "delta.navigate-regex=^•"; }
git_wrapper::hunks()      { git_wrapper::hunks-only; }
git_wrapper::no-files()   { git_wrapper::hunks-only; }
git_wrapper::nf()         { git_wrapper::hunks-only; }
git_wrapper::_help hunks-only "Navigate hunks only (skip files)"

# List all available -cc options using reflection
git_wrapper::_list_options() {
  print -l ${(k)functions} | awk -F'::' '$1 == "git_wrapper" && NF == 2 { print $2 }'
}

function git_wrapper::_completion_options() {
  local opt
  for opt in $(git_wrapper::_list_options); do
    # Skip internal functions (those starting with _)
    [[ "$opt" == _* ]] && continue
    
    # Get help text for this option
    echo "${opt}:$(git_wrapper::_help "$opt" 2>/dev/null)"
  done
}

# The wrapper
git_wrapper() {
  local git_config_overrides=() git_args=()
  while (( $# > 0 )); do
    case "$1" in
      -cc)
        if [ -z "${2}" ]; then
          log::err "'-cc' flag must have an argument! | valid=[$(git_wrapper::_list_options | str::colorize cyan | str::join '|')]"
          return 1
        fi
        
        local func_name="git_wrapper::${2}"
        if (( ${+functions[$func_name]} )); then
          local config_value
          config_value=$("$func_name")
          git_config_overrides+=("-c" "$config_value")
          log::info "Expanded {lhs} into {rhs} | lhs='-cc $2' rhs='-c $config_value'"
        else
          log::err "Unknown -cc option: $2 | valid=[$(git_wrapper::_list_options | str::colorize cyan | str::join '|')]"
          return 1
        fi
        shift 2
        ;;
      *)
        git_args+=("${1}")
        shift 
        ;;
    esac
  done
  # Call the real git with our expanded options plus remaining args
  command git "${git_config_overrides[@]}" "${git_args[@]}"
}

# Take over 'git': invoke the wrapper
git() {
  git_wrapper "$@"
}
