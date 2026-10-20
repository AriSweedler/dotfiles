# step dotfiles_docs — every part of the dotfiles program says what it is. Each rule is a
# docs::rule::<name> function, run in DOCS_RULES order; today one, docs::rule::steps: each step's
# line 1, --desc, --apply when it has an apply, and step::watches or --none (steps::doc_gaps). A
# gap is never a load error: it fails this step, by hand only, naming the edit that fixes it.
step::declare dotfiles_docs --group repo \
  --desc "every step documented: its '# step NAME — summary' line, --desc, --apply for an apply, step::watches or --none (dotfiles steps)"
step::watches dotfiles_docs '.config/dotfiles/steps/**' '.config/dotfiles/cmd/**'

typeset -ga DOCS_RULES=(steps)

# docs::rule::<name>: appends one '<unit>: <what it lacks>' per undocumented unit to the caller's
# `gaps`, and the command that fixes it to `fixes`; counts what it looked at in `units`.
docs::rule::steps() {
  local name
  if ! steps::load "${ARI_DOTFILES_STEPS}" 2>/dev/null; then
    gaps+=("steps: the registry does not load"); fixes+=("${CLI_NAME} steps")
    return 0
  fi
  units+=("${#STEPS} steps")
  for name in "${STEPS[@]}"; do
    [[ -n "${STEP_UNDOCUMENTED[${name}]:-}" ]] || continue
    gaps+=("${name}: ${STEP_UNDOCUMENTED[${name}]}")
    fixes+=("${CLI_NAME} steps edit ${name}")
  done
}

check::dotfiles_docs() {
  local rule
  local -a gaps=() fixes=() units=()
  for rule in "${DOCS_RULES[@]}"; do "docs::rule::${rule}"; done
  if (( ${#gaps} )); then
    verdict fail undocumented -m -d "${(j:; :)gaps}" -f "${fixes[1]}"
    return 0
  fi
  verdict ok documented -d "${(j:, :)units}"
}
