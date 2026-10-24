#!/usr/bin/env bash
# Check speed: the kernel sources without running a single external command, and a cached
# verdict is reused only while its inputs hold — a changed input, a just-written input, an
# error verdict and setup mode all run the check.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
LIB="${ORIG_CONFIG_DIR}/dotfiles/lib"

# ── kernel: zero external commands at source time ────────────────────────────
# PATH holds only tracing shims, one per command name on the machine; each logs its name.
TRACE_DIR="${FIX}/trace-bin" TRACE_LOG="${FIX}/trace.log"
mkdir -p "${TRACE_DIR}"
printf '#!/bin/sh\nprintf "%%s\\n" "${0##*/}" >> "%s"\n' "${TRACE_LOG}" > "${FIX}/tracer"
chmod +x "${FIX}/tracer"
for d in /bin /usr/bin /usr/sbin /sbin /opt/homebrew/bin /usr/local/bin; do
  [[ -d "${d}" ]] || continue
  for c in "${d}"/*; do
    n="${c##*/}"
    [[ -e "${TRACE_DIR}/${n}" ]] || ln -s "${FIX}/tracer" "${TRACE_DIR}/${n}"
  done
done
: > "${TRACE_LOG}"
cat > "${FIX}/source-kernel.zsh" <<'ZSH'
set -euo pipefail
for f in "${KERNEL_LIB}"/*.zsh(N); do source "${f}"; done
print -r -- "loaded ${#SUBMODULES} ${JOBS_LABEL} ${ARI_DOTFILES_HOST} ${RUN_ID}"
ZSH
printf '[submodule "a"]\n\tpath = .config/a\n\turl = x\n[submodule "b"]\n  path=.config/b\n' > "${HOME}/.gitmodules"
RC=0
OUT="$(env -i HOME="${HOME}" PATH="${TRACE_DIR}" KERNEL_LIB="${LIB}" TZ=UTC \
  "${FIX}/tools/zsh" -f "${FIX}/source-kernel.zsh" 2> "${FIX}/kernel.err")" || RC=$?
assert_eq "kernel sources under a tracing PATH" 0 "${RC}"; [[ "${RC}" == 0 ]] || cat "${FIX}/kernel.err" >&2
assert_contains "kernel derived its values" "${OUT}" "loaded 2 com."
assert_eq "kernel ran no external command" "" "$(cat "${TRACE_LOG}")"
assert_contains "submodules parsed without git" "$(env -i HOME="${HOME}" PATH="${TRACE_DIR}" KERNEL_LIB="${LIB}" \
  "${FIX}/tools/zsh" -f -c 'source "${KERNEL_LIB}/env.zsh"; print -r -- "${(j:,:)SUBMODULES}"')" ".config/a,.config/b"
assert_eq "host is hostname -s" "$(hostname -s)" "$(env -i HOME="${HOME}" PATH=/usr/bin:/bin KERNEL_LIB="${LIB}" \
  "${FIX}/tools/zsh" -f -c 'source "${KERNEL_LIB}/env.zsh"; print -r -- "${ARI_DOTFILES_HOST}"')"

# ── cache: a hit only while every input holds ────────────────────────────────
mkdir -p "${FIX}/run"
INPUT="${FIX}/input.txt"
printf 'one\n' > "${INPUT}"
touch -t 202001010000 "${INPUT}"
cat > "${FIX}/cache-probe.zsh" <<'ZSH'
set -euo pipefail
for f in "${KERNEL_LIB}"/*.zsh(N); do source "${f}"; done
probe::check() {
  print -r -- x >> "${PROBE_COUNT}"
  print -r -- side > "${RUN_DIR}/probe.side.json"
  verdict "${PROBE_STATUS:-ok}" fine -d "read $(<"${PROBE_INPUT}")"
}
cache::check probe::check "${PROBE_INPUT}"
ZSH
probe() {
  RC=0
  env -i HOME="${HOME}" PATH="${PATH}" KERNEL_LIB="${LIB}" STEP=probe RUN_DIR="${FIX}/run" \
    ARI_DOTFILES_STATE_DIR="${ARI_DOTFILES_STATE_DIR}" \
    PROBE_INPUT="${INPUT}" PROBE_COUNT="${FIX}/count" "$@" \
    "${FIX}/tools/zsh" -f "${FIX}/cache-probe.zsh" > "${FIX}/probe.out" 2> "${FIX}/probe.err" || RC=$?
  OUT="$(cat "${FIX}/probe.out")"
}
runs() { wc -l < "${FIX}/count" | tr -d ' '; }

probe
assert_eq "first run checks" 1 "$(runs)"
assert_json "first run is fresh" "${FIX}/probe.out" '.detail' 'read one'
rm -f "${FIX}/run/probe.side.json"
probe
assert_eq "unchanged input: no second check" 1 "$(runs)"
assert_json "hit keeps the status" "${FIX}/probe.out" '.status' ok
assert_json "hit is marked in the detail" "${FIX}/probe.out" '.detail | test("\ncached: true \\| fp=")' true
assert_json "hit keeps the fresh detail first" "${FIX}/probe.out" '.detail | split("\n")[0]' 'read one'
assert_file "hit restores what the check wrote into RUN_DIR" "${FIX}/run/probe.side.json"

printf 'two\n' > "${INPUT}"; touch -t 202001010001 "${INPUT}"
probe
assert_eq "changed input: checks again" 2 "$(runs)"
assert_json "the changed input's verdict" "${FIX}/probe.out" '.detail' 'read two'

# A same-size rewrite keeping the old mtime is invisible to the fingerprint; only a forged mtime
# gets there, since a real write lands at "now" and the racy rule refuses to store it.
printf 'tw0\n' > "${INPUT}"; touch -t 202001010001 "${INPUT}"
probe
assert_eq "a forged mtime is the documented blind spot" 2 "$(runs)"

printf 'three\n' > "${INPUT}"   # mtime now: racy, so never stored
probe; probe
assert_eq "an input written this second is never cached" 4 "$(runs)"
touch -t 202001010002 "${INPUT}"

probe PROBE_STATUS=error; probe PROBE_STATUS=error
assert_eq "an error verdict is never cached" 6 "$(runs)"
probe; probe
assert_eq "after the error, ok is cached again" 7 "$(runs)"
probe ARI_DOTFILES_MODE=setup
assert_eq "setup mode always checks" 8 "$(runs)"
probe ARI_DOTFILES_NO_CACHE=1
assert_eq "ARI_DOTFILES_NO_CACHE=1 always checks" 9 "$(runs)"
rm -f "${INPUT}"
probe
assert_eq "an input that vanishes is a change" 10 "$(runs)"

report
