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

alttab_edit_help() {
  cat <<EOF
${CLI_NAME} alttab edit [--header] [--no-commit]

Opens the files free.patch changes, in alttab-free-build's clone ($(ui::paths "${ALTTAB_SRC}")),
in \$EDITOR (vi when unset). On save free.patch becomes its prose header plus the clone's
'git diff HEAD'. With --header it opens free.patch itself, and prints the change as a diff.
Either way the new patch must apply to a clean ${ALTTAB_REF:-free.patch.ref} checkout
(alttab-free-build --check-patch), and its header's "What it changes" list must name every file
it touches (the file's name without .swift, first on its line). A patch that passes replaces
free.patch and is committed in the shared tier; one that does not is kept for the next
'alttab edit' (on a terminal, offered for another edit). Nothing is built or installed.

The patch keeps Pro locked except shortcut slot 2 (AGENTS.md): do not edit it to unlock more.

  --header     edit free.patch itself (its header, or the diff below it)
  --no-commit  put the patch in place, leave it uncommitted

Refuses while 'alttab-free-build --rebase-patch' is unfinished, and when the clone is missing,
at another ref, or carries changes free.patch does not (alttab-free-build --build-only resets it
from free.patch).

Exit 0 saved (or no change); 1 refused, the patch did not pass, the editor failed or the commit
was refused; 64 usage.
EOF
}

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

alttab::edit() {
  local header=0 commit=1 arg
  for arg in "$@"; do
    case "${arg}" in
      -h|--help) alttab_edit_help; return 0 ;;
      --header) header=1 ;;
      --no-commit) commit=0 ;;
      *) usage_error "alttab edit: bad argument | arg='${arg}'" ;;
    esac
  done
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

  local editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  local -i tty=0
  [[ -t 0 && -t 1 ]] && tty=1
  local -a files untracked
  local mode=source what
  (( header )) && mode=header
  while true; do
    if [[ "${mode}" == source ]]; then
      files=("${(@f)$(git -C "${src}" diff --name-only HEAD)}")
      files=("${(@)files:#}")
      alttab::_edit_rule
      print -r -- "opening ${#files} patched file(s) in $(ui::paths "${src}")"
      if ! ${=editor} "${files[@]/#/${src}/}"; then
        alttab::_edit_clone_diff
        [[ "${REPLY}" == "${body}" ]] || alttab::_edit_keep "${pending}" "${sum}"
        log::err "editor exited non-zero; free.patch unchanged, the clone keeps what was saved | editor='${editor}' fix='${CLI_NAME} alttab edit'"
        return 1
      fi
      untracked=("${(@f)$(git -C "${src}" ls-files --others --exclude-standard)}")
      untracked=("${(@)untracked:#}")
      (( ${#untracked} )) && log::warn "new files are not in the patch until git knows them | files='${(j:, :)untracked}' fix='git -C ${src} add -N FILE'"
      [[ -f "${pending}" ]] || cp -p -- "${patch}" "${pending}"
      zsh "${build}" --regen-patch --src "${src}" --patch "${pending}" --ref "${ALTTAB_REF}" >/dev/null 2>&1 || {
        alttab::_edit_keep "${pending}" "${sum}"
        log::err "could not regenerate the patch from the clone | pending='${pending}' fix='zsh ${build} --regen-patch --patch ${pending}'"
        return 1
      }
    else
      [[ -f "${pending}" ]] || cp -p -- "${patch}" "${pending}"
      alttab::_edit_rule
      if ! ${=editor} "${pending}"; then
        cmp -s -- "${pending}" "${patch}" || alttab::_edit_keep "${pending}" "${sum}"
        log::err "editor exited non-zero; free.patch unchanged | editor='${editor}' pending='${pending}' fix='${CLI_NAME} alttab edit --header'"
        return 1
      fi
    fi
    if cmp -s -- "${pending}" "${patch}"; then
      rm -f -- "${pending}" "${pending}.base"
      print -r -- "alttab: no change | patch=$(ui::paths "${patch}")"
      return 0
    fi
    if [[ "${mode}" == header ]]; then
      diff -u -L "free.patch (before)" -L "free.patch (after)" -- "${patch}" "${pending}" || true
    fi
    alttab::_edit_check "${pending}" && break
    alttab::_edit_keep "${pending}" "${sum}"
    if [[ "${REPLY}" == header ]]; then
      if (( tty )) && ui::confirm "Name them in free.patch's header now?"; then mode=header; continue; fi
      log::err "free.patch not saved; the edit is kept | pending='${pending}' fix='${CLI_NAME} alttab edit --header'"
      return 1
    fi
    what="the patched files"; [[ "${mode}" == header ]] && what=free.patch
    if (( tty )) && ui::confirm "Edit ${what} again?"; then continue; fi
    log::err "free.patch not saved; the edit is kept | pending='${pending}' fix='${CLI_NAME} alttab edit${${mode:#source}:+ --header}'"
    return 1
  done

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
    if cmp -s -- "${pending}" "${patch}"; then
      rm -f -- "${pending}" "${pending}.base"
      print -r -- "alttab: no change | patch=$(ui::paths "${patch}")"
      return 0
    fi
  fi

  # In place, keeping free.patch's mode (600): written beside it and renamed over it.
  zmodload -F zsh/stat b:zstat
  local -a st
  local perm=600
  zstat -A st +mode -- "${patch}" 2>/dev/null && perm="$(( [##8] st[1] & 8#777 ))"
  cp -- "${pending}" "${patch}.edit.$$" && chmod "${perm}" "${patch}.edit.$$" && mv -f -- "${patch}.edit.$$" "${patch}" || {
    rm -f -- "${patch}.edit.$$"
    log::err "could not put free.patch in place; the edit is kept | patch='${patch}' pending='${pending}'"
    return 1
  }
  rm -f -- "${pending}" "${pending}.base"
  local -a diffs=("${(@M)${(@f)$(<"${patch}")}:#diff --git *}") hunks=("${(@M)${(@f)$(<"${patch}")}:#@@*}")
  print -r -- "alttab: free.patch saved | files=${#diffs} hunks=${#hunks} patch=$(ui::paths "${patch}")"
  if (( commit )); then
    tier::commit shared "${CLI_NAME}: edit alttab free.patch" "${patch}" || return 1
  else
    print -r -- "not committed | file=$(ui::paths "${patch}")"
  fi
  print -r -- "next: ${CLI_NAME} alttab install"
}
