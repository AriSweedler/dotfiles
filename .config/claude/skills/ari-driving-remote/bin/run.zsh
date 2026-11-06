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
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/dry_run.zsh"
readonly SCRIPT_PATH="${0:a}"

# Sourced here for the command checks, and prepended to the host script so the gate, the exact pane
# lookup and the lock run the same on every host as on a click (focus.zsh).
readonly LIB_TMUX_PANE="${XDG_CONFIG_HOME:-${HOME}/.config}/claude/lib/tmux-pane.sh"
if [[ ! -r "${LIB_TMUX_PANE}" ]]; then
  log::err "Missing tmux pane lib | path='${LIB_TMUX_PANE}'"
  exit 1
fi
source "${LIB_TMUX_PANE}"

# Sourced, not copied (load_wrap_lib, for a run_log-wrapped --cmd only), so a --cmd types exactly what a
# /ari-driving-tmux --run click types.
readonly LIB_WRAP="${SKILLS_DIR}/ari-driving-tmux/lib/wrap.zsh"

# --- Constants ---

readonly POLL_SECONDS=5
readonly DEFAULT_TIMEOUT=90   # under the Bash tool's 120 s default, so exit 124 reaches the caller
readonly DEFAULT_LINES=60
readonly EXIT_TIMEOUT=124
readonly EXIT_NO_TARGET=70
readonly EXIT_BUSY=75   # EX_TEMPFAIL: the pane is not an idle shell at its prompt; nothing was typed
readonly EXIT_NOT_OPTED_IN=77   # EX_NOPERM: the pane's OPT_IN_OPTION is not on; nothing was typed
readonly EXIT_PASTE_FAILED=73   # tmux could not paste the text; nothing is on the line
readonly EXIT_ENTER_FAILED=74   # the text is on the line, Enter did not reach it
# A 75 or 77 prints 'REFUSED_KIND: <kind>' on the line right after its REFUSED: text, and no other exit prints
# one; callers classify by the kind, never by the REFUSED: words. The exit code follows from the kind:
# not_opted_in is 77, every other kind 75. A held lock is other_caller; each reason tmux_pane_gate_refusal gives
# is an sh case pattern below, with its kind; a reason none matches (the lib changed) is unknown.
# tests/run-refusal-kind.test.zsh puts every reason the lib holds through the case.
readonly REFUSED_KIND_PREFIX='REFUSED_KIND: '
readonly KIND_NOT_OPTED_IN=not_opted_in
readonly KIND_OTHER_CALLER=other_caller
readonly KIND_UNKNOWN=unknown
readonly KIND_NOT_ZSH=not_zsh   # run.zsh's own reason: a laid-out text into a pane whose shell is not zsh
readonly GATE_REASON_KINDS=(
  "'not opted in'*"                          "${KIND_NOT_OPTED_IN}"
  "'in copy mode'*"                          copy_mode
  "'synchronize-panes'*"                     synchronized
  "'running '*', not a shell'"               not_a_shell
  "'last line does not end in the prompt'*"  not_at_prompt
  "'no such pane'"                           pane_gone
)
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
# Where --put lands a file on the host: PUT_DIR/<project>/<name>.<sha256>.txt; the hash makes the same text the same
# path. Checked by tests/run-put.test.zsh.
readonly PUT_DIR=/tmp
readonly PUT_PROJECT_PATTERN='[A-Za-z0-9._-]##(/[A-Za-z0-9._-]##)#'   # relative, one or more segments
readonly PUT_NAME_PATTERN='[A-Za-z0-9._-]##'
readonly PUT_SEGMENT_DOTS_PATTERN='(*/|).##(/*|)'   # a segment of dots only: '.', '..', '...'
# How the host (and this machine) hash the put file, first found wins; a host with none exits EXIT_PUT_NO_HASH.
readonly PUT_HASH_TOOLS=('sha256sum --' 'shasum -a 256 --' 'openssl dgst -sha256 -r --')
readonly EXIT_PUT_REFUSED=2    # the host refused the path (not a dir, not ours, a symlink, not a regular file)
readonly EXIT_PUT_NO_HASH=3    # no sha256 tool on the host; nothing copied
readonly EXIT_PUT_WRITE=4      # the host could not write the file; its message is on stderr
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

# Script constants expand in the heredoc; every environment variable ($HOME, $SCRATCHPAD, $CLAUDE_CODE_SESSION_ID)
# is written \$NAME, so the help is the same on every machine and set -u cannot kill it (tests/run-help.test.zsh).
help() {
  cat <<EOF
${c_green}run.zsh${c_rst} — type a command into a tmux pane (this machine or over ssh), wait for the shell prompt, print the pane

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --hosts
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition DEF --list
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition DEF --target %6 --cmd TEXT [OPTIONS] [--execute]
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition DEF --put FILE --project DIR [--name NAME] [--execute]
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition DEF [--host USER@HOST] --describe TEXT [--execute]
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition DEF --forget [--execute]

A ${c_bold}definition${c_rst} is a file under ${HOSTS_DIR}: the host's user@host (or '${LOCAL_HOST}' for
this machine, no ssh), PATH prefix, shell-prompt end, the panes seen on the last --list, when it last
answered, and a description. --host-definition fills --host, --path-prefix and --prompt-end from it;
an explicit flag wins. The first --list on a new DEF writes it at once; --describe, --cmd and --put write it with --execute. '${LOCAL_NAME}' is always seeded.
Definitions still under ${OLD_HOSTS_DIR} are moved there on the next run.

