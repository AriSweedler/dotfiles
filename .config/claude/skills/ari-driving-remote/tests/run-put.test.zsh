#!/usr/bin/env zsh
# --put lands a file at /tmp/<project>/<name>.<sha256>.txt through one host script: the name defaults to the
# file's basename without its last extension, the project is relative and nestable, a path that is not ours to
# write is refused with its own message, a file already holding the bytes is left alone, and a failure prints no
# PUT: line. The local definition exercises the script for real in a throwaway project under /tmp; a fake ssh on
# PATH plays the remote host by running the script here with run.zsh's stdin as the file. No tmux, no network.
# Run: zsh $HOME/.claude/skills/ari-driving-remote/tests/run-put.test.zsh

set -uo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly RUN_ZSH="${SCRIPT_DIR:h}/bin/run.zsh"
readonly PROJECT="ari-driving-remote-test-$$"

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | needle='${2}'"; fi
}

readonly T="$(mktemp -d)"
trap 'chmod -R u+w "${T}" 2>/dev/null; rm -rf "${T}" "/tmp/${PROJECT}"' EXIT
mkdir -p "${T}/bin" "${T}/nohash" "${T}/nosh" "${T}/data" "${T}/state" "${T}/cache"
print -r -- 'hello from the put test' > "${T}/swap.py"
print -r -- 'SECRET=1' > "${T}/.env"
readonly SHA="$(shasum -a 256 < "${T}/swap.py" | awk '{print $1}')"
readonly ENV_SHA="$(shasum -a 256 < "${T}/.env" | awk '{print $1}')"

# The fake ssh: drops the options and the host, runs the command here with the same stdin, in zsh, the login
# shell sshd hands a Mac's command to. Under /bin/sh this fake passed while the laptop's zsh failed the first real
# put (2026-10-31, `command not found: sha256sum --`: zsh does not word-split `$h`). FAKE_SSH_PATH narrows the
# host's PATH (a host without a hash tool, or without sh).
cat > "${T}/bin/ssh" <<'FAKE'
#!/usr/bin/env zsh
while (( $# > 1 )); do
  case "${1}" in
    -o) shift 2 ;;
    *) shift ;;
  esac
done
zsh_bin="$(command -v zsh)"   # before PATH narrows: sshd finds the login shell without PATH
if [[ -n "${FAKE_SSH_PATH:-}" ]]; then export PATH="${FAKE_SSH_PATH}"; fi
exec "${zsh_bin}" -c "${1}"
FAKE
chmod +x "${T}/bin/ssh"
# a host with sh, mkdir, cat, mv, rm and awk, and no sha256 tool; and one with everything but sh
for tool in sh mkdir cat mv rm awk; do ln -s "$(command -v "${tool}")" "${T}/nohash/${tool}"; done
for tool in mkdir cat mv rm awk shasum; do ln -s "$(command -v "${tool}")" "${T}/nosh/${tool}"; done

run() {   # <args…>; stdout on $out, exit code on $rc
  out="$(PATH="${T}/bin:${PATH}" XDG_DATA_HOME="${T}/data" XDG_STATE_HOME="${T}/state" XDG_CACHE_HOME="${T}/cache" LOG_COLOR=0 \
    zsh "${RUN_ZSH}" "$@" 2>"${T}/err")"; rc=$?
}

# --- the happy paths ---

run --host-definition here --host local --put "${T}/swap.py" --project "${PROJECT}/nested"
check "local put exits 0" 0 "${rc}"
check "local put prints the project, default name and hash" "PUT: /tmp/${PROJECT}/nested/swap.${SHA}.txt" "${out}"
check "local put wrote the file" "hello from the put test" "$(cat "/tmp/${PROJECT}/nested/swap.${SHA}.txt" 2>/dev/null)"
check "local put made the project dir mode 700" "700" "$(stat -f %Lp "/tmp/${PROJECT}/nested" 2>/dev/null || stat -c %a "/tmp/${PROJECT}/nested")"

