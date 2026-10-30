#!/usr/bin/env zsh
# Type one command into a tmux pane, on this machine or a remote host, wait for the shell prompt, print the pane.
# Refuses to type into a pane that is not an idle shell at its prompt.
# Hosts are remembered as definitions under the XDG data dir, so a run names a definition, not a host.
# Run: zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --help

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# Sourced here for the command checks, and prepended to the host script so the gate, the exact pane
# lookup and the lock run the same on every host as on a click (focus.zsh).
readonly LIB_TMUX_PANE="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/lib/tmux-pane.sh"
if [[ ! -r "${LIB_TMUX_PANE}" ]]; then
  log::err "Missing tmux pane lib | path='${LIB_TMUX_PANE}'"
  exit 1
fi
source "${LIB_TMUX_PANE}"

# --- Constants ---

readonly POLL_SECONDS=5
readonly DEFAULT_TIMEOUT=90   # under the Bash tool's 120 s default, so exit 124 reaches the caller
readonly DEFAULT_LINES=60
readonly EXIT_TIMEOUT=124
readonly EXIT_NO_TARGET=70
readonly EXIT_BUSY=75   # EX_TEMPFAIL: the pane is not an idle shell at its prompt; nothing was typed
readonly EXIT_NOT_OPTED_IN=77   # EX_NOPERM: the pane's OPT_IN_OPTION is not on; nothing was typed
# Ari marks a pane typeable with `ari-driving on` in it, which sets this pane option. The window option of
# the same name is display only (the ✦ in the status bar); the gate reads the pane option alone.
readonly OPT_IN_OPTION=@ari_driving
readonly OPT_IN_COMMAND='ari-driving on'
# A driven pane belongs to the Claude session that first typed into it. `ari-driving on` also stamps the pane
# with the grant's epoch; a stamp newer than the binding's is Ari granting the pane afresh, and only that rebinds.
readonly EXIT_BOUND_ELSEWHERE=76   # the pane is bound to another Claude session; nothing was typed
readonly STAMP_OPTION=@ari_driving_since
readonly SESSION_ID="${CLAUDE_CODE_SESSION_ID:-}"
# One file per bound pane under <definition>/<pane number>: 'session=<id>' and 'since=<stamp>'.
readonly BINDINGS_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/ari-driving-remote/bindings"
# How every message names a pane: 'ID=%301|pane=2.4', pane ID then window.pane. No spaces, so it is one field.
readonly PANE_LABEL_FORMAT='ID=#{pane_id}|pane=#{window_index}.#{pane_index}'
readonly EXIT_SSH=255
readonly EXIT_NOT_FOUND=127
# Where the dotfiles put run_log on any of Ari's machines; checked on the host before wrapping.
readonly HOST_RUN_LOG='$HOME/.config/bin/run_log'
readonly DEFAULT_PATH_PREFIX=/opt/homebrew/bin
readonly DEFAULT_PROMPT_END='❯'
readonly SSH_OPTS=(-o ConnectTimeout=8 -o BatchMode=yes -o ServerAliveInterval=10 -o ServerAliveCountMax=3)
# A definition whose host is this value runs tmux on this machine instead of over ssh.
readonly LOCAL_HOST=local
# Every machine's everyday name, one word, as the host's dotfiles print it (stdout only the name;
# a host without the verb fails on stderr).
readonly HOST_MACHINE_NAME_CMD='"$HOME/.config/bin/dotfiles" machine-name'
readonly PANE_ID_PATTERN='%<0->'
# Ari's friendly address from prefix-q display-panes: window.pane in his current session.
readonly FRIENDLY_PATTERN='<0->.<0->'
# Last non-blank line of the pane, trailing whitespace removed (awk: BSD and GNU agree).
readonly AWK_LAST_LINE='{sub(/[[:space:]]+$/,"")} NF {l=$0} END {print l}'
readonly AWK_NONBLANK='{sub(/[[:space:]]+$/,"")} NF'
# `--list` lines are 'ID=%301|pane=2.4 ✦|- bound=this|other|none zsh session: window_name -- pane_title', one per
# pane; ✦ marks an opted-in pane, bound= which Claude session owns it. The host script fills the opt-in mark and
# the grant stamp per pane (in a format, a pane option inherits the window's); the stamp becomes bound= here.
readonly TMUX_LIST_FORMAT="${PANE_LABEL_FORMAT} #{pane_current_command} #{session_name}: #{window_name} -- #{pane_title}"
# Heads the inventory a "no pane matches" refusal carries: TMUX_LIST_FORMAT lines without the opt-in
# column, so it costs one list-panes and no per-pane lookups.
readonly INVENTORY_HEADER='PANES: every pane on the host, label command session: window -- title'
# Saved hint per pane: the label alone, 'ID=%301|pane=2.4'.
readonly AWK_WINDOW_NAMES='{print $1}'
readonly WINDOWS_SEPARATOR=' | '

# One file per definition, key=value lines in DEFINITION_KEYS order. The file name is the definition name.
readonly HOSTS_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/ari-driving-remote/hosts"
# Where definitions lived before; a cache sweep could delete what Ari said about a host. Moved on the next run.
readonly OLD_HOSTS_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/ari-driving-remote/hosts"
readonly DEFINITION_KEYS=(host path_prefix prompt_end windows last_seen description)

# The one remote host every session starts from. Written when no definition exists.
readonly SEED_NAME=laptop
readonly SEED_HOST=arisweedler@Aris-MacBook-Pro.local
readonly SEED_DESCRIPTION="Ari's personal MacBook, session 0. The only machine with an ssh key on the Pi: reach ads@ganymede.local from it with a nested ssh -t."
# This machine. Written whenever it is missing.
readonly LOCAL_NAME=local
readonly LOCAL_DESCRIPTION="This machine: tmux runs directly, no ssh."

# --- Prerequisites ---

