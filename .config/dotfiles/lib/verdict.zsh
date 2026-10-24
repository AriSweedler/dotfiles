# dotfiles/lib/verdict.zsh — what a check says. One JSON line on stdout:
#   {step,status,reason,detail,fix,manual,actionable,items}
# status: ok | warn | fail | error | skip. The rule: fail = the baseline is unmet and something
# could move it; error = the check could not tell (a busy brew, a timeout, a crash, a tool the
# check itself needs). manual = a human must act, so it is never auto-applied.

# verdict <status> <reason> [-d DETAIL] [-f FIX] [-m] [-a] [-i ITEMS_JSON_FILE]
#   -m  manual; -a  actionable even when the status is warn
#   actionable defaults to: status==fail && !manual && apply::${STEP} is defined
# `status` is zsh's readonly alias of $?, hence verdict_status.
verdict() {
  local verdict_status="${1}" reason="${2}"; shift 2
  local detail="" fix="" manual=false actionable="" items='[]'
  while (( $# )); do
    case "${1}" in
      -d) detail="${2}"; shift 2 ;;  -f) fix="${2}"; shift 2 ;;  -m) manual=true; shift ;;
      -a) actionable=true; shift ;;  -i) items="$(<"${2}")"; shift 2 ;;
      *) print -u2 "verdict: bad flag ${1}"; return 64 ;;
    esac
  done
  local has_apply=false; (( ${+functions[apply::${STEP}]} )) && has_apply=true
  [[ "${has_apply}" == false ]] && actionable=false
  if [[ -z "${actionable}" ]]; then
    actionable=false; [[ "${verdict_status}" == fail && "${manual}" == false ]] && actionable=true
  fi
  jq -cn --arg step "${STEP}" --arg status "${verdict_status}" --arg reason "${reason}" --arg detail "${detail}" \
         --arg fix "${fix}" --argjson manual "${manual}" --argjson actionable "${actionable}" --argjson items "${items}" \
    '{step:$step,status:$status,reason:$reason,detail:$detail,fix:(if $fix=="" then null else $fix end),
      manual:$manual,actionable:$actionable,items:$items}'
}

# A verdict the runner writes on a step's behalf when its check could not run.
verdict::synth() {
  local name="${1}" verdict_status="${2}" reason="${3}" detail="${4:-}"
  jq -cn --arg step "${name}" --arg status "${verdict_status}" --arg reason "${reason}" --arg detail "${detail}" \
    '{step:$step,status:$status,reason:$reason,detail:$detail,fix:null,manual:false,actionable:false,items:[]}'
}

# The process exit code a run's roll-up status maps to: 0 ok|warn|skip, 1 fail, 2 error.
verdict::exit_code() {
  case "${1}" in
    ok|warn|skip) return 0 ;;
    fail) return 1 ;;
    *) return 2 ;;
  esac
}
