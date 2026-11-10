# step karabiner — Karabiner's own healthcheck. The config invariant left with Nix: karabiner.nix
# places karabiner.json and fails the switch on invalid JSON, and the df pre-commit rule keeps it
# `jq -S` sorted. The healthcheck's process/device/IPC findings are runtime state, not baseline,
# so its exit 1 is a warn and never a fail.
step::declare karabiner --group tools \
  --desc "Karabiner's own healthcheck passes, when it is present (karabiner.nix places karabiner.json and fails the switch on invalid JSON; the pre-commit hook keeps it sorted)"
step::watches karabiner '.config/karabiner/**'

check::karabiner() {
  local healthcheck="${HOME}/.config/karabiner/bin/healthcheck"
  local healthcheck_lib="${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
  if [[ ! -x "${healthcheck}" ]]; then
    verdict skip no_healthcheck -d "path='${healthcheck}'"
    return 0
  fi
  if [[ ! -r "${healthcheck_lib}" ]]; then
    verdict skip no_logging_lib -d "the healthcheck needs the skill logging lib | path='${healthcheck_lib}'"
    return 0
  fi
  local out rc=0
  out="$("${healthcheck}")" || rc=$?
  local -a summary=(${(M)${(f)out}:#(status|issues)=*})
  case "${rc}" in
    0) verdict ok healthy -d "healthcheck='${healthcheck}'" ;;
    1) verdict warn karabiner_healthcheck -d "${(F)summary:-${out}}" -f "${healthcheck}" ;;
    *) verdict warn karabiner_healthcheck -d "healthcheck exited ${rc}"$'\n'"$(print -r -- "${out}" | tail -n 5)" -f "${healthcheck}" ;;
  esac
}
