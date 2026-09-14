# Environment contract, paths, and shared primitives for new-machine. Sourced by the CLI, by
# every isolated check/apply subprocess, and by tests one lib at a time, so it must be
# side-effect-free: functions and readonly constants derived from the environment only.
# stdout is data, stderr is logs.
(( ${+NEW_MACHINE_COMMON_LOADED} )) && return 0
typeset -g NEW_MACHINE_COMMON_LOADED=1

# log.zsh loads only strftime/epochtime; EPOCHSECONDS and EPOCHREALTIME need the full module.
zmodload zsh/datetime
zmodload -F zsh/stat b:zstat

typeset -gx NEW_MACHINE_SHARED_DIR="${NEW_MACHINE_SHARED_DIR:-${0:A:h:h}}"

# ── Logging ──────────────────────────────────────────────────────────────────
typeset -g NEW_MACHINE_LOG_LIB="${NEW_MACHINE_SHARED_DIR:h}/zsh/plugins/log.zsh"
typeset -g NEW_MACHINE_LOG_ROTATE_LIB="${NEW_MACHINE_SHARED_DIR:h}/zsh/plugins/log_rotate.zsh"
typeset -g NEW_MACHINE_EDIT_WINDOW="${NEW_MACHINE_SHARED_DIR:h}/bin/tmux-edit-window"
if [[ ! -r "${NEW_MACHINE_LOG_LIB}" || ! -r "${NEW_MACHINE_LOG_ROTATE_LIB}" ]]; then
  print -u2 "[ERROR] missing logging lib | path='${NEW_MACHINE_LOG_LIB}' rotate='${NEW_MACHINE_LOG_ROTATE_LIB}'"
  return 3
fi
source "${NEW_MACHINE_LOG_LIB}"
source "${NEW_MACHINE_LOG_ROTATE_LIB}"
export OTTO_LOG_NOTIF_GROUP=new-machine OTTO_LOG_NOTIF_TITLE=new-machine
# Log files and launchd captures should not carry escape codes.
if [[ ! -t 2 ]]; then
  c_red='' c_green='' c_yellow='' c_blue='' c_magenta='' c_cyan='' c_white='' c_grey='' c_rst=''
fi

# ── Process environment every run and every subprocess share ─────────────────
# .zshenv exports the XDG set once HOME is checked out; the first run predates that.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-${HOME}/.cache}"
export GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_COLOR=0 HOMEBREW_NO_EMOJI=1 NO_COLOR=1

