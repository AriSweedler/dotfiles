# dotfiles/lib/jobs.zsh — `dotfiles jobs`: one launchd job runs every job plugin, from both tiers.
zmodload zsh/datetime
zmodload zsh/stat

# --- plugins ---

# Every directory that may hold job plugins: the shared tier's, then the local tier's.
jobs_roots() {
  print -r -- "${JOBS_ROOT_DF}"
  print -r -- "${JOBS_ROOT_LDF}"
}

# Fill JOB_PATH (name → executable) and JOB_TIER (name → df | ldf). Non-executables (a
# README) are not plugins. A name present in both tiers runs from the shared one, logged.
jobs_discover() {
  JOB_PATH=(); JOB_TIER=()
  local root tier file name
  for root in "${(@f)$(jobs_roots)}"; do
    tier=df; [[ "${root}" == "${JOBS_ROOT_LDF}" ]] && tier=ldf
    for file in "${root}"/*(N-.x); do
      name="${file:t}"
      if [[ -n "${JOB_PATH[${name}]:-}" ]]; then
        log::err "job defined in both tiers; the shared one runs | name='${name}' shadowed='${file}'"; continue
      fi
      JOB_PATH[${name}]="${file}"; JOB_TIER[${name}]="${tier}"
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

#######################################
# Run a command, killing it (children first, then itself) after a limit. One hung plugin
# must not hold the job: launchd never spawns a second instance while one runs, so a hang
# would swallow every later trigger. Returns the command's rc, or 124 on the limit.
# The watchdog holds no file descriptor and its sleep is killed with it: a background
# `sleep` that inherited the caller's stdout would keep the pipe open, and the pipeline
# reading it would wait the whole limit.
# Arguments: seconds, command...
#######################################
jobs_with_timeout() {
  local seconds="${1}"; shift
  local pid watchdog rc=0
  "${@}" &
  pid=$!
  { sleep "${seconds}"; pkill -TERM -P "${pid}" 2>/dev/null; kill -TERM "${pid}" 2>/dev/null; sleep 5; pkill -KILL -P "${pid}" 2>/dev/null; kill -KILL "${pid}" 2>/dev/null; } >/dev/null 2>&1 </dev/null &
  watchdog=$!
  wait "${pid}" || rc=$?
  pkill -P "${watchdog}" 2>/dev/null || true
  kill "${watchdog}" 2>/dev/null || true
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
jobs_cron_valid() {
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
jobs_cron_due() {
  local name="${1}" expr="${2}" stamp="${JOBS_STATE_DIR}/${1}.ran" prev
  local -a f=(${=expr})
  if ! jobs_cron_valid "${f[@]}"; then
    log::warn "bad cron trigger; ignored | job='${name}' cron='${expr}' want='minute hour day-of-month month day-of-week'"; return 1
  fi
  prev="$(jobs_cron_previous "${f[@]}")" || return 1
  [[ -f "${stamp}" ]] || return 0
  (( $(zstat +mtime "${stamp}") < prev ))
}

# The job's spawn count since launchd loaded it; 0 when it is not loaded.
jobs_run_count() {
  local runs
  runs="$(launchctl print "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null | awk '/^[[:space:]]*runs = /{print $3; exit}')"
  [[ "${runs}" == <-> ]] || runs=0
  print -r -- "${runs}"
}

#######################################
# Run one job for a trigger. Its output goes to ~/.local/state/dotfiles/jobs/<name>.log
# (plain text, the previous run in .log.bak.1) and to stdout; the run touches the stamp the
# cron due check reads and records its rc beside it. One log line here either way.
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
    jobs_with_timeout "${limit}" "${plugin}" "${trigger}" 2>&1
  } | strip_ansi | tee "${logfile}" || rc=$?   # pipefail: the group exits with the plugin's rc
  touch "${JOBS_STATE_DIR}/${name}.ran"
  print -r -- "${rc}" > "${JOBS_STATE_DIR}/${name}.rc"
  if (( rc == 0 )); then
    log::info "job ok | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' took='$(elapsed "${start}")s' log='${logfile}'"
  elif (( rc == 124 )); then
    log::err "job timed out | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' limit='${limit}s' log='${logfile}'"
  else
    log::err "job failed | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' rc='${rc}' took='$(elapsed "${start}")s' log='${logfile}'"
  fi
  return "${rc}"
}

#######################################
# True (0) when a plugin should run for this trigger: a named trigger it declares, or a cron
# schedule whose moment has come (on a tick and at load only). Unknown tokens are warned about,
# not ignored.
# Arguments: name, trigger
#######################################
jobs_plugin_due() {
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
      jobs_cron_due "${name}" "${expr}" && return 0
    done
  fi
  return 1
}

#######################################
# What launchd runs. The tag comes from the event consumer: the event's key
# (screenIsUnlocked) when one started the job, else 'launchd', which is RunAtLoad on the
# job's first spawn since it was loaded (login, or install) and the StartInterval tick after
# that. Cron schedules run on a tick and at load when due; unlock and load on their named
# trigger. Every due plugin runs even after one fails; the tick fails if any did.
# Arguments: tag
#######################################
jobs_tick() {
  local tag="${1}" trigger name rc=0 ran=0
  case "${tag}" in
    screenIsUnlocked) trigger=unlock ;;
    launchd) if (( $(jobs_run_count) == 1 )); then trigger=load; else trigger=tick; fi ;;
    *) trigger="${tag}" ;;
  esac
  jobs_discover
  for name in "${(@ko)JOB_PATH}"; do
    jobs_plugin_due "${name}" "${trigger}" || continue
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

jobs_list() {
  jobs_discover
  print -r -- "${c_bold}jobs${c_rst} (${JOBS_LABEL}: on unlock, at login, every ${JOBS_INTERVAL_SECONDS}s)"
  if (( ${#JOB_PATH} == 0 )); then print -r -- "  none | roots='${JOBS_ROOT_DF}, ${JOBS_ROOT_LDF}'"; return 0; fi
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
  if launchctl print "gui/$(id -u)/${JOBS_LABEL}" >/dev/null 2>&1; then
    print -r -- "  launchd: loaded, runs since load=$(jobs_run_count)"
  else
    print -r -- "  launchd: ${c_red}not loaded${c_rst} (dotfiles jobs install)"
  fi
}

# --- the launchd job ---

#######################################
# Write and compile the XPC event consumer, the job's program. launchd delivers a LaunchEvents
# trigger as an XPC event and re-spawns the job every 10 s until the job's own process
# registers a handler and receives it; a shell cannot, and a child process does not count
# (tried), so this 40-line C program is the program: it consumes the event, then execs the
# harness with --trigger <event key | launchd>. Compiled only when the source changed.
# Globals: JOBS_CONSUMER_BIN
#######################################
jobs_write_consumer() {
  local src="${JOBS_CONSUMER_BIN}.c" rendered
  mkdir -p "${JOBS_CONSUMER_BIN:h}"
  rendered="$(mktemp)"
  cat >"${rendered}" <<'CSRC'
// launch-event-consume <stream> <timeout-seconds> <program> [args...]
// Generated and compiled by `dotfiles jobs install` (see dotfiles/lib/jobs.zsh).
//
// launchd delivers the trigger that started the job as an XPC event on <stream> and, until
// the job's own process registers a handler and receives it, re-spawns the job every
// ThrottleInterval. This runs as the job's program: it registers, waits up to
// <timeout-seconds> for the event, then execs <program> [args...] --trigger <event key>
// (com.apple. stripped), or --trigger launchd when nothing arrived (RunAtLoad, StartInterval,
// `launchctl kickstart`).
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <xpc/xpc.h>

static int g_argc;
static char **g_argv;

static void run(const char *tag) {
    static char trigger[256];
    const char *prefix = "com.apple.";
    if (strncmp(tag, prefix, strlen(prefix)) == 0) {
        tag += strlen(prefix);
    }
    snprintf(trigger, sizeof trigger, "%s", tag);
    int n = g_argc - 3;
    char **args = calloc((size_t)n + 3, sizeof *args);
    for (int i = 0; i < n; i++) {
        args[i] = g_argv[3 + i];
    }
    args[n] = "--trigger";
    args[n + 1] = trigger;
    args[n + 2] = NULL;
    execv(args[0], args);
    perror("execv");
    exit(3);
}

int main(int argc, char **argv) {
    if (argc < 4) {
        fprintf(stderr, "usage: %s <stream> <timeout-seconds> <program> [args...]\n", argv[0]);
        return 2;
    }
    g_argc = argc;
    g_argv = argv;
    xpc_set_event_stream_handler(argv[1], NULL, ^(xpc_object_t event) {
        const char *name = xpc_dictionary_get_string(event, XPC_EVENT_KEY_NAME);
        run(name ? name : "event");
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(atof(argv[2]) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ run("launchd"); });
    dispatch_main();
}
CSRC
  if [[ -x "${JOBS_CONSUMER_BIN}" ]] && cmp -s "${rendered}" "${src}"; then
    rm -f "${rendered}"; log::info "event consumer current | bin='${JOBS_CONSUMER_BIN}'"; return 0
  fi
  if ! command -v cc >/dev/null 2>&1; then
    rm -f "${rendered}"
    log::err "no C compiler; the jobs launchd job needs the Command Line Tools | fix='xcode-select --install'"; return 1
  fi
  mv "${rendered}" "${src}"
  cc -O2 -Wall -Wextra -o "${JOBS_CONSUMER_BIN}" "${src}"
  log::info "compiled event consumer | bin='${JOBS_CONSUMER_BIN}'"
}

#######################################
# Render the plist through jq + plutil (jq escapes every value; plutil rejects malformed
# output) and install it only when it differs. Sets jobs_plist_changed for the caller.
# Globals: JOBS_*, jobs_plist_changed
#######################################
jobs_write_plist() {
  local rendered
  rendered="$(mktemp)"
  jq -n \
    --arg label "${JOBS_LABEL}" --arg consumer "${JOBS_CONSUMER_BIN}" --arg wait "${JOBS_EVENT_WAIT_SECONDS}" \
    --arg harness "${HOME}/.config/bin/dotfiles" --arg path "${JOBS_LAUNCHD_PATH}" \
    --arg stream "${JOBS_EVENT_STREAM}" --arg event "${JOBS_EVENT_NAME}" --argjson interval "${JOBS_INTERVAL_SECONDS}" \
    --arg out "${JOBS_STATE_DIR}/launchd.out.log" --arg err "${JOBS_STATE_DIR}/launchd.err.log" \
    '{
      Label: $label,
      ProgramArguments: [$consumer, $stream, $wait, "/bin/zsh", $harness, "jobs", "tick"],
      RunAtLoad: true,
      StartInterval: $interval,
      LaunchEvents: {($stream): {($event): {Notification: $event}}},
      EnvironmentVariables: {PATH: $path},
      StandardOutPath: $out,
      StandardErrorPath: $err
    }' | plutil -convert xml1 - -o "${rendered}"
  plutil -lint -s "${rendered}"
  if cmp -s "${rendered}" "${JOBS_PLIST}"; then rm -f "${rendered}"; jobs_plist_changed=0; return 0; fi
  mkdir -p "${JOBS_PLIST:h}"   # a fresh account may not have ~/Library/LaunchAgents yet
  mv "${rendered}" "${JOBS_PLIST}"
  chmod 0644 "${JOBS_PLIST}"
  jobs_plist_changed=1
}

#######################################
# Idempotent, and an init step: the per-plugin jobs this framework replaced are booted out
# and their plists removed; the consumer is compiled and the plist written only on change;
# a loaded job whose plist did not change is left alone (a bootout + bootstrap would fire
# RunAtLoad again).
#######################################
jobs_install() {
  local label plist
  for label in "${JOBS_LEGACY_LABELS[@]}"; do
    plist="${HOME}/Library/LaunchAgents/${label}.plist"
    [[ -f "${plist}" ]] || launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1 || continue
    if [[ "${DRY_RUN}" == true ]]; then log::info "dry-run, would remove legacy job | label='${label}'"; continue; fi
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    rm -f "${plist}"
    log::info "removed legacy job | label='${label}' plist='${plist}'"
  done
  if [[ "${DRY_RUN}" == true ]]; then
    log::info "dry-run, would compile the consumer, write the plist and bootstrap, each only if changed | label='${JOBS_LABEL}' plist='${JOBS_PLIST}'"; return 0
  fi
  mkdir -p "${JOBS_STATE_DIR}"
  jobs_write_consumer || return 1
  local jobs_plist_changed=1
  jobs_write_plist
  if (( jobs_plist_changed == 0 )) && launchctl print "gui/$(id -u)/${JOBS_LABEL}" >/dev/null 2>&1; then
    log::info "jobs launchd job current | label='${JOBS_LABEL}'"; return 0
  fi
  launchctl bootout "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "${JOBS_PLIST}"
  log::info "installed jobs launchd job | label='${JOBS_LABEL}' triggers='${JOBS_EVENT_NAME}, login, every ${JOBS_INTERVAL_SECONDS}s' logs='${JOBS_STATE_DIR}'"
}

jobs_uninstall() {
  launchctl bootout "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null || true
  rm -f "${JOBS_PLIST}"
  log::info "removed jobs launchd job | label='${JOBS_LABEL}'"
}

# --- command ---

cmd_jobs() {
  local sub="${JOBS_ARGS[1]:-list}" trigger=manual name=""
  local -a rest=("${JOBS_ARGS[@]:1}")
  while (( ${#rest} > 0 )); do case "${rest[1]}" in
    --trigger) trigger="${rest[2]:?--trigger requires a value}"; rest=("${rest[@]:2}") ;;
    -*) log::err "Unknown jobs flag | flag='${rest[1]}'"; return 1 ;;
    *) name="${rest[1]}"; rest=("${rest[@]:1}") ;;
  esac; done
  case "${sub}" in
    list) jobs_list ;;
    run)
      if [[ -z "${name}" ]]; then log::err "jobs run needs a name | see='dotfiles jobs list'"; return 1; fi
      jobs_discover
      if [[ -z "${JOB_PATH[${name}]:-}" ]]; then log::err "no such job | name='${name}' known='${(kj:, :)JOB_PATH}'"; return 1; fi
      jobs_run_one "${name}" "${trigger}" ;;
    tick) jobs_tick "${trigger}" ;;
    install) jobs_install ;;
    uninstall) jobs_uninstall ;;
    *) log::err "Unknown jobs subcommand | sub='${sub}' valid='list, run <name>, tick, install, uninstall'"; return 1 ;;
  esac
}