before="$(stat -f %m "/tmp/${PROJECT}/nested/swap.${SHA}.txt" 2>/dev/null || stat -c %Y "/tmp/${PROJECT}/nested/swap.${SHA}.txt")"
sleep 1
run --host-definition here --put "${T}/swap.py" --project "${PROJECT}/nested"
check "a repeat put exits 0" 0 "${rc}"
check "a repeat put prints the same path" "PUT: /tmp/${PROJECT}/nested/swap.${SHA}.txt" "${out}"
after="$(stat -f %m "/tmp/${PROJECT}/nested/swap.${SHA}.txt" 2>/dev/null || stat -c %Y "/tmp/${PROJECT}/nested/swap.${SHA}.txt")"
check "a repeat put leaves a file that already holds the bytes alone" "${before}" "${after}"

run --host-definition here --put "${T}/swap.py" --project "${PROJECT}" --name body
check "--name replaces the default" "PUT: /tmp/${PROJECT}/body.${SHA}.txt" "${out}"

run --host-definition here --put "${T}/.env" --project "${PROJECT}"
check "a dotfile keeps its whole basename as the default name" "PUT: /tmp/${PROJECT}/.env.${ENV_SHA}.txt" "${out}"

run --host-definition fake --host fake@host --put "${T}/swap.py" --project "${PROJECT}/remote"
check "remote put exits 0" 0 "${rc}"
check "remote put prints the path" "PUT: /tmp/${PROJECT}/remote/swap.${SHA}.txt" "${out}"
check "remote put made the dir and wrote the file through one ssh" "hello from the put test" "$(cat "/tmp/${PROJECT}/remote/swap.${SHA}.txt" 2>/dev/null)"
check "remote put left no .part file" "" "$(ls "/tmp/${PROJECT}/remote" | awk '/\.part\./ {n++} END {if (n) print n}')"
check "a new definition was saved by the put" "fake@host" "$(awk -F= '$1 == "host" {print $2}' "${T}/data/ari-driving-remote/hosts/fake")"

run --host-definition fake --dry-run --put "${T}/swap.py" --project "${PROJECT}/dry" --name plan
check "dry run exits 0" 0 "${rc}"
check "dry run prints WOULD PUT" "WOULD PUT: /tmp/${PROJECT}/dry/plan.${SHA}.txt" "${out}"
check "dry run copies nothing" "" "$(ls "/tmp/${PROJECT}/dry" 2>/dev/null)"

# --- the flag refusals, before any connection ---

run --host-definition fake --put "${T}/swap.py"
check "missing --project is refused" 1 "${rc}"
check "missing --project prints no PUT line" "" "${out}"
contains "missing --project names the flag" "Missing --project" "$(<"${T}/err")"

run --host-definition fake --put "${T}/swap.py" --project "/tmp/${PROJECT}"
check "absolute --project is refused" 1 "${rc}"
check "absolute --project prints no PUT line" "" "${out}"

run --host-definition fake --put "${T}/swap.py" --project "${PROJECT}/../escape"
check "a .. in --project is refused" 1 "${rc}"
check "a .. in --project prints no PUT line" "" "${out}"
contains "a .. in --project names the value" "project='${PROJECT}/../escape'" "$(<"${T}/err")"

run --host-definition fake --put "${T}/swap.py" --project "./${PROJECT}"
check "a dots-only segment in --project is refused" 1 "${rc}"
check "a dots-only segment prints no PUT line" "" "${out}"

run --host-definition fake --put "${T}/swap.py" --project "has space"
check "a bad character in --project is refused" 1 "${rc}"
check "a bad character in --project prints no PUT line" "" "${out}"

run --host-definition fake --put "${T}/swap.py" --project "${PROJECT}" --name 'has space'
check "a bad --name is refused" 1 "${rc}"
check "a bad --name prints no PUT line" "" "${out}"

