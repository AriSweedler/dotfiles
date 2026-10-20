# cmd/git/edit.zsh — `dotfiles --local git edit`: the local tier's allowlist template in $EDITOR
# as a draft; checked, put in place, installed as info/exclude, committed in the shared tier.
# Loaded by cmd/git.zsh; defines functions only.
#
# The template is what every machine's info/exclude starts from, and info/exclude is what makes
# `git ldf add -A` safe: a draft that would admit a secret never reaches either. It lives in
# <state>/drafts/git (edit::draft) until it passes, so a failed edit resumes.

# git_edit_check DRAFT: every problem with the draft on stderr, one per line, and 1 when any.
git_edit_check() {
  setopt localoptions extendedglob
  local draft="${1}" rule entry dir tmp rc=0
  local -a rules problems=() dirs=() reply
  rules=("${(@f)$(exclude_rules "${draft}")}")
  rules=("${(@)rules:#}")
  [[ "${rules[1]:-}" == '/*' ]] || problems+=("the first rule is '${rules[1]:-}', not '/*': an allowlist starts by excluding everything")
  for rule in "${rules[@]}"; do
    [[ "${rule}" != '!' ]] || problems+=("a bare '!' admits nothing")
    [[ "${rule}" != *[^\\][[:space:]] ]] || problems+=("'${rule}' ends in whitespace, which git drops: quote it with \\ or remove it")
    # Every directory the allowlist admits by name; the secret check below looks inside each.
    [[ "${rule}" == '!/'*/ && "${rule}" != *[\*\?\[]* ]] && dirs+=("${${rule#!/}%/}")
  done
  # git reads the draft as a real repo's info/exclude: a secret in any admitted directory, or at
  # the top, must stay excluded.
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/git-edit.XXXXXX")" || return 1
  if git init -q --bare "${tmp}/repo.git" 2>/dev/null && mkdir -p "${tmp}/repo.git/info" "${tmp}/work" \
     && cp -- "${draft}" "${tmp}/repo.git/info/exclude"; then
    local -a secrets=("x.secret.zsh")
    for dir in "${dirs[@]}"; do mkdir -p "${tmp}/work/${dir}" && secrets+=("${dir}/x.secret.zsh"); done
    for entry in "${secrets[@]}"; do
      : > "${tmp}/work/${entry}"
      rc=0
      (cd "${tmp}/work" && git --git-dir="${tmp}/repo.git" --work-tree="${tmp}/work" check-ignore -q -- "${entry}") || rc=$?
      if (( rc == 1 )); then problems+=("'${entry}' would be tracked: keep '*.secret.zsh' after every '!' that could admit it")
      elif (( rc != 0 )); then problems+=("git could not read the rules (check-ignore exit ${rc})"); break
      fi
    done
  else
    problems+=("could not build a scratch repo to test the rules | dir='${tmp}'")
  fi
  rm -rf -- "${tmp}"
  git_allowlist_undocumented "${draft}"
  for entry in "${reply[@]}"; do problems+=("undocumented: '${entry}' has no '# why' comment on the line above it"); done
  (( ${#problems} == 0 )) && return 0
  print -u2 -rl -- "${problems[@]}"
  return 1
}

git_edit() {
  local commit="${1:-1}" template="${LDF_EXCLUDE_TEMPLATE}" git_dir="${ARI_DOTFILES_LDF_GIT_DIR}"
  local exclude="${ARI_DOTFILES_LDF_GIT_DIR}/info/exclude" draft REPLY fix="${CLI_NAME} --local git --edit"
  [[ -r "${template}" ]] || { log::err "allowlist template missing | path='${template}'"; return 1; }
  [[ -d "${git_dir}" ]] || { log::err "no local tier yet | git_dir='${git_dir}' fix='${CLI_NAME} apply local_dotfiles_repo'"; return 1; }
  # This machine keeps an allowlist it changed by hand (local_dotfiles_repo warns): installing over
  # it would drop those rules, so the two must agree before the template changes.
  if [[ -f "${exclude}" && -n "$(exclude_rules "${exclude}")" && "$(exclude_rules "${exclude}")" != "$(exclude_rules "${template}")" ]]; then
    diff -u -- "${exclude}" "${template}" || true
    log::err "this machine's allowlist has rules the template does not; nothing changed. Make them agree first: copy the rules to keep into the template, then 'cp' it over info/exclude | exclude='${exclude}' template='${template}'"
    return 1
  fi

  edit::draft "${template}" "${ARI_DOTFILES_STATE_DIR}/drafts/git" || return 1
  draft="${REPLY}"
  local -i rc=0
  edit::session "${draft}" --check git_edit_check --what "the allowlist" ${${EDIT_RESUMED:#0}:+--changed} \
    --resume "${fix}" || rc=$?
  if (( rc == 2 )) || { (( rc == 0 )) && edit::same "${draft}" "${template}"; }; then
    rm -f -- "${draft}"
    print -r -- "allowlist: no change | file=$(ui::paths "${template}")"
    return 0
  fi
  (( rc == 0 )) || return 1
  if is_dry_run; then
    print -r -- "would put the draft in place, install it and commit it; draft kept | draft=$(ui::paths "${draft}") template=$(ui::paths "${template}") exclude=$(ui::paths "${exclude}")"
    return 0
  fi

  # In place, then installed: each written beside its file and renamed over it.
  edit::install "${draft}" "${template}" 644 || return 1
  mkdir -p -- "${exclude:h}" && cp -- "${template}" "${exclude}.edit.$$" && mv -f -- "${exclude}.edit.$$" "${exclude}" || {
    rm -f -- "${exclude}.edit.$$"
    log::err "template saved but not installed | exclude='${exclude}' fix='cp ${template} ${exclude}'"
    return 1
  }
  print -r -- "allowlist: saved and installed | template=$(ui::paths "${template}") exclude=$(ui::paths "${exclude}")"
  print -r -- "git ldf status --short --untracked-files=all (?? = admitted, not yet tracked):"
  tier::git local status --short --untracked-files=all || true
  if (( commit )); then
    tier::commit shared "${CLI_NAME}: edit the local tier's allowlist" "${template}" || return 1
  else
    print -r -- "not committed | file=$(ui::paths "${template}")"
  fi
  print -r -- "next: ${CLI_NAME} --local git add -A && ${CLI_NAME} --local git commit   (track what it now admits)"
}
