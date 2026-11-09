#!/usr/bin/env bash
# Run every tests/test_*.sh, or the suites named as arguments (a test_*.sh, or a zsh plugin suite
# NAME.test.zsh under its OTTO_TEST__ZSH_PLUGINS_<NAME> gate), side by side: ARI_DOTFILES_TEST_JOBS
# at a time (default: half the CPUs). One line per suite as it finishes, then each failed suite's
# whole output and a summary; exit non-zero if any fails. The logs stay only when one fails.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

if ! command -v plutil >/dev/null 2>&1; then
  printf 'skipped: not macOS\n'
  exit 0
fi

if (( $# )); then suites=("$@"); else suites=(test_*.sh); fi
jobs="${ARI_DOTFILES_TEST_JOBS:-$(( $(sysctl -n hw.ncpu 2>/dev/null || echo 2) / 2 ))}"
(( jobs >= 1 )) || jobs=1
RUN_LOGS="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tests.XXXXXX")" || exit 1
export RUN_LOGS

run_one() {
  local suite="$1" name rc start="${SECONDS}" gate
  name="$(basename "${suite}")"
  case "${name}" in
    *.test.zsh)
      gate="OTTO_TEST__ZSH_PLUGINS_$(printf '%s' "${name%.test.zsh}" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9' '_')"
      env "${gate}=true" zsh "${suite}" > "${RUN_LOGS}/${name}.log" 2>&1 ;;
    *) bash "${suite}" > "${RUN_LOGS}/${name}.log" 2>&1 ;;
  esac
  rc=$?
  printf '%s\n' "${rc}" > "${RUN_LOGS}/${name}.rc"
  if (( rc == 0 )); then printf 'ok    %3ss  %s\n' $(( SECONDS - start )) "${name}"
  else printf 'FAIL  %3ss  %s (exit %s)\n' $(( SECONDS - start )) "${name}" "${rc}"; fi
}
export -f run_one

start="${SECONDS}"
printf '%s\0' "${suites[@]}" | xargs -0 -n 1 -P "${jobs}" "${BASH}" -c 'run_one "$1"' _

failed=()
for suite in "${suites[@]}"; do
  name="$(basename "${suite}")"
  [[ "$(cat "${RUN_LOGS}/${name}.rc" 2>/dev/null)" == 0 ]] || failed+=("${name}")
done
for name in ${failed[@]+"${failed[@]}"}; do
  printf '\n== %s\n' "${name}"
  cat "${RUN_LOGS}/${name}.log" 2>/dev/null || printf '(no output: the suite never ran)\n'
done
printf 'suites=%s failed=%s jobs=%s wall=%ss\n' "${#suites[@]}" "${#failed[@]}" "${jobs}" $(( SECONDS - start ))
if (( ${#failed[@]} )); then
  printf 'logs: %s\n' "${RUN_LOGS}"
  exit 1
fi
rm -rf "${RUN_LOGS}"