run --host-definition fake --target %5 --cmd 'echo hi' --project "${PROJECT}"
check "--project without --put is refused" 1 "${rc}"
contains "--project without --put says so" "--project and --name go with --put" "$(<"${T}/err")"

run --host-definition fake --put "${T}/swap.py" --project "${PROJECT}" --target %5
check "--target with --put is refused" 1 "${rc}"
contains "--target with --put says a put types nothing" "A --put types nothing" "$(<"${T}/err")"

run --host-definition fake --put "${T}/empty.txt" --project "${PROJECT}"
check "a missing file is refused" 1 "${rc}"
contains "a missing file names the scratchpad" "write it to the scratchpad first" "$(<"${T}/err")"

# --- the host refusals: a message of their own, no PUT line, no raw shell error ---

mkdir -p "/tmp/${PROJECT}/isfile"
print -r -- 'x' > "/tmp/${PROJECT}/isfile/blocker"
run --host-definition here --put "${T}/swap.py" --project "${PROJECT}/isfile/blocker"
check "local put onto a project path that is a file exits 1" 1 "${rc}"
check "local put onto a file prints no PUT line" "" "${out}"
contains "local put onto a file says the path is not a directory" "project path is not a directory" "$(<"${T}/err")"
check "local put onto a file prints no raw zsh error" "" "$(awk '/put_file:/ {n++} END {if (n) print n}' "${T}/err")"

run --host-definition fake --put "${T}/swap.py" --project "${PROJECT}/isfile/blocker"
check "remote put onto a project path that is a file exits 1" 1 "${rc}"
contains "remote put onto a file says the same flags fail the same way" "the same flags fail the same way" "$(<"${T}/err")"

mkdir -p "/tmp/${PROJECT}/link"
ln -s "${T}/elsewhere" "/tmp/${PROJECT}/link/swap.${SHA}.txt"
run --host-definition here --put "${T}/swap.py" --project "${PROJECT}/link"
check "a symlink at the path is refused" 1 "${rc}"
contains "a symlink at the path is named" "a symlink sits at the path" "$(<"${T}/err")"
check "a symlink at the path was not written through" "" "$(cat "${T}/elsewhere" 2>/dev/null)"

FAKE_SSH_PATH="${T}/nohash" run --host-definition fake --put "${T}/swap.py" --project "${PROJECT}/nohash"
check "a host without a sha256 tool exits 1" 1 "${rc}"
check "a host without a sha256 tool prints no PUT line" "" "${out}"
contains "a host without a sha256 tool is named as such" "No sha256 tool on the host" "$(<"${T}/err")"
check "a host without a sha256 tool got no file" "" "$(ls "/tmp/${PROJECT}/nohash" 2>/dev/null)"

FAKE_SSH_PATH="${T}/nosh" run --host-definition fake --put "${T}/swap.py" --project "${PROJECT}/nosh"
check "a host without sh exits 1" 1 "${rc}"
check "a host without sh prints no PUT line" "" "${out}"
contains "a host without sh is named as such, not as a hash mismatch" "No sh on the host" "$(<"${T}/err")"
check "a host without sh got no file" "" "$(ls "/tmp/${PROJECT}/nosh" 2>/dev/null)"

# --- a put that succeeded is reported as such even when the definition cannot be saved ---

chmod 500 "${T}/data/ari-driving-remote/hosts"
run --host-definition here --put "${T}/swap.py" --project "${PROJECT}/readonly-hosts"
chmod 700 "${T}/data/ari-driving-remote/hosts"
check "PUT with an unwritable hosts dir exits 0" 0 "${rc}"
check "PUT with an unwritable hosts dir prints the path" "PUT: /tmp/${PROJECT}/readonly-hosts/swap.${SHA}.txt" "${out}"
contains "PUT with an unwritable hosts dir warns" "Definition not saved" "$(<"${T}/err")"

print -- "${pass} passed, ${fail} failed"
if (( fail > 0 )); then print -u2 -- "--- run.zsh stderr of the last run:"; cat "${T}/err" >&2; exit 1; fi
