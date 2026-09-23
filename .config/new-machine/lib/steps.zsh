# Step registry, runner, and every check::/apply:: pair (§2.4, §2.5). Requires common.zsh,
# brew.zsh and launchd.zsh to be sourced first. Side-effect-free at source time.
#
# check::<step> is pure: writes nothing outside RUN_DIR, prints exactly one verdict on stdout,
# logs on stderr, returns 0. apply::<step> mutates only through run_cmd_mutating and returns
# the command's rc. Each runs in its own zsh so a crash can never abort the loop.
(( ${+NEW_MACHINE_STEPS_LOADED} )) && return 0
typeset -g NEW_MACHINE_STEPS_LOADED=1

typeset -gra STEPS=(brew brew_pkgs brew_drift dotfiles_repo local_dotfiles_repo bob_neovim claude
                    terminal_nerdfont karabiner claude_notifications claude_skills chrome_exoskeleton
                    dotfiles_jobs)
typeset -gA STEP_NEEDS=([brew_pkgs]=brew [brew_drift]=brew [terminal_nerdfont]=brew [chrome_exoskeleton]=dotfiles_repo [dotfiles_jobs]=dotfiles_repo)
typeset -gA STEP_DESC=(
  [brew]="Homebrew is installed"
  [brew_pkgs]="every item declared in the merged Brewfiles is installed (brew bundle check/install --no-upgrade)"
  [brew_drift]="nothing installed on request is undeclared, orphaned, or declared twice (new-machine brew triage)"
  [dotfiles_repo]="shared dotfiles bare repo cloned, checked out into HOME, hooks wired"
  [local_dotfiles_repo]="local dotfiles bare repo exists with the allowlist, hooks, and a remote"
  [bob_neovim]="neovim installed through bob"
  [claude]="Claude Code installed"
  [terminal_nerdfont]="a Nerd Font cask is installed and at least one Terminal.app profile uses a Nerd Font"
  [karabiner]="karabiner.json exists, is valid JSON, and is jq -S sorted; healthcheck runs when present"
  [claude_notifications]="Claude Code hooks wired: Notification → notification-fire.sh, PreToolUse guard → pretooluse-headless-chrome-guard.sh; terminal-notifier resolves"
  [claude_skills]="every skill a dotfiles tier holds is symlinked into ~/.claude/skills and no link dangles"
  [chrome_exoskeleton]="the Chrome Exoskeleton submodule has its dependencies (which wire its hooks) and a built dist/"
  [dotfiles_jobs]="dotfiles jobs launchd job (runs the job plugins of both tiers) installed and loaded"
)

typeset -gr BREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
typeset -gr CLAUDE_INSTALLER="https://claude.ai/install.sh"
typeset -gra STEP_LIBS=(common brew steps)

# ── Runner ───────────────────────────────────────────────────────────────────

# Kills a process tree deepest-first, so a brew two forks down (a function run inside $(...))
# dies with the check instead of surviving it and holding brew's lock.
step::_kill_tree() {
  local sig="${1}" pid="${2}" child
  local -a children=(${(f)"$(pgrep -P "${pid}" 2>/dev/null || true)"})
  for child in "${children[@]}"; do
    step::_kill_tree "${sig}" "${child}"
  done
  kill "-${sig}" "${pid}" 2>/dev/null || true
}

# Watchdog. TERM to the child's whole tree, KILL 5 s later; reaps its own sleep so runs and tests
# leave no stragglers. 0 = no timeout.
step::with_timeout() {
  local secs="${1}"; shift
  if (( secs == 0 )); then "$@"; return; fi
  "$@" & local pid=$!
  ( sleep "${secs}"; step::_kill_tree TERM "${pid}"; sleep 5; step::_kill_tree KILL "${pid}" ) & local wd=$!
  local rc=0; wait "${pid}" || rc=$?
  pkill -P "${wd}" 2>/dev/null; kill "${wd}" 2>/dev/null; wait "${wd}" 2>/dev/null || true
  return "${rc}"
}

step::is_known() {
  (( ${STEPS[(Ie)${1}]} ))
}

step::has_apply() {
  (( ${+functions[apply::${1}]} ))
}

# A verdict the runner writes on the step's behalf when the check itself could not run.
step::synth_verdict() {
  local name="${1}" step_status="${2}" reason="${3}" detail="${4:-}"
  jq -cn --arg step "${name}" --arg status "${step_status}" --arg reason "${reason}" --arg detail "${detail}" \
    '{step:$step,status:$status,reason:$reason,detail:$detail,fix:null,manual:false,actionable:false,items:[]}'
}

step::result_status() {
  local file="${RUN_DIR}/${1}.result.json"
  if [[ -f "${file}" ]]; then
    jq -r '.status' "${file}"
  fi
}

