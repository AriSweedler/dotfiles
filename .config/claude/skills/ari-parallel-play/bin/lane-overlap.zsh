#!/usr/bin/env zsh
# Which lanes may run at once: each lane's owned files (merge-base diff + working tree + untracked),
# the pairwise overlaps, and the ready set against the lanes marked --running. Read-only.
# Run: zsh $HOME/.claude/skills/ari-parallel-play/bin/lane-overlap.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly DEFAULT_BASE="origin/main"
# Paths every lane may touch but only one lane of a group at a time; the repo profile overrides via --shared.
readonly DEFAULT_SHARED=('docs/')
# Untracked entries never counted as owned (the shared dependency symlink); the repo profile overrides via --ignore.
readonly DEFAULT_IGNORED_PREFIX='node_modules'

help() {
  cat <<EOF
${c_green}lane-overlap${c_rst} — owned files, pairwise overlaps and the ready set of parallel lanes

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-parallel-play/bin/lane-overlap.zsh --root DIR --lane ID=WORKTREE|BRANCH [--lane ID=WORKTREE|BRANCH ...] [--running ID ...] [--base REF] [--shared PREFIX ...]

${c_bold}Options:${c_rst}
  --root DIR         The main checkout (its origin is fetched before measuring)
  --lane ID=SOURCE   A lane: its id and its worktree path, or its branch name for a handed-off lane (measured from origin/BRANCH; repeat per lane)
  --running ID       A lane that is running now; the ready set excludes lanes overlapping any of these (repeat)
  --base REF         The ref lanes branch from (default: ${DEFAULT_BASE}); the merge-base with it bounds a lane's diff
  --shared PREFIX    A path prefix that counts as shared, from the repo profile (default: ${(j:, :)DEFAULT_SHARED}; repeat)
  --ignore PREFIX    An untracked prefix never counted as owned, e.g. the shared dependency symlink (default: ${DEFAULT_IGNORED_PREFIX})
  -h, --help         Show this help

${c_bold}Output:${c_rst} JSON on stdout between "=== start RESULT ===" and "=== end RESULT ===":
  {lanes: [{id, source, files_owned, shared_files}], overlaps: [{a, b, files}], ready: [id...]}
EOF
}

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in git jq comm sort; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

#######################################
# The files one lane owns: its commits since the merge-base with the base ref plus, for a live
# worktree, its working-tree changes and untracked files; deduplicated and sorted, the ignored prefix dropped.
# A handed-off lane (its worktree removed) is measured from origin/<branch> in the root.
# Arguments:
#   $1 - root checkout
#   $2 - worktree dir, or a branch name
#   $3 - base ref
# Outputs: one path per line
#######################################
lane_files() {
  local root="${1}" source="${2}" base="${3}" merge_base
  if [[ -d "${source}" ]]; then
    merge_base="$(git -C "${source}" merge-base HEAD "${base}")"
    {
      git -C "${source}" diff --name-only "${merge_base}..HEAD"
      git -C "${source}" diff --name-only
      git -C "${source}" ls-files --others --exclude-standard
    } | drop_ignored_prefix | sort -u
    return 0
  fi
  log::info "Measuring a handed-off lane from its remote branch | branch='${source}'"
  merge_base="$(git -C "${root}" merge-base "origin/${source}" "${base}")"
  git -C "${root}" diff --name-only "${merge_base}..origin/${source}" | drop_ignored_prefix | sort -u
}

#######################################
# Drop the lines that start with the ignored prefix. awk, not grep -v: grep exits 1 when nothing is
# left, which under pipefail made an empty lane (no files yet) kill the script.
# Globals: IGNORED_PREFIX
# Outputs: the remaining lines
#######################################
drop_ignored_prefix() {
  # substr, not index: macOS awk's index($0, "") is 1, which would drop every line under an empty prefix.
  awk -v prefix="${IGNORED_PREFIX}" 'prefix == "" || substr($0, 1, length(prefix)) != prefix'
}

#######################################
# Lines on stdin as a JSON array of strings; empty input is [] and exits 0.
# Outputs: the JSON array
#######################################
lines_to_json_array() {
  jq -Rsc 'split("\n") | map(select(. != ""))'
}

