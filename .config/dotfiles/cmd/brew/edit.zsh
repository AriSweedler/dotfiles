# cmd/brew/edit.zsh — `dotfiles brew edit`: open one tier's Brewfile or Brewfile.ignore in $EDITOR,
# check it parses and documents every entry, and commit it. Loaded by cmd/brew.zsh after cmd/brew/{brew,decree}.zsh; defines
# functions only.
#
# Entry point: edit::edit [--global|--local] [--ignore] [--no-commit] [--no-push]
# Reads: EDITOR, ARI_DOTFILES_NO_PUSH; the tier file paths come from decree::tier_file.

edit::help() {
  print -r -- "${CLI_NAME} brew edit [--global|--local] [--ignore] [--no-commit] [--no-push]"
  cat <<'EOF'

Opens one tier's Brewfile (or, with --ignore, its Brewfile.ignore) in $EDITOR, vi when unset.
On save the file must parse: a Brewfile through `brew bundle list`, an ignore file with every
line `<formula|cask|tap|vscode> <name>  # reason` or `include-declared <abs path>  # reason`.
Every entry must also say why it is there: a Brewfile entry by a trailing `# why`, or by a
heading comment opening its paragraph (lines between blank lines; a commented-out entry is no
heading, and in the decree block only the trailing comment counts); an ignore entry by its
non-empty `# reason`. A file that passes is committed in its tier, the subject naming each item
added or removed; one that does not is reported line by line and left exactly as edited,
uncommitted. Nothing is installed or uninstalled.

  --local      ~/.local/share/new-machine/Brewfile   (git ldf; committed and pushed) [default]
  --global     ~/.config/new-machine/Brewfile        (git df; committed, never pushed)
  --ignore     the tier's Brewfile.ignore instead
  --no-commit  check the file, leave it uncommitted
  --no-push    skip the local tier's push
  -h           this help

Exit 0 saved (or no change); 1 the file does not parse, an entry lacks its why, the editor
failed, or the commit was refused; 64 usage.
EOF
}

# edit::check <Brewfile|Brewfile.ignore> <file>: 0 when the file parses and documents every entry
# (decree::undocumented's rule); 1 with the parser's complaint on stderr when it does not parse;
# 2 with one `line N: kind:name lacks …` per gap when an entry lacks its why. A Brewfile is Ruby,
# so brew is its only parser (one call, ~0.7 s).
edit::check() {
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
    return 1
  fi
  decree::undocumented "${kind}" "${file}"
  (( ${#reply} )) || return 0
  doc="a trailing '# why', or a heading comment opening its paragraph"
  [[ "${kind}" == Brewfile ]] || doc="a '# reason'"
  for gap in "${reply[@]}"; do
    print -u2 -r -- "line ${gap%%$'\t'*}: ${gap#*$'\t'} lacks ${doc}"
  done
  return 2
}

# edit::items <Brewfile|Brewfile.ignore> <file>: one `kind:name` per declared or ignored line,
# sorted and unique, through decree's line patterns; no brew call.
edit::items() {
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

# edit::summary <before items> <after items> → the item lines for decree::commit_message
# (`+ kind:name` added, `- kind:name` removed), added first.
edit::summary() {
  local -a before=("${(@f)1}") after=("${(@f)2}") lines=()
  before=("${(@)before:#}") after=("${(@)after:#}")
  local item
  for item in "${after[@]}"; do (( ${before[(Ie)${item}]} )) || lines+=("+ ${item}"); done
  for item in "${before[@]}"; do (( ${after[(Ie)${item}]} )) || lines+=("- ${item}"); done
  (( ${#lines} )) && print -rl -- "${lines[@]}"
  return 0
}

# edit::message <tier> <kind> <summary lines>: `dotfiles: edit <kind> (<tier>): +a -b`, or with
# more than three changes a count and one body line each; comments or order alone say so.
edit::message() {
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

edit::edit() {
  local tier=local kind=Brewfile file editor before head_items after_items summary rel
  local -i commit=1 tiers=0 created=0
  while (( $# )); do
    case "${1}" in
      -h|--help) edit::help; return 0 ;;
      --local) tier=local; tiers+=1 ;;
      --global) tier=global; tiers+=1 ;;
      --ignore) kind=Brewfile.ignore ;;
      --no-commit) commit=0 ;;
      --no-push) export ARI_DOTFILES_NO_PUSH=1 ;;
      *) log::err "unknown argument | arg='${1}'"; edit::help >&2; return 64 ;;
    esac
    shift
  done
  if (( tiers > 1 )); then
    log::err "--global and --local are exclusive"
    edit::help >&2
    return 64
  fi
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
  head_items="$(edit::items "${kind}" =(tier::git "${tier}" show "HEAD:${rel}" 2>/dev/null))"
  before="$(mktemp "${TMPDIR:-/tmp}/brew-edit.XXXXXX")" || return 1
  cp -- "${file}" "${before}"
  editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  if ! ${=editor} "${file}"; then
    rm -f -- "${before}"
    log::err "editor exited non-zero; not checked or committed | editor='${editor}' file='${file}'"
    return 1
  fi
  if cmp -s -- "${before}" "${file}"; then
    rm -f -- "${before}"
    (( ! created )) || rm -f -- "${file}"
    print -r -- "brew: no change | tier=${tier} file=$(ui::paths "${file}")"
    return 0
  fi
  rm -f -- "${before}"
  local -i check_rc=0
  edit::check "${kind}" "${file}" || check_rc=$?
  if (( check_rc )); then
    local problem="does not parse"
    (( check_rc != 2 )) || problem="has an entry that does not say why"
    log::err "${kind} ${problem}; left as edited, not committed | tier='${tier}' file='${file}' fix='${CLI_NAME} brew edit --${tier}${${kind:#Brewfile}:+ --ignore}'"
    return 1
  fi
  if tier::git "${tier}" cat-file -e "HEAD:${rel}" 2>/dev/null && tier::git "${tier}" diff --quiet HEAD -- "${file}"; then
    print -r -- "brew: matches the committed file; nothing to commit | tier=${tier} file=$(ui::paths "${file}")"
    return 0
  fi
  after_items="$(edit::items "${kind}" "${file}")"
  summary="$(edit::summary "${head_items}" "${after_items}")"
  (( ! ${#summary} )) || print -r -- "${summary}"
  if (( commit )); then
    tier::commit "${tier}" "$(edit::message "${tier}" "${kind}" "${summary}")" "${file}" || return 1
  else
    print -r -- "not committed | file=$(ui::paths "${file}")"
  fi
  # Added Brewfile lines install on the next apply; removed ones leave orphans for triage.
  if [[ "${kind}" == Brewfile && "${summary}" == *'+ '* ]]; then
    print -r -- "next: ${CLI_NAME} apply brew_pkgs"
  elif [[ -n "${summary}" ]]; then
    print -r -- "next: ${CLI_NAME} brew triage"
  fi
  return 0
}
