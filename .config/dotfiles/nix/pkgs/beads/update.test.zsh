#!/usr/bin/env zsh
# Proves update.zsh's rewrite of a copy of default.nix with curl and nix stubbed on PATH: a dry run
# writes nothing, --execute rewrites only the version and the four hashes, a second run changes
# nothing, and a missing release, a missing asset, a bad version or a wrong built version write
# nothing. No network, no nix store, never the real default.nix.
# Run: zsh $HOME/dotfiles/.config/dotfiles/nix/pkgs/beads/update.test.zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly UPDATE="${SCRIPT_DIR}/update.zsh"
readonly REAL_NIX="${SCRIPT_DIR}/default.nix"
readonly HEX_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly HEX_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
readonly HEX_C="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
readonly HEX_D="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

typeset -i passed=0 failed=0

#######################################
# Record one check: pass when the two values are equal.
# Arguments: $1 test name, $2 wanted, $3 actual
#######################################
expect_eq() {
  local name="${1}" want="${2}" got="${3}"
  if [[ "${want}" == "${got}" ]]; then
    passed=$(( passed + 1 ))
    log::info "ok | test='${name}'"
    return 0
  fi
  failed=$(( failed + 1 ))
  log::err "FAIL | test='${name}' want='${want}' got='${got}'"
}

#######################################
# Record one check: pass when the text holds the literal string.
# Arguments: $1 test name, $2 text, $3 string
#######################################
expect_has() {
  local name="${1}" got="${2}" want="${3}"
  if [[ "${got}" == *"${want}"* ]]; then
    passed=$(( passed + 1 ))
    log::info "ok | test='${name}'"
    return 0
  fi
  failed=$(( failed + 1 ))
  log::err "FAIL | test='${name}' want='${want}' got='${got}'"
}

work="$(mktemp -d "${${TMPDIR:-/tmp}%/}/beads-update-test.XXXXXX")"
trap "rm -rf '${work}'" EXIT
readonly STUBS="${work}/stubs" SERVE="${work}/serve" PKG="${work}/nix/pkgs/beads/default.nix"
mkdir -p "${STUBS}" "${SERVE}/v9.9.9" "${SERVE}/v9.9.8" "${work}/nix/pkgs/beads" "${work}/store"
mkdir -p "${work}/skills/bd-skill" "${work}/skills/other-skill"
print -r -- "Written against bd 1.3.4." > "${work}/skills/bd-skill/SKILL.md"
print -r -- "Nothing about versions." > "${work}/skills/other-skill/SKILL.md"
: > "${work}/nix/flake.nix"

# The stub curl serves files under SERVE by URL path and fails like `curl -f` on anything else.
cat > "${STUBS}/curl" <<'EOF'
#!/usr/bin/env zsh
url="${@[-1]}"
case "${url}" in
  https://api.github.com/repos/gastownhall/beads/releases/latest) cat "${STUB_SERVE}/latest.json" ;;
  https://github.com/gastownhall/beads/releases/download/*)
    f="${STUB_SERVE}/${url#https://github.com/gastownhall/beads/releases/download/}"
    [[ -r "${f}" ]] || { print -u2 "curl: (22) The requested URL returned error: 404"; exit 22; }
    cat "${f}" ;;
  *) print -u2 "curl stub: unexpected url ${url}"; exit 99 ;;
esac
EOF
# The stub nix turns a hex digest into a recognizable SRI and builds a bd that prints the version
# of the package file named in the --expr, or STUB_BD_VERSION when set.
cat > "${STUBS}/nix" <<'EOF'
#!/usr/bin/env zsh
case "${1} ${2}" in
  "hash convert") print -r -- "sha256-SRI-${@[-1][1,8]}=" ;;
  "build "*)
    expr="${@[-1]}"; file="${expr##*\(/. + \"}"; file="${file%%\"*}"
    v="$(awk -F'"' '/^ *version = /{ print $2 }' "${file}")"
    out="${STUB_STORE}/beads-${v}"; mkdir -p "${out}/bin"
    print -r -- "#!/bin/sh
echo 'bd version ${STUB_BD_VERSION:-${v}} (stub)'" > "${out}/bin/bd"; chmod +x "${out}/bin/bd"
    print -r -- "${out}" ;;
  *) print -u2 "nix stub: unexpected args $*"; exit 99 ;;
esac
EOF
chmod +x "${STUBS}/curl" "${STUBS}/nix"

#######################################
# Write a checksums.txt for a version, with every asset or all but one.
# Arguments: $1 version; $2 a platform to leave out (optional)
#######################################
serve_checksums() {
  local v="${1}" skip="${2:-}" p hex
  local -A hexes=(linux_amd64 "${HEX_A}" linux_arm64 "${HEX_B}" darwin_amd64 "${HEX_C}" darwin_arm64 "${HEX_D}")
  : > "${SERVE}/v${v}/checksums.txt"
  for p in linux_amd64 linux_arm64 darwin_amd64 darwin_arm64; do
    [[ "${p}" == "${skip}" ]] && continue
    print -r -- "${hexes[$p]}  beads_${v}_${p}.tar.gz" >> "${SERVE}/v${v}/checksums.txt"
  done
  print -r -- "eeee  beads_${v}_windows_amd64.zip" >> "${SERVE}/v${v}/checksums.txt"
}
serve_checksums 9.9.9
serve_checksums 9.9.8 darwin_arm64
print -r -- '{"tag_name":"v9.9.9"}' > "${SERVE}/latest.json"

