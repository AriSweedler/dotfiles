# dotfiles/cmd/pull.zsh — `dotfiles pull`: bring the shared tier up to origin (fast-forward, or
# replay local commits on top), then name the steps the pulled paths affect (step::watches) and
# the one `dotfiles apply` that brings the machine along. No check runs: that is init's job.
zmodload zsh/datetime   # EPOCHREALTIME / EPOCHSECONDS

help_pull() {
  cat <<EOF
update the shared tier from origin; name the steps the pulled changes affect

${c_bold}Usage${c_rst}
  ${DF} pull [--dry-run]

  'git df pull --rebase --autostash': a fast-forward when nothing is local,
  otherwise the local commits are replayed onto origin, with uncommitted edits
  stashed around it. A replay that conflicts is aborted, the tier is left as it
  was, and the conflicting files are named: resolve by hand
  ('git df pull --rebase'), then pull again. Then the pulled paths are mapped
  to the steps that watch them (no check runs): a warning names each affected
  step and its paths, and one 'dotfiles apply STEP..' brings the machine along.
  The harness (lib/, cmd/) is live as soon as it lands. The local tier is never
  pulled: it has one machine.

${c_bold}Flags${c_rst}
  --dry-run   fetch, then name what the pull would bring and the steps it
              affects; merge nothing

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
  local -a lines order harness removed changed
  local -A why=()
  ui::is_fancy || true   # decided here, before any $(…) below
  if [[ "${before}" == "${after}" ]]; then print -r -- "up to date: nothing to pull"; return 0; fi
  local changes; changes="$(pull::changes "${before}" "${after}")"
  lines=("${(@f)$(watch::map <<< "${changes}")}")
  changed=(${(f)changes})
  for p in "${lines[@]}"; do
    kind="${p%% *}"; p="${p#* }"
    case "${kind}" in
      step)    name="${p%% *}"; (( ${order[(Ie)${name}]} )) || order+=("${name}"); why[${name}]+="${p#* }"$'\n' ;;
      harness) harness+=("${p}") ;;
      removed) removed+=("${p%% *}") ;;
    esac
  done
  local verb=pulled; is_dry_run && verb="would pull"
  print -r -- "${verb} $(plural "${#changed}" "changed path" "changed paths") (${before[1,7]}..${after[1,7]})"
  (( ${#harness} )) && print -r -- "harness updated, live now: $(pull::paths "${harness[@]}")"
  (( ${#removed} )) && print -r -- "step removed, nothing to apply: ${(j:, :)removed}"
  if (( ! ${#order} )); then print -r -- "no step watches these paths: nothing to apply"; return 0; fi
  ui::paint warn "$(ui::glyph warn) $(plural "${#order}" "step" "steps") may have drifted:"
  local width=0
  for name in "${order[@]}"; do (( ${#name} > width )) && width=${#name}; done
  for name in "${order[@]}"; do
    printf '  %-*s  %s\n' "${width}" "${name}" "$(pull::paths "${(@f)${why[${name}]%$'\n'}}")"
  done
  print -r -- "run: $(ui::paint bold "${CLI_NAME} apply ${order[*]}")"
  log::warn "pulled changes affect steps | steps='${(j:,:)order}' fix='${CLI_NAME} apply ${order[*]}'"
}

# The registry, for its watches; sourcing the step files runs no check. A registry that does not
# load still leaves the step-file mapping, which needs none.
pull::load_registry() {
  (( ${#STEPS} )) && return 0
  steps::load && watch::validate && return 0
  log::warn "step registry did not load; mapping step files only | fix='${CLI_NAME} steps'"
  return 0
}

cmd_pull() {
  [[ "${1:-}" != --dry-run ]] || { export ARI_DOTFILES_DRY_RUN=1; shift; }
  (( $# == 0 )) || usage_error "pull takes no arguments | args='$*'"
  local start="${EPOCHREALTIME}" before after
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
  return 0
}

# Everything after the pull: the registry, the mapping, the report. Budget 0.5 s.
pull::analyze() {
  pull::load_registry
  pull::report "${1}" "${2}"
}