Before typing, --cmd refuses unless the pane option ${OPT_IN_OPTION} is on (Ari runs '${OPT_IN_COMMAND}' in that
pane), the pane is not in copy mode or synchronized, its foreground command is a shell, and its last line ends
in the prompt. TEXT is one line, with no control characters, no leading clear, no pbcopy, and nothing that spells
the opt-in ('${OPT_IN_COMMAND}', 'ari-remote-tmux on' or ${OPT_IN_OPTION}, case and quotes ignored, a new pane's
startup command included); any of those exits 1 before connecting. Claude never sets the opt-in, by any route.
Panes are named 'ID=%301|pane=2.4'.
A --cmd is handed to run_log when the host has ${HOST_RUN_LOG} (else typed bare, with a NOTE: line), in the form
a /ari-driving-tmux run link types (its Command layout; wrap_run_log_text in its lib/wrap.zsh): one line, or a
quoted heredoc over several lines, never '\\''. It goes in as one bracketed paste; a text over several lines
goes into a zsh pane only. After typing it prints 'TYPED: <the exact text sent>', spanning those lines, and,
once Enter is sent (or skipped), 'SENT'.

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
  --put FILE              copy FILE to the host as ${PUT_DIR}/<--project>/<--name>.<sha256 of its bytes>.txt and print
                          'PUT: <remote path>' once the host's hash matches (a dry run checks the local file, project and name only, prints 'WOULD PUT: …' and copies nothing; the host's own refusals show only with --execute).
                          The one ssh use that is not typing: a copy, never a command; a --cmd then names the path
  --describe TEXT         replace the definition's description without connecting
  --forget                print the definition and delete it

