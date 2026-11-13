# dotfiles/cmd/jobs.zsh — `dotfiles jobs`: one launchd job runs every job plugin of the set Nix builds.
zmodload zsh/datetime
zmodload -F zsh/stat b:zstat

verb::define jobs 'the job plugins and the one launchd job that runs them'
verb::usage jobs 'jobs [list]' 'jobs run JOB [--trigger TRIGGER]' 'jobs tick --trigger TRIGGER' 'jobs unlock' \
  'jobs install [--dry-run] | uninstall'
verb::about jobs <<'EOF'
One launchd job, ${JOBS_LABEL}: a resident agent that runs
the plugins whose triggers match on screen unlock (a distributed
notification only a resident observer can hear), at login and every
${JOBS_INTERVAL_SECONDS}s. A plugin is an executable in $(help::tilde "${JOBS_ROOT}"),
the set a dotfiles switch builds from $(help::tilde "${JOBS_ROOT_DF}") (shared)
and $(help::tilde "${JOBS_ROOT_LDF}") (this machine), whose header has
'# triggers: unlock load' and any '# cron: m h dom mon dow' lines; it gets
the trigger as \$1; the engine posts a banner when it ends (an alert, click
copies the log's path and opens it, on failure), except for an ending a '# notifies: ok fail' line
says the plugin reports itself. A '# deps: name...' line names setup run before
it: executables in $(help::tilde "${DEPS_ROOT}") (built from $(help::tilde "${DEPS_ROOT_DF}") and
$(help::tilde "${DEPS_ROOT_LDF}"), a local dep replacing a shared one) whose stdout, NAME=VALUE lines, becomes the
plugin's environment; a failing dep blocks the plugin. Logs and success
stamps: $(help::tilde "${JOBS_STATE_DIR}"). Every plugin and dep says in its
header what it does (a plugin also when it runs); one that does not fails
the dotfiles_jobs step. The README beside the shared plugins has the
contract.
EOF
verb::sub jobs list 'every plugin, its triggers, last run and rc, then the deps they name (the default)'
verb::sub jobs run 'run one plugin now; output to its log and stdout'
verb::sub jobs tick 'what the agent runs: every plugin due for --trigger T (load, tick, screenIsUnlocked)'
verb::sub jobs unlock 'simulate a screen unlock (SIGUSR1 to the resident agent)'
verb::sub jobs install 'remove the per-plugin jobs this framework replaced; the job itself is nix-darwin'"'"'s, installed by dotfiles switch (the dotfiles_jobs step runs this)'
verb::sub jobs uninstall 'boot out and remove a job nix-darwin did not install'
verb::arg jobs --for run 'JOB'
verb::arg jobs --for edit 'JOB|DEP'
verb::edit jobs jobs::edit 'JOB|DEP [--new] [--local|--global] [--dep] [--no-commit] [--no-push]' \
  'a plugin (or --dep) in \$EDITOR as a draft: checked on save (syntax, header lines, docs), then put in place and committed in its tier'
verb::flag jobs '--trigger TRIGGER' 'run, tick: the trigger the plugin sees as \$1 (run: manual)' --for 'run, tick'
verb::flag jobs '--dry-run' 'install: print what would change and change nothing' --for 'install, uninstall'
verb::flag jobs '--new' 'edit: start NAME from a template (in the local tier unless --global)' --for 'edit'
verb::flag jobs '--local' 'edit --new: in ~/.local/share/dotfiles (git ldf; committed and pushed)' --for 'edit'
verb::flag jobs '--global' 'edit --new: in ~/.config/dotfiles (git df; committed, never pushed)' --for 'edit'
verb::flag jobs '--dep' 'edit: a dep, not a plugin' --for 'edit'
verb::flag jobs '--no-commit' 'edit: put it in place, leave it uncommitted' --for 'edit'
verb::flag jobs '--no-push' "edit: skip the local tier's push" --for 'edit'
verb::env jobs ARI_DOTFILES_INVOKED_BY 'set by the job plugins (dotfiles-jobs); a verb that sees it posts banners instead of logging them'

jobs::edit() { need_lib "${ARI_DOTFILES_CMD}/jobs/edit.zsh" || return 3; jobs_edit "$@"; }

# --- plugins ---

# jobs_tier_of <link>: REPLY is df or ldf, read from where the set's link points. The set is one
# directory a switch builds (nix/dotfiles-jobs.nix); which tier wrote a name is already settled
# there, so nothing here scans or ranks the tiers.
jobs_tier_of() {
  if [[ "${1:A}" == "${XDG_DATA_HOME:A}/"* ]]; then REPLY=ldf; else REPLY=df; fi
}

# Fill JOB_PATH (name → executable) and JOB_TIER (name → df | ldf) from the set. A plugin
# turned off with chmod -x is not one. The deps the plugins may name are discovered alongside.
jobs_discover() {
  JOB_PATH=(); JOB_TIER=()
  local file
  for file in "${JOBS_ROOT}"/*(N-.x); do
    jobs_tier_of "${file}"
    JOB_PATH[${file:t}]="${file}"; JOB_TIER[${file:t}]="${REPLY}"
  done
  deps_discover
}

# Fill DEP_PATH (name → executable) and DEP_TIER (name → df | ldf) from the set.
deps_discover() {
  DEP_PATH=(); DEP_TIER=()
  local file
  for file in "${DEPS_ROOT}"/*(N-.x); do
    jobs_tier_of "${file}"
    DEP_PATH[${file:t}]="${file}"; DEP_TIER[${file:t}]="${REPLY}"
  done
}

# --- documentation ---

# jobs_doc_problems <file> <plugin|dep>: `reply` is what the file's header lacks to count as
# documented, one phrase each; empty when it is. The header is the leading comment block: the shebang, then
# `#` lines up to the first other line. It needs a line saying what the file does (any comment
# but a directive, a blank or a TODO), and a plugin also a `# triggers:` or `# cron:` line, or it
# only ever runs by hand. Reads the file in zsh; no command or subshell runs, so a check can
# afford it on every run.
jobs_doc_problems() {
  setopt localoptions extendedglob
  local file="${1}" kind="${2:-plugin}" line body
  local -i n=0 prose=0 schedule=0
  reply=()
  if [[ ! -r "${file}" ]]; then reply=(unreadable); return 0; fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$(( n + 1 ))
    (( n == 1 )) && [[ "${line}" == '#!'* ]] && continue
    [[ "${line}" == '#'* ]] || break
    body="${${line#\#}##[[:space:]]#}"
    case "${body}" in
      triggers:*|cron:*) schedule=1 ;;
      timeout:*|deps:*|notifies:*|'') ;;
      (#i)todo*) ;;
      *) prose=1 ;;
    esac
  done < "${file}"
  (( prose )) || reply+=("no line saying what it does")
  [[ "${kind}" == dep ]] || (( schedule )) || reply+=("no '# triggers:' or '# cron:' line")
  return 0
}

# jobs_undocumented: one `<plugin|dep> <name>: <problem>, <problem>` line per plugin and dep of
# the set whose header lacks what jobs_doc_problems asks for.
jobs_undocumented() {
  local name kind
  local -a reply
  local -A paths
  jobs_discover
  for kind in plugin dep; do
    if [[ "${kind}" == plugin ]]; then paths=("${(@kv)JOB_PATH}"); else paths=("${(@kv)DEP_PATH}"); fi
    for name in "${(@ok)paths}"; do
      jobs_doc_problems "${paths[${name}]}" "${kind}"
      (( ${#reply} == 0 )) || print -r -- "${kind} ${name}: ${(j:, :)reply}"
    done
  done
}

# A plugin's triggers, from its `# triggers:` header line: unlock, load.
jobs_triggers() {
  setopt local_options extended_glob   # the ## quantifier below
  local line
  line="$(grep -m1 -E '^# triggers:' "${1}" 2>/dev/null || true)"
  line="${line#\# triggers:}"
  print -r -- "${line##[[:space:]]##}"
}

# A plugin's cron schedules, one five-field expression per `# cron:` header line.
jobs_crons() {
  setopt local_options extended_glob
  local line
  grep -E '^# cron:' "${1}" 2>/dev/null | while IFS= read -r line; do
    line="${line#\# cron:}"
    print -r -- "${${line##[[:space:]]##}%%[[:space:]]##}"
  done
}

# A plugin's run limit in seconds: its `# timeout:` header line, else JOBS_TIMEOUT_SECONDS.
jobs_timeout() {
  setopt local_options extended_glob   # the ## quantifier below
  local line
  line="$(grep -m1 -E '^# timeout:' "${1}" 2>/dev/null || true)"
  line="${${line#\# timeout:}##[[:space:]]##}"
  [[ "${line}" == <-> ]] && print -r -- "${line}" || print -r -- "${JOBS_TIMEOUT_SECONDS}"
}

# A plugin's deps, the names on its `# deps:` header line, in the order they run.
jobs_deps() {
  setopt local_options extended_glob
  local line
  line="$(grep -m1 -E '^# deps:' "${1}" 2>/dev/null || true)"
  line="${line#\# deps:}"
  print -r -- "${line##[[:space:]]##}"
}

# A plugin's `# notifies:` header line: the endings it reports itself, ok and/or fail, for
# which the engine posts nothing.
jobs_notifies() {
  setopt local_options extended_glob
  local line
  line="$(grep -m1 -E '^# notifies:' "${1}" 2>/dev/null || true)"
  line="${line#\# notifies:}"
  print -r -- "${line##[[:space:]]##}"
}

#######################################
# Run a plugin under the kernel's watchdog. One hung plugin must not hold the job: launchd
# never spawns a second instance while one runs, so a hang would swallow every later trigger.
# Returns the command's rc, or 124 on the limit (with_timeout kills the tree with TERM, then KILL).
# Arguments: seconds, command...
#######################################
jobs_with_timeout() {
  local rc=0
  with_timeout "${@}" || rc=$?
  (( rc == 143 || rc == 137 )) && rc=124
  return "${rc}"
}

#######################################
# Does a value satisfy one cron field: `*`, `n`, `a-b`, `*/s`, `a-b/s`, or a comma list of
# those. Returns 0 matched, 1 not, 2 malformed (out of range, or not a number).
# Arguments: field, value, lo, hi
#######################################
jobs_cron_field() {
  local spec="${1}" value="${2}" lo="${3}" hi="${4}" part a b step matched=1
  for part in ${(s:,:)spec}; do
    step=1
    if [[ "${part}" == */* ]]; then step="${part#*/}"; part="${part%/*}"; fi
    if [[ "${part}" == '*' ]]; then a="${lo}"; b="${hi}"
    elif [[ "${part}" == *-* ]]; then a="${part%-*}"; b="${part#*-}"
    else a="${part}"; b="${part}"; fi
    [[ "${a}" == <-> && "${b}" == <-> && "${step}" == <-> ]] || return 2
    (( a >= lo && b <= hi && a <= b && step >= 1 )) || return 2
    (( value >= a && value <= b && (value - a) % step == 0 )) && matched=0
  done
  return "${matched}"
}

# The day-of-week field, where both 0 and 7 are Sunday. Arguments: field, %w value (0-6).
jobs_cron_dow() {
  local rc
  jobs_cron_field "${1}" "${2}" 0 7; rc=$?
  if (( rc == 1 && ${2} == 0 )); then jobs_cron_field "${1}" 7 0 7; rc=$?; fi
  return "${rc}"
}

# Returns 0 when a five-field expression is well formed, 2 otherwise (with the offending field).
jobs_is_cron_valid() {
  local -a f=("${@}")
  (( ${#f} == 5 )) || return 2
  local rc
  jobs_cron_field "${f[1]}" 0 0 59;  rc=$?; (( rc == 2 )) && return 2
  jobs_cron_field "${f[2]}" 0 0 23;  rc=$?; (( rc == 2 )) && return 2
  jobs_cron_field "${f[3]}" 1 1 31;  rc=$?; (( rc == 2 )) && return 2
  jobs_cron_field "${f[4]}" 1 1 12;  rc=$?; (( rc == 2 )) && return 2
  jobs_cron_field "${f[5]}" 0 0 7;   rc=$?; (( rc == 2 )) && return 2
  return 0
}

#######################################
# Prints the epoch of the most recent minute at or before now that matches a five-field cron
# expression, looking back up to a year; prints nothing (rc 1) when none does. Days are walked
# back through `date -v` so DST changes land on real local midnights; within a matching day the
# hours and minutes are walked down from the latest allowed.
# Arguments: the five fields
#######################################
jobs_cron_previous() {
  local -a f=("${@}")
  local d h m day_start dom mon dow hi_h hi_m mm_hi
  for (( d = 0; d <= 366; d++ )); do
    day_start="$(date -j -v-"${d}"d -v0H -v0M -v0S +%s)"
    strftime -s dom '%d' "${day_start}"; strftime -s mon '%m' "${day_start}"; strftime -s dow '%w' "${day_start}"
    jobs_cron_field "${f[3]}" $(( 10#${dom} )) 1 31 || continue
    jobs_cron_field "${f[4]}" $(( 10#${mon} )) 1 12 || continue
    jobs_cron_dow "${f[5]}" "${dow}" || continue
    hi_h=23; hi_m=59
    if (( d == 0 )); then strftime -s hi_h '%H' "${EPOCHSECONDS}"; strftime -s hi_m '%M' "${EPOCHSECONDS}"; hi_h=$(( 10#${hi_h} )); hi_m=$(( 10#${hi_m} )); fi
    for (( h = hi_h; h >= 0; h-- )); do
      jobs_cron_field "${f[2]}" "${h}" 0 23 || continue
      mm_hi=59; (( d == 0 && h == hi_h )) && mm_hi="${hi_m}"
      for (( m = mm_hi; m >= 0; m-- )); do
        if jobs_cron_field "${f[1]}" "${m}" 0 59; then
          date -j -r "${day_start}" -v"${h}"H -v"${m}"M -v0S +%s; return 0
        fi
      done
    done
  done
  return 1
}

#######################################
# True (0) when a cron schedule is due: its most recent moment at or before now is later than
# the plugin's last run, so a moment missed asleep fires on the first tick after wake (unlike
# cron, which skips it) and a plugin that never ran is due at once. A malformed expression is
# warned about and never due.
# Arguments: name, expression
#######################################
jobs_is_cron_due() {
  local name="${1}" expr="${2}" stamp="${JOBS_STATE_DIR}/${1}.ran" prev
  local -a f=(${=expr})
  if ! jobs_is_cron_valid "${f[@]}"; then
    log::warn "bad cron trigger; ignored | job='${name}' cron='${expr}' want='minute hour day-of-month month day-of-week'"; return 1
  fi
  prev="$(jobs_cron_previous "${f[@]}")" || return 1
  [[ -f "${stamp}" ]] || return 0
  (( $(zstat +mtime "${stamp}") < prev ))
}

# The agent's pid from launchd, or nothing when the job is not running (launchctl exits 113
# then). Parsed in zsh: the hermetic suite allows no awk.
jobs_agent_pid() {
  local -a lines
  lines=("${(@f)$(launchctl print "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null || true)}")
  local line pid
  line="${${(@M)lines:#*pid = *}[1]:-}"   # (@) keeps the matches an array, so [1] is a line, not a character
  pid="${line##*= }"
  if [[ "${pid}" == <-> ]]; then print -r -- "${pid}"; fi
}

#######################################
# Run a plugin's deps, the names on its `# deps:` line, in order, and export what each prints.
# A dep is setup for the job: its stdout is its contribution to the job's environment, one
# NAME=VALUE per line and nothing else; its stderr is setup chatter and lands in the job log with
# the rest of the run. An unknown name, a non-zero exit, a timeout or a stray stdout line blocks
# the job, and the line printed here says which dep and why.
# Arguments: name, plugin
# Returns: 0 when every dep ran clean, 1 otherwise
#######################################
jobs_run_deps() {
  setopt local_options extended_glob   # the # quantifier in the NAME=VALUE pattern
  local name="${1}" plugin="${2}" dep exe tmp line rc start
  local -a lines
  for dep in ${=$(jobs_deps "${plugin}")}; do
    exe="${DEP_PATH[${dep}]:-}"
    if [[ -z "${exe}" ]]; then
      print -r -- "# dep ${dep}: unknown | root='${DEPS_ROOT}'"; return 1
    fi
    start="${EPOCHREALTIME}"; rc=0
    tmp="${JOBS_STATE_DIR}/${name}.dep"   # the dep's stdout; kept until the next dep overwrites it
    jobs_with_timeout "${JOBS_DEP_TIMEOUT_SECONDS}" "${exe}" "${name}" >"${tmp}" || rc=$?
    lines=("${(@f)$(<"${tmp}")}")
    if (( rc )); then
      print -r -- "# dep ${dep}: failed | rc='${rc}' exe='${exe}'"; return 1
    fi
    local exported=0
    for line in "${lines[@]}"; do
      [[ -z "${line}" ]] && continue
      if [[ "${line}" != [A-Za-z_][A-Za-z0-9_]#=* ]]; then
        print -r -- "# dep ${dep}: stdout must be NAME=VALUE lines | got='${line}'"; return 1
      fi
      export "${line}"; exported=$(( exported + 1 ))
    done
    print -r -- "# dep ${dep} ok | tier='${DEP_TIER[${dep}]}' vars='${exported}' took='$(elapsed "${start}")s'"
  done
  return 0
}

#######################################
# A plugin's deps, then the plugin, in the caller's subshell: what the deps export reaches the
# plugin and nothing after it. A dep that fails blocks the plugin.
# Arguments: name, plugin, trigger, limit
# Returns: the plugin's rc (124 on its limit), or JOBS_DEP_FAILED_RC
#######################################
jobs_run_guarded() {
  local name="${1}" plugin="${2}" trigger="${3}" limit="${4}"
  jobs_run_deps "${name}" "${plugin}" || return "${JOBS_DEP_FAILED_RC}"
  jobs_with_timeout "${limit}" "${plugin}" "${trigger}"
}

#######################################
# Run one job for a trigger. Its output goes to ~/.local/state/dotfiles/jobs/<name>.log
# (plain text, the KEEP_BACKUPS runs before it in .log.bak.N) and to stdout; the run touches
# the stamp the cron due check reads and records its rc beside it. One log line here either
# way, and a notification from jobs_notify_finish: the engine reports every ending, so a
# plugin need not.
# Arguments: name, trigger
#######################################
jobs_run_one() {
  # `plugin`, never `path`: zsh ties the array `path` to PATH, and a local by that name
  # replaced the search path with the plugin's own (mkdir, date and tee "not found").
  local name="${1}" trigger="${2}" plugin="${JOB_PATH[${name}]}" logfile rc=0 start="${EPOCHREALTIME}" limit
  logfile="${JOBS_STATE_DIR}/${name}.log"
  limit="$(jobs_timeout "${plugin}")"
  mkdir -p "${JOBS_STATE_DIR}"
  log_rotate "${logfile}" "${KEEP_BACKUPS}"
  {
    print -r -- "# $(date -u +%FT%TZ) dotfiles jobs run ${name} (${trigger}) timeout=${limit}s"
    jobs_run_guarded "${name}" "${plugin}" "${trigger}" "${limit}" 2>&1
  } | strip_ansi | tee "${logfile}" || rc=$?   # pipefail: the group exits with the plugin's rc
  touch "${JOBS_STATE_DIR}/${name}.ran"
  print -r -- "${rc}" > "${JOBS_STATE_DIR}/${name}.rc"
  local took; took="$(elapsed "${start}")"
  if (( rc == 0 )); then
    log::info "job ok | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' took='${took}s' log='${logfile}'"
  elif (( rc == 124 )); then
    log::err "job timed out | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' limit='${limit}s' log='${logfile}'"
  elif (( rc == JOBS_DEP_FAILED_RC )); then
    log::err "job blocked, a dep failed | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' took='${took}s' log='${logfile}'"
  else
    log::err "job failed | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' rc='${rc}' took='${took}s' log='${logfile}'"
  fi
  jobs_notify_finish "${name}" "${rc}" "${took}" "${logfile}"
  return "${rc}"
}

#######################################
# True (0) when a plugin should run for this trigger: a named trigger it declares, or a cron
# schedule whose moment has come (on a tick and at load only). Unknown tokens are warned about,
# not ignored.
# Arguments: name, trigger
#######################################
jobs_is_plugin_due() {
  local name="${1}" trigger="${2}" plugin="${JOB_PATH[${name}]}" t expr
  local periodic=1; [[ "${trigger}" == tick || "${trigger}" == load ]] && periodic=0
  for t in ${=$(jobs_triggers "${plugin}")}; do
    case "${t}" in
      unlock|load) [[ "${t}" == "${trigger}" ]] && return 0 ;;
      *)           log::warn "unknown trigger; ignored | job='${name}' trigger='${t}'" ;;
    esac
  done
  if (( periodic == 0 )); then
    for expr in "${(@f)$(jobs_crons "${plugin}")}"; do
      [[ -n "${expr}" ]] || continue
      jobs_is_cron_due "${name}" "${expr}" && return 0
    done
  fi
  return 1
}

#######################################
# What the agent runs. The tag names why: 'load' when the agent starts (login, install, or a
# restart by launchd), 'screenIsUnlocked' for the distributed notification of that name, 'tick'
# for its timer. Cron schedules run on a tick and at load when due; unlock and load on their
# named trigger. Every due plugin runs even after one fails; the tick fails if any did.
# Arguments: tag
#######################################
jobs_tick() {
  local tag="${1}" trigger name rc=0 ran=0
  case "${tag}" in
    screenIsUnlocked) trigger=unlock ;;
    *) trigger="${tag}" ;;
  esac
  jobs_discover
  for name in "${(@ko)JOB_PATH}"; do
    jobs_is_plugin_due "${name}" "${trigger}" || continue
    ran=$(( ran + 1 ))
    jobs_run_one "${name}" "${trigger}" || rc=1
  done
  log::info "tick done | trigger='${trigger}' ran='${ran}' plugins='${#JOB_PATH}'"
  return "${rc}"
}

