# shellcheck shell=bash
# Shared helpers for tests/test_*.sh. Source, don't execute.
# Every test runs the CLI in a fake HOME under mktemp with brew/launchctl/curl shims on PATH.
# world_new aborts (exit 99) before touching anything if HOME would resolve to the real home;
# nothing here may ever read or write outside $FIX once a world exists.

# shellcheck disable=SC2034  # used by the sourcing test files
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="${REPO_DIR}/tests"
ORIG_HOME="$(cd "${HOME}" && pwd -P)"
ORIG_PATH="${PATH}"
ORIG_CONFIG_DIR="$(cd "${REPO_DIR}/.." && pwd)"
PASS=0
FAIL=0
FIX=""
WORLD_PIDS=()
OUT=""
ERR=""
RC=0
HERMETIC_ENV=()

pass() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n       %s\n' "$1" "$2" >&2; }
abort() { printf 'ABORT: %s\n' "$*" >&2; exit 99; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [[ "${expected}" == "${actual}" ]]; then pass "${name}"
  else fail "${name}" "expected: ${expected}
       actual:   ${actual}"
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "${haystack}" == *"${needle}"* ]]; then pass "${name}"
  else fail "${name}" "missing: ${needle}
       in:      ${haystack}"
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then pass "${name}"
  else fail "${name}" "unexpected: ${needle}
       in:         ${haystack}"
  fi
}

assert_json() {
  local name="$1" file="$2" expr="$3" expected="$4" actual
  if [[ ! -f "${file}" ]]; then fail "${name}" "no such file: ${file}"; return; fi
  actual="$(jq -r "${expr}" "${file}" 2>&1)"
  assert_eq "${name}" "${expected}" "${actual}"
}

assert_file() {
  local name="$1" path="$2"
  if [[ -e "${path}" ]]; then pass "${name}"; else fail "${name}" "missing file: ${path}"; fi
}

assert_no_file() {
  local name="$1" path="$2"
  if [[ ! -e "${path}" ]]; then pass "${name}"; else fail "${name}" "unexpected file: ${path}"; fi
}

# The brew shim logs MUTATION lines, the launchctl shim logs bootstrap, the curl shim logs
# every call; none of the three may appear in a read-only run.
assert_no_mutation() {
  local name="$1" problems=""
  local brew_log="${BREW_SHIM_LOG_DIR}/brew.log" lc_log="${BREW_SHIM_LOG_DIR}/launchctl.log"
  local curl_log="${BREW_SHIM_LOG_DIR}/curl.log"
  if [[ -f "${brew_log}" ]] && grep -q '^MUTATION' "${brew_log}"; then
    problems+="brew: $(grep '^MUTATION' "${brew_log}" | head -n 3 | tr '\n' ';') "
  fi
  if [[ -f "${lc_log}" ]] && grep -q '^bootstrap' "${lc_log}"; then
    problems+="launchctl: bootstrap seen "
  fi
  if [[ -s "${curl_log}" ]]; then
    problems+="curl: $(head -n 1 "${curl_log}")"
  fi
  if [[ -z "${problems}" ]]; then pass "${name}"; else fail "${name}" "${problems}"; fi
}

report() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "${PASS}" "${FAIL}"
  (( FAIL == 0 ))
}

# ── World ────────────────────────────────────────────────────────────────────

# Refuses any path that is not strictly inside $FIX, so every rm -rf below is scoped.
_assert_in_fix() {
  local p="$1"
  [[ -n "${FIX}" ]] || abort "no world"
  [[ "${p}" == "${FIX}/"* ]] || abort "path escapes the world: ${p}"
}

