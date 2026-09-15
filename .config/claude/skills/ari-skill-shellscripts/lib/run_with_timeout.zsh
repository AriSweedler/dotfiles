#!/usr/bin/env zsh
# Canonical run_with_timeout helper for skill zsh scripts. Source it; do not execute.
# Convention documented in /ari-skill-shellscripts § Bounded subprocesses.
#
#   source "${SKILLS_DIR}/ari-skill-shellscripts/lib/run_with_timeout.zsh"

#######
# Run a command with a hard wall-clock timeout.
# Prefers GNU `timeout` (Linux) / `gtimeout` (macOS w/ coreutils) when available;
# falls back to a pure-zsh polling loop that backgrounds the command, polls once
# per second, and SIGKILLs once the cap is exceeded.
# Arguments:
#   $1 = timeout_secs (integer cap on total runtime)
#   $2 = err_file (path; receives the command's stderr)
#   $@ = command + args
# Returns: command's exit code, OR 124 on timeout (mirrors GNU `timeout`).
#######
run_with_timeout() {
    local timeout_secs="${1}" err_file="${2}"
    shift 2

    local timeout_cmd=""
    if command -v timeout >/dev/null 2>&1; then
        timeout_cmd="timeout"
    elif command -v gtimeout >/dev/null 2>&1; then
        timeout_cmd="gtimeout"
    fi

    if [[ -n "${timeout_cmd}" ]]; then
        local exit_code=0
        "${timeout_cmd}" "${timeout_secs}" "$@" 2>"${err_file}" || exit_code=$?
        return "${exit_code}"
    fi

    # Fallback: no `timeout`/`gtimeout` available — poll the backgrounded process.
    "$@" 2>"${err_file}" &
    local pid=$! elapsed=0 exit_code=0
    while kill -0 "${pid}" 2>/dev/null; do
        sleep 1
        elapsed=$(( elapsed + 1 ))
        if (( elapsed >= timeout_secs )); then
            kill -9 "${pid}" 2>/dev/null || true
            wait "${pid}" 2>/dev/null || true
            return 124
        fi
    done
    # `wait` propagates the child's non-zero exit; capture explicitly so `set -e`
    # doesn't abort before the return value reaches the caller.
    wait "${pid}" || exit_code=$?
    return "${exit_code}"
}