# ── Seams (§2.3): every default is the real machine; tests override and nothing else ─
typeset -gxr NEW_MACHINE_LOCAL_DIR="${NEW_MACHINE_LOCAL_DIR:-${XDG_DATA_HOME}/new-machine}"
typeset -gxr NEW_MACHINE_STATE_DIR="${NEW_MACHINE_STATE_DIR:-${XDG_STATE_HOME}/new-machine}"
typeset -gxr NEW_MACHINE_DESKTOP_DIR="${NEW_MACHINE_DESKTOP_DIR:-${HOME}/Desktop}"
typeset -gxr NEW_MACHINE_LAUNCH_AGENTS_DIR="${NEW_MACHINE_LAUNCH_AGENTS_DIR:-${HOME}/Library/LaunchAgents}"
typeset -gxr NEW_MACHINE_DF_GIT_DIR="${NEW_MACHINE_DF_GIT_DIR:-${HOME}/dotfiles.git}"
typeset -gxr NEW_MACHINE_LDF_GIT_DIR="${NEW_MACHINE_LDF_GIT_DIR:-${HOME}/.local/local-dotfiles.git}"
typeset -gxr NEW_MACHINE_DF_HOOKS="${NEW_MACHINE_DF_HOOKS:-${HOME}/.config/git/dotfiles-hooks}"
typeset -gxr NEW_MACHINE_LDF_HOOKS="${NEW_MACHINE_LDF_HOOKS:-${HOME}/.config/git/local-dotfiles-hooks}"
typeset -gxr DOTFILES_REMOTE="${DOTFILES_REMOTE:-git@github.com:AriSweedler/dotfiles.git}"
typeset -gxr NEW_MACHINE_BREW_PREFIXES="${NEW_MACHINE_BREW_PREFIXES-/opt/homebrew /usr/local}"
typeset -gxr NEW_MACHINE_NOW="${NEW_MACHINE_NOW:-${EPOCHSECONDS}}"
typeset -gxr NEW_MACHINE_HOST="${NEW_MACHINE_HOST:-$(hostname -s)}"
typeset -gxr NEW_MACHINE_CHECK_TIMEOUT_SECS="${NEW_MACHINE_CHECK_TIMEOUT_SECS:-120}"
typeset -gxr NEW_MACHINE_APPLY_TIMEOUT_SECS="${NEW_MACHINE_APPLY_TIMEOUT_SECS:-1800}"
typeset -gxr NEW_MACHINE_RETRY_SECS="${NEW_MACHINE_RETRY_SECS:-60}"
typeset -gxr NEW_MACHINE_LOCK_MAX_AGE_SECS="${NEW_MACHINE_LOCK_MAX_AGE_SECS:-7200}"
typeset -gxr NEW_MACHINE_BREW_BUSY_PATTERN="${NEW_MACHINE_BREW_BUSY_PATTERN:-Homebrew/Library/Homebrew/brew.rb}"
# zsh arithmetic reads a non-numeric string as 0, which would silently disable a watchdog.
for nm_seam in NEW_MACHINE_CHECK_TIMEOUT_SECS NEW_MACHINE_APPLY_TIMEOUT_SECS NEW_MACHINE_RETRY_SECS NEW_MACHINE_LOCK_MAX_AGE_SECS; do
  if [[ "${(P)nm_seam}" != <-> ]]; then
    print -u2 "[ERROR] seam must be a non-negative integer | var='${nm_seam}' value='${(P)nm_seam}'"
    return 3
  fi
done
unset nm_seam

# launchd's PATH lacks Homebrew, so tools are also probed by absolute path under the prefixes.
nm::probe_tool() {
  local tool="${1}" found prefix
  found="$(command -v "${tool}" 2>/dev/null || true)"
  if [[ -n "${found}" ]]; then
    print -r -- "${found}"
    return 0
  fi
  for prefix in ${=NEW_MACHINE_BREW_PREFIXES}; do
    if [[ -x "${prefix}/bin/${tool}" ]]; then
      print -r -- "${prefix}/bin/${tool}"
      return 0
    fi
  done
  return 0
}
typeset -gxr NEW_MACHINE_BREW="${NEW_MACHINE_BREW:-$(nm::probe_tool brew)}"
typeset -gxr NEW_MACHINE_NOTIFIER="${NEW_MACHINE_NOTIFIER:-$(nm::probe_tool terminal-notifier)}"
typeset -gxr NEW_MACHINE_CODE="${NEW_MACHINE_CODE:-$(nm::probe_tool code)}"

# PATH self-heal: brew's own helpers and `code` must resolve for `brew bundle check` under launchd,
# and ~/.local/bin holds the claude installer's symlink. Local bin wins, as in the interactive shell.
typeset -U path
if [[ -n "${NEW_MACHINE_BREW}" ]]; then
  path=("${NEW_MACHINE_BREW:h}" $path)
fi
if [[ -d "${HOME}/.local/bin" ]]; then
  path=("${HOME}/.local/bin" $path)
fi

