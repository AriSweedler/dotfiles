# step dotfiles_docs — every part of the dotfiles program says what it is. Each rule is a
# docs::rule::<name> function, run in DOCS_RULES order: docs::rule::steps, each step's line 1,
# --desc, --apply when it has an apply, and step::watches or --none (steps::doc_gaps); and
# docs::rule::help, each verb's help_VERB and the top-level help: a one-line synopsis, a Usage
# section, every flag the parsers accept (help::doc_gap, cmd/help.zsh). A gap is never a load
# error: it fails this step, by hand only, naming the edit that fixes it.
step::declare dotfiles_docs --group repo \
  --desc "every step documented (its '# step NAME — summary' line, --desc, --apply for an apply, watches: dotfiles steps) and every verb's help (a synopsis, Usage, every flag it parses: dotfiles help --edit VERB)"
step::watches dotfiles_docs '.config/dotfiles/steps/**' '.config/dotfiles/cmd/**' '.config/dotfiles/lib/dispatch.zsh'

typeset -ga DOCS_RULES=(steps help)

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

docs::rule::help() {
  local verb REPLY
  local -a reply verbs
  need_lib "${ARI_DOTFILES_CMD}/help.zsh" || return 3
  help::top_gap
  if [[ -n "${REPLY}" ]]; then gaps+=("${CLI_NAME} --help: ${REPLY}"); fixes+=("${CLI_NAME} help --edit"); fi
  help::verb_names
  verbs=("${reply[@]}")
  for verb in "${verbs[@]}"; do
    help::verb_gap "${verb}"
    [[ -n "${REPLY}" ]] || continue
    gaps+=("${CLI_NAME} ${verb} --help: ${REPLY}")
    fixes+=("${CLI_NAME} help --edit ${verb}")
  done
  units+=("$(( ${#verbs} + 1 )) helps")
}

step::dotfiles_docs::live() {
  local rule
  local -a gaps=() fixes=() units=()
  for rule in "${DOCS_RULES[@]}"; do "docs::rule::${rule}" || return; done
  if (( ${#gaps} )); then
    verdict fail undocumented -m -d "${(j:; :)gaps}" -f "${fixes[1]}"
    return 0
  fi
  verdict ok documented -d "${(j:, :)units}"
}

# Every rule reads only the program's own files: the verdict holds while none of them changes.
check::dotfiles_docs() {
  local -a reply=()
  cache::tree "${ARI_DOTFILES_STEPS}" "${ARI_DOTFILES_CMD}" "${ARI_DOTFILES_LIB}"
  cache::check step::dotfiles_docs::live "${reply[@]}"
}
