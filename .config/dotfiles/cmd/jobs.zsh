# dotfiles/cmd/jobs.zsh — `dotfiles jobs`: one launchd job runs every job plugin, from both tiers.
zmodload zsh/datetime
zmodload zsh/stat

help_jobs() {
  cat <<EOF
dotfiles jobs [list] | run NAME [--trigger T] | tick --trigger T | unlock | install | uninstall   the job plugins and their launchd job

  One launchd job, ${JOBS_LABEL}: a resident agent that runs the plugins whose triggers match on
  screen unlock (a distributed notification only a resident observer can hear), at login and every
  ${JOBS_INTERVAL_SECONDS}s. A plugin is an executable in ${JOBS_ROOT_DF} (shared) or
  ${JOBS_ROOT_LDF} (this machine) whose header has '# triggers: unlock load' and any
  '# cron: m h dom mon dow' lines; it gets the trigger as \$1; the engine posts a banner when it ends
  (an alert, click opens the log, on failure). The README beside the shared plugins has the contract.

  list               every plugin, its triggers, last run and rc (the default)
  run NAME           run one plugin now (trigger 'manual', or --trigger T); output to its log and stdout
  tick --trigger T   what the agent runs: every plugin due for T (load, tick, screenIsUnlocked)
  unlock             simulate a screen unlock (SIGUSR1 to the resident agent)
  install|uninstall  the launchd job (init runs install); --dry-run applies

  Logs and success stamps: ${JOBS_STATE_DIR}.
EOF
}

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

# The agent's pid from launchd, or nothing when the job is not running.
jobs_agent_pid() {
  local pid
  pid="$(launchctl print "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null | awk '/^[[:space:]]*pid = /{print $3; exit}')"
  [[ "${pid}" == <-> ]] && print -r -- "${pid}"
}

#######################################
# Run one job for a trigger. Its output goes to ~/.local/state/dotfiles/jobs/<name>.log
# (plain text, the previous run in .log.bak.1) and to stdout; the run touches the stamp the
# cron due check reads and records its rc beside it. One log line here either way, and a
# notification from jobs_notify_finish: the engine reports every ending, so a plugin need not.
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
  local took; took="$(elapsed "${start}")"
  if (( rc == 0 )); then
    log::info "job ok | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' took='${took}s' log='${logfile}'"
  elif (( rc == 124 )); then
    log::err "job timed out | name='${name}' tier='${JOB_TIER[${name}]}' trigger='${trigger}' limit='${limit}s' log='${logfile}'"
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
  local pid; pid="$(jobs_agent_pid)"
  if [[ -n "${pid}" ]]; then
    print -r -- "  agent: running (pid ${pid}); 'dotfiles jobs unlock' simulates an unlock"
  elif launchctl print "gui/$(id -u)/${JOBS_LABEL}" >/dev/null 2>&1; then
    print -r -- "  agent: ${c_yellow}loaded but not running${c_rst} (launchd restarts it; see ${JOBS_STATE_DIR}/launchd.err.log)"
  else
    print -r -- "  agent: ${c_red}not loaded${c_rst} (dotfiles jobs install)"
  fi
}

# --- notifications: the engine reports how every job ended, so no plugin can forget to ---

# terminal-notifier, probed by absolute path (probe_tool) because launchd's PATH may lack
# Homebrew. Without it there is no banner: an osascript banner cannot be removed and would sit
# in Notification Center forever.
jobs_notifier_bin() {
  local tn
  tn="$(probe_tool terminal-notifier)"
  [[ -n "${tn}" ]] || return 1
  print -r -- "${tn}"
}

