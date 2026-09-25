# step karabiner — the config invariant (exists, valid, `jq -S .` equals itself: the df
# pre-commit rule) is the verdict. The healthcheck's process/device/IPC findings are runtime
# state, not baseline, so its exit 1 is a warn and never a fail.
step::declare karabiner --group tools \
  --desc "karabiner.json exists, is valid JSON, and is jq -S sorted; healthcheck runs when present"

check::karabiner() {
  local cfg="${HOME}/.config/karabiner/karabiner.json"
  local problem=""
  if [[ ! -f "${cfg}" ]]; then
    problem="karabiner.json missing"
  elif ! jq -e . "${cfg}" >/dev/null 2>&1; then
    problem="karabiner.json is not valid JSON"
  elif ! jq -S . "${cfg}" | cmp -s - "${cfg}"; then
    problem="karabiner.json is not jq -S sorted"
  fi
  if [[ -n "${problem}" ]]; then
    if ! command -v npm >/dev/null 2>&1; then
      verdict skip no_npm -d "${problem}; the bake needs npm | file='${cfg}'"
      return 0
    fi
    verdict fail karabiner_config -d "${problem} | file='${cfg}'" -f "${CLI_NAME} apply karabiner"
    return 0
  fi
  local healthcheck="${HOME}/.config/karabiner/bin/healthcheck"
  local healthcheck_lib="${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
  if [[ ! -x "${healthcheck}" ]]; then
    verdict ok config_valid -d "file='${cfg}' healthcheck='absent'"
    return 0
  fi
  if [[ ! -r "${healthcheck_lib}" ]]; then
    # Without its logging lib the healthcheck exits 1 before checking anything; not a config problem.
    verdict ok config_valid -d "file='${cfg}' healthcheck='unusable (logging lib missing)'"
    return 0
  fi
  local out rc=0
  out="$("${healthcheck}")" || rc=$?
  local -a summary=(${(M)${(f)out}:#(status|issues)=*})
  case "${rc}" in
    0) verdict ok config_valid -d "file='${cfg}' healthcheck='ok'" ;;
    1) verdict warn karabiner_healthcheck -d "${(F)summary:-${out}}" -f "${healthcheck}" ;;
    *) verdict warn karabiner_healthcheck -d "healthcheck exited ${rc}"$'\n'"$(print -r -- "${out}" | tail -n 5)" -f "${healthcheck}" ;;
  esac
}

apply::karabiner() {
  run_mut "${HOME}/.config/karabiner/bin/bake"
}
