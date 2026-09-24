# json_sort — canonical JSON: object keys sorted recursively, 2-space indent, one trailing
# newline; arrays keep their order (array order is data, never sorted here). This is the one
# place JSON canonicalisation lives in the dotfiles: bake runs it on every generated JSON
# (karabiner.json, raycast_bindings.json) so a regenerated file diffs only where the data moved.
#
# Usage: json_sort [FILE...]            canonical form of each file (stdin when none) on stdout
#        json_sort --in-place FILE...   rewrite each file atomically, only when the content changes
# Env:   JSON_SORT_INDENTATION          spaces per level, an integer 0..7 (jq's range; 0 keeps
#                                       one value per line with no indent); default 2, bake's.
# Exit 1 when any input is not JSON, naming the file and jq's position, or when the indentation
# is not an integer 0..7.

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"

: "${JSON_SORT_INDENTATION:=2}"

# Exit 1 with a log::err when JSON_SORT_INDENTATION is outside jq's 0..7.
function json_sort::check_indentation() {
  if [[ ! "${JSON_SORT_INDENTATION}" =~ '^[0-7]$' ]]; then
    log::err "Invalid indentation | JSON_SORT_INDENTATION='${JSON_SORT_INDENTATION}' expected='an integer 0..7'"
    return 1
  fi
}

# stdin → stdout. jq's --sort-keys is recursive over objects and leaves arrays alone.
function json_sort::canonical() {
  json_sort::check_indentation || return 1
  jq --sort-keys --indent "${JSON_SORT_INDENTATION}" .
}

# Input: a file (or "-" for stdin). Output: its canonical form; exit 1 with the jq message when
# the input is not JSON.
function json_sort::file() {
  local file="${1}" err out
  if [[ "${file}" == "-" ]]; then
    out="$(json_sort::canonical 2>&1)" || { log::err "Invalid JSON | file='<stdin>' error='${out}'"; return 1; }
  else
    if [[ ! -r "${file}" ]]; then
      log::err "Cannot read file | file='${file}'"
      return 1
    fi
    out="$(json_sort::canonical < "${file}" 2>&1)" || { log::err "Invalid JSON | file='${file}' error='${out}'"; return 1; }
  fi
  print -r -- "${out}"
}

# Input: a file. Rewrites it in canonical form through a sibling temp file, only when the
# content differs, so an already-canonical file keeps its mtime.
function json_sort::in_place() {
  local file="${1}" tmp
  if [[ ! -w "${file}" ]]; then
    log::err "Cannot write file | file='${file}'"
    return 1
  fi
  tmp="$(mktemp "${file}.XXXXXX")" || return 1
  if ! json_sort::file "${file}" > "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi
  if cmp -s "${tmp}" "${file}"; then
    rm -f "${tmp}"
    log::info "json sorted | file='${file}' changed='no'"
    return 0
  fi
  mv "${tmp}" "${file}"
  log::info "json sorted | file='${file}' changed='yes'"
}

function json_sort::help() {
  cat >&2 <<EOF
json-sort — canonical JSON: keys sorted recursively, 2-space indent, arrays in data order

  json-sort [FILE...]            print the canonical form (stdin when no file)
  json-sort --in-place FILE...   rewrite each file atomically, only when its content changes
  json-sort --help

  JSON_SORT_INDENTATION=N        spaces per level, an integer 0..7 (default 2; bake uses the default)

Exit 1 on invalid JSON, naming the file and jq's position, or on a bad indentation. Every
generated JSON in the dotfiles goes through this (bake runs it), so it is the one place
canonicalisation lives.
EOF
}

function json_sort() {
  local in_place=0 rc=0 file
  local -a files
  json_sort::check_indentation || return 1
  while (( $# > 0 )); do case "${1}" in
    -h|--help)   json_sort::help; return 0 ;;
    --in-place)  in_place=1; shift ;;
    --)          shift; files+=("$@"); break ;;
    -*)          log::err "Unknown flag | flag='${1}'"; json_sort::help; return 1 ;;
    *)           files+=("${1}"); shift ;;
  esac; done
  if (( in_place )); then
    if (( ${#files} == 0 )); then
      log::err "--in-place needs at least one file"
      return 1
    fi
    for file in "${files[@]}"; do json_sort::in_place "${file}" || rc=1; done
    return "${rc}"
  fi
  (( ${#files} == 0 )) && files=(-)
  for file in "${files[@]}"; do json_sort::file "${file}" || rc=1; done
  return "${rc}"
}