# terminal-notifier with the given arguments, output discarded, killed after
# JOBS_NOTIFIER_TIMEOUT_SECONDS. The watchdog holds no descriptor and its sleep dies with it,
# or a caller's pipe stays open. Returns its rc, or 124 on the timeout.
jobs_notify() {
  local tn pid watchdog rc=0
  tn="$(jobs_notifier_bin)" || return 1
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

# The command a failure alert's click runs: the job's log in a new tmux window on the user's
# default server (launchd has no $TMUX, so the socket path is derived), else in Terminal.
# Absolute paths throughout: the click runs under /bin/sh with launchd's PATH.
jobs_click_command() {
  local logfile="${1}" sock="/private/tmp/tmux-$(id -u)/default" tmux_bin editor_bin
  tmux_bin="$(command -v tmux 2>/dev/null || true)"
  [[ -z "${tmux_bin}" && -x /opt/homebrew/bin/tmux ]] && tmux_bin=/opt/homebrew/bin/tmux
  editor_bin="$(command -v "${${EDITOR:-vi}%% *}" 2>/dev/null || command -v vi)"
  if [[ -S "${sock}" && -n "${tmux_bin}" ]]; then
    print -r -- "${(q)tmux_bin} -S ${(q)sock} new-window -n dotfiles-jobs-log ${(q)editor_bin} + ${(q)logfile}"
  else
    print -r -- "/usr/bin/open -a Terminal ${(q)logfile}"
  fi
}

#######################################
# Tell the user how a job ended. Success: a JOBS_HUD_SECONDS banner (post, sleep, remove by
# group; macOS gives banners no duration control) carrying the plugin's last output line, so a
# plugin's summary is what it prints last; any earlier failure alert for the job comes down.
# Failure or timeout: a persistent alert, one per job (its group), whose click opens the log.
# Arguments: name, rc, took, logfile
#######################################
jobs_notify_finish() {
  local name="${1}" rc="${2}" took="${3}" logfile="${4}" last verdict
  jobs_notifier_bin >/dev/null || return 0
  last="$(grep -v -E '^# |^[[:space:]]*$' "${logfile}" 2>/dev/null | tail -n 1 | cut -c1-140)"
  if (( rc == 0 )); then
    jobs_notify -remove "dotfiles-jobs-${name}" || true
    jobs_notify -group dotfiles-jobs -title "dotfiles jobs" -message "${name} ok in ${took}s${last:+ · ${last}}" || return 0
    sleep "${JOBS_HUD_SECONDS}"
    jobs_notify -remove dotfiles-jobs || true
    return 0
  fi
  verdict="failed (rc ${rc})"; (( rc == 124 )) && verdict="timed out"
  jobs_notify -group "dotfiles-jobs-${name}" -title "dotfiles jobs: ${name} ${verdict}" \
    -message "${last:-no output} — click to open the log" -execute "$(jobs_click_command "${logfile}")" || true
}

# --- the launchd job ---

#######################################
# Write and compile the agent, the job's program, which launchd keeps alive. macOS posts the
# screen-unlock event only as a distributed notification (NSDistributedNotificationCenter),
# which launchd's LaunchEvents cannot subscribe to and notifyutil never sees, so a resident
# observer is the only way to hear it. The agent also owns the timer and the load run, and
# serializes every run. Compiled only when the source changed.
# Globals: JOBS_AGENT_BIN
#######################################
jobs_write_agent() {
  local src="${JOBS_AGENT_BIN}.c" rendered
  mkdir -p "${JOBS_AGENT_BIN:h}"
  rendered="$(mktemp)"
  cat >"${rendered}" <<'CSRC'
// dotfiles-jobs-agent <harness> <interval-seconds> <unlock-notification>
// Generated and compiled by `dotfiles jobs install` (see dotfiles/lib/jobs.zsh); launchd keeps
// it alive as the dotfiles jobs job's program. It runs
//     /bin/zsh <harness> jobs tick --trigger <tag>
// once at start (load), on every <unlock-notification> from the distributed notification
// center (screenIsUnlocked), every <interval-seconds> (tick), and on SIGUSR1 (screenIsUnlocked
// again, so `dotfiles jobs unlock` can simulate an unlock). Runs are serialized: an event that
// arrives during a run is delivered after it. A timer missed asleep fires once on wake.
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
static const char *g_harness;

static void run(const char *tag) {
    char *argv[] = {"/bin/zsh", (char *)g_harness, "jobs", "tick", "--trigger", (char *)tag, NULL};
    pid_t pid;
    int rc = posix_spawn(&pid, "/bin/zsh", NULL, NULL, argv, environ);
    if (rc != 0) {
        fprintf(stderr, "dotfiles-jobs-agent: spawn failed: %s\n", strerror(rc));
        return;
    }
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
}

static void on_unlock(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef ui) {
    (void)c; (void)o; (void)n; (void)obj; (void)ui;
    run("screenIsUnlocked");
}

static void on_timer(CFRunLoopTimerRef t, void *info) {
    (void)t; (void)info;
    run("tick");
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <harness> <interval-seconds> <unlock-notification>\n", argv[0]);
        return 2;
    }
    g_harness = argv[1];
    double interval = atof(argv[2]);
    if (interval < 1) {
        interval = 300;
    }
    CFStringRef name = CFStringCreateWithCString(NULL, argv[3], kCFStringEncodingUTF8);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), NULL, on_unlock, name, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0, on_timer, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);
    // SIGUSR1 simulates an unlock; the handler runs on the main queue, which the run loop drains.
    signal(SIGUSR1, SIG_IGN);
    dispatch_source_t usr1 = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(usr1, ^{ run("screenIsUnlocked"); });
    dispatch_resume(usr1);
    run("load");
    CFRunLoopRun();
    return 0;
}
CSRC
  if [[ -x "${JOBS_AGENT_BIN}" ]] && cmp -s "${rendered}" "${src}"; then
    rm -f "${rendered}"; jobs_agent_changed=0; log::info "agent current | bin='${JOBS_AGENT_BIN}'"; return 0
  fi
  if ! command -v cc >/dev/null 2>&1; then
    rm -f "${rendered}"
    log::err "no C compiler; the jobs agent needs the Command Line Tools | fix='xcode-select --install'"; return 1
  fi
  mv "${rendered}" "${src}"
  cc -O2 -Wall -Wextra -framework CoreFoundation -o "${JOBS_AGENT_BIN}" "${src}"
  jobs_agent_changed=1
  log::info "compiled agent | bin='${JOBS_AGENT_BIN}'"
}