${c_bold}Options:${c_rst}
  --host-definition DEF   definition to use (required unless --hosts)
  --host USER@HOST        ssh destination ('${LOCAL_HOST}' for this machine), saved onto a new definition; on an existing one needs --re-point
  --re-point              allow --host to change an existing definition (its panes and last_seen reset)
  --target W.P|%N|S:W[.P]  pane: Ari's window.pane (2.4, matched exactly), a %pane_id, or session:window[.pane] (required with --cmd)
  --session S             session a window.pane target is looked up in (default: the most recently active client's)
  --project DIR           with --put: the dir under ${PUT_DIR} the file lands in: the repo or system the file belongs
                          to, one optional subsystem segment (homelab, homelab/torrent); letters, digits, . _ - and /,
                          never absolute, empty, '..' or a dots-only segment
  --name NAME             with --put: what the file is, letters, digits, . _ -; default FILE's basename without its
                          last extension (swap.py -> swap, queue.tar.gz -> queue.tar, .env -> .env)
  --no-enter              type without pressing Enter (Ari presses it)
  --no-run-log            type the command bare instead of handing it to run_log (the default when the host
                          has ${HOST_RUN_LOG}; its capture lands in the host's /tmp/run_log)
  --no-wait               return right after typing instead of waiting for the shell prompt
  --lines N               pane lines to print (default: ${DEFAULT_LINES})
  --timeout S             seconds to wait for the shell prompt, at least ${POLL_SECONDS} (default: ${DEFAULT_TIMEOUT});
                          set the Bash tool's timeout above it
  --path-prefix DIR       prepended to PATH on the host so tmux resolves (default: ${DEFAULT_PATH_PREFIX}; '' for none)
  --prompt-end STR        what the idle shell-prompt line ends with (default: ${DEFAULT_PROMPT_END})
  --execute               act. Without it --cmd TEXT (not ''), --put, --describe and --forget are a dry run: --cmd resolves
                          the pane, runs the gate and the binding check, prints under 'WOULD TYPE:' the text the pane would
                          get, verbatim, and types nothing; --put prints WOULD PUT; --describe and --forget log what they
                          would write or delete. --hosts, --list and --cmd '' only read and ignore it
  --dry-run               the default, said explicitly; wins over --execute and an inherited DRY_RUN other than 0
  -h, --help              show this help

${c_bold}Exit codes:${c_rst}
  0    the shell prompt returned, or PUT: printed
  1    refused before connecting (the text check, a malformed --project or --name, an unreadable or empty FILE),
       or a --put that failed on the host (no PUT: line; the [ERROR] line says which: the path refused, no sha256
       tool, the write failed, the hash differs)
  ${EXIT_TIMEOUT}  still running (timed out, --no-wait, or ssh dropped after SENT); the pane is printed; never resend
  ${EXIT_NO_TARGET}   no pane matches the target, or no attached client to resolve a window.pane against (--session);
       every pane on the host is printed under the refusal, so the right one can be picked without --list
  ${EXIT_NOT_OPTED_IN}   pane not opted in (nothing typed); the line after REFUSED: is '${REFUSED_KIND_PREFIX}${KIND_NOT_OPTED_IN}'
  ${EXIT_BUSY}   pane busy (nothing typed); the line after REFUSED: is '${REFUSED_KIND_PREFIX}<kind>', one of
       ${KIND_OTHER_CALLER}, $(gate_busy_kinds), ${KIND_NOT_ZSH} (the text spans lines and the pane's shell is not zsh),
       ${KIND_UNKNOWN} (a gate reason this version does not map).
       Only ${EXIT_NOT_OPTED_IN} and ${EXIT_BUSY} carry a kind; switch on the exit code first, then on the kind
  ${EXIT_BOUND_ELSEWHERE}   pane bound to another Claude session (nothing typed); get a pane of your own
  ${EXIT_PASTE_FAILED}   tmux could not paste the text; nothing is on the line; resend once
  ${EXIT_ENTER_FAILED}   the text is on the line but Enter did not reach it; Ari presses Enter or clears it
  ${EXIT_NOT_FOUND}  tmux not found on the host (--path-prefix)
  ${EXIT_SSH}  ssh could not connect before anything was typed; for a --put, nothing is at the path

${c_bold}Examples:${c_rst}
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition local --list
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition local --target %6 --no-enter --cmd 'kubectl get pods' --execute
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %6 --cmd 'diskutil list external physical' --execute
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %7 --cmd ''
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --put "\$SCRATCHPAD/body.md" --project homelab/beads --name bead-frontier --execute
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --put "\$SCRATCHPAD/swap.py" --project homelab/torrent
  zsh \$HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition pi --host pi@pi.local --describe 'Pi 4 B at 192.0.2.94, no tmux; reached from the laptop with a nested ssh -t' --execute
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
# Arguments: $1 name  $2 gated(true|false): true for an edit Ari asked for (--describe), a dry run unless --execute;
#            false for the bookkeeping of a run (last_seen, panes), the skill's own state
# Returns: 1 when the hosts dir is not writable
#######################################
save_definition() {
  local name="${1}" gated="${2}" file tmp key body=""
  file="$(definition_file "${name}")"
  for key in "${DEFINITION_KEYS[@]}"; do
    body+="${key}=${def[${key}]//$'\n'/ }"$'\n'
  done
  if [[ "${gated}" == "true" ]] && is_dry_run; then
    print -rn -- "${body}" | write_mut "${file}"
    return 0
  fi
  mkdir -p "${HOSTS_DIR}" 2>/dev/null || { log::err "Hosts dir not writable | dir='${HOSTS_DIR}'"; return 1; }
  tmp="$(mktemp "${HOSTS_DIR}/.${name}.XXXXXX")" || { log::err "Hosts dir not writable | dir='${HOSTS_DIR}'"; return 1; }
  trap 'rm -f "${tmp}"' EXIT
  print -rn -- "${body}" > "${tmp}"
  mv -f "${tmp}" "${file}"
  trap - EXIT
  if [[ "${gated}" == "true" ]]; then (( MUT_COUNT += 1 )); fi
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
# Arguments: $1 name  $2 gated (save_definition)  $3 windows ('' keeps)  $4 description ('' keeps)  $5 touch_last_seen(true|false)
#######################################
record_definition() {
  local name="${1}" gated="${2}" windows="${3}" description="${4}" touch_last_seen="${5}"
  def[host]="${host}" def[path_prefix]="${path_prefix}" def[prompt_end]="${prompt_end}"
  if [[ -n "${windows}" ]]; then def[windows]="${windows}"; fi
  if [[ -n "${description}" ]]; then
    if [[ -n "${def[description]}" && "${def[description]}" != "${description}" ]]; then
      log::warn "Replacing description | name='${name}' previous='${def[description]}'"
    fi
    def[description]="${description}"
  fi
  if [[ "${touch_last_seen}" == "true" ]]; then def[last_seen]="$(now_utc)"; fi
  save_definition "${name}" "${gated}"
}

#######################################
# Print the definition, then delete its file.
# Arguments: $1 name
#######################################
forget_definition() {
  local name="${1}" file
  file="$(definition_file "${name}")"
  print -r -- "name=${name}"
  cat "${file}"
  run_mut rm -f -- "${file}"
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
# The sh pipeline that prints the pane's last non-blank lines: the tail under a refusal, and the capture.
# Globals: AWK_NONBLANK
# Arguments: $1 lines
# Returns: the pipeline on stdout
#######################################
pane_tail_cmd() {
  print -r -- "tmux capture-pane -p -t \"\$pane\" -S -${1} | awk ${(qq)AWK_NONBLANK} | tail -n ${1}"
}

#######################################
# The kinds of a 75 that the gate's reasons map to, comma-separated, for the help.
# Globals: GATE_REASON_KINDS KIND_NOT_OPTED_IN
#######################################
gate_busy_kinds() {
  local pattern kind
  local -a kinds=()
  for pattern kind in "${GATE_REASON_KINDS[@]}"; do
    [[ "${kind}" == "${KIND_NOT_OPTED_IN}" ]] || kinds+=("${kind}")
  done
  print -r -- "${(j:, :)kinds}"
}

#######################################
# One sh statement that sets sh variable `kind` from the gate's `reason`, per GATE_REASON_KINDS.
# Globals: GATE_REASON_KINDS KIND_UNKNOWN
# Returns: the statement on stdout
#######################################
gate_kind_case() {
  local pattern kind statement="case \"\$reason\" in"
  for pattern kind in "${GATE_REASON_KINDS[@]}"; do
    statement+=" ${pattern}) kind=${kind} ;;"
  done
  print -r -- "${statement} *) kind=${KIND_UNKNOWN} ;; esac"
}

#######################################
# The gate before any keys are sent (tmux_pane_gate_refusal: opted in, not in copy mode or synchronized,
# an idle shell, last line ends in the prompt), under the pane's lock so two callers cannot both pass it.
# A refusal on a pane that closed since it resolved is EXIT_NO_TARGET with the inventory, as in resolve_block:
# the lib reads a gone pane as not opted in. Any other refusal prints why, its REFUSED_KIND line and the pane
# tail, and exits untyped with the kind's code. The lock is released after the send.
# Globals: REFUSED_KIND_PREFIX KIND_* EXIT_BUSY EXIT_NOT_OPTED_IN EXIT_NO_TARGET
# Arguments: $1 quoted_prompt_end  $2 lines
# Returns: the script lines on stdout
#######################################
gate_block() {
  local quoted_prompt_end="${1}" lines="${2}"
  print -r -- "tmux_pane_lock \"\$pane\" || { echo \"REFUSED: \$label another caller is typing into it\"; echo ${(qq)REFUSED_KIND_PREFIX}${KIND_OTHER_CALLER}; $(pane_tail_cmd "${lines}"); exit ${EXIT_BUSY}; }"
  print -r -- "trap 'tmux_pane_unlock \"\$pane\"' EXIT"
  print -r -- "reason=\$(tmux_pane_gate_refusal \"\$pane\" ${quoted_prompt_end}); rc=\$?"
  print -r -- "if [ \$rc -ne 0 ]; then"
  print -r -- "  tmux list-panes -a -F '#{pane_id}' | awk -v p=\"\$pane\" '\$1 == p {f = 1} END {exit !f}' || { echo \"REFUSED: no pane matches \$target\"; $(inventory_line); exit ${EXIT_NO_TARGET}; }"   # sh, no pipefail; awk reads to EOF  # lint: ok
  print -r -- "  echo \"REFUSED: \$label \$reason\"; $(gate_kind_case); echo ${(qq)REFUSED_KIND_PREFIX}\"\$kind\"; $(pane_tail_cmd "${lines}")"
  print -r -- "  if [ \"\$kind\" = ${KIND_NOT_OPTED_IN} ]; then exit ${EXIT_NOT_OPTED_IN}; fi; exit ${EXIT_BUSY}"
  print -r -- "fi"
}

#######################################
# The binding check, after the gate and under the same lock: the pane's grant stamp against this
# definition's bindings. Another session's binding that the stamp does not outdate refuses with
# EXIT_BOUND_ELSEWHERE, untyped. Otherwise 'BIND: <pane> <stamp>' tells the caller to record the pane as
# this session's (new, refreshed, or regranted by Ari).
# Globals: STAMP_OPTION SESSION_ID EXIT_BOUND_ELSEWHERE
# Arguments: $1 bindings ('%N session since' lines)  $2 lines
# Returns: the script lines on stdout
#######################################
binding_block() {
  local bindings="${1}" lines="${2}"
  local tail_cmd
  tail_cmd="$(pane_tail_cmd "${lines}")"
  print -r -- "since=\$(tmux show-options -pqv -t \"\$pane\" ${(qq)STAMP_OPTION}); since=\${since:-0}"
  print -r -- "bound=\$(printf '%s\\n' ${(qq)bindings} | awk -v p=\"\$pane\" '\$1 == p {print \$2, \$3}')"
  print -r -- "bsession=\${bound%% *}; bsince=\${bound##* }; [ -n \"\$bound\" ] || bsince=0"
  print -r -- "if [ -n \"\$bsession\" ] && [ \"\$bsession\" != ${(qq)SESSION_ID} ] && [ \"\$since\" -le \"\$bsince\" ]; then echo \"REFUSED: \$label bound to another Claude session \${bsession%%-*}; get a pane of your own\"; ${tail_cmd}; exit ${EXIT_BOUND_ELSEWHERE}; fi"
  print -r -- "echo \"BIND: \$pane \$since\""
}

#######################################
# The script lines that put the text on the pane's line: the command bare, or handed to run_log when the host
# has HOST_RUN_LOG, in the form /ari-driving-tmux's wrap_run_log_text gives (the lib's rule; never '\''). A
# text over several lines goes into zsh only, as focus.zsh's layout_refusal holds: another shell would run the
# heredoc differently, so it is refused with KIND_NOT_ZSH, untyped. One bracketed paste (load-buffer,
# paste-buffer -p), not send-keys: a newline lands as a newline, not an Enter, and a trailing `;` is not a
# tmux separator; not the lib's tmux_paste_line, which adds a leading space and turns newlines into CRs.
# Checked by tests/run-typed-text.test.zsh.
# A dry run stops after the checks: the host prints, under WOULD TYPE:, the exact text it would paste.
# Globals: HOST_RUN_LOG REFUSED_KIND_PREFIX KIND_NOT_ZSH EXIT_BUSY EXIT_PASTE_FAILED
# Arguments: $1 cmd  $2 run_log(true|false)  $3 lines  $4 dry(true|false)
# Returns: the script lines on stdout
#######################################
type_block() {
  local cmd="${1}" run_log="${2}" lines="${3}" dry="${4:-false}" run_log_text
  print -r -- "typed=${(qq)cmd}"
  if [[ "${run_log}" == "true" ]]; then
    run_log_text="$(wrap_run_log_text '' "${cmd}")"
    print -r -- "if [ -x \"${HOST_RUN_LOG}\" ]; then typed=${(qq)run_log_text}; else echo \"NOTE: no ${HOST_RUN_LOG} on the host; typed the command bare\"; fi"
  fi
  print -r -- "nl=\$(printf '\\n.'); nl=\${nl%.}"
  print -r -- "case \"\$typed\" in *\"\$nl\"*) program=\$(tmux display-message -p -t \"\$pane\" '#{pane_current_command}'); case \"\$program\" in zsh|-zsh) ;; *) echo \"REFUSED: \$label the command is laid out over several lines, which only zsh reads as one; \$program runs there\"; echo ${(qq)REFUSED_KIND_PREFIX}${KIND_NOT_ZSH}; $(pane_tail_cmd "${lines}"); exit ${EXIT_BUSY} ;; esac ;; esac"
  if [[ "${dry}" == "true" ]]; then
    print -r -- "printf 'WOULD TYPE:\\n%s\\n' \"\$typed\""
    print -r -- "tmux_pane_unlock \"\$pane\"; trap - EXIT"
    pane_tail_cmd "${lines}"
    print -r -- "exit 0"
    return 0
  fi
  print -r -- "buffer=\"ari-driving-remote-\$\$\""
  print -r -- "printf '%s' \"\$typed\" | tmux load-buffer -b \"\$buffer\" - && tmux paste-buffer -p -r -d -b \"\$buffer\" -t \"\$pane\" || { tmux delete-buffer -b \"\$buffer\" 2>/dev/null; echo \"FAILED: paste into \$label; nothing is on the line\"; exit ${EXIT_PASTE_FAILED}; }"
  print -r -- "printf 'TYPED: %s\\n' \"\$typed\""
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
#   $11 bindings ('%N session since' lines of this definition)  $12 dry(true|false): gate and check the binding, then
#   print WOULD TYPE and type nothing
# Returns: the script on stdout
#######################################
remote_script() {
  local target="${1}" cmd="${2}" press_enter="${3}" wait="${4}"
  local lines="${5}" timeout="${6}" path_prefix="${7}" prompt_end="${8}" session="${9}" run_log="${10}" bindings="${11}" dry="${12}"
  local quoted_prompt_end="${(qq)prompt_end}"

  prelude_block "${path_prefix}"
  print -r -- "$(<"${LIB_TMUX_PANE}")"
  resolve_block "${target}" "${session}"
  if [[ -n "${cmd}" ]]; then
    gate_block "${quoted_prompt_end}" "${lines}"
    binding_block "${bindings}" "${lines}"
    type_block "${cmd}" "${run_log}" "${lines}" "${dry}"
    if [[ "${dry}" == "true" ]]; then return 0; fi
  fi
  if [[ "${press_enter}" == "true" ]]; then print -r -- "tmux send-keys -t \"\$pane\" Enter || { echo \"FAILED: Enter to \$label; the text is on the line\"; exit ${EXIT_ENTER_FAILED}; }"; fi
  if [[ -n "${cmd}" ]]; then
    # From here a dropped connection must not read as "never typed": the caller sees SENT.
    print -r -- "echo SENT"
    print -r -- "sleep 0.2; tmux_pane_unlock \"\$pane\"; trap - EXIT"
  fi
  wait_block '"$pane"' "${quoted_prompt_end}" "${wait}" "${press_enter}" "${timeout}"
  pane_tail_cmd "${lines}"
  print -r -- "exit \$rc"
}

# --- Actions ---

#######################################
# Run a host script under POSIX sh: directly for the local definition, as `sh -c` inside whatever login shell
# sshd hands the command to otherwise (a Mac's zsh does not word-split, and ran the put's `$h "$file"` as one
# word on 2026-10-31). A host whose login shell finds no `sh` exits EXIT_NOT_FOUND.
# Globals: host LOCAL_HOST SSH_OPTS
# Arguments: $1 script
# Returns: the script's exit code
#######################################
execute_script() {
  emulate -L zsh   # (qq) must quote as '\'' here, which RC_QUOTES would turn into ''
  local script="${1}"
  if [[ "${host}" == "${LOCAL_HOST}" ]]; then
    log::info "Running on this machine | host='${host}'"
    sh -c "${script}"
    return
  fi
  log::info "Running over ssh | host='${host}'"
  ssh "${SSH_OPTS[@]}" "${host}" "sh -c ${(qq)script}"
}

#######################################
# Check --project and --name for a put, defaulting the name to the file's basename without its last extension
# (a dotfile keeps its whole basename). Before any connection; checked by tests/run-put.test.zsh.
# Globals: put_project put_name (read; put_name written), PUT_PROJECT_PATTERN PUT_NAME_PATTERN PUT_SEGMENT_DOTS_PATTERN
# Arguments: $1 local file
# Returns: 1 on a malformed project or name
#######################################
validate_put_args() {
  setopt local_options extended_glob
  if [[ -z "${put_project}" ]]; then
    log::err "Missing --project | hint='the dir under ${PUT_DIR} the file lands in: the repo or system it belongs to, e.g. homelab or homelab/torrent'"
    return 1
  fi
  if [[ "${put_project}" != ${~PUT_PROJECT_PATTERN} || "${put_project}" == ${~PUT_SEGMENT_DOTS_PATTERN} ]]; then
    log::err "Invalid --project | project='${put_project}' expected='relative dir of letters, digits, . _ - and /; no leading /, no segment of dots only'"
    return 1
  fi
  if [[ -z "${put_name}" ]]; then
    put_name="${${1:t}%.*}"
    [[ -n "${put_name}" ]] || put_name="${1:t}"
    log::info "Defaulting --name to the file's basename | name='${put_name}'"
  fi
  if [[ "${put_name}" != ${~PUT_NAME_PATTERN} || "${put_name}" == ${~PUT_SEGMENT_DOTS_PATTERN} ]]; then
    log::err "Invalid --name | name='${put_name}' expected='letters, digits, . _ -, not dots only'"
    return 1
  fi
}

#######################################
# The sha256 command available on this machine, first of PUT_HASH_TOOLS found.
# Globals: PUT_HASH_TOOLS
# Returns: the command words on stdout; 1 when none is installed
#######################################
local_hash_command() {
  local tool
  for tool in "${PUT_HASH_TOOLS[@]}"; do
    if command -v "${tool%% *}" >/dev/null 2>&1; then print -r -- "${tool}"; return 0; fi
  done
  log::err "No sha256 tool on this machine | tried='${(j:, :)PUT_HASH_TOOLS}'"
  return 1
}

#######################################
# The host side of a put, POSIX sh, the same on this machine and over ssh: find a hash tool, refuse a path that is
# not ours to write (REFUSED: … and EXIT_PUT_REFUSED), make the project dir mode 700, leave a file that already
# holds the bytes alone, else write stdin beside it and move it into place, and print the file's hash last. Both
# paths are ours, validated, and single-quoted once. Checked by tests/run-put.test.zsh.
# Globals: PUT_HASH_TOOLS EXIT_PUT_*
# Arguments: $1 remote dir  $2 remote file  $3 expected sha256
# Returns: the script on stdout
#######################################
host_put_script() {
  local dir="${1}" file="${2}" sha="${3}" tool
  print -r -- "h=''"
  for tool in "${PUT_HASH_TOOLS[@]}"; do
    print -r -- "[ -n \"\$h\" ] || command -v ${tool%% *} >/dev/null 2>&1 && h=\${h:-${(qq)tool}}"
  done
  print -r -- "[ -n \"\$h\" ] || { echo 'REFUSED: no sha256 tool on the host'; exit ${EXIT_PUT_NO_HASH}; }"
  print -r -- "dir=${(qq)dir}; file=${(qq)file}; want=${(qq)sha}"
  print -r -- "if [ -e \"\$dir\" ] && [ ! -d \"\$dir\" ]; then echo \"REFUSED: project path is not a directory: \$dir\"; exit ${EXIT_PUT_REFUSED}; fi"
  print -r -- "mkdir -p -m 700 -- \"\$dir\" || exit ${EXIT_PUT_WRITE}"
  print -r -- "if [ ! -O \"\$dir\" ]; then echo \"REFUSED: project dir belongs to another user: \$dir\"; exit ${EXIT_PUT_REFUSED}; fi"
  print -r -- "if [ -L \"\$file\" ]; then echo \"REFUSED: a symlink sits at the path: \$file\"; exit ${EXIT_PUT_REFUSED}; fi"
  print -r -- "if [ -e \"\$file\" ] && [ ! -f \"\$file\" ]; then echo \"REFUSED: the path is not a regular file: \$file\"; exit ${EXIT_PUT_REFUSED}; fi"
  print -r -- "if [ -f \"\$file\" ] && [ \"\$(\$h \"\$file\" | awk '{print \$1}')\" = \"\$want\" ]; then echo \"\$want\"; exit 0; fi"   # the exit is sh's, after the pipeline  # lint: ok
  print -r -- "part=\"\$file.part.\$\$\"; { cat > \"\$part\" && mv -f -- \"\$part\" \"\$file\"; } || { rm -f -- \"\$part\"; exit ${EXIT_PUT_WRITE}; }"
  print -r -- "\$h \"\$file\" | awk '{print \$1}'"
}

#######################################
# Log why a put's host script failed, from its exit code and its REFUSED: line. EXIT_NOT_FOUND is the login shell
# finding no sh; EXIT_SSH is a put's own message:
# nothing is at the path (the write goes to a .part file that is moved into place only when complete).
# Globals: host EXIT_PUT_* EXIT_SSH
# Arguments: $1 exit_code  $2 host output  $3 remote path
#######################################
report_put_exit() {
  local exit_code="${1}" output="${2}" remote="${3}" refused
  local -a refusals=(${(M)${(f)output}:#REFUSED: *})
  refused="${refusals[1]:-}"
  if (( exit_code == EXIT_PUT_REFUSED )); then
    log::err "Host refused the path; nothing copied | reason='${refused#REFUSED: }' hint='the same flags fail the same way: another --project or --name, or the cleanup is a --cmd of Ari'"
    return 0
  fi
  if (( exit_code == EXIT_PUT_NO_HASH )); then
    log::err "No sha256 tool on the host; nothing copied | host='${host}' tried='${(j:, :)PUT_HASH_TOOLS}' hint='tell Ari; the host needs one of them'"
    return 0
  fi
  if (( exit_code == EXIT_NOT_FOUND )); then
    log::err "No sh on the host; nothing copied | host='${host}' hint='its login shell said so above; tell Ari which host; a re-put fails the same way'"
    return 0
  fi
  if (( exit_code == EXIT_PUT_WRITE )); then
    log::err "Host could not write the file | host='${host}' remote='${remote}' hint='its message is above (No space left, Permission denied): Ari gets it with the remote and local paths; a re-put only after he fixed the host'"
    return 0
  fi
  if (( exit_code == EXIT_SSH )); then
    log::err "ssh failed before or during the copy; nothing is at the path | host='${host}' remote='${remote}' hint='asleep, wrong address, or no key: Ari runs ssh ${host} once in a pane; re-put after he says done'"
    return 0
  fi
  log::err "Put failed on the host with no message | host='${host}' exit_code='${exit_code}' remote='${remote}' hint='re-put once; a second failure goes to Ari with both hashes'"
}

#######################################
# Copy a file to the host as PUT_DIR/<project>/<name>.<sha256>.txt through host_put_script (under sh on either side:
# directly for the local definition, through one ssh otherwise, the file on stdin), confirm the hash it prints, and print 'PUT: <remote path>'.
# The only ssh use besides typing: it moves bytes and runs nothing of the caller's. A failure prints no PUT: line.
# Checked by tests/run-put.test.zsh.
# Globals: host PUT_DIR put_project put_name name def
# Arguments: $1 local file
# Returns: 1 on a missing or empty file, a bad project or name, a refused path, a failed copy or a hash mismatch;
#          EXIT_SSH when ssh failed
#######################################
put_file() {
  local file="${1:A}" sha remote remote_dir remote_sha bytes hash_cmd output exit_code=0
  if [[ ! -f "${file}" || ! -r "${file}" ]]; then
    log::err "File to put is not a readable regular file | file='${file}' hint='write it to the scratchpad first'"
    return 1
  fi
  bytes="$(wc -c < "${file}" | tr -d ' ')"
  if (( bytes == 0 )); then
    log::err "File to put is empty; a write that did not land | file='${file}' hint='rewrite the scratchpad file, then put it'"
    return 1
  fi
  validate_put_args "${file}" || return 1
  hash_cmd="$(local_hash_command)" || return 1
  # hashed from stdin: a name starting with '-' or holding a backslash would change the tool's output
  sha="$(${=hash_cmd} < "${file}" | awk '{print $1}')"
  remote_dir="${PUT_DIR}/${put_project}"
  remote="${remote_dir}/${put_name}.${sha}.txt"
  log::info "Putting file on the host | host='${host}' file='${file}' bytes='${bytes}' remote='${remote}'"
  if is_dry_run; then
    (( MUT_COUNT += 1 ))
    log::info "would copy and verify | host='${host}' remote='${remote}'"
    print -r -- "WOULD PUT: ${remote}"
    return 0
  fi
  (( MUT_COUNT += 1 ))
  # a definition named for the first time is saved before connecting, as --describe saves it, so a retry can drop --host
  if [[ ! -r "$(definition_file "${name}")" ]]; then record_definition "${name}" false "" "" false || true; fi
  # the host's own stderr stays visible: 'Permission denied', 'No space left'
  output="$(execute_script "$(host_put_script "${remote_dir}" "${remote}" "${sha}")" < "${file}")" || exit_code=$?
  if (( exit_code != 0 )); then
    report_put_exit "${exit_code}" "${output}" "${remote}"
    (( exit_code == EXIT_SSH )) && return "${EXIT_SSH}"
    return 1
  fi
  local -a output_lines=(${(f)output})
  remote_sha="${output_lines[-1]:-}"
  if [[ "${remote_sha}" != "${sha}" ]]; then
    log::err "Hash mismatch after copy; the remote file is not the text | local='${sha}' remote='${remote_sha:-unreadable}' remote_path='${remote}' hint='re-put once; a second mismatch goes to Ari with both hashes'"
    return 1
  fi
  print -r -- "PUT: ${remote}"
  record_definition "${name}" false "" "" true || log::warn "Definition not saved; the put itself succeeded | name='${name}'"
}

#######################################
# Log what a host-script exit code means for the caller. 0 logs nothing.
# Globals: host target timeout path_prefix OPT_IN_COMMAND
# Arguments: $1 exit_code  $2 kind (the REFUSED_KIND of a 75 or 77; '' otherwise)
#######################################
report_exit() {
  local exit_code="${1}" kind="${2:-}"
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
    log::err "Pane not opted in; nothing typed | target='${target}' kind='${kind}' hint='Ari runs ${OPT_IN_COMMAND} in that pane himself; never type it for him'"
    return 0
  fi
  if (( exit_code == EXIT_BOUND_ELSEWHERE )); then
    log::err "Pane bound to another Claude session; nothing typed | target='${target}' hint='a branch, fork or other session owns it: get a pane of your own; only Ari running ${OPT_IN_COMMAND} there again rebinds it'"
    return 0
  fi
  if (( exit_code == EXIT_BUSY )); then
    log::err "Pane is not an idle shell at its prompt, or another caller is typing; nothing typed | target='${target}' kind='${kind}' hint='say nothing was typed; the command announced above stands, never reprinted; never retry into a busy pane'"
    if [[ "${kind}" == "${KIND_UNKNOWN}" ]]; then
      log::warn "Gate reason with no GATE_REASON_KINDS pattern | target='${target}' hint='run tests/run-refusal-kind.test.zsh; /ari-skill-update ari-driving-remote'"
    fi
    return 0
  fi
  if (( exit_code == EXIT_PASTE_FAILED )); then
    log::err "tmux could not paste the text; nothing is on the line | target='${target}' hint='resend once, announced again; a second failure goes to Ari with the label'"
    return 0
  fi
  if (( exit_code == EXIT_ENTER_FAILED )); then
    log::err "Enter did not reach the pane; the text is on the line | target='${target}' hint='tell Ari, as for --no-enter; type nothing more there until he pressed Enter or cleared it'"
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
# Globals: host path_prefix name WINDOWS_SEPARATOR AWK_WINDOW_NAMES
# Returns: the host script's exit code
#######################################
list_windows() {
  local script output windows exit_code=0
  script="$(list_script "${path_prefix}")"
  log::info "Listing tmux panes | host='${host}'"
  output="$(execute_script "${script}")" || exit_code=$?
  if (( exit_code != 0 )); then print -r -- "${output}"; fi
  report_exit "${exit_code}"
  (( exit_code == 0 )) || return "${exit_code}"
  output="$(list_with_owners "${name}" "${output}")"
  print -r -- "${output}"
  # The reminder that holds after a compaction, when SKILL.md may be out of context: the first --cmd is the one most often sent unannounced.
  print -r -- "NEXT: a --cmd into a ✦ pane goes in chat first: its label in inline code, then the one line you pass --cmd in a fenced block (never the run_log form TYPED: shows), above the Bash call; --cmd '' needs none"
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
# The kind of a 75 or 77: the line right after the first REFUSED: line, which the host prints before the pane
# tail; unknown when that line is not a kind. Any other exit has none, whatever the pane tail holds.
# Globals: EXIT_BUSY EXIT_NOT_OPTED_IN REFUSED_KIND_PREFIX KIND_UNKNOWN
# Arguments: $1 exit_code  $2 host output
# Outputs: the kind on stdout, or nothing
#######################################
refusal_kind() {
  local exit_code="${1}" output="${2}" i
  if (( exit_code != EXIT_BUSY && exit_code != EXIT_NOT_OPTED_IN )); then
    return 0
  fi
  local -a lines=("${(@f)output}")
  for (( i = 1; i < ${#lines}; i++ )); do
    [[ "${lines[i]}" == 'REFUSED: '* ]] || continue
    if [[ "${lines[i+1]}" == "${REFUSED_KIND_PREFIX}"* ]]; then
      print -r -- "${lines[i+1]#${REFUSED_KIND_PREFIX}}"
      return 0
    fi
    break
  done
  print -r -- "${KIND_UNKNOWN}"
}

#######################################
# Gate, check the binding, type the command into the pane, record the binding, and print the pane.
# Globals: host target cmd press_enter wait run_log lines timeout path_prefix prompt_end name
# Returns: 0 prompt back; EXIT_TIMEOUT; EXIT_NO_TARGET; EXIT_NOT_OPTED_IN; EXIT_BOUND_ELSEWHERE; EXIT_BUSY; the host script's code otherwise
#######################################
run_command() {
  local script exit_code=0 bind_line kind dry=false
  if is_dry_run; then dry=true; fi
  script="$(remote_script "${target}" "${cmd}" "${press_enter}" "${wait}" "${lines}" "${timeout}" "${path_prefix}" "${prompt_end}" "${session}" "${run_log}" "$(bindings_of "${name}")" "${dry}")"
  log::info "Typing into pane | host='${host}' target='${target}' enter='${press_enter}' wait='${wait}' cmd='${cmd}'"
  if [[ -n "${cmd}" ]]; then (( MUT_COUNT += 1 )); fi
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
  if [[ -n "${bind_line}" ]] && ! is_dry_run; then write_binding "${name}" "${bind_line%% *}" "${bind_line##* }"; fi
  print -r -- "${output}"
  if [[ "${dry}" == "true" && -n "${cmd}" ]] && (( exit_code == 0 )); then print -r -- "DRY RUN: nothing was typed; the pane above is its state, not this command's output"; fi
  exit_code="$(sent_exit_code "${exit_code}" "${output}")"
  kind="$(refusal_kind "${exit_code}" "${output}")"
  report_exit "${exit_code}" "${kind}"
  # The pane answered, even late: the definition is current.
  if (( exit_code == 0 || exit_code == EXIT_TIMEOUT )) && [[ "${dry}" == "false" || -z "${cmd}" ]]; then
    record_definition "${name}" false "" "" true
  fi
  return "${exit_code}"
}

#######################################
# Source /ari-driving-tmux's layout lib for a run_log-wrapped --cmd; every other mode runs without it.
# Globals: LIB_WRAP
# Returns: 1 when the lib is missing
#######################################
load_wrap_lib() {
  if [[ ! -r "${LIB_WRAP}" ]]; then
    log::err "Missing command layout lib; nothing typed | path='${LIB_WRAP}' hint='link the ari-driving-tmux skill (/ari-dotfiles-skill-registry); --no-run-log types the command bare meanwhile'"
    return 1
  fi
  source "${LIB_WRAP}"
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
  if [[ -n "${cmd}" && "${run_log}" == "true" ]]; then
    load_wrap_lib || return 1
  fi
  if [[ -n "${cmd}" && -z "${SESSION_ID}" ]]; then
    log::err "CLAUDE_CODE_SESSION_ID is unset; nothing typed | hint='run.zsh types only from a Claude session, whose id binds the pane; never set or unset it by hand'"
    return 1
  fi
  if [[ "${cmd}" == *pbcopy* ]]; then
    log::err "pbcopy in --cmd | hint='never the clipboard on his machine; print the text in chat (/ari-driving-tmux)'"
    return 1
  fi
  # content smuggled through the pane: typed base64 drops bytes on long sends (a 3,000-byte chunk lost 8 on 2026-10-30)
  if [[ "${cmd}" == *base64\ -d* || "${cmd}" == *base64\ --decode* || "${cmd}" == *base64\ -D* ]]; then
    log::err "Refusing --cmd; it decodes content typed into the pane | hint='content goes by --put FILE; the --cmd then names the PUT: path'"
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
  local -a args=("${@}")
  local execute=false
  local name="" host="" host_set=false re_point=false target="" session="" cmd="" cmd_set=false describe="" describe_set=false
  local put="" put_set=false put_project="" put_name=""
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
    --put)              put="${2:?--put requires a value}"; put_set=true; shift 2 ;;
    --project)          put_project="${2:?--project requires a value}"; shift 2 ;;
    --name)             put_name="${2:?--name requires a value}"; shift 2 ;;
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
    --execute)          execute=true; shift ;;
    --dry-run)          dry_run=true; shift ;;
    -*)                 log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)                  log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === MASSAGE ===
  local actions=0 flag
  for flag in "${hosts}" "${list}" "${cmd_set}" "${put_set}" "${describe_set}" "${forget}"; do
    [[ "${flag}" == "true" ]] && actions=$((actions + 1))
  done
  # Whitespace alone is an empty command: a capture, never a typed `run_log ' '`.
  if [[ "${cmd_set}" == "true" && "${cmd}" != *[^[:space:]]* ]]; then cmd=""; fi
  if [[ "${cmd_set}" == "true" && -z "${cmd}" && "${press_enter}" == "true" ]]; then
    log::info "Empty --cmd captures only; not pressing Enter"
    press_enter=false
  fi
  # A capture, --list and --hosts only read; the rest type, copy or edit what Ari said about a host.
  local mutates=false
  if [[ "${put_set}" == "true" || "${describe_set}" == "true" || "${forget}" == "true" || -n "${cmd}" ]]; then mutates=true; fi
  if [[ "${mutates}" == "true" ]]; then resolve_dry_run "${execute}" "${dry_run}" || return 1; fi

  # === VALIDATE ===
  if [[ "${put_set}" == "false" && ( -n "${put_project}" || -n "${put_name}" ) ]]; then
    log::err "--project and --name go with --put | project='${put_project}' name='${put_name}'"
    return 1
  fi
  if [[ "${put_set}" == "true" && ( -n "${target}" || -n "${session}" || "${press_enter}" == "false" || "${wait}" == "false" || "${run_log}" == "false" || "${lines}" != "${DEFAULT_LINES}" || "${timeout}" != "${DEFAULT_TIMEOUT}" ) ]]; then
    log::err "A --put types nothing: it takes no pane or typing flag | refused='--target, --session, --no-enter, --no-wait, --no-run-log, --lines, --timeout'"
    return 1
  fi
  if (( actions != 1 )); then
    log::err "Choose one action | given='${actions}' actions='--hosts, --list, --cmd, --put, --describe, --forget'"
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
    forget_definition "${name}"
    report_dry_run "${SCRIPT_PATH}" "${args[@]}"
    return 0
  fi
  resolve_definition "${name}" || return 1
  if [[ "${describe_set}" == "true" ]]; then
    if [[ "${def[description]:-}" == "${describe}" ]]; then
      log::info "Description already current; nothing to change | name='${name}'"
      return 0
    fi
    record_definition "${name}" true "" "${describe}" false
    report_dry_run "${SCRIPT_PATH}" "${args[@]}"
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
  local exit_code=0
  if [[ "${put_set}" == "true" ]]; then
    put_file "${put}" || exit_code=$?
    if (( exit_code == 0 )); then report_dry_run "${SCRIPT_PATH}" "${args[@]}"; fi
    return "${exit_code}"
  fi
  validate_run_args || return 1
  run_command || exit_code=$?
  if [[ "${mutates}" == "true" ]] && (( exit_code == 0 )); then report_dry_run "${SCRIPT_PATH}" "${args[@]}"; fi
  return "${exit_code}"
}

main "${@}"
