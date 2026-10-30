#!/usr/bin/env zsh
# One PR's life: wait for it, follow CI per head with the read account, merge on the gate job's green
# with the write account, verify MERGED, delete the remote branch, watch the base branch's run and,
# when --url is given, curl the live page.
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
readonly DEFAULT_WORKFLOW="CI"
readonly DEFAULT_INTERVAL=60
readonly DEFAULT_PR_WAIT_MIN=120
# A chain's top PR lands as a merge commit so each lane's commits survive; a lone lane passes --merge-method squash.
readonly DEFAULT_MERGE_METHOD="merge"
readonly VALID_MERGE_METHODS=(squash merge rebase)
readonly HEAD_ATTEMPTS=12
readonly RUN_LOOKUPS=12
# How many --interval polls a red run waits for a push or a rerun before the watcher ends as unattended (30 at 60 s is 30 min).
readonly RED_WAIT_POLLS=30
readonly HEARTBEAT_EVERY=5
readonly RATE_LIMIT_SLEEP=300
readonly CURL_MAX_TIME=20

help() {
  cat <<EOF
${c_green}watch-merge${c_rst} — follow one branch's PR through CI, merge it on green, watch the base branch and, optionally, the live site

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-parallel-play/bin/watch-merge.zsh --branch BRANCH --read-user USER [--write-user USER] [--url URL] [--bundle-regex RE] [--repo OWNER/NAME] [--base BRANCH] [--workflow NAME] [--gate JOB] [--interval SEC] [--merge-method M] [--keep-branch] [--dry-run]

${c_bold}Options:${c_rst}
  --branch BRANCH     The PR's head branch
  --read-user USER    gh account for every read
  --write-user USER   gh account for the merge, its verification and the branch delete (default: the read account)
  --url URL           The live page to curl after the base deploys; omit to skip the live check
  --bundle-regex RE   An awk regex (ERE) whose first match in the live page proves the new build is up, e.g. 'main\.[0-9a-f]{8}\.js' (needs --url; default: none)
  --repo OWNER/NAME   The repository (default: the gh default of the current directory)
  --base BRANCH       The PR's base (default: ${DEFAULT_BASE}); the base run and the live check run only for that default
  --workflow NAME     The CI workflow name as gh run list sees it (default: ${DEFAULT_WORKFLOW})
  --gate JOB          The CI job whose success merges (default: ${DEFAULT_GATE})
  --interval SEC      Every poll's interval: CI, run lookups, the red wait (default: ${DEFAULT_INTERVAL}; never lower than 60 with many watchers)
  --merge-method M    ${(j:|:)VALID_MERGE_METHODS} (default: ${DEFAULT_MERGE_METHOD})
  --keep-branch       Do not delete the remote branch after the merge
  --dry-run           Log the merge instead of running it
  -h, --help          Show this help

The head's newest run is resolved again on every poll, so a "gh run rerun" is seen. A red run waits ${RED_WAIT_POLLS} polls
for a push or a rerun, with a heartbeat naming the unblock commands, then the watcher ends as "Red and unattended".
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
# A branch's head sha, or nothing when the ref cannot be read.
# Globals: READ_TOKEN REPO
# Arguments:
#   $1 - branch
#######################################
head_sha() {
  gh_as "${READ_TOKEN}" api "repos/${REPO}/git/ref/heads/${1}" --jq .object.sha 2>/dev/null || true
}

#######################################
# One look at the newest CI run for a commit: "id status conclusion", e.g. "123 completed success",
# "123 in_progress " (a rerun in flight has no conclusion yet), or nothing when no run exists yet or
# the API did not answer.
# Globals: READ_TOKEN REPO WORKFLOW
# Arguments:
#   $1 - sha
#######################################
run_line_for_sha() {
  gh_as "${READ_TOKEN}" run list --repo "${REPO}" --workflow "${WORKFLOW}" --commit "${1}" --limit 1 \
    --json databaseId,status,conclusion --jq '.[0] | select(. != null) | "\(.databaseId) \(.status) \(.conclusion)"' 2>/dev/null || true
}

#######################################
# The newest CI run for a head sha, polling at the interval until one exists.
# Globals: READ_TOKEN REPO WORKFLOW INTERVAL RUN_LOOKUPS
# Arguments:
#   $1 - sha
# Outputs: the run line (see run_line_for_sha), or nothing after RUN_LOOKUPS looks
#######################################
latest_run_for_sha() {
  local sha="${1}" line=""
  for (( i = 1; i <= RUN_LOOKUPS; i++ )); do
    line="$(run_line_for_sha "${sha}")"
    [[ -n "${line}" ]] && { echo "${line}"; return 0; }
    sleep "${INTERVAL}"
  done
}

#######################################
# After a red run: wait for a new head on the branch or for the run line to change (a rerun puts the
# run back in progress; a later look shows another conclusion). Checks before the first sleep, polls
# at the interval, and every HEARTBEAT_EVERY polls logs the commands that unblock it.
# Globals: READ_TOKEN REPO WORKFLOW INTERVAL RED_WAIT_POLLS HEARTBEAT_EVERY
# Arguments:
#   $1 - branch; $2 - the red head sha; $3 - the red run line, from the run view in hand ("id completed conclusion")
# Returns: 0 when something changed; 1 when RED_WAIT_POLLS passed with no push and no rerun
#######################################
wait_for_push_or_rerun() {
  local branch="${1}" sha="${2}" red_line="${3}" rid="${3%% *}" now_sha="" now_line=""
  for (( i = 1; i <= RED_WAIT_POLLS; i++ )); do
    now_sha="$(head_sha "${branch}")"
    if [[ -n "${now_sha}" && "${now_sha}" != "${sha}" ]]; then
      log::info "New head after a red run | sha='${now_sha}'"
      return 0
    fi
    now_line="$(run_line_for_sha "${sha}")"
    if [[ -n "${now_line}" && "${now_line}" != "${red_line}" ]]; then
      log::info "Run changed after a red (a rerun or a new run) | was='${red_line}' now='${now_line}'"
      return 0
    fi
    if (( i % HEARTBEAT_EVERY == 0 )); then
      log::info "Still red | run='${rid}' sha='${sha}' poll='${i}/${RED_WAIT_POLLS}' unblock='gh run rerun ${rid} --failed (a flake), or push a fix to ${branch}'"
    fi
    sleep "${INTERVAL}"
  done
  log::warn "Still red, no push and no rerun | run='${rid}' sha='${sha}' polls='${RED_WAIT_POLLS}'"
  return 1
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
# Curl the live page once the base has deployed; skipped when no --url was given.
# Globals: URL BUNDLE_REGEX LIVE_STATUS LIVE_BUNDLE
#######################################
check_live() {
  if [[ -z "${URL}" ]]; then
    log::info "No live URL; skipping the live check"
    return 0
  fi
  sleep 45
  LIVE_STATUS="$(curl -s --max-time "${CURL_MAX_TIME}" -o /dev/null -w '%{http_code}' "${URL}?nocache=$(date +%s)" || echo "000")"
  if [[ -n "${BUNDLE_REGEX}" ]]; then
    # The shellscripts rule: no grep mid-pipe, no early-exiting consumer under pipefail; awk latches the first match
    # and reads to EOF. The regex goes through ENVIRON, since -v strips backslashes; LC_ALL=C, since macOS awk exits 2
    # on invalid UTF-8. `|| true` covers only a failed curl.
    LIVE_BUNDLE="$(curl -s --max-time "${CURL_MAX_TIME}" "${URL}?nocache=$(date +%s)" \
      | BUNDLE_REGEX="${BUNDLE_REGEX}" LC_ALL=C awk '!found && match($0, ENVIRON["BUNDLE_REGEX"]) { print substr($0, RSTART, RLENGTH); found = 1 }' || true)"
  fi
  log::info "Live | url='${URL}' status='${LIVE_STATUS}' bundle='${LIVE_BUNDLE}'"
}

#######################################
# Follow the base branch's run for the merge, then the live check.
# Globals: READ_TOKEN REPO INTERVAL MAIN_RUN MAIN_EXIT
# Arguments:
#   $1 - base branch
#######################################
watch_main_and_live() {
  local base="${1}" sha="" mid="" exit_code=0
  sleep 20
  sha="$(head_sha "${base}")"
  mid="$(latest_run_for_sha "${sha}")"; mid="${mid%% *}"
  if [[ -z "${mid}" ]]; then
    log::warn "No run found for the base head | base='${base}' sha='${sha}'"
    MAIN_RUN=""; MAIN_EXIT="none"
  else
    log::info "Base run | base='${base}' run='${mid}'"
    gh_as "${READ_TOKEN}" run watch "${mid}" --repo "${REPO}" --interval "${INTERVAL}" --exit-status >/dev/null 2>&1 || exit_code=$?
    MAIN_RUN="${mid}"; MAIN_EXIT="${exit_code}"
    log::info "Base run finished | run='${mid}' exit='${exit_code}'"
  fi
  check_live
}

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local branch="" url="" bundle_regex="" read_user="" write_user="" repo="" base="${DEFAULT_BASE}" gate="${DEFAULT_GATE}" workflow="${DEFAULT_WORKFLOW}"
  local interval="${DEFAULT_INTERVAL}" merge_method="${DEFAULT_MERGE_METHOD}" keep_branch=false dry_run=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)       help; return 0 ;;
    --branch)        branch="${2:?--branch requires a value}"; shift 2 ;;
    --url)           url="${2:?--url requires a value}"; shift 2 ;;
    --bundle-regex)  bundle_regex="${2:?--bundle-regex requires a pattern}"; shift 2 ;;
    --workflow)      workflow="${2:?--workflow requires a name}"; shift 2 ;;
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
  [[ -n "${write_user}" ]] || write_user="${read_user}"
  unset GITHUB_TOKEN
  [[ -n "${repo}" ]] || repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)"

  # === VALIDATE ===
  [[ -n "${branch}" ]] || { log::err "Missing --branch"; help; return 1; }
  [[ -n "${read_user}" ]] || { log::err "Missing --read-user"; help; return 1; }
  [[ -z "${bundle_regex}" || -n "${url}" ]] || { log::err "--bundle-regex needs --url | bundle_regex='${bundle_regex}'"; help; return 1; }
  [[ -n "${repo}" ]] || { log::err "No repository | expected='--repo OWNER/NAME or a gh default in the current directory'"; return 1; }
  is_valid_option "${merge_method}" "${VALID_MERGE_METHODS[@]}" || { log::err "Invalid --merge-method | merge_method='${merge_method}' valid='${(j:, :)VALID_MERGE_METHODS}'"; return 1; }
  (( interval >= 60 )) || { log::err "Interval too low | interval='${interval}' minimum='60'"; return 1; }

  typeset -g READ_TOKEN WRITE_TOKEN REPO URL BUNDLE_REGEX WORKFLOW DRY_RUN MERGE_METHOD KEEP_BRANCH INTERVAL
  READ_TOKEN="$(gh auth token --user "${read_user}")" || { log::err "No token for the read user | read_user='${read_user}'"; return 1; }
  WRITE_TOKEN="$(gh auth token --user "${write_user}")" || { log::err "No token for the write user | write_user='${write_user}'"; return 1; }
  REPO="${repo}"; URL="${url}"; BUNDLE_REGEX="${bundle_regex}"; WORKFLOW="${workflow}"; DRY_RUN="${dry_run}"; MERGE_METHOD="${merge_method}"; KEEP_BRANCH="${keep_branch}"; INTERVAL="${interval}"

  # === LOGIC ===
  log::info "Waiting for the PR | branch='${branch}' repo='${REPO}' minutes='${DEFAULT_PR_WAIT_MIN}'"
  local pr
  pr="$(wait_for_pr "${branch}" "${DEFAULT_PR_WAIT_MIN}")" || { log::err "No PR appeared | branch='${branch}' minutes='${DEFAULT_PR_WAIT_MIN}'"; return 1; }
  log::info "PR found | pr='${pr}' branch='${branch}'"

  local merged=false sha="" run_line="" rid="" view="" conclusion="" jobs="" exit_code=0
  for (( attempt = 1; attempt <= HEAD_ATTEMPTS; attempt++ )); do
    if [[ "$(pr_state "${pr}")" == "MERGED" ]]; then log::info "Already merged | pr='${pr}'"; merged=true; break; fi
    sha="$(head_sha "${branch}")"
    log::info "Head | sha='${sha}' attempt='${attempt}'"
    run_line="$(latest_run_for_sha "${sha}")"
    if [[ -z "${run_line}" ]]; then log::warn "No run for the head (a conflicting PR gets none) | sha='${sha}'"; sleep "${INTERVAL}"; continue; fi
    rid="${run_line%% *}"
    log::info "CI run | run='${rid}' status='${${run_line#* }%% *}' conclusion='${run_line##* }'"
    exit_code=0
    gh_as "${READ_TOKEN}" run watch "${rid}" --repo "${REPO}" --interval "${INTERVAL}" --exit-status >/dev/null 2>&1 || exit_code=$?
    # One view: the run's conclusion, then its jobs as "name:conclusion", separated by a tab.
    view="$(gh_as "${READ_TOKEN}" run view "${rid}" --repo "${REPO}" --json jobs,conclusion \
      --jq '"\(.conclusion)\t" + ([.jobs[] | "\(.name):\(.conclusion)"] | join(" "))' 2>/dev/null || true)"
    conclusion="${view%%	*}"; jobs="${view#*	}"
    log::info "Run finished | run='${rid}' exit='${exit_code}' conclusion='${conclusion}' jobs='${jobs}'"
    if [[ -z "${jobs}" ]]; then log::warn "Empty job list, a rate limit not a red run | retry_in='${RATE_LIMIT_SLEEP}s'"; sleep "${RATE_LIMIT_SLEEP}"; continue; fi
    if ! run_is_green "${jobs}" "${gate}"; then
      log::info "Red; waiting for a new push or a rerun | run='${rid}'"
      if ! wait_for_push_or_rerun "${branch}" "${sha}" "${rid} completed ${conclusion}"; then
        log::err "Red and unattended | pr='${pr}' run='${rid}' sha='${sha}' next='gh run rerun ${rid} --failed, or push a fix, then start the watcher again'"
        return 1
      fi
      continue
    fi
    if merge_pr "${pr}"; then merged=true; break; fi
    sleep 120
  done

  if [[ "${merged}" != "true" ]]; then
    log::err "Not merged within the attempts | pr='${pr}' attempts='${HEAD_ATTEMPTS}'"
    return 1
  fi
  delete_branch "${branch}"

  typeset -g MAIN_RUN="" MAIN_EXIT="skipped" LIVE_STATUS="" LIVE_BUNDLE=""
  if [[ "${base}" == "${DEFAULT_BASE}" && "${DRY_RUN}" != "true" ]]; then
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