#######################################
# Render the plist through jq + plutil (jq escapes every value; plutil rejects malformed
# output) and install it only when it differs. Sets jobs_plist_changed for the caller. The
# agent is the program and launchd keeps it alive; it owns the unlock observer and the timer.
# Globals: JOBS_*, jobs_plist_changed
#######################################
jobs_write_plist() {
  local rendered
  rendered="$(mktemp)"
  jq -n \
    --arg label "${JOBS_LABEL}" --arg agent "${JOBS_AGENT_BIN}" --arg harness "${HOME}/.config/bin/dotfiles" \
    --arg interval "${JOBS_INTERVAL_SECONDS}" --arg notification "${JOBS_UNLOCK_NOTIFICATION}" \
    --arg path "${JOBS_LAUNCHD_PATH}" \
    --arg out "${JOBS_STATE_DIR}/launchd.out.log" --arg err "${JOBS_STATE_DIR}/launchd.err.log" \
    '{
      Label: $label,
      ProgramArguments: [$agent, $harness, $interval, $notification],
      RunAtLoad: true,
      KeepAlive: true,
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
# and their plists removed; the agent is compiled and the plist written only on change; the
# job is restarted only when one of them changed (a running agent is the old binary until it
# is), since a bootout + bootstrap runs the load tick again.
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
  if is_dry_run; then
    log::info "dry-run, would compile the agent, write the plist and bootstrap, each only if changed | label='${JOBS_LABEL}' plist='${JOBS_PLIST}'"; return 0
  fi
  mkdir -p "${JOBS_STATE_DIR}"
  rm -f "${JOBS_STATE_DIR}"/bin/launch-event-consume(N) "${JOBS_STATE_DIR}"/bin/launch-event-consume.c(N)   # the pre-agent helper
  local jobs_agent_changed=1 jobs_plist_changed=1
  jobs_write_agent || return 1
  jobs_write_plist
  if (( jobs_plist_changed == 0 && jobs_agent_changed == 0 )) && launchctl print "gui/$(id -u)/${JOBS_LABEL}" >/dev/null 2>&1; then
    log::info "jobs launchd job current | label='${JOBS_LABEL}'"; return 0
  fi
  launchctl bootout "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "${JOBS_PLIST}"
  log::info "installed jobs launchd job | label='${JOBS_LABEL}' triggers='${JOBS_UNLOCK_NOTIFICATION}, login, every ${JOBS_INTERVAL_SECONDS}s' logs='${JOBS_STATE_DIR}'"
}

jobs_uninstall() {
  launchctl bootout "gui/$(id -u)/${JOBS_LABEL}" 2>/dev/null || true
  rm -f "${JOBS_PLIST}"
  log::info "removed jobs launchd job | label='${JOBS_LABEL}'"
}

# Simulate a screen unlock: SIGUSR1 to the agent, which runs the unlock tick as if the
# distributed notification had arrived. Only a real lock and unlock proves the observer itself.
jobs_simulate_unlock() {
  local pid; pid="$(jobs_agent_pid)"
  if [[ -z "${pid}" ]]; then log::err "agent not running | fix='dotfiles jobs install'"; return 1; fi
  kill -USR1 "${pid}" && log::info "unlock simulated | agent_pid='${pid}' watch='${JOBS_STATE_DIR}/launchd.err.log'"
}

# --- command ---

cmd_jobs() {
  local sub="${1:-list}" trigger=manual name=""
  (( $# > 0 )) && shift
  while (( $# > 0 )); do case "${1}" in
    --trigger) trigger="${2:?--trigger requires a value}"; shift 2 ;;
    --dry-run) export DOTFILES_DRY_RUN=1; shift ;;
    -*) usage_error "Unknown jobs flag | flag='${1}'" ;;
    *) name="${1}"; shift ;;
  esac; done
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
    *) log::err "Unknown jobs subcommand | sub='${sub}' valid='list, run <name>, tick, unlock, install, uninstall'"; return 1 ;;
  esac
}