# Runs one check::/apply:: in a fresh zsh that sources the libs, under the watchdog. The
# function name travels in $STEP so no shell quoting of the name is needed.
step::run_isolated() {
  local kind="${1}" name="${2}" timeout_secs="${3}"
  local -a libs=("${STEP_LIBS[@]}")
  export STEP="${name}"
  step::with_timeout "${timeout_secs}" zsh -c '
    set -euo pipefail
    for lib in '"${libs[*]}"'; do source "${NEW_MACHINE_SHARED_DIR}/lib/${lib}.zsh"; done
    "'"${kind}"'::${STEP}"'
}

# Runs the check, normalizing crashes and timeouts into error verdicts in <check_file>.
step::run_check() {
  local name="${1}" check_file="${2}" log_file="${3}"
  local rc=0
  local -F start="${EPOCHREALTIME}"
  step::run_isolated check "${name}" "${NEW_MACHINE_CHECK_TIMEOUT_SECS}" > "${check_file}" 2>> "${log_file}" || rc=$?
  local -i elapsed_ms
  (( elapsed_ms = (EPOCHREALTIME - start) * 1000 ))
  local timed_out=0 verdict_status=""
  if jq -e 'type=="object" and (.status|type)=="string"' "${check_file}" >/dev/null 2>&1; then
    verdict_status="$(jq -r '.status' "${check_file}")"
  fi
  if (( rc == 143 || rc == 137 )); then
    timed_out=1
  elif (( NEW_MACHINE_CHECK_TIMEOUT_SECS > 0 && elapsed_ms >= NEW_MACHINE_CHECK_TIMEOUT_SECS * 1000 )) \
       && ! { (( rc == 0 )) && [[ "${verdict_status}" == (ok|warn) ]]; }; then
    # The watchdog fired, so brew under the check was killed; anything but a clean ok/warn reached
    # after that describes the kill, not the machine.
    timed_out=1
  fi
  if (( timed_out )); then
    log::err "check timed out | step='${name}' secs='${NEW_MACHINE_CHECK_TIMEOUT_SECS}'" 2>> "${log_file}"
    step::synth_verdict "${name}" error timed_out "timed out after ${NEW_MACHINE_CHECK_TIMEOUT_SECS}s" > "${check_file}"
  elif (( rc != 0 )) || [[ -z "${verdict_status}" ]]; then
    local tail_text
    tail_text="$(nm::tail_lines "${log_file}" 10)"
    step::synth_verdict "${name}" error check_crashed "check exited ${rc}${tail_text:+$'\n'}${tail_text}" > "${check_file}"
  fi
  print -r -- "${rc} ${elapsed_ms}"
}

step::record_result() {
  local name="${1}" verdict_file="${2}" rc="${3}" duration_ms="${4}" log_file="${5}" applied_json="${6}"
  jq -c --argjson rc "${rc}" --argjson duration_ms "${duration_ms}" --arg log "${log_file}" --argjson applied "${applied_json}" \
    '. + {rc:$rc, duration_ms:$duration_ms, log:$log, applied:$applied}' "${verdict_file}" > "${RUN_DIR}/${name}.result.json"
}

step::record_skip() {
  local name="${1}" reason="${2}" log_file="${RUN_DIR}/${1}.log"
  : >> "${log_file}"
  step::synth_verdict "${name}" skip "${reason}" > "${RUN_DIR}/${name}.check.json"
  step::record_result "${name}" "${RUN_DIR}/${name}.check.json" 0 0 "${log_file}" false
  log::info "skip | step='${name}' reason='${reason}'"
}

