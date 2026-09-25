#!/usr/bin/env zsh
# Capture this machine's brew state into tests/fixtures/this-machine/ for the no-false-alarm
# tests. Read-only: every brew call here is from the check-mode allowlist (§2.7). Receipts are
# trimmed to installed_on_request/installed_as_dependency/source.{tap,path} with the prefix
# replaced by __PREFIX__; brew info is trimmed to the alias-map fields; paths a receipt or a
# tap's Casks/ directory names become empty placeholder files so existence checks reproduce.
#
#   zsh tests/capture-fixtures.zsh            # writes tests/fixtures/this-machine/
#   zsh tests/capture-fixtures.zsh <outdir>   # writes elsewhere
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly NEW_MACHINE_DIR="${SCRIPT_DIR:h}"
readonly LOG_LIB="${NEW_MACHINE_DIR:h}/zsh/plugins/log.zsh"
if [[ ! -r "${LOG_LIB}" ]]; then
  print -u2 "[ERROR] missing logging lib | path='${LOG_LIB}'"
  exit 3
fi
source "${LOG_LIB}"
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_COLOR=0 HOMEBREW_NO_EMOJI=1

readonly OUT_DIR="${1:-${SCRIPT_DIR}/fixtures/this-machine}"
readonly SHARED_BREWFILE="${NEW_MACHINE_DIR}/Brewfile"

if ! command -v brew &> /dev/null; then
  log::err "brew not on PATH"
  exit 3
fi
if [[ "${OUT_DIR}" != "${SCRIPT_DIR}/fixtures/"* && "${OUT_DIR}" != /private/tmp/* && "${OUT_DIR}" != /tmp/* && "${OUT_DIR}" != "${TMPDIR:-/nonexistent}"* ]]; then
  log::err "refusing to write outside tests/fixtures or a temp dir | out='${OUT_DIR}'"
  exit 64
fi

readonly PREFIX="$(brew --prefix)"
readonly CELLAR="$(brew --cellar)"
readonly CASKROOM="$(brew --caskroom)"
log::info "capturing | prefix='${PREFIX}' out='${OUT_DIR}'"
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/prefix" "${OUT_DIR}/tap_info"

# Replace the real prefix in a path with the placeholder the harness splices back.
placeholder_path() {
  local p="${1}"
  if [[ "${p}" == "${PREFIX}/"* ]]; then
    print -r -- "__PREFIX__${p#${PREFIX}}"
  else
    print -r -- "${p}"
  fi
}

# Empty file at the fixture-relative location of a real path under the prefix, when it exists.
mirror_existence() {
  local real="${1}"
  [[ "${real}" == "${PREFIX}/"* && -e "${real}" ]] || return 0
  local rel="${real#${PREFIX}/}"
  mkdir -p "${OUT_DIR}/prefix/${rel:h}"
  : > "${OUT_DIR}/prefix/${rel}"
}

trim_receipt() {
  local src="${1}" dst="${2}"
  mkdir -p "${dst:h}"
  jq --arg prefix "${PREFIX}" '
    {installed_on_request: (.installed_on_request // false),
     installed_as_dependency: (.installed_as_dependency // false),
     source: {tap: .source.tap,
              path: (.source.path | if . == null then null elif startswith($prefix + "/") then "__PREFIX__" + .[($prefix | length):] else . end)}}' \
    "${src}" > "${dst}"
}

local receipt real_path
for receipt in "${CELLAR}"/*/*/INSTALL_RECEIPT.json(N); do
  trim_receipt "${receipt}" "${OUT_DIR}/prefix/Cellar/${receipt#${CELLAR}/}"
  real_path="$(jq -r '.source.path // empty' "${receipt}")"
  [[ -n "${real_path}" ]] && mirror_existence "${real_path}"
done
for receipt in "${CASKROOM}"/*/.metadata/INSTALL_RECEIPT.json(N); do
  trim_receipt "${receipt}" "${OUT_DIR}/prefix/Caskroom/${receipt#${CASKROOM}/}"
  real_path="$(jq -r '.source.path // empty' "${receipt}")"
  [[ -n "${real_path}" ]] && mirror_existence "${real_path}"
done

brew info --json=v2 --installed | jq '{
  formulae: [.formulae[] | {name, full_name, tap, aliases: (.aliases // []), oldnames: (.oldnames // [])}],
  casks: [.casks[] | {token, full_token, tap, old_tokens: (.old_tokens // [])}]}' > "${OUT_DIR}/info_installed.json"

brew tap > "${OUT_DIR}/taps.txt"
brew list --formula --full-name > "${OUT_DIR}/list_formula.txt"
brew list --cask > "${OUT_DIR}/list_cask.txt"

local tap repo cask_rb
for tap in ${(f)"$(<"${OUT_DIR}/taps.txt")"}; do
  [[ -n "${tap}" ]] || continue
  brew tap-info --json "${tap}" | jq '[.[] | {name, formula_names: (.formula_names // []), cask_tokens: (.cask_tokens // []), installed}]' \
    > "${OUT_DIR}/tap_info/${tap%%/*}__${tap#*/}.json"
  repo="$(brew --repository "${tap}")"
  for cask_rb in "${repo}"/Casks/**/*.rb(N); do
    mirror_existence "${cask_rb}"
  done
done

if command -v code &> /dev/null; then
  code --list-extensions > "${OUT_DIR}/vscode.txt"
else
  : > "${OUT_DIR}/vscode.txt"
  log::warn "code not on PATH; vscode.txt is empty"
fi

local rc=0
brew bundle check --no-upgrade --verbose --file="${SHARED_BREWFILE}" > "${OUT_DIR}/bundle_check.out" 2>&1 || rc=$?
print -r -- "${rc}" > "${OUT_DIR}/bundle_check.rc"
brew bundle dump --file=- --formula --cask --tap --vscode --no-describe > "${OUT_DIR}/bundle_dump.out"
cp "${SHARED_BREWFILE}" "${OUT_DIR}/Brewfile.global"

log::info "captured | receipts=$(find "${OUT_DIR}/prefix" -name INSTALL_RECEIPT.json | wc -l | tr -d ' ') taps=$(wc -l < "${OUT_DIR}/taps.txt" | tr -d ' ') bundle_check_rc=${rc}"