#######################################
# Whether a path starts with one of the shared prefixes.
# Arguments:
#   $1 - path
#   $2.. - prefixes
# Returns: 0 when shared
#######################################
is_shared_path() {
  local file="${1}"; shift
  for prefix in "${@}"; do
    [[ "${file}" == "${prefix}"* ]] && return 0
  done
  return 1
}

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local root="" base="${DEFAULT_BASE}" ignored="${DEFAULT_IGNORED_PREFIX}"
  local -a lane_specs running shared
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --root)     root="${2:?--root requires a value}"; shift 2 ;;
    --lane)     lane_specs+=("${2:?--lane requires ID=DIR}"); shift 2 ;;
    --running)  running+=("${2:?--running requires an id}"); shift 2 ;;
    --base)     base="${2:?--base requires a ref}"; shift 2 ;;
    --shared)   shared+=("${2:?--shared requires a prefix}"); shift 2 ;;
    --ignore)   ignored="${2:?--ignore requires a prefix}"; shift 2 ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  (( ${#shared} > 0 )) || shared=("${DEFAULT_SHARED[@]}")
  typeset -g IGNORED_PREFIX="${ignored}"
  # Unquoted subscripts throughout: zsh keeps quotes as part of an associative key, so a["A"] and a[${id}] differ.
  local -A lane_dir
  for spec in "${lane_specs[@]}"; do
    lane_dir[${spec%%=*}]="${spec#*=}"
  done
  local -a ids
  ids=("${(@ko)lane_dir}")

  # === VALIDATE ===
  [[ -n "${root}" ]] || { log::err "Missing --root | expected='the main checkout'"; help; return 1; }
  [[ -d "${root}/.git" || -f "${root}/.git" ]] || { log::err "Not a git checkout | root='${root}'"; return 1; }
  (( ${#ids} > 0 )) || { log::err "Missing --lane | expected='at least one ID=WORKTREE|BRANCH'"; help; return 1; }
  lvl=DEBUG run_cmd git -C "${root}" fetch -q origin || log::warn "Fetch failed; measuring against the local refs | base='${base}'"
  for id in "${ids[@]}"; do
    local source="${lane_dir[${id}]}"
    [[ -d "${source}" ]] && continue
    git -C "${root}" show-ref --verify --quiet "refs/remotes/origin/${source}" \
      || { log::err "Lane source is neither a worktree nor a remote branch | id='${id}' source='${source}' expected='a directory or origin/<branch>'"; return 1; }
  done
  for id in "${running[@]}"; do
    [[ -n "${lane_dir[${id}]:-}" ]] || { log::err "Running lane not given as --lane | id='${id}' lanes='${(j:, :)ids}'"; return 1; }
  done

  # === LOGIC ===

  local -A files_of
  for id in "${ids[@]}"; do
    files_of[${id}]="$(lane_files "${root}" "${lane_dir[${id}]}" "${base}")"
    log::info "Lane measured | id='${id}' files='$(print -l "${files_of[${id}]}" | grep -c . || true)'"
  done

  local lanes_json="[]" overlaps_json="[]"
  for id in "${ids[@]}"; do
    local -a owned shared_hits
    owned=("${(@f)files_of[${id}]}")
    shared_hits=()
    for file in "${owned[@]}"; do
      [[ -n "${file}" ]] && is_shared_path "${file}" "${shared[@]}" && shared_hits+=("${file}")
    done
    lanes_json="$(jq -cn --argjson lanes "${lanes_json}" --arg id "${id}" --arg dir "${lane_dir[${id}]}" \
      --argjson owned "$(print -l "${owned[@]}" | lines_to_json_array)" \
      --argjson shared "$(print -l "${shared_hits[@]}" | lines_to_json_array)" \
      '$lanes + [{id: $id, source: $dir, files_owned: $owned, shared_files: $shared}]')"
  done

  local -A blocked
  local i j a b common   # declared once: a re-`local` inside the loop prints "common=…" to stdout in zsh
  for (( i = 1; i <= ${#ids}; i++ )); do
    for (( j = i + 1; j <= ${#ids}; j++ )); do
      a="${ids[i]}"; b="${ids[j]}"
      common="$(comm -12 <(print -l "${files_of[${a}]}") <(print -l "${files_of[${b}]}") | grep . || true)"
      [[ -z "${common}" ]] && continue
      overlaps_json="$(jq -cn --argjson all "${overlaps_json}" --arg a "${a}" --arg b "${b}" \
        --argjson files "$(print -l "${common}" | lines_to_json_array)" \
        '$all + [{a: $a, b: $b, files: $files}]')"
      for r in "${running[@]}"; do
        [[ "${r}" == "${a}" ]] && blocked[${b}]=1
        [[ "${r}" == "${b}" ]] && blocked[${a}]=1
      done
      log::info "Overlap | a='${a}' b='${b}' files='$(print -l "${common}" | grep -c . || true)'"
    done
  done

  local -a ready
  for id in "${ids[@]}"; do
    [[ -n "${blocked[${id}]:-}" ]] && continue
    for r in "${running[@]}"; do [[ "${r}" == "${id}" ]] && continue 2; done
    ready+=("${id}")
  done
  log::info "Ready set | ready='${(j:, :)ready}' running='${(j:, :)running}'"

  echo "=== start RESULT ==="
  jq -cn --argjson lanes "${lanes_json}" --argjson overlaps "${overlaps_json}" \
    --argjson ready "$(print -l "${ready[@]}" | lines_to_json_array)" \
    '{lanes: $lanes, overlaps: $overlaps, ready: $ready}'
  echo "=== end RESULT ==="
}

main "$@"