# One line for the list: the triggers, then each cron expression in quotes.
jobs_schedule() {
  local out expr
  out="$(jobs_triggers "${1}")"
  for expr in "${(@f)$(jobs_crons "${1}")}"; do
    [[ -n "${expr}" ]] || continue
    out="${out:+${out} }cron:'${expr}'"
  done
  print -r -- "${out}"
}

# The deps block of the list: every dep a plugin names or a root holds, with the tier that
# provides it (or "missing") and the plugins that want it.
jobs_list_deps() {
  local name dep
  local -A wanted=()
  for name in "${(@k)JOB_PATH}"; do
    for dep in ${=$(jobs_deps "${JOB_PATH[${name}]}")}; do
      wanted[${dep}]="${wanted[${dep}]:+${wanted[${dep}]} }${name}"
    done
  done
  local -a names=("${(@k)wanted}" "${(@k)DEP_PATH}")
  (( ${#names} )) || return 0
  print -r -- "  ${c_bold}deps${c_rst} (a plugin's '# deps:' line, run as its setup; from ${DEPS_ROOT})"
  printf '  %-4s %-20s %s\n' tier name 'wanted by'
  for dep in "${(@uo)names}"; do
    if [[ -n "${DEP_PATH[${dep}]:-}" ]]; then
      printf '  %-4s %-20s %s\n' "${DEP_TIER[${dep}]}" "${dep}" "${wanted[${dep}]:--}"
    else
      printf '  %-4s %-20s %s\n' - "${dep}" "${wanted[${dep}]} (${c_red}missing${c_rst})"
    fi
  done
}

jobs_list() {
  jobs_discover
  print -r -- "${c_bold}jobs${c_rst} (${JOBS_LABEL}: on unlock, at login, every ${JOBS_INTERVAL_SECONDS}s)"
  if (( ${#JOB_PATH} == 0 )); then print -r -- "  none | root='${JOBS_ROOT}' (a dotfiles switch builds it)"; return 0; fi
  local name stamp last rc
  printf '  %-4s %-20s %-22s %-20s %s\n' tier name triggers 'last run' rc
  for name in "${(@ko)JOB_PATH}"; do
    stamp="${JOBS_STATE_DIR}/${name}.ran"; last=never; rc=-
    if [[ -f "${stamp}" ]]; then
      last="$(date -r "${stamp}" '+%Y-%m-%dT%H:%M:%S')"
      [[ -f "${JOBS_STATE_DIR}/${name}.rc" ]] && rc="$(<"${JOBS_STATE_DIR}/${name}.rc")"
    fi
    printf '  %-4s %-20s %-22s %-20s %s\n' "${JOB_TIER[${name}]}" "${name}" "$(jobs_schedule "${JOB_PATH[${name}]}")" "${last}" "${rc}"
  done
  jobs_list_deps
  local pid; pid="$(jobs_agent_pid)"
  if [[ -n "${pid}" ]]; then
    print -r -- "  agent: running (pid ${pid}); 'dotfiles jobs unlock' simulates an unlock"
  elif launchctl print "gui/$(id -u)/${JOBS_LABEL}" >/dev/null 2>&1; then
    print -r -- "  agent: ${c_yellow}loaded but not running${c_rst} (launchd restarts it; see ${JOBS_STATE_DIR}/launchd.err.log)"
  else
    print -r -- "  agent: ${c_red}not loaded${c_rst} (dotfiles switch)"
  fi
}

# --- notifications: the engine reports how every job ended, so no plugin can forget to ---

# atn, the terminal-notifier logging shim, probed (probe_tool) on the self-healed PATH. Without
# it there is no banner: an osascript banner cannot be removed and would sit in Notification
# Center forever.
jobs_notifier_bin() {
  local tn
  tn="$(probe_tool atn)"
  [[ -n "${tn}" ]] || return 1
  print -r -- "${tn}"
}

# terminal-notifier with the given arguments, output discarded, killed after
# JOBS_NOTIFIER_TIMEOUT_SECONDS. The watchdog holds no descriptor and its sleep dies with it,
# or a caller's pipe stays open. Returns its rc, or 124 on the timeout.
jobs_notify() {
  local tn pid watchdog rc=0
  tn="$(jobs_notifier_bin)" || return 1
  [[ "${1}" == -remove ]] || set -- "${@}" -contentImage "${ARI_DOTFILES_NOTIFIER_IMAGE}"
  log::notify_image_check "${@}"
  "${tn}" "${@}" >/dev/null 2>&1 </dev/null &
  pid=$!
  { sleep "${JOBS_NOTIFIER_TIMEOUT_SECONDS}"; kill "${pid}" 2>/dev/null; } >/dev/null 2>&1 </dev/null &
  watchdog=$!
  wait "${pid}" || rc=$?
  pkill -P "${watchdog}" 2>/dev/null || true
  kill "${watchdog}" 2>/dev/null || true
  if (( rc == 143 )); then log::warn "terminal-notifier hung; killed | args='${*}'"; rc=124; fi
  return "${rc}"
}

# The command a failure alert's click runs: the log's path onto the clipboard (to paste into a
# shell or a Claude prompt), then the log itself, at its end, in $EDITOR in a new tmux window
# of the working session via tmux-edit-window (ARI_DOTFILES_EDIT_WINDOW), else in Terminal.
# The editor resolves inside that window, not here: the click runs under /bin/sh with launchd's
# environment, where $EDITOR is unset and nvim (under bob) is off PATH, so resolving here gave
# vi. Absolute paths throughout, for the same reason.
jobs_click_command() {
  local logfile="${1}"
  print -r -- "printf %s ${(q)logfile} | /usr/bin/pbcopy; ${(q)ARI_DOTFILES_EDIT_WINDOW} -n dotfiles-jobs-log + ${(q)logfile}"
}

#######################################
# Tell the user how a job ended. Success: a JOBS_HUD_SECONDS banner (post, sleep, remove by
# group; macOS gives banners no duration control) carrying the plugin's last output line, so a
# plugin's summary is what it prints last; any earlier failure alert for the job comes down.
# Failure or timeout: a persistent alert, one per job (its group), whose click copies the log's
# path and opens the log.
# An ending the plugin's `# notifies:` line claims (ok, fail) gets no banner and no alert from
# here: the plugin posted its own. A timeout or a blocked dep is always the engine's alert,
# since the plugin never got to speak.
# Arguments: name, rc, took, logfile
#######################################
jobs_notify_finish() {
  local name="${1}" rc="${2}" took="${3}" logfile="${4}" last verdict
  jobs_notifier_bin >/dev/null || return 0
  local -a notifies=(${=$(jobs_notifies "${JOB_PATH[${name}]:-}")})
  # grep exits 1 when only header lines remain (a plugin that printed nothing, a blocked run).
  last="$(grep -v -E '^# |^[[:space:]]*$' "${logfile}" 2>/dev/null | tail -n 1 | cut -c1-140 || true)"
  if (( rc == 0 )); then
    jobs_notify -remove "dotfiles-jobs-${name}" || true
    (( ${notifies[(I)ok]} )) && return 0
    jobs_notify -group dotfiles-jobs -title "dotfiles jobs" -message "${name} ok in ${took}s${last:+ · ${last}}" || return 0
    sleep "${JOBS_HUD_SECONDS}"
    jobs_notify -remove dotfiles-jobs || true
    return 0
  fi
  if (( rc != 124 && rc != JOBS_DEP_FAILED_RC && ${notifies[(I)fail]} )); then return 0; fi
  verdict="failed (rc ${rc})"; (( rc == 124 )) && verdict="timed out"; (( rc == JOBS_DEP_FAILED_RC )) && verdict="blocked: a dep failed"
  jobs_notify -group "dotfiles-jobs-${name}" -title "dotfiles jobs: ${name} ${verdict}" \
    -message "${last:-no output} — click to open the log (path copied)" -execute "$(jobs_click_command "${logfile}")" || true
}

# --- the launchd job ---

# The plist runs an agent from the Nix store: nix-darwin's launchd.user.agents wrote it, so a
# switch owns the job and an install here would only fight it.
jobs_nix_managed() {
  [[ -f "${JOBS_PLIST}" ]] || return 1
  local program
  program="$(plutil -extract ProgramArguments.0 raw -o - "${JOBS_PLIST}" 2>/dev/null)" || return 1
  [[ "${program}" == "${ARI_DOTFILES_NIX_STORE}"/* ]]
}

#######################################
# Idempotent, and the dotfiles_jobs step's apply: boots out and removes the per-plugin jobs this
# framework replaced. The job itself is nix-darwin's (launchd.user.agents.dotfiles-jobs in
# nix/darwin.nix), so `dotfiles switch` installs and updates it; without it this fails with that fix.
#######################################
jobs_install() {
  local label plist
  for label in "${JOBS_LEGACY_LABELS[@]}"; do
    plist="${HOME}/Library/LaunchAgents/${label}.plist"
    [[ -f "${plist}" ]] || launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1 || continue
    if is_dry_run; then log::info "dry-run, would remove legacy job | label='${label}'"; continue; fi
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    rm -f "${plist}"
    log::info "removed legacy job | label='${label}' plist='${plist}'"
  done
  if jobs_nix_managed; then
    log::info "jobs launchd job managed by nix-darwin; a switch installs it | label='${JOBS_LABEL}' plist='${JOBS_PLIST}'"; return 0
  fi
  log::err "the jobs launchd job is nix-darwin's and this machine has not switched to it | label='${JOBS_LABEL}' plist='${JOBS_PLIST}' fix='dotfiles switch'"
  return 1
}

jobs_uninstall() {
  if jobs_nix_managed; then
    log::err "nix-darwin owns the jobs launchd job; a switch would put it back | label='${JOBS_LABEL}' fix='remove launchd.user.agents.dotfiles-jobs from nix/darwin.nix, then dotfiles switch'"
    return 1
  fi
  launchctl bootout "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null || true
  rm -f "${JOBS_PLIST}"
  log::info "removed jobs launchd job | label='${JOBS_LABEL}'"
}

# Simulate a screen unlock: SIGUSR1 to the agent, which runs the unlock tick as if the
# distributed notification had arrived. Only a real lock and unlock proves the observer itself.
jobs_simulate_unlock() {
  local pid; pid="$(jobs_agent_pid)"
  if [[ -z "${pid}" ]]; then log::err "agent not running | fix='dotfiles switch'"; return 1; fi
  kill -USR1 "${pid}" && log::info "unlock simulated | agent_pid='${pid}' watch='${JOBS_STATE_DIR}/launchd.err.log'"
}

# --- command ---

cmd_jobs() {
  local -A opts; local -a args
  verb::parse jobs "$@"
  local sub="${args[1]:-list}" name="${args[2]:-}" trigger="${opts[--trigger]:-manual}"
  (( ${+opts[--dry-run]} )) && export ARI_DOTFILES_DRY_RUN=1
  case "${sub}" in
    list) jobs_list ;;
    run)
      if [[ -z "${name}" ]]; then log::err "jobs run needs a name | see='dotfiles jobs list'"; return 1; fi
      jobs_discover
      if [[ -z "${JOB_PATH[${name}]:-}" ]]; then log::err "no such job | name='${name}' known='${(kj:, :)JOB_PATH}'"; return 1; fi
      jobs_run_one "${name}" "${trigger}" ;;
    tick) jobs_tick "${trigger}" ;;
    unlock) jobs_simulate_unlock ;;
    install) jobs_install ;;
    uninstall) jobs_uninstall ;;
    *) usage_error "jobs: unknown subcommand | sub='${sub}' known='list run edit tick unlock install uninstall'" ;;
  esac
}