world_new() {
  [[ -z "${FIX}" ]] || abort "world_new without world_teardown"
  local tmp_root fix_real home_real
  tmp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  FIX="$(mktemp -d "${tmp_root}/nm-test.XXXXXX")"
  fix_real="$(cd "${FIX}" && pwd -P)"
  [[ "${fix_real}" == "${tmp_root}/"* ]] || abort "mktemp dir is not under ${tmp_root}: ${fix_real}"
  [[ "${fix_real}" != "${ORIG_HOME}" && "${fix_real}" != "${ORIG_HOME}/"* ]] || abort "mktemp dir is inside the real home: ${fix_real}"
  FIX="${fix_real}"
  HOME="${FIX}/home"
  mkdir -p "${HOME}"
  home_real="$(cd "${HOME}" && pwd -P)"
  [[ "${home_real}" != "${ORIG_HOME}" ]] || abort "fake HOME resolves to the real home"
  [[ "${home_real}" == "${FIX}/home" ]] || abort "fake HOME resolves outside the world: ${home_real}"
  export HOME
  trap world_teardown EXIT

  mkdir -p "${HOME}/Desktop" "${HOME}/Library/LaunchAgents" "${HOME}/.local/state" "${HOME}/.local/share" "${HOME}/.config"
  export TZ=UTC
  export XDG_CONFIG_HOME="${HOME}/.config" XDG_DATA_HOME="${HOME}/.local/share"
  export XDG_STATE_HOME="${HOME}/.local/state" XDG_CACHE_HOME="${HOME}/.cache"
  export NEW_MACHINE_SHARED_DIR="${HOME}/.config/new-machine"
  export NEW_MACHINE_LOCAL_DIR="${XDG_DATA_HOME}/new-machine"
  export NEW_MACHINE_STATE_DIR="${XDG_STATE_HOME}/new-machine"
  export NEW_MACHINE_DESKTOP_DIR="${HOME}/Desktop"
  export NEW_MACHINE_LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
  export NEW_MACHINE_DF_GIT_DIR="${HOME}/dotfiles.git" NEW_MACHINE_LDF_GIT_DIR="${HOME}/.local/local-dotfiles.git"
  export NEW_MACHINE_DF_HOOKS="${HOME}/.config/git/dotfiles-hooks" NEW_MACHINE_LDF_HOOKS="${HOME}/.config/git/local-dotfiles-hooks"
  export DOTFILES_REMOTE="${FIX}/remotes/dotfiles.git"
  export NEW_MACHINE_BREW_PREFIXES=""
  export NEW_MACHINE_NOW=1789000000 NEW_MACHINE_HOST=testhost
  # The default 60 s retry would stall every erroring verify test; the retry test sets its own.
  export NEW_MACHINE_RETRY_SECS=0
  export BREW_SHIM_LOG_DIR="${FIX}/shimlog" LAUNCHCTL_SHIM_STATE="${FIX}/launchctl"
  export XCODE_SELECT_SHIM_STATE="${FIX}/xcode-select"
  export GIT_CONFIG_NOSYSTEM=1
  mkdir -p "${BREW_SHIM_LOG_DIR}" "${LAUNCHCTL_SHIM_STATE}"
  unset NEW_MACHINE_INVOKED_BY BREW_SHIM_ALLOW_MUTATION BREW_SHIM_FIXTURE BOB_SHIM_LS BOB_SHIM_RC
  unset NEW_MACHINE_BREW NEW_MACHINE_NOTIFIER NEW_MACHINE_CODE NEW_MACHINE_CHECK_TIMEOUT_SECS
  # The default busy pattern would see a real brew running on this machine; start_busy_brew
  # points it at a sleeper the test owns.
  export NEW_MACHINE_BREW_BUSY_PATTERN="nm-tests-no-such-process-$$"

  # Hermetic PATH: symlinks to the real binaries named in real-tools.txt, then the shims.
  mkdir -p "${FIX}/tools" "${FIX}/shims"
  local name resolved
  while IFS= read -r name || [[ -n "${name}" ]]; do
    [[ -n "${name}" && "${name}" != \#* ]] || continue
    resolved="$(PATH="${ORIG_PATH}" bash -c "type -P '${name}'" 2>/dev/null || true)"
    [[ -n "${resolved}" ]] || abort "real tool not found: ${name}"
    ln -s "${resolved}" "${FIX}/tools/${name}"
  done < "${TESTS_DIR}/real-tools.txt"
  local shim
  for shim in "${TESTS_DIR}"/shims/*; do
    [[ "$(basename "${shim}")" == npm ]] && continue
    cp "${shim}" "${FIX}/shims/"
  done
  chmod +x "${FIX}"/shims/*
  PATH="${FIX}/shims:${FIX}/tools"
  export PATH

  # The "checked out" config the CLI reads: copies of the tier files, symlinks to the code.
  world_install_config "${HOME}/.config"
  # git needs an identity to commit; init.defaultBranch keeps the fake repos on main.
  mkdir -p "${HOME}/.config/git"
  printf '[user]\n\tname = new-machine tests\n\temail = tests@example.invalid\n[init]\n\tdefaultBranch = main\n' > "${HOME}/.config/git/config"
}

# Populate <dir>/new-machine (Brewfile, ignore, exclude template, lib/ + bin/ symlinks) and
# <dir>/zsh/plugins (log libs) from the repo under test.
world_install_config() {
  local dir="$1"
  _assert_in_fix "${dir}"
  mkdir -p "${dir}/new-machine" "${dir}/zsh/plugins"
  cp "${REPO_DIR}/Brewfile" "${dir}/new-machine/Brewfile"
  cp "${REPO_DIR}/local-dotfiles-exclude" "${dir}/new-machine/local-dotfiles-exclude"
  if [[ -f "${REPO_DIR}/Brewfile.ignore" ]]; then cp "${REPO_DIR}/Brewfile.ignore" "${dir}/new-machine/Brewfile.ignore"; fi
  rm -f "${dir}/new-machine/lib" "${dir}/new-machine/bin"
  ln -s "${REPO_DIR}/lib" "${dir}/new-machine/lib"
  ln -s "${REPO_DIR}/bin" "${dir}/new-machine/bin"
  cp "${ORIG_CONFIG_DIR}/zsh/plugins/log.zsh" "${ORIG_CONFIG_DIR}/zsh/plugins/log_rotate.zsh" "${dir}/zsh/plugins/"
}

# Idempotent; the EXIT trap may run it after an explicit call.
world_teardown() {
  [[ -n "${FIX}" ]] || return 0
  local p
  for p in "${WORLD_PIDS[@]}"; do
    pkill -P "${p}" 2>/dev/null || true
    kill "${p}" 2>/dev/null || true
    wait "${p}" 2>/dev/null || true
  done
  WORLD_PIDS=()
  local tmp_root
  tmp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
  [[ "${FIX}" == "${tmp_root}/"* && "${FIX}" != "${ORIG_HOME}"* ]] || abort "refusing to remove ${FIX}"
  rm -rf "${FIX}"
  FIX=""
  HOME="${ORIG_HOME}"
  PATH="${ORIG_PATH}"
  export HOME PATH
}

# A fresh Mac: no dotfiles, no repos, no config. The CLI then runs from a snapshot of the
# shared checkout kept outside HOME, exactly like a first run from a clone.
world_empty_home() {
  _assert_in_fix "${HOME}"
  [[ "${HOME}" == "${FIX}/home" ]] || abort "world_empty_home: unexpected HOME ${HOME}"
  if [[ "${NEW_MACHINE_SHARED_DIR}" != "${FIX}/shared/new-machine" ]]; then
    mkdir -p "${FIX}/shared/zsh/plugins"
    rm -rf "${FIX}/shared/new-machine"
    cp -R "${NEW_MACHINE_SHARED_DIR}" "${FIX}/shared/new-machine"
    cp "${NEW_MACHINE_SHARED_DIR}/../zsh/plugins/log.zsh" "${NEW_MACHINE_SHARED_DIR}/../zsh/plugins/log_rotate.zsh" "${FIX}/shared/zsh/plugins/"
    export NEW_MACHINE_SHARED_DIR="${FIX}/shared/new-machine"
  fi
  rm -rf "${HOME}"
  mkdir -p "${HOME}/Desktop" "${HOME}/Library/LaunchAgents"
}

# Materialize tests/fixtures/NAME into $FIX/brew; receipts get the fake prefix spliced into
# source.path. Also installs the fixture's global Brewfile as the machine's and clears every
# ignore list and the local tier, so each test starts from "empty local/ignores".
world_use_fixture() {
  local name="$1" src="${TESTS_DIR}/fixtures/$1" dst="${FIX}/brew"
  [[ -d "${src}" ]] || abort "no fixture ${name}"
  _assert_in_fix "${dst}"
  rm -rf "${dst}"
  mkdir -p "${dst}"
  cp -R "${src}/." "${dst}/"
  local receipt
  while IFS= read -r receipt; do
    jq --arg p "${dst}/prefix" '.source.path |= (if . == null then . else sub("^__PREFIX__"; $p) end)' "${receipt}" > "${receipt}.tmp"
    mv "${receipt}.tmp" "${receipt}"
  done < <(find "${dst}/prefix" -name INSTALL_RECEIPT.json 2>/dev/null)
  export BREW_SHIM_FIXTURE="${dst}"
  if [[ -f "${dst}/Brewfile.global" ]]; then
    mkdir -p "${NEW_MACHINE_SHARED_DIR}"
    cp "${dst}/Brewfile.global" "${NEW_MACHINE_SHARED_DIR}/Brewfile"
    if [[ -d "${HOME}/.config/new-machine" ]]; then cp "${dst}/Brewfile.global" "${HOME}/.config/new-machine/Brewfile"; fi
  fi
  rm -f "${NEW_MACHINE_SHARED_DIR}/Brewfile.ignore" "${HOME}/.config/new-machine/Brewfile.ignore"
  rm -f "${NEW_MACHINE_LOCAL_DIR}/Brewfile" "${NEW_MACHINE_LOCAL_DIR}/Brewfile.ignore"
}

# Select which canned `brew bundle check` transcript the shim replays.
world_bundle_check() {
  local variant="$1"
  [[ -f "${BREW_SHIM_FIXTURE}/bundle_check.${variant}.out" ]] || abort "no bundle_check variant ${variant}"
  cp "${BREW_SHIM_FIXTURE}/bundle_check.${variant}.out" "${BREW_SHIM_FIXTURE}/bundle_check.out"
  cp "${BREW_SHIM_FIXTURE}/bundle_check.${variant}.rc" "${BREW_SHIM_FIXTURE}/bundle_check.rc"
}

# Copy a fixture text file, expanding the __FIX__ placeholder (used for include-declared paths).
fixture_file_subst() {
  local src="$1" dst="$2" line
  [[ -f "${src}" ]] || abort "no fixture file ${src}"
  mkdir -p "$(dirname "${dst}")"
  : > "${dst}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    printf '%s\n' "${line//__FIX__/${FIX}}" >> "${dst}"
  done < "${src}"
}

world_local_brewfile() {
  mkdir -p "${NEW_MACHINE_LOCAL_DIR}"
  fixture_file_subst "${BREW_SHIM_FIXTURE}/Brewfile.local.$1" "${NEW_MACHINE_LOCAL_DIR}/Brewfile"
}

# world_ignore <global|local> <variant>: install a Brewfile.ignore variant into one tier.
world_ignore() {
  local tier="$1" variant="$2"
  case "${tier}" in
    global)
      fixture_file_subst "${BREW_SHIM_FIXTURE}/Brewfile.ignore.${variant}" "${NEW_MACHINE_SHARED_DIR}/Brewfile.ignore"
      if [[ -d "${HOME}/.config/new-machine" ]]; then
        fixture_file_subst "${BREW_SHIM_FIXTURE}/Brewfile.ignore.${variant}" "${HOME}/.config/new-machine/Brewfile.ignore"
      fi ;;
    local)
      mkdir -p "${NEW_MACHINE_LOCAL_DIR}"
      fixture_file_subst "${BREW_SHIM_FIXTURE}/Brewfile.ignore.${variant}" "${NEW_MACHINE_LOCAL_DIR}/Brewfile.ignore" ;;
    *) abort "world_ignore: bad tier ${tier}" ;;
  esac
}

# Add an on-request core formula to the materialized fixture (receipt, list line, info entry).
fixture_add_formula() {
  local name="$1" tap="${2:-homebrew/core}" full="$1"
  [[ "${tap}" == homebrew/core ]] || full="${tap}/${name}"
  local dir="${BREW_SHIM_FIXTURE}/prefix/Cellar/${name}/1.0"
  mkdir -p "${dir}"
  jq -n --arg tap "${tap}" --arg p "${BREW_SHIM_FIXTURE}/prefix/api/formula.jws.json" \
    '{installed_on_request: true, installed_as_dependency: false, source: {tap: $tap, path: $p}}' > "${dir}/INSTALL_RECEIPT.json"
  printf '%s\n' "${full}" >> "${BREW_SHIM_FIXTURE}/list_formula.txt"
  jq --arg name "${name}" --arg full "${full}" --arg tap "${tap}" \
    '.formulae += [{name: $name, full_name: $full, tap: $tap, aliases: [], oldnames: []}]' \
    "${BREW_SHIM_FIXTURE}/info_installed.json" > "${BREW_SHIM_FIXTURE}/info_installed.json.tmp"
  mv "${BREW_SHIM_FIXTURE}/info_installed.json.tmp" "${BREW_SHIM_FIXTURE}/info_installed.json"
}

# Add an on-request cask to the materialized fixture.
fixture_add_cask() {
  local token="$1" tap="${2:-homebrew/cask}"
  local dir="${BREW_SHIM_FIXTURE}/prefix/Caskroom/${token}/.metadata"
  mkdir -p "${dir}"
  jq -n --arg tap "${tap}" --arg p "${BREW_SHIM_FIXTURE}/prefix/api/cask.jws.json" \
    '{installed_on_request: true, installed_as_dependency: false, source: {tap: $tap, path: $p}}' > "${dir}/INSTALL_RECEIPT.json"
  printf '%s\n' "${token}" >> "${BREW_SHIM_FIXTURE}/list_cask.txt"
  jq --arg token "${token}" --arg tap "${tap}" \
    '.casks += [{token: $token, full_token: $token, tap: $tap, old_tokens: []}]' \
    "${BREW_SHIM_FIXTURE}/info_installed.json" > "${BREW_SHIM_FIXTURE}/info_installed.json.tmp"
  mv "${BREW_SHIM_FIXTURE}/info_installed.json.tmp" "${BREW_SHIM_FIXTURE}/info_installed.json"
}

# Remove a keg from the materialized fixture (receipt dir + list line + info entry).
fixture_remove_formula() {
  local keg="$1" full="${2:-$1}" list="${BREW_SHIM_FIXTURE}/list_formula.txt" line
  _assert_in_fix "${BREW_SHIM_FIXTURE}/prefix/Cellar/${keg}"
  rm -rf "${BREW_SHIM_FIXTURE}/prefix/Cellar/${keg}"
  : > "${list}.tmp"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == "${full}" ]] || printf '%s\n' "${line}" >> "${list}.tmp"
  done < "${list}"
  mv "${list}.tmp" "${list}"
  jq --arg keg "${keg}" '.formulae |= map(select(.name != $keg))' \
    "${BREW_SHIM_FIXTURE}/info_installed.json" > "${BREW_SHIM_FIXTURE}/info_installed.json.tmp"
  mv "${BREW_SHIM_FIXTURE}/info_installed.json.tmp" "${BREW_SHIM_FIXTURE}/info_installed.json"
}

shim_add() { cp "${TESTS_DIR}/shims/$1" "${FIX}/shims/$1"; chmod +x "${FIX}/shims/$1"; }
shim_remove() { rm -f "${FIX}/shims/$1"; }
shim_logs_reset() { rm -f "${BREW_SHIM_LOG_DIR}"/*.log; }
shim_log() { local f="${BREW_SHIM_LOG_DIR}/$1.log"; if [[ -f "${f}" ]]; then cat "${f}"; fi; }

# ── Running the code under test ──────────────────────────────────────────────

# The environment every process under test gets, and nothing else: the real shell's ZDOTDIR,
# PATH extras and plugins can never reach the code. Fills HERMETIC_ENV for `env -i`.
hermetic_env() {
  HERMETIC_ENV=("HOME=${HOME}" "PATH=${PATH}" "TZ=${TZ:-UTC}" "GIT_CONFIG_NOSYSTEM=1")
  local v
  for v in "${!XDG_@}" "${!NEW_MACHINE_@}" "${!BREW_SHIM_@}" "${!BOB_SHIM_@}" "${!LAUNCHCTL_SHIM_@}" "${!XCODE_SELECT_SHIM_@}"; do
    HERMETIC_ENV+=("${v}=${!v}")
  done
  if [[ -n "${DOTFILES_REMOTE+x}" ]]; then HERMETIC_ENV+=("DOTFILES_REMOTE=${DOTFILES_REMOTE}"); fi
}

# nm ARGS...: the CLI under env -i with only the contract's variables; captures OUT, ERR, RC.
nm() { nm_run "${REPO_DIR}/bin/new-machine" "$@"; }

nm_run() {
  local script="$1"; shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" "${script}" "$@" > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}

# bs ARGS...: bin/bootstrap.sh as the one-liner runs it. NEW_MACHINE_SHARED_DIR is withheld so
# the hand-off has to find new-machine in the checkout it just made; bs_argv and bs_pipe are the
# `sh -c "$(curl …)"` and `curl … | sh` shapes.
bs() { bs_run /bin/sh "${REPO_DIR}/bin/bootstrap.sh" "$@"; }
bs_argv() { bs_run /bin/sh -c "$(cat "${REPO_DIR}/bin/bootstrap.sh")" bootstrap "$@"; }
bs_pipe() { bs_run_stdin "${REPO_DIR}/bin/bootstrap.sh" /bin/sh; }

bs_env() {
  hermetic_env
  BS_ENV=()
  local v
  for v in "${HERMETIC_ENV[@]}"; do
    [[ "${v}" == NEW_MACHINE_SHARED_DIR=* ]] || BS_ENV+=("${v}")
  done
}

bs_run() {
  bs_env
  RC=0
  env -i "${BS_ENV[@]}" "$@" > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}

bs_run_stdin() {
  local script="$1"; shift
  bs_env
  RC=0
  cat "${script}" | env -i "${BS_ENV[@]}" "$@" > "${FIX}/nm.out" 2> "${FIX}/nm.err" || RC=$?
  OUT="$(cat "${FIX}/nm.out")"
  ERR="$(cat "${FIX}/nm.err")"
}

# zfn LIB FN ARGS...: one pure lib function, in the same hermetic environment as the CLI.
# common.zsh is sourced first because every lib reads the env contract it defines; it guards
# against being sourced twice.
zfn() {
  local lib="$1" fn="$2"; shift 2
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -c 'source "$1"; if [[ "$2" != "$1" ]]; then source "$2"; fi; shift 2; "$@"' _ \
    "${REPO_DIR}/lib/common.zsh" "${REPO_DIR}/lib/${lib}" "${fn}" "$@" > "${FIX}/zfn.out" 2> "${FIX}/zfn.err" || RC=$?
  OUT="$(cat "${FIX}/zfn.out")"
  ERR="$(cat "${FIX}/zfn.err")"
}

# Save $OUT as JSON and print the path (for jq assertions on `--json` output).
out_json() {
  printf '%s\n' "${OUT}" > "${FIX}/out.json"
  printf '%s' "${FIX}/out.json"
}

# step_get STEP JQ: a field of one step in the saved summary, e.g. step_get brew .status
step_get() {
  jq -r --arg s "$1" ".steps[] | select(.step==\$s) | $2" "${FIX}/out.json" 2>&1
}

newest_run_dir() {
  local d latest=""
  for d in "${NEW_MACHINE_STATE_DIR}"/runs/*/; do
    [[ -d "${d}" ]] && latest="${d}"
  done
  printf '%s' "${latest%/}"
}

sha256() { shasum -a 256 "$1" | cut -c1-64; }

# Seconds and days move NEW_MACHINE_NOW; consecutive runs must not share a run id.
bump_now() { NEW_MACHINE_NOW=$((NEW_MACHINE_NOW + $1 * 86400)); export NEW_MACHINE_NOW; }
bump_now_secs() { NEW_MACHINE_NOW=$((NEW_MACHINE_NOW + $1)); export NEW_MACHINE_NOW; }

# ── Fake dotfiles repos ──────────────────────────────────────────────────────

# A remote for the shared dotfiles: the df-remote seed tree plus the current shared config and
# code, committed into a bare repo at $FIX/remotes/dotfiles.git (what DOTFILES_REMOTE points at).
seed_df_remote() {
  local work="${FIX}/remotes/dotfiles-work" bare="${FIX}/remotes/dotfiles.git" shared="${NEW_MACHINE_SHARED_DIR}"
  mkdir -p "${work}/.config/new-machine/lib" "${work}/.config/new-machine/bin" "${work}/.config/zsh/plugins" "${work}/.config/git"
  cp -R "${TESTS_DIR}/fixtures/df-remote/." "${work}/"
  cp "${shared}/Brewfile" "${shared}/local-dotfiles-exclude" "${work}/.config/new-machine/"
  if [[ -f "${shared}/Brewfile.ignore" ]]; then cp "${shared}/Brewfile.ignore" "${work}/.config/new-machine/"; fi
  cp -R "${shared}/lib/." "${work}/.config/new-machine/lib/"
  cp -R "${shared}/bin/." "${work}/.config/new-machine/bin/"
  cp "${shared}/../zsh/plugins/log.zsh" "${shared}/../zsh/plugins/log_rotate.zsh" "${work}/.config/zsh/plugins/"
  printf '[user]\n\tname = new-machine tests\n\temail = tests@example.invalid\n[init]\n\tdefaultBranch = main\n' > "${work}/.config/git/config"
  chmod +x "${work}"/.config/bin/* "${work}"/.config/claude/bin/* "${work}"/.config/new-machine/bin/*
  git init -q --bare --initial-branch=main "${bare}"
  git --git-dir="${bare}" --work-tree="${work}" add -A -- "${work}"
  git --git-dir="${bare}" --work-tree="${work}" -c user.name=seed -c user.email=seed@example.invalid commit -q -m "seed dotfiles remote"
}

# An origin for the local-dotfiles repo (push tests). seed_fake_repos must have run.
seed_ldf_remote() {
  git init -q --bare --initial-branch=main "${FIX}/remotes/local-dotfiles.git"
  git --git-dir="${NEW_MACHINE_LDF_GIT_DIR}" remote add origin "${FIX}/remotes/local-dotfiles.git"
  # A bootstrapped machine has run `git ldf push --set-upstream origin main`; a bare `git push`
  # needs that tracking config even before the first commit exists.
  git --git-dir="${NEW_MACHINE_LDF_GIT_DIR}" config branch.main.remote origin
  git --git-dir="${NEW_MACHINE_LDF_GIT_DIR}" config branch.main.merge refs/heads/main
}

# The two bare repos as they exist on a bootstrapped machine: dotfiles.git tracking the files
# currently under $HOME/.config (so decree commits land on top of a real HEAD), and an empty
# local-dotfiles.git carrying the template exclude. Both with hooksPath wired.
seed_fake_repos() {
  git init -q --bare --initial-branch=main "${NEW_MACHINE_DF_GIT_DIR}"
  local -a files=()
  local f
  while IFS= read -r f; do files+=("${f}"); done < <(find "${HOME}/.config" -type f | sort)
  git --git-dir="${NEW_MACHINE_DF_GIT_DIR}" --work-tree="${HOME}" add -- "${files[@]}"
  git --git-dir="${NEW_MACHINE_DF_GIT_DIR}" --work-tree="${HOME}" commit -q -m "seed dotfiles"
  git --git-dir="${NEW_MACHINE_DF_GIT_DIR}" config --local core.hooksPath "${NEW_MACHINE_DF_HOOKS}"

  git init -q --bare --initial-branch=main "${NEW_MACHINE_LDF_GIT_DIR}"
  mkdir -p "${NEW_MACHINE_LDF_GIT_DIR}/info"
  cp "${NEW_MACHINE_SHARED_DIR}/local-dotfiles-exclude" "${NEW_MACHINE_LDF_GIT_DIR}/info/exclude"
  git --git-dir="${NEW_MACHINE_LDF_GIT_DIR}" config --local core.hooksPath "${NEW_MACHINE_LDF_HOOKS}"
}

df_git() { git --git-dir="${NEW_MACHINE_DF_GIT_DIR}" --work-tree="${HOME}" "$@"; }
ldf_git() { git --git-dir="${NEW_MACHINE_LDF_GIT_DIR}" --work-tree="${HOME}/.local" "$@"; }

# ── The non-brew steps' happy path ───────────────────────────────────────────

# Everything the non-brew checks look at, in its "ok" state: sorted karabiner.json, the claude
# notification hook, a loaded dotfiles-jobs job, and the weekly job's plist rendered by the lib
# itself (so weekly_verify compares equal). Shim logs are reset afterwards so a following
# read-only run can still assert_no_mutation.
seed_home_baseline() {
  local uid label plist
  uid="$(id -u)"
  mkdir -p "${HOME}/.config/karabiner" "${HOME}/.config/claude/bin" "${HOME}/.config/bin" "${HOME}/.claude"
  cp "${TESTS_DIR}/fixtures/df-remote/.config/karabiner/karabiner.json" "${HOME}/.config/karabiner/karabiner.json"
  cp "${TESTS_DIR}/fixtures/df-remote/.config/claude/bin/initialize.sh" "${HOME}/.config/claude/bin/initialize.sh"
  cp "${TESTS_DIR}/fixtures/df-remote/.config/claude/bin/notification-fire.sh" "${HOME}/.config/claude/bin/notification-fire.sh"
  cp "${TESTS_DIR}/fixtures/df-remote/.config/bin/git-health" "${HOME}/.config/bin/git-health"
  chmod +x "${HOME}/.config/claude/bin/initialize.sh" "${HOME}/.config/claude/bin/notification-fire.sh" "${HOME}/.config/bin/git-health"
  "${HOME}/.config/claude/bin/initialize.sh"

  label="com.$(id -un).dotfiles-jobs"
  plist="${HOME}/Library/LaunchAgents/${label}.plist"
  jq -n --arg label "${label}" '{Label: $label, ProgramArguments: ["/bin/zsh", "dotfiles", "jobs", "tick"], StartInterval: 300}' \
    | plutil -convert xml1 - -o "${plist}"
  touch "${LAUNCHCTL_SHIM_STATE}/${label}"

  zfn launchd.zsh launchd::render_plist
  if (( RC != 0 )) || [[ -z "${OUT}" ]]; then
    fail "seed_home_baseline: launchd::render_plist" "rc=${RC} ${ERR}"
  else
    printf '%s\n' "${OUT}" > "${HOME}/Library/LaunchAgents/com.$(id -un).new-machine-verify.plist"
    touch "${LAUNCHCTL_SHIM_STATE}/com.$(id -un).new-machine-verify"
  fi
  shim_logs_reset
}

# A brew that is busy: a long sleeper whose argv carries a unique marker for pgrep -f.
start_busy_brew() {
  local marker="nm-busy-brew-$$-${RANDOM}"
  # Two commands, so bash keeps the marker in its own argv instead of exec'ing sleep directly;
  # its stderr is dropped so the eventual kill does not print "Terminated" into the test output.
  bash -c "sleep 300; true # ${marker}" 2>/dev/null &
  WORLD_PIDS+=("$!")
  export NEW_MACHINE_BREW_BUSY_PATTERN="${marker}"
  # pgrep must see it before the CLI runs.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -f "${marker}" >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  abort "busy sleeper did not start"
}

# Write a karabiner healthcheck double into the fake HOME: exit code $1, degraded output.
seed_fake_healthcheck() {
  local rc="$1"
  mkdir -p "${HOME}/.config/karabiner/bin" "${HOME}/.claude/skills/ari-skill-shellscripts/lib"
  : > "${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
  printf '#!/usr/bin/env bash\nprintf "status=degraded\\nissues=2\\n"\nexit %s\n' "${rc}" > "${HOME}/.config/karabiner/bin/healthcheck"
  chmod +x "${HOME}/.config/karabiner/bin/healthcheck"
}