# ── Run identity ─────────────────────────────────────────────────────────────
nm::run_id() {
  local id
  strftime -s id '%Y%m%dT%H%M%S' "${1:-${NEW_MACHINE_NOW}}"
  print -r -- "${id}"
}
nm::date_ymd() {
  local d
  strftime -s d '%Y-%m-%d' "${1:-${NEW_MACHINE_NOW}}"
  print -r -- "${d}"
}
nm::iso_ts() {
  local ts
  strftime -s ts '%Y-%m-%dT%H:%M:%S%z' "${1:-${NEW_MACHINE_NOW}}"
  print -r -- "${ts}"
}
typeset -gx RUN_ID="${RUN_ID:-$(nm::run_id)}"
typeset -gx RUN_DIR="${RUN_DIR:-${NEW_MACHINE_STATE_DIR}/runs/${RUN_ID}}"

# ── Tier files ───────────────────────────────────────────────────────────────
# Resources needed before HOME is checked out resolve relative to the script; files the tool
# edits or commits resolve under HOME once the checkout exists.
if [[ -d "${HOME}/.config/new-machine" ]]; then
  typeset -gx NEW_MACHINE_GLOBAL_DIR="${NEW_MACHINE_GLOBAL_DIR:-${HOME}/.config/new-machine}"
else
  typeset -gx NEW_MACHINE_GLOBAL_DIR="${NEW_MACHINE_GLOBAL_DIR:-${NEW_MACHINE_SHARED_DIR}}"
fi
typeset -gx GLOBAL_BREWFILE="${NEW_MACHINE_GLOBAL_DIR}/Brewfile"
typeset -gx GLOBAL_BREWFILE_IGNORE="${NEW_MACHINE_GLOBAL_DIR}/Brewfile.ignore"
typeset -gx LOCAL_BREWFILE="${NEW_MACHINE_LOCAL_DIR}/Brewfile"
typeset -gx LOCAL_BREWFILE_IGNORE="${NEW_MACHINE_LOCAL_DIR}/Brewfile.ignore"
typeset -gx LDF_EXCLUDE_TEMPLATE="${NEW_MACHINE_GLOBAL_DIR}/local-dotfiles-exclude"
typeset -gx LAST_RESULT_FILE="${NEW_MACHINE_STATE_DIR}/last_result.json"
typeset -gx VERIFY_TRAIL="${NEW_MACHINE_STATE_DIR}/verify.log"
typeset -gx REPORT_PATH="${NEW_MACHINE_DESKTOP_DIR}/new-machine-FAILED.md"

# ── Verdict (§2.4) ───────────────────────────────────────────────────────────
# verdict <status> <reason> [-d DETAIL] [-f FIX] [-m] [-a] [-i ITEMS_JSON_FILE]
#   -m  manual: a human must act (never auto-applied); -a  actionable even when status is warn
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

# ── Mutations ────────────────────────────────────────────────────────────────
# NM_DRY_RUN is the CLI's --dry-run, exported so every subprocess and lib reads one truth.
nm::is_dry_run() {
  case "${NM_DRY_RUN:-0}" in 0|false|no|"") return 1 ;; esac
  return 0
}

# Every mutation goes through here so --dry-run has no second code path to disagree with.
run_cmd_mutating() {
  if nm::is_dry_run; then
    log::info "dry-run, would run | cmd='$*'"
    return 0
  fi
  run_cmd "$@"
}

nm::plural() {
  local n="${1}" one="${2}" many="${3}"
  if (( n == 1 )); then print -r -- "${n} ${one}"; else print -r -- "${n} ${many}"; fi
}

# The rules of an ignore file: comments and blank lines dropped, so two files that differ
# only in commentary compare equal. Also parses Brewfile.ignore.
exclude_rules() {
  grep -vE '^[[:space:]]*(#|$)' "${1}" || true
}

# ── Data trail and notifications (§4.2, §4.6) ────────────────────────────────
# One line per run in verify.log; grep it for history.
note() {
  local ts
  strftime -s ts '%Y-%m-%d %H:%M:%S' "${NEW_MACHINE_NOW}"
  local line="${ts} [verify] $*"
  mkdir -p "${VERIFY_TRAIL:h}"
  print -r -- "${line}" >> "${VERIFY_TRAIL}"
  log::info "${line}"
}