#######################################
# Check that ssh, awk and date are installed.
# Returns: 1 if any is missing
#######################################
check_prerequisites() {
  local missing=() cmd
  for cmd in ssh awk date; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Help ---

help() {
  cat <<EOF
${c_green}run.zsh${c_rst} — type a command into a tmux pane (this machine or over ssh), wait for the shell prompt, print the pane

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --hosts
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition NAME --list
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition NAME --target 2.4 --cmd TEXT [OPTIONS]
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition NAME [--host USER@HOST] --describe TEXT
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition NAME --forget

A ${c_bold}definition${c_rst} is a file under ${HOSTS_DIR}: the host's user@host (or '${LOCAL_HOST}' for
this machine, no ssh), PATH prefix, shell-prompt end, the panes seen on the last --list, when it last
answered, and a description. --host-definition fills --host, --path-prefix and --prompt-end from it;
an explicit flag wins. The first --describe, --list or --cmd on a new NAME writes it. '${LOCAL_NAME}' is always seeded.
Definitions still under ${OLD_HOSTS_DIR} are moved there on the next run.

Before typing, --cmd refuses unless the pane option ${OPT_IN_OPTION} is on (Ari runs '${OPT_IN_COMMAND}' in that
pane), the pane is not in copy mode or synchronized, its foreground command is a shell, and its last line ends
in the prompt. TEXT is one line, with no control characters, no leading clear, no pbcopy, and nothing that spells
the opt-in ('${OPT_IN_COMMAND}', 'ari-remote-tmux on' or ${OPT_IN_OPTION}, case and quotes ignored, a new pane's
startup command included); any of those exits 1 before connecting. Claude never sets the opt-in, by any route.
Panes are named 'ID=%301|pane=2.4'.
After typing it prints 'TYPED: <the exact text sent>' and, once Enter is sent (or skipped), 'SENT'.

A pane is bound to the Claude session (\$CLAUDE_CODE_SESSION_ID) that first types into it, in
${BINDINGS_DIR}/<definition>/<pane>; another session is refused with ${EXIT_BOUND_ELSEWHERE} and types nothing.
Only Ari rebinds, by running '${OPT_IN_COMMAND}' there again (it stamps ${STAMP_OPTION}); no flag does. --list
shows each pane's owner as bound=this|other|none and drops bindings of panes that are gone or regranted.
Captures ('' TEXT) and --list are never bound.

${c_bold}Actions${c_rst} (exactly one):
  --hosts                 print every definition as name= plus its key=value lines
  --list                  print every pane as 'ID=%301|pane=2.4 ✦|- bound=this|other|none command session: window -- title'
                          (✦ = opted in; bound = which Claude session owns it), save them
  --cmd TEXT              gate, type TEXT into --target, wait for the shell prompt; '' types nothing and only captures
  --describe TEXT         replace the definition's description without connecting
  --forget                print the definition and delete it

${c_bold}Options:${c_rst}
  --host-definition NAME  definition to use (required unless --hosts)
  --host USER@HOST        ssh destination ('${LOCAL_HOST}' for this machine), saved onto a new definition; on an existing one needs --re-point
  --re-point              allow --host to change an existing definition (its panes and last_seen reset)
  --target W.P|%N|S:W[.P]  pane: Ari's window.pane (2.4, matched exactly), a %pane_id, or session:window[.pane] (required with --cmd)
  --session S             session a window.pane target is looked up in (default: the most recently active client's)
  --no-enter              type without pressing Enter (Ari presses it)
  --no-run-log            type the command bare; by default it is typed as run_log '<cmd>' when the host
                          has ${HOST_RUN_LOG}, so the capture lands in the host's /tmp/run_log
  --no-wait               return right after typing instead of waiting for the shell prompt
  --lines N               pane lines to print (default: ${DEFAULT_LINES})
  --timeout S             seconds to wait for the shell prompt, at least ${POLL_SECONDS} (default: ${DEFAULT_TIMEOUT});
                          set the Bash tool's timeout above it
  --path-prefix DIR       prepended to PATH on the host so tmux resolves (default: ${DEFAULT_PATH_PREFIX}; '' for none)
  --prompt-end STR        what the idle shell-prompt line ends with (default: ${DEFAULT_PROMPT_END})
  --dry-run               print the host script, or the definition that would be written, and change nothing
  -h, --help              show this help

${c_bold}Exit codes:${c_rst}
  0    the shell prompt returned
  ${EXIT_TIMEOUT}  still running (timed out, --no-wait, or ssh dropped after SENT); the pane is printed; never resend
  ${EXIT_NO_TARGET}   no pane matches the target, or no attached client to resolve a window.pane against (--session);
       every pane on the host is printed under the refusal, so the right one can be picked without --list
  ${EXIT_BUSY}   pane in copy mode, synchronized, not a shell, or not at an empty prompt, or another caller is typing (nothing typed)
  ${EXIT_NOT_OPTED_IN}   pane not opted in (nothing typed)
  ${EXIT_BOUND_ELSEWHERE}   pane bound to another Claude session (nothing typed); get a pane of your own
  ${EXIT_NOT_FOUND}  tmux not found on the host (--path-prefix)
  ${EXIT_SSH}  ssh could not connect before anything was typed

${c_bold}Examples:${c_rst}
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition local --list
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition local --target 2.4 --no-enter --cmd 'kubectl get pods'
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target 4.1 --cmd 'diskutil list external physical'
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %7 --cmd ''
  zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --host pi@pi.local --describe 'Pi 4 B at 192.0.2.94, no tmux; reached from the laptop with a nested ssh -t'
EOF
}

# --- Host definitions ---
# `def` is an associative array declared in main and filled by load_definition.

#######################################
# Path of a definition file.
# Globals: HOSTS_DIR
# Arguments: $1 name
# Returns: the path on stdout
#######################################
definition_file() {
  print -r -- "${HOSTS_DIR}/${1}"
}

#######################################
# Names of every definition, one per line; nothing when none exists.
# Globals: HOSTS_DIR
#######################################
definition_names() {
  local file
  for file in "${HOSTS_DIR}"/*(N); do print -r -- "${file:t}"; done
}

#######################################
# Known names as one comma-separated string, for error messages.
#######################################
known_names() {
  print -r -- "${(j:, :)${(f)"$(definition_names)"}}"
}

#######################################
# Load a definition into def (every key present, missing ones empty).
# Blank lines, lines without '=' and CR line endings are tolerated.
# Globals: def (written)
# Arguments: $1 name
# Returns: 1 when the file does not exist
#######################################
load_definition() {
  local name="${1}" file line key value
  file="$(definition_file "${name}")"
  for key in "${DEFINITION_KEYS[@]}"; do def[${key}]=""; done
  [[ -r "${file}" ]] || return 1
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    [[ -n "${line}" ]] || continue
    if [[ "${line}" != *=* ]]; then
      log::warn "Ignoring line without '=' | name='${name}' line='${line}'"
      continue
    fi
    key="${line%%=*}" value="${line#*=}"
    if (( ${DEFINITION_KEYS[(Ie)${key}]} == 0 )); then
      log::warn "Ignoring unknown key | name='${name}' key='${key}' known='${(j:, :)DEFINITION_KEYS}'"
      continue
    fi
    def[${key}]="${value}"
  done < "${file}"
}

#######################################
# Write def to the definition file atomically. Newlines in values are flattened.
# Globals: HOSTS_DIR, def (read)
# Arguments: $1 name  $2 dry_run(true|false)
# Returns: 1 when the hosts dir is not writable
#######################################
save_definition() {
  local name="${1}" dry_run="${2}" file tmp key body=""
  file="$(definition_file "${name}")"
  for key in "${DEFINITION_KEYS[@]}"; do
    body+="${key}=${def[${key}]//$'\n'/ }"$'\n'
  done
  if [[ "${dry_run}" == "true" ]]; then
    log::info "Dry run — would write definition | name='${name}' file='${file}'"
    print -rn -- "${body}"
    return 0
  fi
  mkdir -p "${HOSTS_DIR}" 2>/dev/null || { log::err "Hosts dir not writable | dir='${HOSTS_DIR}'"; return 1; }
  tmp="$(mktemp "${HOSTS_DIR}/.${name}.XXXXXX")" || { log::err "Hosts dir not writable | dir='${HOSTS_DIR}'"; return 1; }
  trap 'rm -f "${tmp}"' EXIT
  print -rn -- "${body}" > "${tmp}"
  mv -f "${tmp}" "${file}"
  trap - EXIT
  log::info "Saved definition | name='${name}' host='${def[host]}' file='${file}'"
}

#######################################
# Current time, UTC, for last_seen.
# Returns: ISO-8601 on stdout
#######################################
now_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

#######################################
# Move definitions from the old cache dir into HOSTS_DIR, once: a name already in HOSTS_DIR wins,
# and the old dir goes when it is empty.
# Globals: OLD_HOSTS_DIR HOSTS_DIR
#######################################
migrate_definitions() {
  local file
  local -a old_files=("${OLD_HOSTS_DIR}"/*(N))
  if (( ${#old_files} == 0 )); then
    return 0
  fi
  mkdir -p "${HOSTS_DIR}" 2>/dev/null || { log::warn "Hosts dir not writable; reading nothing from the old dir | dir='${HOSTS_DIR}'"; return 0; }
  for file in "${old_files[@]}"; do
    if [[ -e "${HOSTS_DIR}/${file:t}" ]]; then
      log::warn "Definition exists in both dirs; keeping the new one | name='${file:t}' old='${file}'"
      continue
    fi
    mv -n -- "${file}" "${HOSTS_DIR}/${file:t}"
    log::info "Moved definition | name='${file:t}' from='${OLD_HOSTS_DIR}' to='${HOSTS_DIR}'"
  done
  rmdir "${OLD_HOSTS_DIR}" 2>/dev/null || true
}

#######################################
# Write the seed definition when no definition exists, so the first session has a host.
# Globals: SEED_*, DEFAULT_*, def (written)
#######################################
seed_definitions() {
  local key
  migrate_definitions
  if [[ -z "$(definition_names)" ]]; then
    log::info "No definitions — seeding | name='${SEED_NAME}' host='${SEED_HOST}' hosts_dir='${HOSTS_DIR}'"
    for key in "${DEFINITION_KEYS[@]}"; do def[${key}]=""; done
    def[host]="${SEED_HOST}" def[path_prefix]="${DEFAULT_PATH_PREFIX}" def[prompt_end]="${DEFAULT_PROMPT_END}"
    def[description]="${SEED_DESCRIPTION}"
    save_definition "${SEED_NAME}" false
  fi
  if [[ -r "$(definition_file "${LOCAL_NAME}")" ]]; then
    return 0
  fi
  log::info "No local definition — seeding | name='${LOCAL_NAME}' hosts_dir='${HOSTS_DIR}'"
  for key in "${DEFINITION_KEYS[@]}"; do def[${key}]=""; done
  def[host]="${LOCAL_HOST}" def[path_prefix]="${DEFAULT_PATH_PREFIX}" def[prompt_end]="${DEFAULT_PROMPT_END}"
  def[description]="${LOCAL_DESCRIPTION}"
  save_definition "${LOCAL_NAME}" false
}

#######################################
# Print every definition: a name= line, the file's own key=value lines, a blank line.
# Globals: HOSTS_DIR
#######################################
print_definitions() {
  local name
  for name in ${(f)"$(definition_names)"}; do
    print -r -- "name=${name}"
    cat "$(definition_file "${name}")"
    print
  done
}

#######################################
# Resolve host, path_prefix and prompt_end from the definition unless a flag set them.
# An unknown name needs --host, which creates it. A different --host on a known name needs --re-point.
# Globals: def (loaded), host path_prefix prompt_end (set), host_set path_prefix_set prompt_end_set re_point (read)
# Arguments: $1 name
# Returns: 1 on an unknown name without --host, or a re-point without --re-point
#######################################
resolve_definition() {
  local name="${1}"
  if ! load_definition "${name}"; then
    if [[ "${host_set}" == "false" ]]; then
      log::err "Unknown host definition | name='${name}' known='$(known_names)' hint='add --host user@host to create it, or --hosts to read the known ones'"
      return 1
    fi
    log::info "New host definition | name='${name}' host='${host}'"
    return 0
  fi
  if [[ "${host_set}" == "true" && "${host}" != "${def[host]}" ]]; then
    if [[ "${re_point}" == "false" ]]; then
      log::err "Definition already has a host | name='${name}' saved='${def[host]}' given='${host}' hint='drop --host, or add --re-point to change it'"
      return 1
    fi
    log::warn "Re-pointing definition | name='${name}' from='${def[host]}' to='${host}'"
    def[windows]="" def[last_seen]=""
  fi
  if [[ "${host_set}" == "false" ]]; then host="${def[host]}"; fi
  if [[ "${path_prefix_set}" == "false" ]]; then path_prefix="${def[path_prefix]}"; fi
  if [[ "${prompt_end_set}" == "false" ]]; then prompt_end="${def[prompt_end]}"; fi
  log::info "Using host definition | name='${name}' host='${host}' path_prefix='${path_prefix}' prompt_end='${prompt_end}'"
}

#######################################
# Fold the resolved flags into def and save; windows and description only when given.
# Globals: def (updated), host path_prefix prompt_end (read)
# Arguments: $1 name  $2 dry_run  $3 windows ('' keeps)  $4 description ('' keeps)  $5 touch_last_seen(true|false)
#######################################
record_definition() {
  local name="${1}" dry_run="${2}" windows="${3}" description="${4}" touch_last_seen="${5}"
  def[host]="${host}" def[path_prefix]="${path_prefix}" def[prompt_end]="${prompt_end}"
  if [[ -n "${windows}" ]]; then def[windows]="${windows}"; fi
  if [[ -n "${description}" ]]; then
    if [[ -n "${def[description]}" && "${def[description]}" != "${description}" ]]; then
      log::warn "Replacing description | name='${name}' previous='${def[description]}'"
    fi
    def[description]="${description}"
  fi
  if [[ "${touch_last_seen}" == "true" ]]; then def[last_seen]="$(now_utc)"; fi
  save_definition "${name}" "${dry_run}"
}

#######################################
# Print the definition, then delete its file.
# Arguments: $1 name  $2 dry_run
#######################################
forget_definition() {
  local name="${1}" dry_run="${2}" file
  file="$(definition_file "${name}")"
  print -r -- "name=${name}"
  cat "${file}"
  if [[ "${dry_run}" == "true" ]]; then
    log::info "Dry run — would delete definition | name='${name}' file='${file}'"
    return 0
  fi
  rm -f -- "${file}"
  log::info "Deleted definition | name='${name}' file='${file}'"
}

# --- Pane bindings ---

#######################################
# Path of a pane's binding file: the definition's dir, the pane number without its %.
# Globals: BINDINGS_DIR
# Arguments: $1 definition name  $2 pane id (%N)
# Returns: the path on stdout
#######################################
binding_file() {
  print -r -- "${BINDINGS_DIR}/${1}/${2#%}"
}

#######################################
# Every binding of a definition, one '%N session since' line each, for the host script's lookup and --list.
# Globals: BINDINGS_DIR
# Arguments: $1 definition name
#######################################
bindings_of() {
  local name="${1}" file key value session since
  for file in "${BINDINGS_DIR}/${name}"/*(N); do
    session="" since=0
    while IFS='=' read -r key value; do
      case "${key}" in
        session) session="${value}" ;;
        since) since="${value}" ;;
      esac
    done < "${file}"
    [[ -n "${session}" ]] || continue
    print -r -- "%${file:t} ${session} ${since:-0}"
  done
}

#######################################
# Record that this session owns a pane, with the grant stamp it saw there.
# Globals: SESSION_ID
# Arguments: $1 definition name  $2 pane id  $3 since
#######################################
write_binding() {
  local name="${1}" pane="${2}" since="${3}" file
  file="$(binding_file "${name}" "${pane}")"
  mkdir -p "${file:h}" 2>/dev/null || { log::warn "Bindings dir not writable; the pane stays unbound | dir='${file:h}'"; return 0; }
  print -r -- "session=${SESSION_ID}"$'\n'"since=${since}" > "${file}"
  log::info "Pane bound to this session | pane='${pane}' since='${since}'"
}

#######################################
# Forget a binding: its pane is gone, or Ari granted the pane afresh.
# Arguments: $1 definition name  $2 pane id  $3 why
#######################################
drop_binding() {
  local name="${1}" pane="${2}" why="${3}"
  rm -f -- "$(binding_file "${name}" "${pane}")"
  log::info "Dropped binding | pane='${pane}' why='${why}'"
}

#######################################
# Turn the host's list lines ('label mark since rest') into the printed form ('label mark bound=… rest'),
# dropping bindings whose pane is gone or whose stamp is older than the pane's (Ari regranted it).
# Globals: SESSION_ID
# Arguments: $1 definition name  $2 host output
# Returns: the printed lines on stdout
#######################################
list_with_owners() {
  local name="${1}" output="${2}" line label mark since rest pane state
  local -A bound_session bound_since
  local -a parts shown
  for line in ${(f)"$(bindings_of "${name}")"}; do
    parts=(${=line})
    bound_session[${parts[1]}]="${parts[2]}" bound_since[${parts[1]}]="${parts[3]}"
  done
  for line in ${(f)output}; do
    label="${line%% *}" rest="${line#* }"
    mark="${rest%% *}" rest="${rest#* }"
    since="${rest%% *}" rest="${rest#* }"
    pane="${${label#*ID=}%%|*}"
    shown+=("${pane}")
    state=none
    if [[ -n "${bound_session[${pane}]:-}" ]]; then
      if (( since > ${bound_since[${pane}]:-0} )); then
        drop_binding "${name}" "${pane}" "Ari granted the pane afresh"
      elif [[ "${bound_session[${pane}]}" == "${SESSION_ID}" ]]; then
        state=this
      else
        state=other
      fi
    fi
    print -r -- "${label} ${mark} bound=${state} ${rest}"
  done
  for pane in ${(k)bound_session}; do
    (( ${shown[(Ie)${pane}]} )) || drop_binding "${name}" "${pane}" "pane gone"
  done
}

# --- Host script ---

#######################################
# Set sh variable `prefix` to 'machine=<name>|' for a remote host (its `dotfiles machine-name`,
# else the definition name), so its panes are never mistaken for this machine's; '' for this machine.
# Globals: host name LOCAL_HOST HOST_MACHINE_NAME_CMD
# Returns: the script lines on stdout
#######################################
machine_block() {
  if [[ "${host}" == "${LOCAL_HOST}" ]]; then
    print -r -- "prefix=''"
    return 0
  fi
  print -r -- "machine=\$(${HOST_MACHINE_NAME_CMD} 2>/dev/null); [ -n \"\$machine\" ] || machine=${(qq)name}"
  print -r -- "prefix=\"machine=\$machine|\""
}

#######################################
# The first lines of every host script: PATH, then the tmux checks behind exit codes 127 and 70, so a
# missing tmux or server never reads as "no pane matches".
# Arguments: $1 path_prefix
# Returns: the script lines on stdout
#######################################
prelude_block() {
  local path_prefix="${1}"
  if [[ -n "${path_prefix}" ]]; then print -r -- "export PATH=${(qq)path_prefix}:\$PATH"; fi
  print -r -- "command -v tmux >/dev/null 2>&1 || { echo \"REFUSED: tmux not on PATH=\$PATH\"; exit ${EXIT_NOT_FOUND}; }"
  print -r -- "tmux list-sessions >/dev/null 2>&1 || { echo 'REFUSED: no tmux server on the host'; exit ${EXIT_NO_TARGET}; }"
}

#######################################
# Compose the script that lists every tmux pane on the host.
# Arguments: $1 path_prefix
# Returns: the script on stdout
#######################################
list_script() {
  local path_prefix="${1}"
  prelude_block "${path_prefix}"
  machine_block
  # Splice the pane-only opt-in mark and grant stamp in after the label (the first field, 'ID=%N|pane=W.P').
  print -r -- "tmux list-panes -a -F ${(qq)TMUX_LIST_FORMAT} | while read -r label rest; do"
  print -r -- "  id=\${label%%|*}; id=\${id#ID=}"
  print -r -- "  if [ \"\$(tmux show-options -pqv -t \"\$id\" ${(qq)OPT_IN_OPTION})\" = on ]; then mark='✦'; else mark='-'; fi"
  print -r -- "  since=\$(tmux show-options -pqv -t \"\$id\" ${(qq)STAMP_OPTION}); since=\${since:-0}"
  print -r -- "  printf '%s%s %s %s %s\\n' \"\$prefix\" \"\$label\" \"\$mark\" \"\$since\" \"\$rest\""
  print -r -- "done"
}

#######################################
# One sh line that prints every pane on the host under INVENTORY_HEADER, each with the machine prefix:
# the inventory a "no pane matches" refusal carries, so the caller picks the right pane without --list.
# Globals: INVENTORY_HEADER TMUX_LIST_FORMAT
# Returns: the script line on stdout
#######################################
inventory_line() {
  print -rn -- "echo ${(qq)INVENTORY_HEADER}; tmux list-panes -a -F \"\$prefix\"${(qq)TMUX_LIST_FORMAT}"
}

#######################################
# Resolve the target to a pane ID in sh variable `pane`, and its label in `label`. A friendly 'W.P' is
# looked up in --session, else the most recently active attached client's session. Exact matches only:
# tmux's own target lookup is fuzzy and would land the keys in some other pane. Every run makes this
# check, so a pane that closed since the last run is refused with the host's live pane inventory.
# Arguments: $1 target  $2 session ('' = most recent client's)
# Returns: the script lines on stdout
#######################################
resolve_block() {
  local target="${1}" session="${2}"
  machine_block
  print -r -- "target=${(qq)target}; session=${(qq)session}"
  print -r -- "pane=\$(tmux_resolve_pane \"\$target\" \"\$session\"); rc=\$?"
  print -r -- "case \$rc in"
  print -r -- "  0) ;;"
  print -r -- "  2) echo \"REFUSED: no attached client to resolve \$target against; pass --session\"; $(inventory_line); exit ${EXIT_NO_TARGET} ;;"
  print -r -- "  *) echo \"REFUSED: no pane matches \$target\"; $(inventory_line); exit ${EXIT_NO_TARGET} ;;"
  print -r -- "esac"
  print -r -- "label=\"\$prefix\$(tmux display-message -p -t \"\$pane\" ${(qq)PANE_LABEL_FORMAT})\""
  print -r -- "echo \"PANE: \$label\""
}

#######################################
# The gate before any keys are sent (tmux_pane_gate_refusal: opted in, not in copy mode or synchronized,
# an idle shell, last line ends in the prompt), under the pane's lock so two callers cannot both pass it.
# Any failure prints why plus the pane tail and exits untyped. The lock is released after the send.
# Arguments: $1 quoted_prompt_end  $2 lines
# Returns: the script lines on stdout
#######################################
gate_block() {
  local quoted_prompt_end="${1}" lines="${2}"
  local tail_cmd="tmux capture-pane -p -t \"\$pane\" -S -${lines} | awk ${(qq)AWK_NONBLANK} | tail -n ${lines}"
  print -r -- "tmux_pane_lock \"\$pane\" || { echo \"REFUSED: \$label another caller is typing into it\"; ${tail_cmd}; exit ${EXIT_BUSY}; }"
  print -r -- "trap 'tmux_pane_unlock \"\$pane\"' EXIT"
  print -r -- "reason=\$(tmux_pane_gate_refusal \"\$pane\" ${quoted_prompt_end}); rc=\$?"
  print -r -- "if [ \$rc -ne 0 ]; then echo \"REFUSED: \$label \$reason\"; ${tail_cmd}; exit \$rc; fi"
}

#######################################
# The binding check, after the gate and under the same lock: the pane's grant stamp against this
# definition's bindings. Another session's binding that the stamp does not outdate refuses with
# EXIT_BOUND_ELSEWHERE, untyped. Otherwise 'BIND: <pane> <stamp>' tells the caller to record the pane as
# this session's (new, refreshed, or regranted by Ari).
# Globals: STAMP_OPTION SESSION_ID EXIT_BOUND_ELSEWHERE AWK_NONBLANK
# Arguments: $1 bindings ('%N session since' lines)  $2 lines
# Returns: the script lines on stdout
#######################################
binding_block() {
  local bindings="${1}" lines="${2}"
  local tail_cmd="tmux capture-pane -p -t \"\$pane\" -S -${lines} | awk ${(qq)AWK_NONBLANK} | tail -n ${lines}"
  print -r -- "since=\$(tmux show-options -pqv -t \"\$pane\" ${(qq)STAMP_OPTION}); since=\${since:-0}"
  print -r -- "bound=\$(printf '%s\\n' ${(qq)bindings} | awk -v p=\"\$pane\" '\$1 == p {print \$2, \$3}')"
  print -r -- "bsession=\${bound%% *}; bsince=\${bound##* }; [ -n \"\$bound\" ] || bsince=0"
  print -r -- "if [ -n \"\$bsession\" ] && [ \"\$bsession\" != ${(qq)SESSION_ID} ] && [ \"\$since\" -le \"\$bsince\" ]; then echo \"REFUSED: \$label bound to another Claude session \${bsession%%-*}; get a pane of your own\"; ${tail_cmd}; exit ${EXIT_BOUND_ELSEWHERE}; fi"
  print -r -- "echo \"BIND: \$pane \$since\""
}

#######################################
# The wait part of the remote script: poll until the pane's last line ends in the prompt, or sleep 1.
# Arguments: $1 quoted_target  $2 quoted_prompt_end  $3 wait(true|false)  $4 press_enter(true|false)  $5 timeout
# Returns: the script lines on stdout
#######################################
wait_block() {
  local quoted_target="${1}" quoted_prompt_end="${2}" wait="${3}" press_enter="${4}" timeout="${5}"
  if [[ "${wait}" != "true" || "${press_enter}" != "true" ]]; then
    print -r -- "sleep 1; rc=0"
    return 0
  fi
  local iterations=$(( (timeout + POLL_SECONDS - 1) / POLL_SECONDS ))
  print -r -- "rc=${EXIT_TIMEOUT}; i=0"
  print -r -- "while [ \$i -lt ${iterations} ]; do sleep ${POLL_SECONDS}; i=\$((i+1))"
  print -r -- "  last=\$(tmux capture-pane -p -t ${quoted_target} | awk ${(qq)AWK_LAST_LINE})"
  print -r -- "  case \"\$last\" in *${quoted_prompt_end}) rc=0; break;; esac"
  print -r -- "done"
}

#######################################
# Compose the POSIX sh script the host runs: resolve the target, gate, send keys, poll, capture.
# Every value is embedded single-quoted via ${(qq)…}, so the text crosses
# ssh and tmux without a second round of quoting.
# Arguments:
#   $1 target  $2 cmd  $3 press_enter(true|false)  $4 wait(true|false)
#   $5 lines   $6 timeout  $7 path_prefix  $8 prompt_end  $9 session  $10 run_log(true|false)
#   $11 bindings ('%N session since' lines of this definition)
# Returns: the script on stdout
#######################################
remote_script() {
  local target="${1}" cmd="${2}" press_enter="${3}" wait="${4}"
  local lines="${5}" timeout="${6}" path_prefix="${7}" prompt_end="${8}" session="${9}" run_log="${10}" bindings="${11}"
  local quoted_prompt_end="${(qq)prompt_end}"

  prelude_block "${path_prefix}"
  print -r -- "$(<"${LIB_TMUX_PANE}")"
  resolve_block "${target}" "${session}"
  if [[ -n "${cmd}" ]]; then
    gate_block "${quoted_prompt_end}" "${lines}"
    binding_block "${bindings}" "${lines}"
    print -r -- "typed=${(qq)cmd}"
    if [[ "${run_log}" == "true" ]]; then
      print -r -- "if [ -x \"${HOST_RUN_LOG}\" ]; then typed=${(qq)${:-run_log ${(qq)cmd}}}; else echo \"NOTE: no ${HOST_RUN_LOG} on the host; typed the command bare\"; fi"
    fi
    print -r -- "tmux send-keys -t \"\$pane\" -l -- \"\$typed\" || { echo \"FAILED: send-keys to \$label\"; exit 1; }"
    print -r -- "printf 'TYPED: %s\\n' \"\$typed\""
  fi
  if [[ "${press_enter}" == "true" ]]; then print -r -- "tmux send-keys -t \"\$pane\" Enter || { echo \"FAILED: Enter to \$label\"; exit 1; }"; fi
  if [[ -n "${cmd}" ]]; then
    # From here a dropped connection must not read as "never typed": the caller sees SENT.
    print -r -- "echo SENT"
    print -r -- "sleep 0.2; tmux_pane_unlock \"\$pane\"; trap - EXIT"
  fi
  wait_block '"$pane"' "${quoted_prompt_end}" "${wait}" "${press_enter}" "${timeout}"
  print -r -- "tmux capture-pane -p -t \"\$pane\" -S -${lines} | awk ${(qq)AWK_NONBLANK} | tail -n ${lines}"
  print -r -- "exit \$rc"
}

# --- Actions ---

#######################################
# Run a host script: directly through sh for the local definition, over ssh otherwise.
# Globals: host LOCAL_HOST SSH_OPTS
# Arguments: $1 script
# Returns: the script's exit code
#######################################
execute_script() {
  local script="${1}"
  if [[ "${host}" == "${LOCAL_HOST}" ]]; then
    log::info "Running on this machine | host='${host}'"
    sh -c "${script}"
    return
  fi
  log::info "Running over ssh | host='${host}'"
  ssh "${SSH_OPTS[@]}" "${host}" "${script}"
}

#######################################
# Log what a host-script exit code means for the caller. 0 logs nothing.
# Globals: host target timeout path_prefix OPT_IN_COMMAND
# Arguments: $1 exit_code
#######################################
report_exit() {
  local exit_code="${1}"
  if (( exit_code == 0 )); then
    return 0
  fi
  if (( exit_code == EXIT_TIMEOUT )); then
    log::warn "Shell prompt did not return in time | timeout='${timeout}' hint='still running: capture with --cmd \"\", never resend'"
    return 0
  fi
  if (( exit_code == EXIT_NO_TARGET )); then
    log::err "No pane matches the target, or no attached client to resolve it against | target='${target}' hint='the PANES: lines above are the host right now; pick the pane Ari means from them (a %pane_id or window.pane), or --list for the opt-in marks'"
    return 0
  fi
  if (( exit_code == EXIT_NOT_OPTED_IN )); then
    log::err "Pane not opted in; nothing typed | target='${target}' hint='Ari runs ${OPT_IN_COMMAND} in that pane himself; never type it for him'"
    return 0
  fi
  if (( exit_code == EXIT_BOUND_ELSEWHERE )); then
    log::err "Pane bound to another Claude session; nothing typed | target='${target}' hint='a branch, fork or other session owns it: get a pane of your own; only Ari running ${OPT_IN_COMMAND} there again rebinds it'"
    return 0
  fi
  if (( exit_code == EXIT_BUSY )); then
    log::err "Pane is not an idle shell at its prompt, or another caller is typing; nothing typed | target='${target}' hint='print the command in chat instead; never retry into a busy pane'"
    return 0
  fi
  if (( exit_code == EXIT_NOT_FOUND )); then
    log::err "tmux not found on the host | host='${host}' path_prefix='${path_prefix}' hint=\"--path-prefix '' on Linux, /opt/homebrew/bin on a Mac\""
    return 0
  fi
  if (( exit_code == EXIT_SSH )); then
    log::err "ssh could not connect; nothing was typed | host='${host}' hint='asleep, wrong address, or no key: Ari runs ssh ${host} once in a pane to accept the host key or fix access'"
    return 0
  fi
  log::err "Host script failed | host='${host}' exit_code='${exit_code}'"
}

#######################################
# List the host's panes, print them, save 'ID=%301|pane=2.4' hints to the definition.
# Globals: host path_prefix name dry_run WINDOWS_SEPARATOR AWK_WINDOW_NAMES
# Returns: the host script's exit code
#######################################
list_windows() {
  local script output windows exit_code=0
  script="$(list_script "${path_prefix}")"
  log::info "Listing tmux panes | host='${host}'"
  if [[ "${dry_run}" == "true" ]]; then
    log::info "Dry run — printing the host script, running nothing"
    print -r -- "${script}"
    return 0
  fi
  output="$(execute_script "${script}")" || exit_code=$?
  report_exit "${exit_code}"
  (( exit_code == 0 )) || return "${exit_code}"
  output="$(list_with_owners "${name}" "${output}")"
  print -r -- "${output}"
  windows="${(pj:$WINDOWS_SEPARATOR:)${(f)"$(print -r -- "${output}" | awk "${AWK_WINDOW_NAMES}")"}}"
  record_definition "${name}" false "${windows}" "" true
}

#######################################
# An ssh failure after the host printed SENT means the keys reached the pane and the command is
# running (a laptop went to sleep mid-wait, say): report it as still running, never as unsent.
# Arguments: $1 exit_code  $2 host script output
# Outputs: the exit code to report on stdout
#######################################
sent_exit_code() {
  local exit_code="${1}" output="${2}"
  if (( exit_code == EXIT_SSH )) && [[ "${output}" == (*$'\n'|)(SENT|TYPED: *)* ]]; then
    log::warn "ssh dropped after the keys were sent; the command is still running | hint='capture with --cmd \"\" once the host answers; never resend'"
    print -r -- "${EXIT_TIMEOUT}"
    return 0
  fi
  print -r -- "${exit_code}"
}

#######################################
# Gate, check the binding, type the command into the pane, record the binding, and print the pane.
# Globals: host target cmd press_enter wait run_log lines timeout path_prefix prompt_end name dry_run
# Returns: 0 prompt back; EXIT_TIMEOUT; EXIT_NO_TARGET; EXIT_NOT_OPTED_IN; EXIT_BOUND_ELSEWHERE; EXIT_BUSY; the host script's code otherwise
#######################################
run_command() {
  local script exit_code=0 bind_line
  script="$(remote_script "${target}" "${cmd}" "${press_enter}" "${wait}" "${lines}" "${timeout}" "${path_prefix}" "${prompt_end}" "${session}" "${run_log}" "$(bindings_of "${name}")")"
  log::info "Typing into pane | host='${host}' target='${target}' enter='${press_enter}' wait='${wait}' cmd='${cmd}'"
  if [[ "${dry_run}" == "true" ]]; then
    log::info "Dry run — printing the host script, sending nothing"
    print -r -- "${script}"
    return 0
  fi
  local output
  output="$(execute_script "${script}")" || exit_code=$?
  # The host printed BIND only after the gate and the binding check passed for this session. Keep this
  # scan a parameter expansion: no `print | awk … exit`, no here-string. With set -e and pipefail, a
  # reader that exits on the first match closes the pipe early, the print writer dies of SIGPIPE once the
  # capture is past the pipe buffer, and the whole run exits 141 before the capture is printed (seen
  # 2026-10-30; tests/run-large-capture.test.zsh); a here-string needs a writable $TMPPREFIX or set -e
  # ends the run the same way. The first BIND line wins.
  local -a bind_lines=(${(M)${(f)output}:#BIND: *})
  bind_line="${${bind_lines[1]:-}#BIND: }"
  if [[ -n "${bind_line}" ]]; then write_binding "${name}" "${bind_line%% *}" "${bind_line##* }"; fi
  print -r -- "${output}"
  exit_code="$(sent_exit_code "${exit_code}" "${output}")"
  report_exit "${exit_code}"
  # The pane answered, even late: the definition is current.
  if (( exit_code == 0 || exit_code == EXIT_TIMEOUT )); then
    record_definition "${name}" false "" "" true
  fi
  return "${exit_code}"
}

#######################################
# Check the flags a --cmd run needs.
# Globals: name target cmd lines timeout prompt_end def
# Returns: 1 on the first bad value
#######################################
validate_run_args() {
  setopt local_options extended_glob
  if [[ "${target}" == *[[:space:]]* ]] || [[ "${target}" != ${~PANE_ID_PATTERN} && "${target}" != ${~FRIENDLY_PATTERN} && "${target}" != *:<0-> && "${target}" != *:<0->.<0-> ]]; then
    log::err "Missing or malformed --target | target='${target}' expected='window.pane as Ari says it (2.4), %pane_id, or session:window[.pane]' panes='${def[windows]:-unknown, run --list}'"
    return 1
  fi
  if [[ -n "${session}" && "${target}" != ${~FRIENDLY_PATTERN} ]]; then
    log::err "--session only applies to a window.pane target | target='${target}' session='${session}'"
    return 1
  fi
  local refusal
  if [[ -n "${cmd}" ]] && ! refusal="$(tmux_text_refusal "${cmd}")"; then
    log::err "Refusing --cmd | reason='${refusal}'"
    return 1
  fi
  if [[ -n "${cmd}" ]] && ! refusal="$(tmux_opt_in_refusal "${cmd}")"; then
    log::err "Refusing --cmd; nothing typed | reason='${refusal}'"
    return 1
  fi
  if [[ -n "${cmd}" && -z "${SESSION_ID}" ]]; then
    log::err "CLAUDE_CODE_SESSION_ID is unset; nothing typed | hint='run.zsh types only from a Claude session, whose id binds the pane; never set or unset it by hand'"
    return 1
  fi
  if [[ "${cmd}" == *pbcopy* ]]; then
    log::err "pbcopy in --cmd | hint='never the clipboard on his machine; print the text in chat (/ari-driving-tmux)'"
    return 1
  fi
  if [[ -z "${prompt_end}" ]]; then
    log::err "Empty prompt end | name='${name}' hint='--prompt-end STR; the definition file has none'"
    return 1
  fi
  [[ "${lines}" == <1-> ]] || { log::err "Invalid --lines | lines='${lines}' expected='positive integer'"; return 1; }
  if [[ "${timeout}" != <1-> ]] || (( timeout < POLL_SECONDS )); then
    log::err "Invalid --timeout | timeout='${timeout}' expected='integer seconds, at least ${POLL_SECONDS}'"
    return 1
  fi
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local name="" host="" host_set=false re_point=false target="" session="" cmd="" cmd_set=false describe="" describe_set=false
  local press_enter=true wait=true run_log=true dry_run=false list=false hosts=false forget=false
  local lines="${DEFAULT_LINES}" timeout="${DEFAULT_TIMEOUT}"
  local path_prefix="${DEFAULT_PATH_PREFIX}" path_prefix_set=false prompt_end="${DEFAULT_PROMPT_END}" prompt_end_set=false
  local -A def

  while (( $# > 0 )); do case "${1}" in
    -h|--help)          help; return 0 ;;
    --host-definition)  name="${2:?--host-definition requires a value}"; shift 2 ;;
    --host)             host="${2:?--host requires a value}"; host_set=true; shift 2 ;;
    --re-point)         re_point=true; shift ;;
    --target)           target="${2:?--target requires a value}"; shift 2 ;;
    --session)          session="${2:?--session requires a value}"; shift 2 ;;
    --cmd)              cmd="${2?--cmd requires a value}"; cmd_set=true; shift 2 ;;
    --hosts)            hosts=true; shift ;;
    --list)             list=true; shift ;;
    --describe)         describe="${2:?--describe requires a value}"; describe_set=true; shift 2 ;;
    --forget)           forget=true; shift ;;
    --no-enter)         press_enter=false; shift ;;
    --no-wait)          wait=false; shift ;;
    --no-run-log)       run_log=false; shift ;;
    --lines)            lines="${2:?--lines requires a value}"; shift 2 ;;
    --timeout)          timeout="${2:?--timeout requires a value}"; shift 2 ;;
    --path-prefix)      path_prefix="${2?--path-prefix requires a value}"; path_prefix_set=true; shift 2 ;;
    --prompt-end)       prompt_end="${2:?--prompt-end requires a value}"; prompt_end_set=true; shift 2 ;;
    --dry-run)          dry_run=true; shift ;;
    -*)                 log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)                  log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  local actions=0 flag
  for flag in "${hosts}" "${list}" "${cmd_set}" "${describe_set}" "${forget}"; do
    [[ "${flag}" == "true" ]] && actions=$((actions + 1))
  done
  if [[ "${cmd_set}" == "true" && -z "${cmd}" && "${press_enter}" == "true" ]]; then
    log::info "Empty --cmd captures only; not pressing Enter"
    press_enter=false
  fi

  # === VALIDATE ===
  if (( actions != 1 )); then
    log::err "Choose one action | given='${actions}' actions='--hosts, --list, --cmd, --describe, --forget'"
    help
    return 1
  fi
  seed_definitions
  if [[ "${hosts}" == "true" ]]; then
    print_definitions
    return 0
  fi
  [[ -n "${name}" ]] || { log::err "Missing --host-definition | known='$(known_names)' hint='--hosts describes each'"; help; return 1; }
  [[ "${name}" != *[^A-Za-z0-9_-]* ]] || { log::err "Invalid --host-definition | name='${name}' expected='letters, digits, _ or -'"; return 1; }
  if [[ "${forget}" == "true" ]]; then
    load_definition "${name}" || { log::err "Unknown host definition | name='${name}' known='$(known_names)'"; return 1; }
    forget_definition "${name}" "${dry_run}"
    return 0
  fi
  resolve_definition "${name}" || return 1
  if [[ "${describe_set}" == "true" ]]; then
    record_definition "${name}" "${dry_run}" "" "${describe}" false
    return 0
  fi
  if [[ -z "${host}" ]]; then
    log::err "Empty host in definition | name='${name}' file='$(definition_file "${name}")' hint='--host user@host --re-point repairs it'"
    return 1
  fi

  # === LOGIC ===
  if [[ "${list}" == "true" ]]; then
    list_windows
    return
  fi
  validate_run_args || return 1
  run_command
}

main "${@}"
