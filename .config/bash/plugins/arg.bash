# Check to make sure that the variable is set
#
# Returns:
#  0 if the variable named by 'arg' has a value. 1 otherwise
function arg::_required() {
  set +u

  local arg="${1:?}"
  if ! [ -v "${arg}" ]; then
    log::err "Required arg is unset | arg='${arg}'"
    exit 1
  fi

  local val="${!arg}"
  if [ -z "${val}" ]; then
    log::err "Required arg is empty | arg='${arg}'"
    exit 1
  fi

  set -u
}

# Check to make sure that one of the group of variables is set
#
# Returns:
#  0 if any of the variables named by '$@' have a value. 1 otherwise
function arg::_required::one() {
  for arg in "$@"; do
    # If any one of the args is present, then return success
    arg::_required "${arg}" &>/dev/null && return
  done

  # If we haven't returned by now, then return failure
  return 1
}

# Checks each environment variable to see if it has a value. N arguments
#
# Args:
#   *: Environment variable to check
#
# Example:
#   arg::_env "OTTO_VAR1" "OTTO_VAR2"
#   some operation depending on "${OTTO_VAR1}" "${OTTO_VAR2}"
#
# Returns:
#   0 if all variables have values, 1 otherwise
function arg::_env() {
  for env in "$@"; do
    if ! [ -v "${env}" ]; then
      log::err "Required env is unset | env='${env}'"
      return 1
    fi
  done
}

# Verifies if the given variable's value is one of the accepted strings.
#
# This function checks if the specified variable exactly matches one of the
# expected string values.
#
# Args:
#   1: Variable name to check. The actual value is accessed indirectly using the variable name provided.
#   2+: Expected string values
#
# Example:
#   arg::_string "VAR_NAME" "expected_string_1" "expected_string_2"
#
# Returns:
#   0 if the variable is one of the expected string, 1 otherwise.
function arg::_string() {
  set +u

  local var="${1:?}"
  local actual="${!var}"
  shift

  if [ -z "${actual}" ]; then
    log::err "Var does not have a value | var='${var}'"
    exit 1
  fi

  for expected in "$@"; do
    [ "${actual}" != "${expected}" ] && continue
    set -u && return 0
  done

  log::err "Variable is not one of the expected string | var='${var}' actual='${actual}' expected=|$(printf "'%s' " "$@")|"
  set -u && return 1
}