# hud <message> [seconds=2] [open_url]. seconds 0 leaves the banner up. Fires only under
# launchd (NEW_MACHINE_INVOKED_BY) and without --no-notify; interactive runs get a log line.
# terminal-notifier is addressed by absolute path because launchd's PATH lacks Homebrew;
# post/sleep/-remove gives an exact lifetime, and the remover is synchronous because launchd's
# process-group cleanup would kill a backgrounded one and orphan the banner.
hud() {
  local msg="${1}" seconds="${2:-2}" open_url="${3:-}"
  if [[ -z "${NEW_MACHINE_INVOKED_BY:-}" || "${NM_NO_NOTIFY:-0}" == 1 ]]; then
    log::info "hud | message='${msg}'"
    return 0
  fi
  if [[ -n "${NEW_MACHINE_NOTIFIER}" ]] && command -v "${NEW_MACHINE_NOTIFIER}" >/dev/null 2>&1; then
    local -a args=(-group new-machine -title new-machine -message "${msg}")
    # A file:// click via -open lands in the .md default app (Xcode); route it through the
    # editor-in-tmux-window script instead. The click runs under /bin/sh, hence (q) quoting.
    if [[ "${open_url}" == file://* ]]; then
      local report_file="${open_url#file://}"
      args+=(-execute "${(q)NEW_MACHINE_EDIT_WINDOW} -n new-machine ${(q)report_file}")
    elif [[ -n "${open_url}" ]]; then
      args+=(-open "${open_url}")
    fi
    "${NEW_MACHINE_NOTIFIER}" "${args[@]}" >/dev/null || return 0
    if (( seconds > 0 )); then
      sleep "${seconds}"
      "${NEW_MACHINE_NOTIFIER}" -remove new-machine >/dev/null || true
    fi
    return 0
  fi
  osascript -e "display notification \"${msg}\" with title \"new-machine\"" || true
}

# ── Small helpers shared by the libs ─────────────────────────────────────────
nm::jq_field() {
  jq -r "${2}" "${1}"
}
nm::tail_lines() {
  local file="${1}" n="${2:-10}"
  if [[ -f "${file}" ]]; then
    tail -n "${n}" "${file}"
  fi
}
nm::json_string_array() {
  jq -cn '$ARGS.positional' --args -- "$@"
}
nm::status_exit_code() {
  case "${1}" in
    ok|warn) return 0 ;;
    fail) return 1 ;;
    error) return 2 ;;
    *) return 2 ;;
  esac
}

# What the test harness asserts hermeticity against: where HOME, brew and PATH resolve.
nm::env_probe() {
  jq -n --arg home "${HOME}" --arg path "${PATH}" --arg brew_on_path "$(command -v brew 2>/dev/null || true)" \
        --arg brew "${NEW_MACHINE_BREW}" --arg notifier "${NEW_MACHINE_NOTIFIER}" --arg code "${NEW_MACHINE_CODE}" \
        --arg shared_dir "${NEW_MACHINE_SHARED_DIR}" --arg global_dir "${NEW_MACHINE_GLOBAL_DIR}" \
        --arg local_dir "${NEW_MACHINE_LOCAL_DIR}" --arg state_dir "${NEW_MACHINE_STATE_DIR}" \
        --arg desktop_dir "${NEW_MACHINE_DESKTOP_DIR}" --arg launch_agents_dir "${NEW_MACHINE_LAUNCH_AGENTS_DIR}" \
        --arg now "${NEW_MACHINE_NOW}" --arg host "${NEW_MACHINE_HOST}" --arg run_id "${RUN_ID}" \
    '{home:$home, path:$path, brew_on_path:$brew_on_path, brew:$brew, notifier:$notifier, code:$code,
      shared_dir:$shared_dir, global_dir:$global_dir, local_dir:$local_dir, state_dir:$state_dir,
      desktop_dir:$desktop_dir, launch_agents_dir:$launch_agents_dir, now:$now, host:$host, run_id:$run_id}'
}
