#!/usr/bin/env zsh
# One PR's life: wait for it, follow CI per head with the read user, merge on the gate job's green
# with the write user, verify MERGED, delete the remote branch, watch main's run, curl the live URL.
# Run: zsh $HOME/.claude/skills/ari-parallel-play/bin/watch-merge.zsh --help

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

readonly DEFAULT_BASE="main"
readonly DEFAULT_GATE="ci-ok"
readonly DEFAULT_INTERVAL=60
readonly DEFAULT_PR_WAIT_MIN=120
# A chain's top PR lands as a merge commit so each lane's commits survive; a lone lane passes --merge-method squash.
readonly DEFAULT_MERGE_METHOD="merge"
readonly DEFAULT_BUNDLE_REGEX='app-[A-Za-z0-9_-]*\.js'
readonly VALID_MERGE_METHODS=(squash merge rebase)
readonly HEAD_ATTEMPTS=12
readonly RUN_LOOKUPS=12
readonly RATE_LIMIT_SLEEP=300
readonly CURL_MAX_TIME=20

help() {
  cat <<EOF
${c_green}watch-merge${c_rst} — follow one branch's PR through CI, merge it on green, check main and the live site

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-parallel-play/bin/watch-merge.zsh --branch BRANCH --url URL --read-user USER --write-user USER [--repo OWNER/NAME] [--base BRANCH] [--gate JOB] [--interval SEC] [--merge-method M] [--keep-branch] [--dry-run]

${c_bold}Options:${c_rst}
  --branch BRANCH     The PR's head branch
  --url URL           The live page to curl after main deploys
  --read-user USER    gh account for every read (the repo is public; spares the write account's rate limit)
  --write-user USER   gh account for the merge, its verification and the branch delete
  --repo OWNER/NAME   The repository (default: the gh default of the current directory)
  --base BRANCH       The PR's base (default: ${DEFAULT_BASE}); main's run and the live check run only for a main base
  --gate JOB          The CI job whose success merges (default: ${DEFAULT_GATE})
  --interval SEC      CI polling interval (default: ${DEFAULT_INTERVAL}; never lower than 60 with many watchers)
  --merge-method M    ${(j:|:)VALID_MERGE_METHODS} (default: ${DEFAULT_MERGE_METHOD})
  --keep-branch       Do not delete the remote branch after the merge
  --dry-run           Log the merge instead of running it
  -h, --help          Show this help

Logs go to stderr; run with "> watch-<branch>.log 2>&1 &" and tail the file. Never use --auto merges.
EOF
}

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local missing=()
  for cmd in gh jq curl; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

#######################################
# Check if a value is in an array of valid options.
# Arguments:
#   $1 - value; $2.. - options
# Returns: 0 if valid
#######################################
is_valid_option() {
  local val="${1}"; shift
  for opt in "${@}"; do
    [[ "${val}" == "${opt}" ]] && return 0
  done
  return 1
}

#######################################
# gh with one account's token.
# Arguments:
#   $1 - token; $2.. - gh arguments
#######################################
gh_as() {
  local token="${1}"; shift
  GH_TOKEN="${token}" gh "${@}"
}

#######################################
# Wait for an open PR from the branch.
# Globals: READ_TOKEN REPO
# Arguments:
#   $1 - branch; $2 - minutes to wait
# Outputs: the PR number
# Returns: 1 when none appears
#######################################
wait_for_pr() {
  local branch="${1}" minutes="${2}" pr=""
  for (( i = 1; i <= minutes; i++ )); do
    pr="$(gh_as "${READ_TOKEN}" pr list --repo "${REPO}" --head "${branch}" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)"
    [[ -n "${pr}" ]] && { echo "${pr}"; return 0; }
    sleep 60
  done
  return 1
}

#######################################
# The PR's state with the write account (the one that merges).
# Arguments:
#   $1 - pr number
#######################################
pr_state() {
  gh_as "${WRITE_TOKEN}" pr view "${1}" --repo "${REPO}" --json state --jq .state
}

#######################################
# The CI run id for a head sha, polling until it exists.
# Arguments:
#   $1 - branch; $2 - sha
# Outputs: the run id, or nothing
#######################################
run_for_sha() {
  local branch="${1}" sha="${2}" rid=""
  for (( i = 1; i <= RUN_LOOKUPS; i++ )); do
    rid="$(gh_as "${READ_TOKEN}" run list --repo "${REPO}" --workflow CI --branch "${branch}" --limit 8 --json databaseId,headSha --jq ".[] | select(.headSha==\"${sha}\") | .databaseId" 2>/dev/null | head -1 || true)"
    [[ -n "${rid}" ]] && { echo "${rid}"; return 0; }
    sleep 30
  done
}

#######################################
# Decide whether a finished run is green: the gate job succeeded.
# Arguments:
#   $1 - "name:conclusion ..." job list; $2 - gate job name
# Returns: 0 when green
#######################################
run_is_green() {
  local jobs="${1}" gate="${2}"
  if [[ "${jobs}" == *"${gate}:success"* ]]; then
    log::info "Gate green | gate='${gate}'"
    return 0
  fi
  log::info "Gate not green | gate='${gate}'"
  return 1
}

#######################################
# Merge the PR (or log it under --dry-run) and verify the state.
# Globals: WRITE_TOKEN REPO DRY_RUN MERGE_METHOD
# Arguments:
#   $1 - pr number
# Returns: 0 when MERGED afterwards
#######################################
merge_pr() {
  local pr="${1}" out=""
  if [[ "${DRY_RUN}" == "true" ]]; then
    log::info "Dry run: would merge | pr='${pr}' method='${MERGE_METHOD}'"
    return 0
  fi
  out="$(gh_as "${WRITE_TOKEN}" pr merge "${pr}" --repo "${REPO}" "--${MERGE_METHOD}" 2>&1 | tail -1 || true)"
  if [[ "$(pr_state "${pr}")" == "MERGED" ]]; then
    log::info "Merged | pr='${pr}'"
    return 0
  fi
  log::warn "Merge refused | pr='${pr}' output='${out}' mergeable='$(gh_as "${READ_TOKEN}" pr view "${pr}" --repo "${REPO}" --json mergeable --jq .mergeable 2>/dev/null || true)'"
  return 1
}

#######################################
# Delete the remote branch, only after a verified merge.
# Globals: WRITE_TOKEN REPO KEEP_BRANCH DRY_RUN
# Arguments:
#   $1 - branch
#######################################
delete_branch() {
  local branch="${1}"
  if [[ "${KEEP_BRANCH}" == "true" || "${DRY_RUN}" == "true" ]]; then
    log::info "Keeping remote branch | branch='${branch}' keep='${KEEP_BRANCH}' dry_run='${DRY_RUN}'"
    return 0
  fi
  gh_as "${WRITE_TOKEN}" api -X DELETE "repos/${REPO}/git/refs/heads/${branch}" >/dev/null 2>&1 \
    && log::info "Remote branch deleted | branch='${branch}'" \
    || log::warn "Remote branch not deleted | branch='${branch}'"
}

#######################################
# Follow main's run for the merge and curl the live page.
# Globals: READ_TOKEN REPO URL BUNDLE_REGEX
# Arguments:
#   $1 - base branch
# Outputs: main_run, main_exit, live_status, live_bundle on stdout via the caller's heredoc variables
#######################################
watch_main_and_live() {
  local base="${1}" sha="" mid="" exit_code=0
  sleep 20
  sha="$(gh_as "${READ_TOKEN}" api "repos/${REPO}/git/ref/heads/${base}" --jq .object.sha 2>/dev/null || true)"
  mid="$(run_for_sha "${base}" "${sha}")"
  if [[ -z "${mid}" ]]; then
    log::warn "No run found for the base head | base='${base}' sha='${sha}'"
    MAIN_RUN=""; MAIN_EXIT="none"
  else
    log::info "Base run | base='${base}' run='${mid}'"
    gh_as "${READ_TOKEN}" run watch "${mid}" --repo "${REPO}" --interval "${INTERVAL}" --exit-status >/dev/null 2>&1 || exit_code=$?
    MAIN_RUN="${mid}"; MAIN_EXIT="${exit_code}"
    log::info "Base run finished | run='${mid}' exit='${exit_code}'"
  fi
  sleep 45
  LIVE_STATUS="$(curl -s --max-time "${CURL_MAX_TIME}" -o /dev/null -w '%{http_code}' "${URL}?nocache=$(date +%s)" || echo "000")"
  LIVE_BUNDLE="$(curl -s --max-time "${CURL_MAX_TIME}" "${URL}?nocache=$(date +%s)" | grep -o "${BUNDLE_REGEX}" | head -1 || true)"
  log::info "Live | url='${URL}' status='${LIVE_STATUS}' bundle='${LIVE_BUNDLE}'"
}

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local branch="" url="" read_user="" write_user="" repo="" base="${DEFAULT_BASE}" gate="${DEFAULT_GATE}"
  local interval="${DEFAULT_INTERVAL}" merge_method="${DEFAULT_MERGE_METHOD}" keep_branch=false dry_run=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)       help; return 0 ;;
    --branch)        branch="${2:?--branch requires a value}"; shift 2 ;;
    --url)           url="${2:?--url requires a value}"; shift 2 ;;
    --read-user)     read_user="${2:?--read-user requires a value}"; shift 2 ;;
    --write-user)    write_user="${2:?--write-user requires a value}"; shift 2 ;;
    --repo)          repo="${2:?--repo requires OWNER/NAME}"; shift 2 ;;
    --base)          base="${2:?--base requires a branch}"; shift 2 ;;
    --gate)          gate="${2:?--gate requires a job name}"; shift 2 ;;
    --interval)      interval="${2:?--interval requires seconds}"; shift 2 ;;
    --merge-method)  merge_method="${2:?--merge-method requires a value}"; shift 2 ;;
    --keep-branch)   keep_branch=true; shift ;;
    --dry-run)       dry_run=true; shift ;;
    -*)              log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)               log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  merge_method="${merge_method:l}"
  unset GITHUB_TOKEN
  [[ -n "${repo}" ]] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"

  # === VALIDATE ===
  [[ -n "${branch}" ]] || { log::err "Missing --branch"; help; return 1; }
  [[ -n "${url}" ]] || { log::err "Missing --url"; help; return 1; }
  [[ -n "${read_user}" && -n "${write_user}" ]] || { log::err "Missing --read-user or --write-user | read_user='${read_user}' write_user='${write_user}'"; help; return 1; }
  [[ -n "${repo}" ]] || { log::err "No repository | expected='--repo OWNER/NAME or a gh default in the current directory'"; return 1; }
  is_valid_option "${merge_method}" "${VALID_MERGE_METHODS[@]}" || { log::err "Invalid --merge-method | merge_method='${merge_method}' valid='${(j:, :)VALID_MERGE_METHODS}'"; return 1; }
  (( interval >= 60 )) || { log::err "Interval too low | interval='${interval}' minimum='60'"; return 1; }

  typeset -g READ_TOKEN WRITE_TOKEN REPO URL BUNDLE_REGEX DRY_RUN MERGE_METHOD KEEP_BRANCH INTERVAL
  READ_TOKEN="$(gh auth token --user "${read_user}")" || { log::err "No token for the read user | read_user='${read_user}'"; return 1; }
  WRITE_TOKEN="$(gh auth token --user "${write_user}")" || { log::err "No token for the write user | write_user='${write_user}'"; return 1; }
  REPO="${repo}"; URL="${url}"; BUNDLE_REGEX="${DEFAULT_BUNDLE_REGEX}"; DRY_RUN="${dry_run}"; MERGE_METHOD="${merge_method}"; KEEP_BRANCH="${keep_branch}"; INTERVAL="${interval}"

  # === LOGIC ===
  log::info "Waiting for the PR | branch='${branch}' repo='${REPO}' minutes='${DEFAULT_PR_WAIT_MIN}'"
  local pr
  pr="$(wait_for_pr "${branch}" "${DEFAULT_PR_WAIT_MIN}")" || { log::err "No PR appeared | branch='${branch}' minutes='${DEFAULT_PR_WAIT_MIN}'"; return 1; }
  log::info "PR found | pr='${pr}' branch='${branch}'"

  local merged=false sha="" rid="" jobs="" exit_code=0
  for (( attempt = 1; attempt <= HEAD_ATTEMPTS; attempt++ )); do
    if [[ "$(pr_state "${pr}")" == "MERGED" ]]; then log::info "Already merged | pr='${pr}'"; merged=true; break; fi
    sha="$(gh_as "${READ_TOKEN}" api "repos/${REPO}/git/ref/heads/${branch}" --jq .object.sha 2>/dev/null || true)"
    log::info "Head | sha='${sha}' attempt='${attempt}'"
    rid="$(run_for_sha "${branch}" "${sha}")"
    if [[ -z "${rid}" ]]; then log::warn "No run for the head (a conflicting PR gets none) | sha='${sha}'"; sleep 60; continue; fi
    log::info "CI run | run='${rid}'"
    exit_code=0
    gh_as "${READ_TOKEN}" run watch "${rid}" --repo "${REPO}" --interval "${INTERVAL}" --exit-status >/dev/null 2>&1 || exit_code=$?
    jobs="$(gh_as "${READ_TOKEN}" run view "${rid}" --repo "${REPO}" --json jobs --jq '.jobs[] | "\(.name):\(.conclusion)"' 2>/dev/null | tr '\n' ' ' || true)"
    log::info "Run finished | run='${rid}' exit='${exit_code}' jobs='${jobs}'"
    if [[ -z "${jobs}" ]]; then log::warn "Empty job list, a rate limit not a red run | retry_in='${RATE_LIMIT_SLEEP}s'"; sleep "${RATE_LIMIT_SLEEP}"; continue; fi
    if ! run_is_green "${jobs}" "${gate}"; then log::info "Red; waiting for a new push"; sleep 90; continue; fi
    if merge_pr "${pr}"; then merged=true; break; fi
    sleep 120
  done

  if [[ "${merged}" != "true" ]]; then
    log::err "Not merged within the attempts | pr='${pr}' attempts='${HEAD_ATTEMPTS}'"
    return 1
  fi
  delete_branch "${branch}"

  typeset -g MAIN_RUN="" MAIN_EXIT="skipped" LIVE_STATUS="" LIVE_BUNDLE=""
  if [[ "${base}" == "main" && "${DRY_RUN}" != "true" ]]; then
    watch_main_and_live "${base}"
  else
    log::info "Skipping the base run and live check | base='${base}' dry_run='${DRY_RUN}'"
  fi

  cat <<EOF
pr=${pr}
branch=${branch}
merged=${merged}
main_run=${MAIN_RUN}
main_exit=${MAIN_EXIT}
live_status=${LIVE_STATUS}
live_bundle=${LIVE_BUNDLE}
EOF
}

main "$@"
