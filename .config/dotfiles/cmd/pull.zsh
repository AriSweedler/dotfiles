# dotfiles/cmd/pull.zsh — `dotfiles pull`: bring the shared tier up to origin (fast-forward, or
# replay local commits on top), then name the steps the pulled paths affect (step::watches) and
# the one `dotfiles apply` that brings the machine along. No check runs: that is init's job.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

# What pull::report found: the affected steps in run order, and each one's paths (one per line).
typeset -ga PULL_ORDER=()
typeset -gA PULL_WHY=()

help_pull() {
  cat <<EOF
update the shared tier from origin; name the steps the pulled changes affect

${c_bold}Usage${c_rst}
  ${DF} pull [--dry-run] [--edit [FILE]]

  'git df pull --rebase --autostash': a fast-forward when nothing is local,
  otherwise the local commits are replayed onto origin, with uncommitted edits
  stashed around it. A replay that conflicts is aborted, the tier is left as it
  was, and the conflicting files are named: resolve by hand
  ('git df pull --rebase'), then pull again. Then the pulled paths are mapped
  to the steps that watch them (no check runs): a warning names each affected
  step and its paths, and one 'dotfiles apply STEP..' brings the machine along.
  The harness (lib/, cmd/) is live as soon as it lands. The local tier is never
  pulled: it has one machine.

  With --edit (a terminal only), the affected steps then open in \$EDITOR as a
  plan, $(help::tilde "${ARI_DOTFILES_STATE_DIR}")/pull-plan.dfpull, one
  'apply|skip STEP  # paths' line each, every one apply. On save the plan is
  checked line by line; an unchanged plan runs as written, one with no step
  line aborts, and the 'apply' steps run in a fresh 'dotfiles apply'. A plan
  with bad lines is kept: edit it again, or resume it with --edit FILE.

${c_bold}Flags${c_rst}
  --dry-run     fetch, then name what the pull would bring and the steps it
                affects; merge nothing (with --edit, the apply is a dry run too)
  --edit [FILE] after the pull, choose the steps to apply in \$EDITOR; FILE
                resumes a plan that did not pass, without pulling again

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_REMOTE)
      the shared repo (default ${ARI_DOTFILES_REMOTE})
EOF
}

# True (0) while a rebase is stopped in the shared tier.
is_rebase_in_progress() {
  local dir
  for dir in rebase-merge rebase-apply; do
    [[ -d "$(repo_git shared rev-parse --git-path "${dir}")" ]] && return 0
  done
  return 1
}

# The pull, and on a stopped replay: name the conflicts, abort (the autostash comes back with it).
pull_rebase() {
  run_mut repo_git shared pull --rebase --autostash && return 0
  if ! is_rebase_in_progress; then
    log::err "pull failed before replaying anything | fix='git df pull --rebase' see='the git output above'"
    return 1
  fi
  local -a conflicts=("${(@f)$(repo_git shared diff --name-only --diff-filter=U 2>/dev/null)}")
  repo_git shared rebase --abort
  log::err "local commits conflict with origin; pull aborted, nothing changed | conflicts='${(j:, :)conflicts:#}' fix='git df pull --rebase, resolve, git df rebase --continue, then dotfiles pull'"
  return 1
}

# The changed paths between two commits, as `git diff --name-status` lines (one git call).
pull::changes() {
  repo_git shared diff --name-status --no-renames "${1}" "${2}" -- 2>/dev/null
}

