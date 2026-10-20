# dotfiles/cmd/pull.zsh — `dotfiles pull`: bring the shared tier up to origin (fast-forward, or
# replay local commits on top), then name the steps the pulled paths affect (step::watches) and
# the one `dotfiles apply` that brings the machine along. No check runs: that is init's job.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

# What pull::report found: the affected steps in run order, and each one's paths (one per line).
typeset -ga PULL_ORDER=()
typeset -gA PULL_WHY=()

verb::define pull 'update the shared tier from origin; name the steps the pulled changes affect'
verb::usage pull 'pull [--dry-run]'
verb::about pull <<'EOF'
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
EOF
verb::edit pull pull::edit_cmd '[FILE] [--dry-run]' 'after the pull, choose the steps to apply in \$EDITOR; FILE resumes a plan that did not pass, without pulling again'
verb::flag pull '--dry-run' 'fetch, then name what the pull would bring and the steps it affects; merge nothing (edit: the apply is a dry run too)'
verb::env pull ARI_DOTFILES_REMOTE 'the shared repo' '${ARI_DOTFILES_REMOTE}'

plan::define pull --actions 'apply|skip' --item step

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

cmd_pull() { pull::main 0 "$@"; }
pull::edit_cmd() { pull::main 1 "$@"; }

# pull::main EDIT ARGS..: the pull, then (EDIT 1, or --edit anywhere in ARGS) the plan.
pull::main() {
  local -i edit="${1}"; shift
  local -A opts; local -a args
  verb::parse pull "$@"
  (( ${+opts[--edit]} )) && edit=1
  (( ! ${+opts[--dry-run]} )) || export ARI_DOTFILES_DRY_RUN=1
  (( ${#args} <= edit )) || usage_error "pull: unknown argument | args='${args[*]}'"
  local start="${EPOCHREALTIME}" before after resume="${args[1]:-}"
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

# The plan for PULL_ORDER: plan::header, then `apply  <step>  # <paths>` per step. A step the
# registry does not know (a dry run of a pull that adds one) is a comment: there is nothing here
# to apply yet.
pull::edit_file() {
  local name paths
  plan::header pull \
    "${CLI_NAME} pull --edit: the steps the pulled changes affect; the note is the paths behind each." \
    "  apply   run the step: its check, then its apply when the check asks for it" \
    "  skip    leave it ('${CLI_NAME} apply STEP' later)" \
    "Save and quit to run one '${CLI_NAME} apply' of every 'apply' step; an unchanged plan runs as" \
    "written. Any step '${CLI_NAME} steps' lists may be added; a plan with no step line aborts" \
    "and applies nothing."
  for name in "${PULL_ORDER[@]}"; do
    paths="$(pull::paths "${(@f)${PULL_WHY[${name}]%$'\n'}}")"
    if step::is_known "${name}"; then plan::line apply "${name}" "${paths}"
    else plan::comment "${name}: not in this checkout yet  # ${paths}"; fi
  done
}

# pull::edit_step <step>: plan::parse's item check, a step the registry knows.
pull::edit_step() { step::is_known "${1}" || { print -r -- "not a step here (${CLI_NAME} steps)"; return 1; }; }
# pull::edit_check <plan>: edit::session's check, every line through plan::parse.
pull::edit_check() { local -a reply; plan::parse pull "${1}" pull::edit_step; }

# `pull --edit`: <plan> in one edit::session, checked on every save, an unchanged one included
# (it runs as written). A plan with no step line aborts; one that skips every step applies
# nothing; otherwise this process becomes a fresh `dotfiles apply` of the chosen steps (the pull
# may have replaced lib/ under this one).
pull::edit() {
  local plan="${1}" bin r
  local -a reply f chosen=() planned=()
  edit::session "${plan}" --check pull::edit_check --what "the plan" --changed \
    --resume "${CLI_NAME} pull --edit ${plan}" || return 1
  plan::parse pull "${plan}" pull::edit_step 2>/dev/null
  rm -f -- "${plan}"
  for r in "${reply[@]}"; do
    f=("${(@ps:\t:)r}")
    planned+=("${f[2]}")
    [[ "${f[1]}" != apply ]] || chosen+=("${f[2]}")
  done
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
