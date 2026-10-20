# cmd/alttab/edit.zsh — `dotfiles alttab edit`: change the Free-tier patch by editing the patched
# source, or (--header) free.patch itself. Loaded by cmd/alttab.zsh after steps/alttab.zsh;
# defines functions only.
#
# The source is alttab-free-build's clone (ALTTAB_SRC), at free.patch.ref with the patch applied,
# so `git diff HEAD` there is the patch's body. On save the new patch is built beside the clone
# as a pending file (free.patch.edit: free.patch's header plus `git diff HEAD`, by
# `alttab-free-build --regen-patch`), checked, and only then put over free.patch. A pending file
# that fails is kept, with the hash of the free.patch it was made against, so the next edit
# resumes it; against a free.patch that has since changed it is set aside as .stale.

# alttab::_edit_rule: AGENTS.md's ground rule, said whenever the patched source opens.
alttab::_edit_rule() {
  ui::paint warn "AGENTS.md: the patch keeps Pro locked except shortcut slot 2 (⌥\`, the active app's windows). Do not edit it, or anything else, to unlock more."
}

# alttab::_edit_body <file>: REPLY is the patch's diff (from its first 'diff --git' line), or empty.
alttab::_edit_body() {
  local text="$(<"${1}")"
  REPLY=""
  [[ "${text}" == 'diff --git '* ]] && { REPLY="${text}"; return 0; }
  [[ "${text}" == *$'\n''diff --git '* ]] && REPLY="diff --git ${text#*$'\n'diff --git }"
  return 0
}

# alttab::_edit_clone_diff: REPLY is `git diff HEAD` in the clone, without trailing newlines.
alttab::_edit_clone_diff() {
  REPLY="$(git -C "${ALTTAB_SRC}" diff --no-ext-diff --no-color HEAD)"
}

# alttab::_edit_keep <pending> <sum>: a pending patch that did not pass stays for the next edit,
# tied to the free.patch it was made against.
alttab::_edit_keep() {
  [[ -f "${1}" ]] || cp -p -- "${ALTTAB_PATCH}" "${1}"
  print -r -- "${2}" > "${1}.base"
}