# Paths, as `a, b, c` or the first three and how many more.
pull::paths() {
  local -a ps=("$@")
  if (( ${#ps} > 3 )); then print -r -- "${(j:, :)ps[1,3]}, +$(( ${#ps} - 3 )) more"
  else print -r -- "${(j:, :)ps}"
  fi
}

# What the pull brought, from `watch::map` lines on stdin: a warning per affected step with the
# paths behind it, then the one apply. One line when nothing changed. Never runs a check.
pull::report() {
  local before="${1}" after="${2}" kind name p
  local -a lines harness removed changed
  PULL_ORDER=() PULL_WHY=()
  ui::is_fancy || true   # decided here, before any $(…) below
  if [[ "${before}" == "${after}" ]]; then print -r -- "up to date: nothing to pull"; return 0; fi
  local changes; changes="$(pull::changes "${before}" "${after}")"
  lines=("${(@f)$(watch::map <<< "${changes}")}")
  changed=(${(f)changes})
  for p in "${lines[@]}"; do
    kind="${p%% *}"; p="${p#* }"
    case "${kind}" in
      step)    name="${p%% *}"; (( ${PULL_ORDER[(Ie)${name}]} )) || PULL_ORDER+=("${name}"); PULL_WHY[${name}]+="${p#* }"$'\n' ;;
      harness) harness+=("${p}") ;;
      removed) removed+=("${p%% *}") ;;
    esac
  done
  local verb=pulled; is_dry_run && verb="would pull"
  print -r -- "${verb} $(plural "${#changed}" "changed path" "changed paths") (${before[1,7]}..${after[1,7]})"
  (( ${#harness} )) && print -r -- "harness updated, live now: $(pull::paths "${harness[@]}")"
  (( ${#removed} )) && print -r -- "step removed, nothing to apply: ${(j:, :)removed}"
  if (( ! ${#PULL_ORDER} )); then print -r -- "no step watches these paths: nothing to apply"; return 0; fi
  ui::paint warn "$(ui::glyph warn) the pull changed files $(plural "${#PULL_ORDER}" "step reads" "steps read"); check this machine still matches:"
  local width=0
  for name in "${PULL_ORDER[@]}"; do (( ${#name} > width )) && width=${#name}; done
  for name in "${PULL_ORDER[@]}"; do
    printf '  %-*s  %s\n' "${width}" "${name}" "$(pull::paths "${(@f)${PULL_WHY[${name}]%$'\n'}}")"
  done
  print -r -- "run: $(ui::paint bold "${CLI_NAME} apply ${PULL_ORDER[*]}")"
  # On a terminal the block above is the warning; the record goes only where a log is kept.
  pull::is_terminal && return 0
  log::warn "pulled changes affect steps | steps='${(j:,:)PULL_ORDER}' fix='${CLI_NAME} apply ${PULL_ORDER[*]}'"
}

# True (0) when the output is fancy and stderr is a terminal: no log is kept there, so the
# stdout block is the one warning.
pull::is_terminal() { ui::is_fancy && [[ -t 2 ]]; }

# The registry, for its watches; sourcing the step files runs no check. A registry that does not
# load still leaves the step-file mapping, which needs none.
pull::load_registry() {
  (( ${#STEPS} )) && return 0
  steps::load && watch::validate && return 0
  log::warn "step registry did not load; mapping step files only | fix='${CLI_NAME} steps'"
  return 0
}

cmd_pull() {
  local start="${EPOCHREALTIME}" before after resume=""
  local -i edit=0
  while (( $# )); do
    case "${1}" in
      --dry-run) export ARI_DOTFILES_DRY_RUN=1 ;;
      --edit)
        edit=1
        if [[ -n "${2:-}" && "${2}" != -* ]]; then resume="${2}"; shift; fi ;;
      *) usage_error "pull: unknown argument | arg='${1}'" ;;
    esac
    shift
  done
  if (( edit )); then
    [[ -t 0 && -t 1 ]] || usage_error "pull --edit opens \$EDITOR: it needs a terminal | fix='${CLI_NAME} pull, then ${CLI_NAME} apply STEP..'"
    if [[ -n "${resume}" ]]; then
      [[ -f "${resume}" ]] || usage_error "pull --edit: no such plan file | file='${resume}'"
      pull::load_registry
      pull::edit "${resume}"
      return
    fi
  fi
  check_prerequisites git || return 1
  before="$(repo_git shared rev-parse HEAD)" || { log::err "shared tier has no HEAD | fix='${CLI_NAME} apply dotfiles_repo'"; return 1; }
  if is_dry_run; then
    # A fetch moves only origin/*, so it runs; what the pull would bring is the upstream's side.
    slow=5 step fetch repo_git shared fetch --quiet || return 1
    after="$(repo_git shared rev-parse '@{u}')" || { log::err "no upstream to pull from | fix='git df branch --set-upstream-to=origin/main'"; return 1; }
    before="$(repo_git shared merge-base HEAD "${after}")" || before="$(repo_git shared rev-parse HEAD)"
    run_mut repo_git shared pull --rebase --autostash
  else
    slow=5 step pull pull_rebase || return 1   # a fetch takes seconds; that is not slow
    after="$(repo_git shared rev-parse HEAD)"
  fi
  log::info "pulled | took='$(elapsed "${start}")s'"
  slow=0.5 timed pull_changes pull::analyze "${before}" "${after}"
  (( edit )) || return 0
  if (( ! ${#PULL_ORDER} )); then print -r -- "pull: no step to plan"; return 0; fi
  local plan="${ARI_DOTFILES_STATE_DIR}/pull-plan.dfpull"
  mkdir -p -- "${plan:h}" || return 1
  pull::edit_file > "${plan}" || return 1
  pull::edit "${plan}"
}

# Everything after the pull: the registry, the mapping, the report. Budget 0.5 s.
pull::analyze() {
  pull::load_registry
  pull::report "${1}" "${2}"
}

# --- pull --edit: the affected steps as a plan in $EDITOR ---

# The plan for PULL_ORDER: a header naming the actions, then `apply  <step>  # <paths>` per step,
# padded to one column. A step the registry does not know (a dry run of a pull that adds one) is
# a comment: there is nothing here to apply yet.
pull::edit_file() {
  local name width=0 paths
  cat <<EOF
# ${CLI_NAME} pull --edit: the steps the pulled changes affect, one per line: <action> <step>  # paths
#   apply   run the step: its check, then its apply when the check asks for it
#   skip    leave it ('${CLI_NAME} apply STEP' later)
# Save and quit to run one '${CLI_NAME} apply' of every 'apply' step; an unchanged plan runs as
# written. Any step '${CLI_NAME} steps' lists may be added. Lines starting with # are comments;
# a plan with no step line aborts and applies nothing.

EOF
  for name in "${PULL_ORDER[@]}"; do (( ${#name} > width )) && width=${#name}; done
  for name in "${PULL_ORDER[@]}"; do
    paths="$(pull::paths "${(@f)${PULL_WHY[${name}]%$'\n'}}")"
    if step::is_known "${name}"; then
      printf 'apply  %-*s  # %s\n' "${width}" "${name}" "${paths}"
    else
      printf '# %s: not in this checkout yet  # %s\n' "${name}" "${paths}"
    fi
  done
}

# Parses a plan: fills the caller's `chosen` (the apply steps, in plan order) and `planned` (every
# step line's step), and prints one `line N: problem | line='…'` per bad line on stderr. Returns 1
# when any line is bad. A line: apply or skip, one step the registry knows, at most once per file,
# then an optional '# comment'.
pull::edit_parse() {
  setopt localoptions extendedglob
  local file="${1}" line body
  local -a words
  local -i n=0 bad=0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    n=$(( n + 1 ))
    body="${${line%%\#*}##[[:space:]]#}"
    body="${body%%[[:space:]]#}"
    [[ -n "${body}" ]] || continue
    words=(${=body})
    if [[ "${words[1]}" != (apply|skip) ]]; then
      print -u2 -r -- "line ${n}: unknown action; use apply or skip | line='${line}'"; bad=1; continue
    fi
    if (( ${#words} != 2 )); then
      print -u2 -r -- "line ${n}: expected one step after the action | line='${line}'"; bad=1; continue
    fi
    if ! step::is_known "${words[2]}"; then
      print -u2 -r -- "line ${n}: not a step here (${CLI_NAME} steps) | step='${words[2]}' line='${line}'"; bad=1; continue
    fi
    if (( ${planned[(Ie)${words[2]}]} )); then
      print -u2 -r -- "line ${n}: listed twice | step='${words[2]}'"; bad=1; continue
    fi
    planned+=("${words[2]}")
    [[ "${words[1]}" != apply ]] || chosen+=("${words[2]}")
  done < "${file}"
  return ${bad}
}

# `pull --edit`: <plan> opened in $EDITOR, then parsed. Bad lines: each reported with its number,
# offered for another edit, else exit 1 naming the --edit FILE that resumes. A plan with no step
# line aborts; one that skips every step applies nothing; otherwise this process becomes a fresh
# `dotfiles apply` of the chosen steps (the pull may have replaced lib/ under this one).
pull::edit() {
  local plan="${1}" editor bin
  local -a chosen planned
  editor="${EDITOR:-vi}"
  command -v "${editor%% *}" >/dev/null 2>&1 || editor=vi
  while true; do
    if ! ${=editor} "${plan}"; then
      log::err "editor exited non-zero; nothing applied | editor='${editor}' plan='${plan}'"
      return 1
    fi
    chosen=() planned=()
    pull::edit_parse "${plan}" && break
    if ui::confirm "Edit the plan again?"; then continue; fi
    log::err "plan not run; fix the lines above, then | fix='${CLI_NAME} pull --edit ${plan}'"
    return 1
  done
  rm -f -- "${plan}"
  if (( ! ${#planned} )); then
    print -r -- "pull: the plan has no step line; aborted, nothing applied"
    return 0
  fi
  if (( ! ${#chosen} )); then
    print -r -- "pull: every step skipped; nothing applied"
    print -r -- "next: ${CLI_NAME} apply ${planned[*]}"
    return 0
  fi
  bin="${ARI_DOTFILES_ROOT:h}/bin/${CLI_NAME}"
  print -r -- "running: ${CLI_NAME} apply ${chosen[*]}"
  exec "${bin}" apply "${chosen[@]}"
}