out="" rc=0
#######################################
# Run update.zsh on the fixture package with the stubs first on PATH.
# Globals: out (stdout and stderr), rc (exit code)
# Arguments: update.zsh's flags
#######################################
run_update() {
  rc=0
  out="$(env -u DRY_RUN PATH="${STUBS}:${PATH}" STUB_SERVE="${SERVE}" STUB_STORE="${work}/store" \
    BEADS_UPDATE_SKILLS_DIR="${work}/skills" zsh "${UPDATE}" --file "${PKG}" "$@" 2>&1)" || rc=$?
}

cp "${REAL_NIX}" "${PKG}"
readonly ORIGINAL="$(cat "${PKG}")"

run_update --help
expect_eq "help: rc 0" 0 "${rc}"
expect_has "help: names --version" "${out}" "--version V"

run_update --version 9.9.9
expect_eq "dry run: rc 0" 0 "${rc}"
expect_eq "dry run: file untouched" "${ORIGINAL}" "$(cat "${PKG}")"
expect_has "dry run: changed=1" "${out}" "changed=1"
expect_has "dry run: dry_run=1" "${out}" "dry_run=1"
expect_has "dry run: logs the write it would make" "${out}" "would write | file='${PKG:A}'"
expect_has "dry run: shows the new version in the diff" "${out}" '+  version = "9.9.9";'
expect_has "dry run: hash per platform" "${out}" "hash_darwin_arm64=sha256-SRI-dddddddd="
expect_has "dry run: built bd reports the version" "${out}" "bd_version=bd version 9.9.9 (stub)"
expect_has "dry run: flags the skill naming the old version" "${out}" "skill_review=bd-skill"

run_update --version v9.9.9 --execute
expect_eq "execute: rc 0" 0 "${rc}"
expect_has "execute: dry_run=0" "${out}" "dry_run=0"
expect_has "execute: changes=1" "${out}" "changes=1"
expect_eq "execute: version rewritten" 1 "$(grep -c '^  version = "9.9.9";$' "${PKG}")"
expect_eq "execute: x86_64-linux hash" 1 "$(grep -c 'platform = "linux_amd64"; hash = "sha256-SRI-aaaaaaaa=";' "${PKG}")"
expect_eq "execute: aarch64-linux hash" 1 "$(grep -c 'platform = "linux_arm64"; hash = "sha256-SRI-bbbbbbbb=";' "${PKG}")"
expect_eq "execute: x86_64-darwin hash" 1 "$(grep -c 'platform = "darwin_amd64"; hash = "sha256-SRI-cccccccc=";' "${PKG}")"
expect_eq "execute: aarch64-darwin hash" 1 "$(grep -c 'platform = "darwin_arm64"; hash = "sha256-SRI-dddddddd=";' "${PKG}")"
expect_eq "execute: exactly five lines changed" 5 \
  "$(diff <(print -r -- "${ORIGINAL}") "${PKG}" | grep -c '^>' || true)"

run_update --version 9.9.9 --execute
expect_eq "rerun: rc 0" 0 "${rc}"
expect_has "rerun: changed=0" "${out}" "changed=0"
expect_has "rerun: changes=0" "${out}" "changes=0"
expect_has "rerun: no skill review" "${out}" $'skill_review=\n'

cp "${REAL_NIX}" "${PKG}"
run_update --execute --no-build
expect_eq "latest: rc 0" 0 "${rc}"
expect_has "latest: takes the API's tag" "${out}" "version=9.9.9"
expect_has "latest: --no-build leaves out_path empty" "${out}" $'out_path=\n'

cp "${REAL_NIX}" "${PKG}"
run_update --version 9.9.7 --execute
expect_eq "no release: rc 1" 1 "${rc}"
expect_has "no release: says so" "${out}" "No checksums.txt for this release; is the version right? | version='9.9.7'"
expect_eq "no release: file untouched" "${ORIGINAL}" "$(cat "${PKG}")"

run_update --version 9.9.8 --execute
expect_eq "missing asset: rc 1" 1 "${rc}"
expect_has "missing asset: names it" "${out}" "asset='beads_9.9.8_darwin_arm64.tar.gz'"
expect_eq "missing asset: file untouched" "${ORIGINAL}" "$(cat "${PKG}")"

run_update --version latest --execute
expect_eq "bad version: rc 1" 1 "${rc}"
expect_has "bad version: names it" "${out}" "Not a release version | version='latest'"
expect_eq "bad version: file untouched" "${ORIGINAL}" "$(cat "${PKG}")"

rc=0
out="$(env -u DRY_RUN PATH="${STUBS}:${PATH}" STUB_SERVE="${SERVE}" STUB_STORE="${work}/store" STUB_BD_VERSION=1.0.0 \
  BEADS_UPDATE_SKILLS_DIR="${work}/skills" zsh "${UPDATE}" --file "${PKG}" --version 9.9.9 --execute 2>&1)" || rc=$?
expect_eq "wrong built version: rc 1" 1 "${rc}"
expect_has "wrong built version: says so" "${out}" "Built bd reports another version; nothing written | want='9.9.9'"
expect_eq "wrong built version: file untouched" "${ORIGINAL}" "$(cat "${PKG}")"

run_update --bogus
expect_eq "unknown flag: rc 1" 1 "${rc}"
expect_has "unknown flag: prints help" "${out}" "Usage:"

print -r -- "passed=${passed} failed=${failed}"
(( failed == 0 ))