# step::run <name> [attempt]. Reads NM_MODE (check|setup), NM_DRY_RUN, RUN_DIR. Attempt 2 is
# verify's retry: the check lands in <name>.check.2.json and replaces the result.
step::run() {
  local name="${1}" attempt="${2:-1}"
  local log_file="${RUN_DIR}/${name}.log" check_file="${RUN_DIR}/${name}.check.json"
  if (( attempt > 1 )); then
    check_file="${RUN_DIR}/${name}.check.${attempt}.json"
  fi
  local need="${STEP_NEEDS[${name}]:-}"
  if [[ -n "${need}" ]]; then
    local need_status
    need_status="$(step::result_status "${need}")"
    if [[ -n "${need_status}" && "${need_status}" != (ok|warn) ]]; then
      step::record_skip "${name}" "prerequisite_${need_status}"
      return 0
    fi
  fi

  log::info "==> ${name}"
  local rc_ms rc duration_ms
  rc_ms="$(step::run_check "${name}" "${check_file}" "${log_file}")"
  rc="${rc_ms%% *}"; duration_ms="${rc_ms##* }"
  local step_status actionable applied=false
  step_status="$(jq -r '.status' "${check_file}")"
  actionable="$(jq -r '.actionable' "${check_file}")"
  log::info "check | step='${name}' status='${step_status}' reason='$(jq -r '.reason' "${check_file}")'"

  if [[ "${NM_MODE:-check}" == setup && "${actionable}" == true ]] && step::has_apply "${name}"; then
    if nm::is_dry_run; then
      log::info "dry-run, would run apply::${name} | fix='$(jq -r '.fix // ""' "${check_file}")'"
      # The apply body runs with every mutation logged instead of executed, so the plan it prints is the real one.
      step::run_isolated apply "${name}" 0 >> "${log_file}" 2>&1 || true
      applied='"would_apply"'
    else
      log::info "apply::${name}"
      local apply_rc=0
      step::run_isolated apply "${name}" "${NEW_MACHINE_APPLY_TIMEOUT_SECS}" >> "${log_file}" 2>&1 || apply_rc=$?
      local -a apply_tail=("${(f)$(nm::tail_lines "${log_file}" 10)}")
      log::info "apply done | step='${name}' rc='${apply_rc}'"
      local recheck_file="${RUN_DIR}/${name}.recheck.json"
      rc_ms="$(step::run_check "${name}" "${recheck_file}" "${log_file}")"
      rc="${rc_ms%% *}"; duration_ms=$(( duration_ms + ${rc_ms##* } ))
      step_status="$(jq -r '.status' "${recheck_file}")"
      # Still failing, or still asking to be applied (an actionable warn), means the apply did not take.
      if [[ "${step_status}" == (fail|error) || "$(jq -r '.actionable' "${recheck_file}")" == true ]]; then
        jq -c --argjson apply_rc "${apply_rc}" --arg tail "${(F)apply_tail}" \
          '.reason = "apply_did_not_converge" | .apply_rc = $apply_rc
           | .detail = (.detail + "\napply rc=" + ($apply_rc|tostring) + ":\n" + $tail)' \
          "${recheck_file}" > "${check_file}"
      else
        cp "${recheck_file}" "${check_file}"
      fi
      applied=true
    fi
  fi
  step::record_result "${name}" "${check_file}" "${rc}" "${duration_ms}" "${log_file}" "${applied}"
}

# ── brew ─────────────────────────────────────────────────────────────────────
check::brew() {
  if [[ -z "${NEW_MACHINE_BREW}" ]]; then
    verdict fail brew_missing -d "brew not found on PATH or under ${NEW_MACHINE_BREW_PREFIXES:-<no prefixes>}" \
      -f "new-machine apply brew"
    return 0
  fi
  local version
  if ! version="$("${NEW_MACHINE_BREW}" --version 2>/dev/null)"; then
    verdict fail brew_missing -d "brew not found at ${NEW_MACHINE_BREW} (--version failed)" -f "new-machine apply brew"
    return 0
  fi
  local -a version_lines=("${(f)version}")
  verdict ok present -d "${version_lines[1]} | brew='${NEW_MACHINE_BREW}'"
}

apply::brew() {
  # NONINTERACTIVE skips the installer's RETURN prompt (its stdout is our log file, so a prompt
  # would look like a hang) but also makes it run `sudo -n`, which aborts on a cold ticket. sudo
  # prompts on /dev/tty, which the watchdog-backgrounded step can still read.
  run_cmd_mutating sudo -v || return 1
  run_cmd_mutating zsh -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$1")"' _ "${BREW_INSTALLER}"
}

# ── brew_pkgs / brew_drift ───────────────────────────────────────────────────
# The brew model owns these bodies (lib/brew.zsh §2.5, §2.7).
check::brew_pkgs() {
  brew::check_pkgs_verdict
}

apply::brew_pkgs() {
  brew::apply_pkgs
}

check::brew_drift() {
  brew::check_drift_verdict
}

# ── dotfiles_repo ────────────────────────────────────────────────────────────
# core.hooksPath is repo-local, so hooks versioned in the dotfiles tree must be wired on every machine.
steps::hooks_path() {
  git --git-dir="${1}" config --local --get core.hooksPath 2>/dev/null || true
}

steps::ensure_hooks_path() {
  local git_dir="${1}" hooks_dir="${2}"
  if [[ ! -d "${git_dir}" ]] && nm::is_dry_run; then
    run_cmd_mutating git --git-dir="${git_dir}" config --local core.hooksPath "${hooks_dir}"
    return 0
  fi
  if [[ "$(steps::hooks_path "${git_dir}")" == "${hooks_dir}" ]]; then
    log::info "hooks wired | git_dir='${git_dir}' hooks_dir='${hooks_dir}'"
    return 0
  fi
  run_cmd_mutating git --git-dir="${git_dir}" config --local core.hooksPath "${hooks_dir}"
}

# A bare clone has no index, so ls-files is empty until the first checkout populates it.
# ls-files lists only the paths under the cwd, so it runs from the work-tree root: a check
# started from a subdirectory of HOME (or from another repo inside it) must not read a populated
# index as empty.
steps::worktree_unpopulated() {
  local git_dir="${1}" work_tree="${2}"
  [[ -d "${git_dir}" ]] || return 0
  [[ -z "$(git -C "${work_tree}" --git-dir="${git_dir}" --work-tree="${work_tree}" ls-files 2>/dev/null | head -n 1)" ]]
}

check::dotfiles_repo() {
  local git_dir="${NEW_MACHINE_DF_GIT_DIR}"
  if [[ ! -d "${git_dir}" ]]; then
    verdict fail missing_bare_repo -d "no bare repo | git_dir='${git_dir}' remote='${DOTFILES_REMOTE}'" -f "new-machine apply dotfiles_repo"
    return 0
  fi
  if ! git --git-dir="${git_dir}" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    verdict fail missing_bare_repo -d "repo has no HEAD | git_dir='${git_dir}'" -f "new-machine apply dotfiles_repo"
    return 0
  fi
  if steps::worktree_unpopulated "${git_dir}" "${HOME}" \
     && [[ -n "$(git --git-dir="${git_dir}" ls-tree -r --name-only HEAD 2>/dev/null | head -n 1)" ]]; then
    verdict fail not_checked_out -d "bare repo exists but HOME was never checked out | git_dir='${git_dir}'" -f "new-machine apply dotfiles_repo"
    return 0
  fi
  local hooks
  hooks="$(steps::hooks_path "${git_dir}")"
  if [[ "${hooks}" != "${NEW_MACHINE_DF_HOOKS}" ]]; then
    verdict fail hooks_path -d "core.hooksPath='${hooks}' expected='${NEW_MACHINE_DF_HOOKS}'" -f "new-machine apply dotfiles_repo"
    return 0
  fi
  if [[ -f "${HOME}/.gitmodules" ]]; then
    local sub_status uninit drifted
    sub_status="$(git -C "${HOME}" --git-dir="${git_dir}" --work-tree="${HOME}" submodule status 2>/dev/null || true)"
    uninit="$(print -r -- "${sub_status}" | awk '/^-/ {print $2}')"
    drifted="$(print -r -- "${sub_status}" | awk '/^\+/ {print $2}')"
    if [[ -n "${uninit}" ]]; then
      verdict fail submodule_uninitialized -d "submodule not checked out | paths='${uninit//$'\n'/, }'" -f "new-machine apply dotfiles_repo"
      return 0
    fi
    if [[ -n "${drifted}" ]]; then
      verdict warn submodule_drift -d "checkout differs from the committed pointer | paths='${drifted//$'\n'/, }'" -f "cd ~ && git df submodule update   (or commit the new pointer)"
      return 0
    fi
  fi
  local dirty
  dirty="$(git --git-dir="${git_dir}" --work-tree="${HOME}" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [[ -n "${dirty}" ]]; then
    local -a lines=("${(f)dirty}")
    verdict warn uncommitted -d "$(nm::plural "${#lines}" 'uncommitted file' 'uncommitted files')" -f "git df status"
    return 0
  fi
  verdict ok clean -d "git_dir='${git_dir}' hooks='${hooks}'"
}

# Populates HOME from the bare clone. Fails, listing the conflicting files in the log, when HOME
# already holds files the checkout would overwrite; nothing is moved or deleted on the user's behalf.
apply::dotfiles_repo() {
  local git_dir="${NEW_MACHINE_DF_GIT_DIR}"
  if [[ ! -d "${git_dir}" ]]; then
    run_cmd_mutating git clone --bare "${DOTFILES_REMOTE}" "${git_dir}" || return 1
  fi
  if steps::worktree_unpopulated "${git_dir}" "${HOME}"; then
    if ! run_cmd_mutating git --git-dir="${git_dir}" --work-tree="${HOME}" checkout; then
      log::err "checkout failed; move the listed files aside and re-run | work_tree='${HOME}'"
      return 1
    fi
  fi
  # Everything after the checkout is the dotfiles harness's job: tracking config, hooks for
  # both tiers, submodules, skill links, the ssh key. It ships in the checkout just made.
  local harness="${HOME}/.config/bin/dotfiles"
  if [[ ! -r "${harness}" ]] && ! nm::is_dry_run; then
    log::err "dotfiles harness missing after checkout | path='${harness}'"
    return 1
  fi
  run_cmd_mutating zsh "${harness}" init
}

# ── local_dotfiles_repo ──────────────────────────────────────────────────────
check::local_dotfiles_repo() {
  local git_dir="${NEW_MACHINE_LDF_GIT_DIR}" exclude="${NEW_MACHINE_LDF_GIT_DIR}/info/exclude"
  if [[ ! -d "${git_dir}" ]]; then
    verdict fail missing_bare_repo -d "no bare repo | git_dir='${git_dir}'" -f "new-machine apply local_dotfiles_repo"
    return 0
  fi
  if [[ ! -r "${LDF_EXCLUDE_TEMPLATE}" ]]; then
    verdict error template_missing -d "allowlist template missing | path='${LDF_EXCLUDE_TEMPLATE}'"
    return 0
  fi
  local current_rules=""
  if [[ -f "${exclude}" ]]; then
    current_rules="$(exclude_rules "${exclude}")"
  fi
  if [[ -z "${current_rules}" ]]; then
    verdict fail allowlist_missing -d "info/exclude has no rules | exclude='${exclude}'" -f "new-machine apply local_dotfiles_repo"
    return 0
  fi
  local hooks
  hooks="$(steps::hooks_path "${git_dir}")"
  if [[ "${hooks}" != "${NEW_MACHINE_LDF_HOOKS}" ]]; then
    verdict fail hooks_path -d "core.hooksPath='${hooks}' expected='${NEW_MACHINE_LDF_HOOKS}'" -f "new-machine apply local_dotfiles_repo"
    return 0
  fi
  # The machine keeps its own allowlist; the tool only points at the difference.
  if [[ "${current_rules}" != "$(exclude_rules "${LDF_EXCLUDE_TEMPLATE}")" ]]; then
    verdict warn allowlist_differs -m -d "info/exclude rules differ from the template" -f "diff ${exclude} ${LDF_EXCLUDE_TEMPLATE}"
    return 0
  fi
  local origin
  origin="$(git --git-dir="${git_dir}" remote get-url origin 2>/dev/null || true)"
  if [[ -z "${origin}" ]]; then
    verdict warn no_remote -m -f "git ldf remote add origin <this machine's private repo>" \
      -d $'the local-dotfiles remote is one private repo per machine:\n  git ldf remote add origin <this machine\'s private repo>\n  git ldf push --set-upstream origin main   # after the first commit'
    return 0
  fi
  # No fetch: origin/main is whatever the last push left behind; before the first push every commit is unpushed.
  local -i unpushed=0
  if git --git-dir="${git_dir}" rev-parse --verify -q origin/main >/dev/null 2>&1; then
    unpushed=$(git --git-dir="${git_dir}" rev-list --count origin/main..HEAD 2>/dev/null || print 0)
  elif git --git-dir="${git_dir}" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    unpushed=$(git --git-dir="${git_dir}" rev-list --count HEAD 2>/dev/null || print 0)
  fi
  if (( unpushed > 0 )); then
    verdict warn unpushed -d "$(nm::plural "${unpushed}" 'unpushed commit' 'unpushed commits')" -f "git ldf push"
    return 0
  fi
  verdict ok configured -d "git_dir='${git_dir}' origin='${origin}'"
}

# info/exclude is the allowlist that makes `git ldf add -A` safe. Installed from the versioned
# template over git's stock (comment-only) file; a machine whose rules differ keeps its copy.
apply::local_dotfiles_repo() {
  local git_dir="${NEW_MACHINE_LDF_GIT_DIR}" exclude="${NEW_MACHINE_LDF_GIT_DIR}/info/exclude"
  if [[ ! -d "${git_dir}" ]]; then
    run_cmd_mutating git init --bare "${git_dir}" || return 1
  fi
  if [[ ! -r "${LDF_EXCLUDE_TEMPLATE}" ]]; then
    log::err "allowlist template missing | path='${LDF_EXCLUDE_TEMPLATE}'"
    return 1
  fi
  local rc=0
  if [[ ! -f "${exclude}" || -z "$(exclude_rules "${exclude}")" ]]; then
    run_cmd_mutating mkdir -p "${exclude:h}" || rc=1
    run_cmd_mutating cp "${LDF_EXCLUDE_TEMPLATE}" "${exclude}" || rc=1
  fi
  steps::ensure_hooks_path "${git_dir}" "${NEW_MACHINE_LDF_HOOKS}" || rc=1
  return "${rc}"
}

# ── bob_neovim ───────────────────────────────────────────────────────────────
check::bob_neovim() {
  if ! command -v bob >/dev/null 2>&1; then
    verdict fail bob_missing -m -d "bob not on PATH (the Brewfile lists it)" -f "new-machine apply brew_pkgs"
    return 0
  fi
  # Read all of `bob ls` rather than `| grep -q`: bob panics on a closed pipe.
  local listing
  listing="$(bob ls 2>/dev/null || true)"
  if [[ "${listing}" == *Used* ]]; then
    verdict ok installed -d "neovim installed via bob"
    return 0
  fi
  verdict fail nvim_missing -d "bob ls shows no version in use" -f "new-machine apply bob_neovim"
}

apply::bob_neovim() {
  run_cmd_mutating bob install latest && run_cmd_mutating bob use latest
}

# ── claude ───────────────────────────────────────────────────────────────────
check::claude() {
  local claude_path
  if ! claude_path="$(command -v claude 2>/dev/null)"; then
    verdict fail claude_missing -d "claude not on PATH" -f "new-machine apply claude"
    return 0
  fi
  local version
  version="$(claude --version 2>/dev/null || true)"
  verdict ok present -d "version='${version}' path='${claude_path}'"
}

apply::claude() {
  run_cmd_mutating zsh -c 'curl -fsSL "$1" | sh' _ "${CLAUDE_INSTALLER}"
}

# ── terminal_nerdfont ────────────────────────────────────────────────────────
check::terminal_nerdfont() {
  if [[ -z "${NEW_MACHINE_BREW}" ]]; then
    verdict error brew_missing -d "brew not found on PATH or under ${NEW_MACHINE_BREW_PREFIXES:-<no prefixes>}"
    return 0
  fi
  local casks
  casks="$("${NEW_MACHINE_BREW}" list --cask 2>/dev/null || true)"
  local -a fonts=(${(M)${(f)casks}:#*nerd-font*})
  if (( ${#fonts} == 0 )); then
    verdict fail font_missing -m -d "no *nerd-font* cask installed (the Brewfile lists font-caskaydia-mono-nerd-font)" \
      -f "new-machine apply brew_pkgs"
    return 0
  fi
  local howto="Set a Nerd Font in Terminal.app: Settings -> Profiles -> Text -> Font"$'\n'"Installed: ${(j:, :)fonts}"
  if [[ ! -r "${NEW_MACHINE_TERMINAL_PLIST}" ]]; then
    verdict warn manual_font -m -d "no Terminal.app preferences yet | plist='${NEW_MACHINE_TERMINAL_PLIST}'"$'\n'"${howto}"
    return 0
  fi
  local -a names=(${(f)"$(step::_terminal_nerd_font_names "${NEW_MACHINE_TERMINAL_PLIST}")"})
  if (( ${#names} == 0 )); then
    verdict fail font_not_set -m -d "no Terminal.app profile uses a Nerd Font | plist='${NEW_MACHINE_TERMINAL_PLIST}'"$'\n'"${howto}"
    return 0
  fi
  verdict ok font_set -d "fonts='${(j:, :)names}' plist='${NEW_MACHINE_TERMINAL_PLIST}'"
}

# Terminal.app stores each profile's font as a base64 NSKeyedArchiver blob, so the PostScript
# name is not greppable in the plist itself. Decode every <data> blob and pull Nerd Font names
# (CaskaydiaMonoNFM-Regular, JetBrainsMonoNF-Bold, HackNerdFont-Regular) out of the bytes.
# Prints unique names, one per line; nothing when no profile uses one.
step::_terminal_nerd_font_names() {
  local plist="${1}" xml joined blob
  xml="$(plutil -convert xml1 -o - "${plist}" 2>/dev/null || true)"
  joined="$(print -r -- "${xml}" | tr -d '\n\t ')"
  local -a blobs=(${(s:<data>:)joined})
  local -a names=()
  for blob in "${blobs[@]:1}"; do
    blob="${blob%%</data>*}"
    names+=(${(f)"$(print -r -- "${blob}" | base64 -d 2>/dev/null | grep -aoE '[A-Za-z0-9]+(NerdFont|NF[MP]?)-[A-Za-z]+' || true)"})
  done
  print -rl -- "${(u)names[@]}"
}

# ── karabiner ────────────────────────────────────────────────────────────────
# The config invariant (exists, valid, `jq -S .` equals itself — the df pre-commit rule) is the
# verdict. The healthcheck's process/device/IPC findings are runtime state, not baseline, so an
# exit 1 is a warn and never a fail.
check::karabiner() {
  local cfg="${HOME}/.config/karabiner/karabiner.json"
  local problem=""
  if [[ ! -f "${cfg}" ]]; then
    problem="karabiner.json missing"
  elif ! jq -e . "${cfg}" >/dev/null 2>&1; then
    problem="karabiner.json is not valid JSON"
  elif ! jq -S . "${cfg}" | cmp -s - "${cfg}"; then
    problem="karabiner.json is not jq -S sorted"
  fi
  if [[ -n "${problem}" ]]; then
    if ! command -v npm >/dev/null 2>&1; then
      verdict skip no_npm -d "${problem}; the bake needs npm | file='${cfg}'"
      return 0
    fi
    verdict fail karabiner_config -d "${problem} | file='${cfg}'" -f "new-machine apply karabiner"
    return 0
  fi
  local healthcheck="${HOME}/.config/karabiner/bin/healthcheck"
  local healthcheck_lib="${HOME}/.claude/skills/ari-skill-shellscripts/lib/logging.zsh"
  if [[ ! -x "${healthcheck}" ]]; then
    verdict ok config_valid -d "file='${cfg}' healthcheck='absent'"
    return 0
  fi
  if [[ ! -r "${healthcheck_lib}" ]]; then
    # Without its logging lib the healthcheck exits 1 before checking anything; not a config problem.
    verdict ok config_valid -d "file='${cfg}' healthcheck='unusable (logging lib missing)'"
    return 0
  fi
  local out rc=0
  out="$("${healthcheck}")" || rc=$?
  local -a summary=(${(M)${(f)out}:#(status|issues)=*})
  case "${rc}" in
    0) verdict ok config_valid -d "file='${cfg}' healthcheck='ok'" ;;
    1) verdict warn karabiner_healthcheck -d "${(F)summary:-${out}}" -f "${healthcheck}" ;;
    *) verdict warn karabiner_healthcheck -d "healthcheck exited ${rc}"$'\n'"$(print -r -- "${out}" | tail -n 5)" -f "${healthcheck}" ;;
  esac
}

apply::karabiner() {
  run_cmd_mutating "${HOME}/.config/karabiner/bin/bake"
}

# ── claude_notifications ─────────────────────────────────────────────────────
check::claude_notifications() {
  local init="${HOME}/.config/claude/bin/initialize.sh" expected="${HOME}/.config/claude/bin/notification-fire.sh"
  local settings="${HOME}/.claude/settings.json"
  if [[ ! -x "${init}" ]]; then
    verdict skip no_initialize -d "init script missing | path='${init}'"
    return 0
  fi
  local current=""
  if [[ -f "${settings}" ]]; then
    current="$(jq -r '.hooks.Notification[0].hooks[0].command // ""' "${settings}" 2>/dev/null || true)"
  fi
  if [[ "${current}" != "${expected}" ]]; then
    verdict fail hook_mismatch -d "hook='${current}' expected='${expected}' settings='${settings}'" -f "new-machine apply claude_notifications"
    return 0
  fi
  # The headless-Chrome guard is a second hook initialize.sh wires (PreToolUse, matcher Bash).
  local guard="${HOME}/.config/claude/bin/pretooluse-headless-chrome-guard.sh" guard_hooks
  guard_hooks="$(jq -r --arg cmd "${guard}" '[.hooks.PreToolUse // [] | .[].hooks[]? | select(.command == $cmd)] | length' "${settings}" 2>/dev/null || echo 0)"
  if [[ "${guard_hooks}" != 1 ]]; then
    verdict fail guard_mismatch -d "PreToolUse guard hooks=${guard_hooks} expected=1 | guard='${guard}' settings='${settings}'" -f "new-machine apply claude_notifications"
    return 0
  fi
  if [[ -z "${NEW_MACHINE_NOTIFIER}" ]] || ! command -v "${NEW_MACHINE_NOTIFIER}" >/dev/null 2>&1; then
    verdict fail notifier_missing -d "terminal-notifier not found (initialize.sh installs it)" -f "new-machine apply claude_notifications"
    return 0
  fi
  verdict ok configured -d "hook='${current}' guard='${guard}' notifier='${NEW_MACHINE_NOTIFIER}'"
}

apply::claude_notifications() {
  run_cmd_mutating "${HOME}/.config/claude/bin/initialize.sh"
}

# ── claude_skills ────────────────────────────────────────────────────────────
# Skills are versioned in the dotfiles tiers and reached through ~/.claude/skills symlinks;
# the registry skill owns the classification. Addressed by its shared-tier path, not the
# symlink, because on a fresh machine the symlink is exactly what does not exist yet.
steps::skill_registry_bin() {
  print -r -- "${HOME}/.config/claude/skills/ari-dotfiles-skill-registry/bin"
}

check::claude_skills() {
  local bin
  bin="$(steps::skill_registry_bin)"
  if [[ ! -r "${bin}/status" ]]; then
    verdict skip no_registry -d "skill registry not checked out | path='${bin}/status'"
    return 0
  fi
  local rows
  rows="$(zsh "${bin}/status" --all 2>/dev/null || true)"
  local -a missing dangling manual
  local line state name linked=0
  for line in "${(f)rows}"; do
    [[ "${line}" == state=* ]] || continue
    state="${${line#state=}%% *}"
    name="${line##*name=}"
    case "${state}" in
      linked) linked=$(( linked + 1 )) ;;
      missing) missing+=("${name}") ;;
      dangling) dangling+=("${name}") ;;
      shadowed|foreign|conflict) manual+=("${name}:${state}") ;;
    esac
  done
  if (( ${#missing} + ${#dangling} > 0 )); then
    verdict fail links_missing -d "missing='${(j:,:)missing}' dangling='${(j:,:)dangling}'" -f "new-machine apply claude_skills"
    return 0
  fi
  if (( ${#manual} > 0 )); then
    verdict warn needs_hand -d "${(j:,:)manual}" -f 'zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status' -m
    return 0
  fi
  verdict ok linked -d "$(nm::plural "${linked}" 'skill linked' 'skills linked')"
}

apply::claude_skills() {
  run_cmd_mutating zsh "$(steps::skill_registry_bin)/link" --prune
}

# ── chrome_exoskeleton ───────────────────────────────────────────────────────
# The framework is a shared-tier submodule (dotfiles_repo initializes it). Its hooks are
# wired by npm's prepare script, so a fresh checkout has none until `exo deps ci` runs;
# `exo build` produces the dist/ Chrome loads. Node comes from the local tier's env.zsh on
# a work machine; a personal machine needs it on PATH, hence a warn, not a fail.
steps::exo_framework_dir() {
  print -r -- "${HOME}/.config/chrome-exoskeleton"
}

steps::exo_have_node() {
  local env_zsh="${XDG_DATA_HOME:-${HOME}/.local/share}/chrome-exoskeleton/env.zsh"
  [[ -r "${env_zsh}" ]] && source "${env_zsh}"
  command -v node >/dev/null 2>&1
}

check::chrome_exoskeleton() {
  local fw
  fw="$(steps::exo_framework_dir)"
  if [[ ! -x "${fw}/bin/exo" ]]; then
    verdict skip no_submodule -d "framework not checked out | path='${fw}'" -f "new-machine apply dotfiles_repo"
    return 0
  fi
  if ! steps::exo_have_node; then
    verdict warn node_missing -d "node is not on PATH and no env.zsh provides it" -f "brew install node   (or set it up in ~/.local/share/chrome-exoskeleton/env.zsh)" -m
    return 0
  fi
  local hooks
  hooks="$(git -C "${fw}" config core.hooksPath 2>/dev/null || true)"
  if [[ ! -d "${fw}/node_modules" || "${hooks}" != ".githooks" ]]; then
    verdict fail deps_missing -d "node_modules='$([[ -d "${fw}/node_modules" ]] && echo present || echo missing)' hooksPath='${hooks:-unset}'" -f "new-machine apply chrome_exoskeleton"
    return 0
  fi
  if [[ ! -f "${fw}/dist/manifest.json" ]]; then
    verdict fail not_built -d "no dist/manifest.json | path='${fw}/dist'" -f "new-machine apply chrome_exoskeleton"
    return 0
  fi
  verdict ok built -d "dist version=$(jq -r .version "${fw}/dist/manifest.json" 2>/dev/null || echo '?') hooks='${hooks}'"
}

apply::chrome_exoskeleton() {
  local fw
  fw="$(steps::exo_framework_dir)"
  if [[ ! -x "${fw}/bin/exo" ]]; then
    log::err "framework not checked out | path='${fw}' fix='new-machine apply dotfiles_repo'"
    return 1
  fi
  if ! steps::exo_have_node; then
    log::warn "node is not on PATH; skipping | fix='brew install node, or ~/.local/share/chrome-exoskeleton/env.zsh'"
    return 0
  fi
  if [[ ! -d "${fw}/node_modules" || "$(git -C "${fw}" config core.hooksPath 2>/dev/null)" != ".githooks" ]]; then
    run_cmd_mutating zsh "${fw}/bin/exo" deps ci || return 1
  fi
  run_cmd_mutating zsh "${fw}/bin/exo" build
}

# ── dotfiles_jobs ────────────────────────────────────────────────────────────
# The one launchd job of the dotfiles jobs framework (screen unlock, login, every 5 minutes);
# it runs the job plugins of both tiers, git-health's hourly tick among them.
check::dotfiles_jobs() {
  local label="com.$(id -un).dotfiles-jobs" plist="${NEW_MACHINE_LAUNCH_AGENTS_DIR}/com.$(id -un).dotfiles-jobs.plist"
  if [[ ! -f "${plist}" ]]; then
    verdict fail not_installed -d "plist missing | path='${plist}'" -f "new-machine apply dotfiles_jobs"
    return 0
  fi
  if ! plutil -lint -s "${plist}" >/dev/null 2>&1; then
    verdict fail not_installed -d "plist does not lint | path='${plist}'" -f "new-machine apply dotfiles_jobs"
    return 0
  fi
  if ! launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1; then
    verdict fail not_loaded -d "job not loaded | label='${label}'" -f "new-machine apply dotfiles_jobs"
    return 0
  fi
  verdict ok loaded -d "label='${label}'"
}

apply::dotfiles_jobs() {
  local harness="${HOME}/.config/bin/dotfiles"
  if [[ ! -f "${harness}" ]]; then
    log::err "dotfiles harness missing | expected='${harness}' fix='new-machine apply dotfiles_repo'"
    return 1
  fi
  run_cmd_mutating zsh "${harness}" jobs install
}
