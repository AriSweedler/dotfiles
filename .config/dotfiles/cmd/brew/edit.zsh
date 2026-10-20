# cmd/brew/edit.zsh — `dotfiles brew edit` (and `brew --edit`): one tier's Brewfile or
# Brewfile.ignore in $EDITOR through edit::session, checked to parse and to document every entry,
# then committed. Loaded by cmd/brew.zsh after cmd/brew/{brew,decree}.zsh; defines functions only.
# The file is edited in place: one that fails its check is left as edited, uncommitted.

# brewedit::check <Brewfile|Brewfile.ignore> <file>: 0 when the file parses and documents every
# entry (decree::undocumented's rule); 1 with the parser's complaint on stderr when it does not
# parse; 2 with one `line N: kind:name lacks …` per gap when an entry lacks its why. A Brewfile is
# Ruby, so brew is its only parser (one call, ~0.7 s).
brewedit::check() {
  local kind="${1}" file="${2}" out brew gap doc
  local -a reply
  local -i rc=0
  if [[ "${kind}" == Brewfile ]]; then
    brew="$(brew::bin)" || { log::err "brew not found"; return 1; }
    out="$(HOMEBREW_NO_AUTO_UPDATE=1 "${brew}" bundle list --all --file="${file}" 2>&1 >/dev/null)" || rc=$?
  else
    out="$(brew::parse_ignore "${file}" local 2>&1 >/dev/null)" || rc=$?
    [[ -z "${out}" ]] || rc=1
  fi
  if (( rc != 0 )); then
    print -u2 -r -- "${out}"
    log::err "${kind} does not parse; left as edited, not committed | file='${file}'"
    return 1
  fi
  decree::undocumented "${kind}" "${file}"
  (( ${#reply} )) || return 0
  doc="a trailing '# why', or a heading comment opening its paragraph"
  [[ "${kind}" == Brewfile ]] || doc="a '# reason'"
  for gap in "${reply[@]}"; do
    print -u2 -r -- "line ${gap%%$'\t'*}: ${gap#*$'\t'} lacks ${doc}"
  done
  log::err "${kind} has an entry that does not say why; left as edited, not committed | file='${file}'"
  return 2
}

# brewedit::items <Brewfile|Brewfile.ignore> <file>: one `kind:name` per declared or ignored line,
# sorted and unique, through decree's line patterns; no brew call.
brewedit::items() {
  local kind="${1}" file="${2}" line
  local -a items=()
  [[ -s "${file}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${kind}" == Brewfile ]]; then
      [[ "${line}" =~ "${DECREE_BREWFILE_LINE_RE}" ]] && items+=("${DECREE_KIND_OF_KEYWORD[${match[1]}]}:${match[2]}")
    else
      [[ "${line}" =~ "${DECREE_IGNORE_LINE_RE}" ]] && items+=("${match[1]}:${match[2]}")
    fi
  done < "${file}"
  (( ${#items} )) && print -rl -- "${(@ou)items}"
  return 0
}

# brewedit::summary <before items> <after items> → the item lines for brewedit::message
# (`+ kind:name` added, `- kind:name` removed), added first.
brewedit::summary() {
  local -a before=("${(@f)1}") after=("${(@f)2}") lines=()
  before=("${(@)before:#}") after=("${(@)after:#}")
  local item
  for item in "${after[@]}"; do (( ${before[(Ie)${item}]} )) || lines+=("+ ${item}"); done
  for item in "${before[@]}"; do (( ${after[(Ie)${item}]} )) || lines+=("- ${item}"); done
  (( ${#lines} )) && print -rl -- "${lines[@]}"
  return 0
}

# brewedit::message <tier> <kind> <summary lines>: `dotfiles: edit <kind> (<tier>): +a -b`, or with
# more than three changes a count and one body line each; comments or order alone say so.
brewedit::message() {
  local tier="${1}" kind="${2}"
  local -a lines=("${(@f)3}")
  lines=("${(@)lines:#}")
  if (( ${#lines} == 0 )); then
    print -r -- "${CLI_NAME}: edit ${kind} (${tier}): comments or order only"
  elif (( ${#lines} <= 3 )); then
    print -r -- "${CLI_NAME}: edit ${kind} (${tier}): ${(j:, :)${lines[@]// /}}"
  else
    print -r -- "${CLI_NAME}: edit ${kind} (${tier}): ${#lines} items"
    print -r -- ""
    print -rl -- "${lines[@]/#/- }"
  fi
}

# brewedit::edit [--global|--local] [--ignore] [--no-commit] [--no-push]
brewedit::edit() {
  local -A opts; local -a args
  verb::parse brew "$@"
  brew::only edit --global --local --ignore --no-commit --no-push
  (( ${#args} == 0 )) || usage_error "brew edit takes no positional arguments | args='${args[*]}'"
  (( ! ${+opts[--global]} || ! ${+opts[--local]} )) || usage_error "brew edit: --global and --local are exclusive"
  (( ${+opts[--no-push]} )) && export ARI_DOTFILES_NO_PUSH=1
  local tier=local kind=Brewfile file head_items summary rel
  (( ${+opts[--global]} )) && tier=global
  (( ${+opts[--ignore]} )) && kind=Brewfile.ignore
  local -i created=0 rc=0
  file="$(decree::tier_file "${tier}" "${kind}")" || return 64
  if [[ ! -e "${file}" ]]; then
    if [[ "${tier}/${kind}" == global/Brewfile ]]; then
      log::err "the shared Brewfile is missing | file='${file}' fix='${CLI_NAME} apply dotfiles_repo'"
      return 1
    fi
    mkdir -p "${file:h}" || return 1
    if [[ "${kind}" == Brewfile ]]; then
      print -rl -- "${DECREE_LOCAL_BREWFILE_HEADER[@]}" > "${file}"
    else
      print -rl -- "${DECREE_IGNORE_HEADER[@]}" > "${file}"
    fi
    created=1
  fi
  # What the tier has committed, so the subject also covers edits made before this one.
  rel="${file#${TIER_WORK_TREE[$(tier::name "${tier}")]}/}"
  head_items="$(brewedit::items "${kind}" =(tier::git "${tier}" show "HEAD:${rel}" 2>/dev/null))"
  BREWEDIT_KIND="${kind}"
  edit::session "${file}" --check brewedit::_check \
    --resume "${CLI_NAME} brew edit --${tier}${${kind:#Brewfile}:+ --ignore}" || rc=$?
  if (( rc == 2 )); then
    (( ! created )) || rm -f -- "${file}"
    print -r -- "brew: no change | tier=${tier} file=$(ui::paths "${file}")"
    return 0
  fi
  (( rc == 0 )) || return 1
  if tier::git "${tier}" cat-file -e "HEAD:${rel}" 2>/dev/null && tier::git "${tier}" diff --quiet HEAD -- "${file}"; then
    print -r -- "brew: matches the committed file; nothing to commit | tier=${tier} file=$(ui::paths "${file}")"
    return 0
  fi
  summary="$(brewedit::summary "${head_items}" "$(brewedit::items "${kind}" "${file}")")"
  (( ! ${#summary} )) || print -r -- "${summary}"
  if (( ${+opts[--no-commit]} )); then
    print -r -- "not committed | file=$(ui::paths "${file}")"
  else
    tier::commit "${tier}" "$(brewedit::message "${tier}" "${kind}" "${summary}")" "${file}" || return 1
  fi
  # Added Brewfile lines install on the next apply; removed ones leave orphans for triage.
  if [[ "${kind}" == Brewfile && "${summary}" == *'+ '* ]]; then
    print -r -- "next: ${CLI_NAME} apply brew_pkgs"
  elif [[ -n "${summary}" ]]; then
    print -r -- "next: ${CLI_NAME} brew triage"
  fi
  return 0
}

brewedit::_check() { brewedit::check "${BREWEDIT_KIND}" "${1}" >&2; }
