# run_tests.zsh — run the zsh-plugin *.test.zsh suites next to this file.
#
# Why this exists
#   Each <name>.test.zsh beside this file is written to two constraints:
#     1. It guards itself behind  OTTO_TEST__ZSH_PLUGINS_<NAME>=true  — so the
#        plugin loader (which sources every *.zsh on shell start) skips it.
#     2. It uses top-level `local`, valid only when the file is SOURCED from
#        inside a function — which is how the plugin loader sources it.
#   Running a suite by hand therefore means "set that env var, then source the
#   file in a function scope". This packages that incantation as `run_tests` so
#   it doesn't have to be rediscovered each time.
#
# Usage
#   run_tests                       # every *.test.zsh next to this file
#   run_tests log_rotate            # just log_rotate.test.zsh (name)
#   run_tests log_rotate.test.zsh   # same, explicit filename
#   zsh run_tests.zsh log_rotate    # executed directly — identical behavior
#
#   When the plugin loader sources this file it ONLY defines `run_tests` (handy
#   to call from any shell); it auto-runs only when the file is executed.
#
# Per-suite env var is derived from the filename:
#   <name>.test.zsh → OTTO_TEST__ZSH_PLUGINS_<name upper-cased, non-alnum → _>
#   e.g. log_rotate.test.zsh → OTTO_TEST__ZSH_PLUGINS_LOG_ROTATE

function run_tests() {
  emulate -L zsh
  # Dir this file lives in — resolved via $functions_source, since inside a
  # function $0 is the function name, not the file path.
  local here="${functions_source[run_tests]:A:h}"

  local -a files
  if (( $# == 0 )); then
    files=("${here}"/*.test.zsh(N))           # (N): no error when none match
  else
    local arg="$1" f
    if   [[ -f "${arg}" ]];                 then f="${arg}"
    elif [[ -f "${here}/${arg}" ]];         then f="${here}/${arg}"
    elif [[ -f "${here}/${arg}.test.zsh" ]]; then f="${here}/${arg}.test.zsh"
    else print -u2 "run_tests: no test file for '${arg}' in ${here}"; return 1; fi
    files=("${f}")
  fi
  (( ${#files} )) || { print -u2 "run_tests: no *.test.zsh in ${here}"; return 1; }

  local file base name var
  for file in "${files[@]}"; do
    base="${file:t}"; name="${base%.test.zsh}"
    var="OTTO_TEST__ZSH_PLUGINS_${${name:u}//[^A-Z0-9]/_}"
    print -- "── ${base}  (${var}=true)"
    export "${var}=true"
    source "${file}"          # sourced in this function scope → top-level `local` ok
    unset "${var}"
  done
}

# Auto-run only when executed directly (zsh run_tests.zsh …). When the plugin
# loader sources us, zsh_eval_context ends in "file", so we just define the
# function above and return.
[[ "${zsh_eval_context[-1]}" == "toplevel" ]] && run_tests "$@"