# alttab::_edit_check <pending>: every problem with the pending patch on stderr; REPLY is
# "ok", "header" (only the doc rule fails) or "patch".
alttab::_edit_check() {
  local pending="${1}" out
  local -a reply
  local -i applies=1
  REPLY=ok
  if ! out="$(zsh "${ALTTAB_DIR}/bin/alttab-free-build" --check-patch --src "${ALTTAB_SRC}" --patch "${pending}" --ref "${ALTTAB_REF}" 2>&1)"; then
    applies=0
    print -u2 -r -- "${out}"
    log::err "the edited patch does not apply to a clean ${ALTTAB_REF} | pending='${pending}'"
  fi
  step::alttab::undocumented "${pending}"
  if (( ${#reply} )); then
    log::err "undocumented: the header's 'What it changes' list does not name ${(j:, :)reply} | pending='${pending}' rule='each file name without .swift, first on its line'"
    REPLY=header
  fi
  (( applies )) || REPLY=patch
  [[ "${REPLY}" == ok ]]
}

# alttab::_edit_source_check <file>: edit::session's check after the patched files were saved: the
# pending patch regenerated from the clone, then checked. A header-only failure passes, with
# ALTTAB_EDIT_FAILED=header, so the caller can offer the header instead of the same files again.
alttab::_edit_source_check() {
  local pending="${ALTTAB_EDIT_PENDING}" src="${ALTTAB_SRC}"
  local -a untracked=("${(@f)$(git -C "${src}" ls-files --others --exclude-standard)}")
  untracked=("${(@)untracked:#}")
  (( ${#untracked} )) && log::warn "new files are not in the patch until git knows them | files='${(j:, :)untracked}' fix='git -C ${src} add -N FILE'"
  [[ -f "${pending}" ]] || cp -p -- "${ALTTAB_PATCH}" "${pending}"
  if ! zsh "${ALTTAB_DIR}/bin/alttab-free-build" --regen-patch --src "${src}" --patch "${pending}" --ref "${ALTTAB_REF}" >/dev/null 2>&1; then
    log::err "could not regenerate the patch from the clone | pending='${pending}' fix='zsh ${ALTTAB_DIR}/bin/alttab-free-build --regen-patch --patch ${pending}'"
    return 1
  fi
  edit::same "${pending}" "${ALTTAB_PATCH}" && return 0
  alttab::_edit_check "${pending}" && return 0
  [[ "${REPLY}" == header ]] && ALTTAB_EDIT_FAILED=header && return 0
  return 1
}

# alttab::_edit_header_check <pending>: edit::session's check after free.patch itself was saved:
# the change as a diff, then the checks.
alttab::_edit_header_check() {
  diff -u -L "free.patch (before)" -L "free.patch (after)" -- "${ALTTAB_PATCH}" "${1}" || true
  alttab::_edit_check "${1}"
}

# alttab::_edit_session source|header: one edit::session on the patched files or on the pending
# patch; its rc (0 passed, 2 unchanged, 1 kept).
alttab::_edit_session() {
  local src="${ALTTAB_SRC}" pending="${ALTTAB_EDIT_PENDING}" changed=""
  alttab::_edit_rule
  if [[ "${1}" == header ]]; then
    [[ -f "${pending}" ]] || cp -p -- "${ALTTAB_PATCH}" "${pending}"
    edit::same "${pending}" "${ALTTAB_PATCH}" || changed=--changed
    edit::session "${pending}" --check alttab::_edit_header_check --what free.patch ${changed} \
      --resume "${CLI_NAME} alttab edit --header"
    return
  fi
  local -a files=("${(@f)$(git -C "${src}" diff --name-only HEAD)}")
  files=("${(@)files:#}")
  if (( ! ${#files} )); then log::err "free.patch changes no file; edit it with --header | fix='${CLI_NAME} alttab edit --header'"; return 1; fi
  print -r -- "opening ${#files} patched file(s) in $(ui::paths "${src}")"
  # --changed: the session compares only the first file; the check finds a real no-change.
  edit::session "${src}/${files[1]}" --check alttab::_edit_source_check --what "the patched source" --changed \
    --resume "${CLI_NAME} alttab edit" --also "${(@)files[2,-1]/#/${src}/}"
}

alttab::edit() {
  local -A opts; local -a args
  verb::parse alttab "$@"
  (( ${#args} == 0 )) || usage_error "alttab edit takes no arguments | args='${args[*]}'"
  alttab::only_flags edit --header --no-commit
  local build="${ALTTAB_DIR}/bin/alttab-free-build" src="${ALTTAB_SRC}" patch="${ALTTAB_PATCH}"
  local rebuild="alttab-free-build --build-only"
  if [[ ! -r "${patch}" || ! -r "${patch}.ref" || ! -r "${build}" ]]; then
    log::err "the AltTab sources are missing | dir='${ALTTAB_DIR}' fix='${CLI_NAME} pull'"
    return 1
  fi
  typeset -g ALTTAB_REF="$(<"${patch}.ref")"
  ALTTAB_REF="${ALTTAB_REF//[[:space:]]/}"
  if [[ -e "${src:h}/rebase/.free-rebase-target" ]]; then
    log::err "a patch rebase is in progress; finish it before editing | worktree='${src:h}/rebase' fix='alttab-free-build --finish-patch'"
    return 1
  fi
  if [[ ! -d "${src}/.git" ]]; then
    log::err "no clone of AltTab to edit; a build makes it | src='${src}' fix='${rebuild}'"
    return 1
  fi
  local head want
  head="$(git -C "${src}" rev-parse HEAD 2>/dev/null)"
  want="$(git -C "${src}" rev-parse --verify --quiet "${ALTTAB_REF}^{commit}" 2>/dev/null)"
  if [[ -z "${want}" || "${head}" != "${want}" ]]; then
    log::err "the clone is not at free.patch's ref | src='${src}' ref='${ALTTAB_REF}' head='${head:0:8}' fix='${rebuild}'"
    return 1
  fi

  local pending="${src:h}/free.patch.edit" sum REPLY
  sum="$(git hash-object -- "${patch}")" || return 1
  if [[ -f "${pending}" ]]; then
    if [[ -r "${pending}.base" && "$(<"${pending}.base")" == "${sum}" ]]; then
      log::info "resuming the edit a failed save left | pending='${pending}'"
    else
      mv -f -- "${pending}" "${pending}.stale"
      rm -f -- "${pending}.base"
      log::warn "an unfinished edit was made against an older free.patch; set aside | kept='${pending}.stale'"
    fi
  fi
  alttab::_edit_body "${patch}"
  local body="${REPLY}"
  alttab::_edit_clone_diff
  if [[ -z "${REPLY}" && -n "${body}" ]]; then
    log::info "applying free.patch to the clone | src='${src}'"
    git -C "${src}" apply -- "${patch}" || { log::err "free.patch does not apply to the clone | fix='${rebuild}'"; return 1; }
  elif [[ "${REPLY}" != "${body}" && ! -f "${pending}" ]]; then
    log::err "the clone carries changes free.patch does not (an older build, or edits made outside alttab edit); a build resets it from free.patch | src='${src}' fix='${rebuild}'"
    return 1
  fi

  typeset -g ALTTAB_EDIT_PENDING="${pending}" ALTTAB_EDIT_FAILED=""
  local mode=source
  (( ${+opts[--header]} )) && mode=header
  local -i rc=0
  alttab::_edit_session "${mode}" || rc=$?
  # A source edit whose only fault is the header: the header is the place to fix it.
  if (( rc == 0 )) && [[ "${ALTTAB_EDIT_FAILED}" == header ]]; then
    alttab::_edit_keep "${pending}" "${sum}"
    if ! [[ -t 0 && -t 1 ]] || ! ui::confirm "Name them in free.patch's header now?"; then
      log::err "free.patch not saved; the edit is kept | pending='${pending}' fix='${CLI_NAME} alttab edit --header'"
      return 1
    fi
    mode=header rc=0
    alttab::_edit_session header || rc=$?
  fi
  # Not passed (or the editor failed): whatever was saved is kept for the next edit.
  if (( rc == 1 )); then
    if [[ "${mode}" == header ]]; then
      if edit::same "${pending}" "${patch}"; then rm -f -- "${pending}" "${pending}.base"; else alttab::_edit_keep "${pending}" "${sum}"; fi
    else
      alttab::_edit_clone_diff
      [[ ! -f "${pending}" && "${REPLY}" == "${body}" ]] || alttab::_edit_keep "${pending}" "${sum}"
    fi
    return 1
  fi
  if (( rc == 2 )) || edit::same "${pending}" "${patch}"; then
    rm -f -- "${pending}" "${pending}.base"
    print -r -- "alttab: no change | patch=$(ui::paths "${patch}")"
    return 0
  fi

  # A --header edit may change the diff itself: the clone takes it, and the patch is rewritten
  # from the clone so its index lines are git's and the next edit finds the two in step.
  alttab::_edit_body "${pending}"
  body="${REPLY}"
  alttab::_edit_clone_diff
  if [[ "${REPLY}" != "${body}" ]]; then
    if ! { git -C "${src}" reset --quiet --hard HEAD && git -C "${src}" apply -- "${pending}" \
        && zsh "${build}" --regen-patch --src "${src}" --patch "${pending}" --ref "${ALTTAB_REF}" >/dev/null 2>&1; }; then
      git -C "${src}" reset --quiet --hard HEAD && git -C "${src}" apply -- "${patch}"
      alttab::_edit_keep "${pending}" "${sum}"
      log::err "the edited patch did not apply to the clone; free.patch unchanged, the edit is kept | pending='${pending}' fix='${CLI_NAME} alttab edit --header'"
      return 1
    fi
    if edit::same "${pending}" "${patch}"; then
      rm -f -- "${pending}" "${pending}.base"
      print -r -- "alttab: no change | patch=$(ui::paths "${patch}")"
      return 0
    fi
  fi

  edit::install "${pending}" "${patch}" || return 1
  rm -f -- "${pending}.base"
  local -a diffs=("${(@M)${(@f)$(<"${patch}")}:#diff --git *}") hunks=("${(@M)${(@f)$(<"${patch}")}:#@@*}")
  print -r -- "alttab: free.patch saved | files=${#diffs} hunks=${#hunks} patch=$(ui::paths "${patch}")"
  if (( ${+opts[--no-commit]} )); then
    print -r -- "not committed | file=$(ui::paths "${patch}")"
  else
    tier::commit shared "${CLI_NAME}: edit alttab free.patch" "${patch}" || return 1
  fi
  print -r -- "next: ${CLI_NAME} alttab install"
}
