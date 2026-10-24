#!/usr/bin/env bash
# The terminal path costs no more than the plain one: run::_show reads a step's fields from what
# the runner's digest already computed (no jq per step), with lines byte-identical to the jq
# reading of result.json; and the spinner contract (lib/ui.zsh) with a gum that runs its
# watcher: a stop is immediate and leaves no process and no sentinel, one spinner at a time, a
# dead parent ends the watcher.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

# zrun [VAR=value…] -- CODE: the kernel sourced in the hermetic env plus VARs, then CODE; OUT, ERR, RC.
zrun() {
  local -a extra=()
  while [[ "$1" != -- ]]; do extra+=("$1"); shift; done
  shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${extra[@]}" "${FIX}/tools/zsh" -c \
    'for f in "$1"/*.zsh(N); do source "${f}"; done; eval "$2"' _ "${ORIG_CONFIG_DIR}/dotfiles/lib" "$1" \
    > "${FIX}/z.out" 2> "${FIX}/z.err" || RC=$?
  OUT="$(cat "${FIX}/z.out"; printf x)"; OUT="${OUT%x}"
  ERR="$(cat "${FIX}/z.err")"
}

FAKE_GUM="${FIX}/fakegum"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/gum.log"\n' "${FIX}" > "${FAKE_GUM}"
chmod +x "${FAKE_GUM}"
FANCY=(ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${FAKE_GUM}" COLUMNS=100 LANG=en_US.UTF-8)

# ── run::_show: the digest's fields against jq on result.json, byte for byte ──
CASES="${FIX}/cases"
mkdir -p "${CASES}"
printf '%s\n' '{"step":"alpha","status":"ok","reason":"clean","actionable":false,"detail":"first line\nsecond line"}' > "${CASES}/alpha.json"
printf '%s\n' '{"step":"beta","status":"fail","actionable":true,"fix":"brew bundle\nand more","detail":""}' > "${CASES}/beta.json"
printf '%s\n' '{"step":"gamma","status":"warn","reason":"odd","actionable":false,"detail":"tab\there \\ back \"q\" ✓é…\u001fus","log":"ignored"}' > "${CASES}/gamma.json"
printf '%s\n' '{"step":"delta","status":"error","reason":"check_crashed","actionable":false}' > "${CASES}/delta.json"
printf '%s\n' '{"step":"eps","status":"ok","reason":"n","actionable":false,"detail":42}' > "${CASES}/eps.json"

# For each case: the digest, its record stored as step::run stores it, the show line kept, then
# run::_show twice, once on the kept fields and once (nothing kept) through jq.
SHOW_CODE='
  RUN_DIR="$3"; RUN_NAME_W=6; ui::is_fancy
  for c in "$4"/*.json; do
    n="${${c:t}%.json}"
    out="$(step::_digest "${c}" 0 1234 "${RUN_DIR}/${n}.log")"
    fields="${out%%$'"'"'\n'"'"'*}"; out="${out#*$'"'"'\n'"'"'}"
    show="${out%%$'"'"'\n'"'"'*}"; record="${out#*$'"'"'\n'"'"'}"
    print -r -- "${record}" > "${RUN_DIR}/${n}.result.json"
    run::_keep_show "${n}" "${show}"
    [[ -f "${RUN_DIR}/.${n}.show" ]] && kept=kept || kept=none
    a="$(run::_show "${n}")"
    left=none; [[ -e "${RUN_DIR}/.${n}.show" ]] && left=left
    b="$(run::_show "${n}" 2>/dev/null)"
    print -r -- "${n} ${kept} ${left} same=$([[ "${a}" == "${b}" ]] && print 1 || print 0)"
    print -r -- "${a}" >> "${RUN_DIR}/shown.txt"
  done'
RUNDIR="${FIX}/run"
mkdir -p "${RUNDIR}"
zrun "${FANCY[@]}" -- "set -- '' '' '${RUNDIR}' '${CASES}'; ${SHOW_CODE}"
assert_eq "kept fields and jq fields give the same line; the kept file is used up" \
$'alpha kept none same=1
beta kept none same=1
delta kept none same=1
eps none none same=1
gamma kept none same=1\n' "${OUT}"
SHOWN="$(cat "${RUNDIR}/shown.txt")"
assert_contains "the detail's first line only" "${SHOWN}" "first line"
assert_not_contains "never its second" "${SHOWN}" "second line"
assert_contains "an error adds the log path" "${SHOWN}" "log: ${RUNDIR}/delta.log"
assert_json "a detail that is not a string still stores its record" "${RUNDIR}/eps.result.json" '.detail' 42
assert_json "the record is the verdict plus the run's fields" "${RUNDIR}/gamma.result.json" '.log' "${RUNDIR}/gamma.log"

# Plain: nothing is kept, so a plain run leaves no file behind.
RUNDIR="${FIX}/run-plain"
mkdir -p "${RUNDIR}"
zrun ARI_DOTFILES_UI=plain -- "RUN_DIR='${RUNDIR}'; run::_keep_show alpha 'x'; print -r -- \$?"
assert_no_file "plain keeps no fields" "${RUNDIR}/.alpha.show"

# ── The spinner, with a gum that logs and then runs its watcher ──────────────
SPIN_GUM="${FIX}/spingum"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/spin.log"\nwhile [ "$#" -gt 0 ] && [ "$1" != -- ]; do shift; done\nshift\nexec "$@"\n' "${FIX}" > "${SPIN_GUM}"
chmod +x "${SPIN_GUM}"
SPINTMP="${FIX}/spintmp"
mkdir -p "${SPINTMP}"
SPIN=(ARI_DOTFILES_UI=fancy ARI_DOTFILES_GUM="${SPIN_GUM}" TMPDIR="${SPINTMP}")
# up: waits (up to 3 s) until the running spinner's watcher has written its pid into the sentinel.
UP='zmodload zsh/zselect; up() { local -i i; for (( i = 0; i < 300; i++ )); do [[ -s "${UI_SPIN_SENTINEL}" ]] && return 0; zselect -t 1; done; return 1; };'

zrun "${SPIN[@]}" -- "${UP}"'
  zmodload zsh/datetime
  ui::spin_start "working"; up
  s=("${TMPDIR}"/dotfiles-spin.*(N)); w=""; read -r w < "${s[1]}"
  print -r -- "sentinels=${#s} watcher=$([[ "${w}" == <1-> ]] && print pid)"
  t=${EPOCHREALTIME}; ui::spin_stop; (( d = (EPOCHREALTIME - t) * 1000 ))
  print -r -- "stop_ms_under_50=$(( d < 50 ))"
  kill -0 "${w}" 2>/dev/null && print -r -- watcher=alive || print -r -- watcher=gone
  s=("${TMPDIR}"/dotfiles-spin.*(N)); print -r -- "left=${#s}"
  ui::spin_stop; print -r -- "again=$? pid=[${UI_SPIN_PID}]"'
assert_eq "a running spinner: one sentinel holding the watcher's pid; stop is immediate and leaves nothing" \
$'sentinels=1 watcher=pid\nstop_ms_under_50=1\nwatcher=gone\nleft=0\nagain=0 pid=[]\n' "${OUT}"
assert_eq "stop clears the line once; a second stop prints nothing" $'\r\e[2K' "${ERR}"
assert_contains "gum got the title" "$(cat "${FIX}/spin.log")" "--title working"

zrun "${SPIN[@]}" -- "${UP}"'
  ui::spin_start one; up; p1="${UI_SPIN_PID}"
  ui::spin_start two; up; p2="${UI_SPIN_PID}"
  kill -0 "${p1}" 2>/dev/null && print -r -- first=alive || print -r -- first=gone
  s=("${TMPDIR}"/dotfiles-spin.*(N)); print -r -- "sentinels=${#s}"
  ui::spin_stop
  kill -0 "${p2}" 2>/dev/null && print -r -- second=alive || print -r -- second=gone'
assert_eq "a second start retitles: one spinner at a time" $'first=gone\nsentinels=1\nsecond=gone\n' "${OUT}"

zrun "${SPIN[@]}" -- '
  ui::spin_start quick; p="${UI_SPIN_PID}"; ui::spin_stop
  kill -0 "${p}" 2>/dev/null && print -r -- gum=alive || print -r -- gum=gone
  zmodload zsh/zselect; zselect -t 20
  s=("${TMPDIR}"/dotfiles-spin.*(N)); print -r -- "left=${#s}"'
assert_eq "a stop right after the start (gum not up yet) leaves nothing" $'gum=gone\nleft=0\n' "${OUT}"

# A parent that dies without stopping: the watcher notices within a poll and goes.
cat > "${FIX}/orphan.zsh" <<'ZSH'
for f in "$1"/*.zsh(N); do source "${f}"; done
eval "$2"
ui::spin_start orphan; up
print -r -- "${UI_SPIN_PID}"
kill -KILL $$
ZSH
zrun "${SPIN[@]}" FIX_ZSH="${FIX}/tools/zsh" ORPHAN="${FIX}/orphan.zsh" UP="${UP}" -- '
  "${FIX_ZSH}" -f "${ORPHAN}" "$1" "${UP}" > "${TMPDIR}/w.txt" 2>/dev/null
  w=""; read -r w < "${TMPDIR}/w.txt"
  zmodload zsh/zselect; zselect -t 40
  kill -0 "${w}" 2>/dev/null && print -r -- watcher=alive || print -r -- watcher=gone
  s=("${TMPDIR}"/dotfiles-spin.*(N)); print -r -- "left=${#s}"'
assert_eq "a dead parent ends the watcher and its sentinel" $'watcher=gone\nleft=0\n' "${OUT}"

report
