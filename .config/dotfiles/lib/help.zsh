# dotfiles/lib/help.zsh — the --help text.

# --- Help ---

help() {
  cat <<EOF
${c_green}dotfiles${c_rst} — harness for the two-tier dotfiles: init, pull, push, status, logs

${c_bold}Usage:${c_rst}
  dotfiles init   [--dry-run]                 a pre-harness ~/dotfiles renamed to ~/dotfiles.git, shared repo
                                              cloned + checked out, hooks wired, submodules checked out,
                                              skills linked, ssh key loaded, the jobs launchd job installed
  dotfiles pull   [--dry-run]                 fast-forward the shared tier, then init
  dotfiles push   [--submodules|--shared|--local|--no-submodules|--no-shared|--no-local] [--dry-run]
                                              push every submodule with something to push, in
                                              parallel (one log each), commit the shared tier's
                                              pointer bumps, then push the shared tier, all as the
                                              personal account; the local tier alongside, to its own
                                              remote with the ssh agent's key (its pre-push hook
                                              included). Repos already at origin are skipped
                                              silently; a submodule failure blocks the shared push.
  dotfiles status                             both tiers, submodules, last push per repo
  dotfiles logs   [--repo NAME] [--previous]  push logs (NAME = 'shared', 'local' or a submodule path)
  dotfiles [--local] git <args…>              git in the shared tier (--git-dir ~/dotfiles.git, --work-tree ~,
                                              what 'git df' does); with --local, the local tier ('git ldf').
                                              Everything after 'git' goes to git untouched.
  dotfiles [--local] --dir                    print the tier's bare repo path and exit
  dotfiles jobs [list]                        the job plugins of both tiers, their triggers and last success
  dotfiles jobs run <name>                    run one plugin now (trigger 'manual'); output to its log and stdout
  dotfiles jobs install|uninstall             the one launchd job that runs them (init runs install)

${c_bold}Flags:${c_rst}
  --dry-run          Print what would run; change nothing
  --timing           Log every step's duration (steps over DOTFILES_SLOW_STEP are logged regardless)
  --submodules       push: the submodules (no selecting flag = all three parts)
  --shared           push: the shared tier
  --local            push: the local tier; git and --dir: act on the local tier instead of the shared
  --dir              print the tier's bare repo path (~/dotfiles.git, or ~/.local/local-dotfiles.git with --local)
  --no-submodules    push: leave the submodules out
  --no-shared        push: leave the shared tier out
  --no-local         push: leave the local tier out
  --repo NAME        logs: one repo instead of all
  --previous         logs: the run before the last one (.log.bak.1)
  -h, --help         This help

${c_bold}Environment:${c_rst}
  DOTFILES_GITHUB_LOGIN        GitHub account every push authenticates as, by its gh token
                               (default ${DOTFILES_GITHUB_LOGIN}); once per machine: env -u GITHUB_TOKEN gh auth login
  DOTFILES_REMOTE              shared repo to clone when missing (default ${DOTFILES_REMOTE})
  DOTFILES_SSH_KEY_OP_ITEM     1Password item holding the ssh key's "Absolute path" and "password"
  DOTFILES_SSH_KEY_OP_VAULT    its vault; both come from the local tier, unset = no key to load
  DOTFILES_SSH_KEY_PATH        the key file, so checking the agent needs no 1Password call (unset = ask the item)
  DOTFILES_SLOW_STEP           seconds; a slower step gets a 'slow step' line (default ${DOTFILES_SLOW_STEP}; pull's fetch allows 5)

${c_bold}Jobs:${c_rst} one launchd job, ${JOBS_LABEL}, fires on screen unlock, at login and every
${JOBS_INTERVAL_SECONDS}s, and runs the plugins whose triggers match. A plugin is an executable in
${JOBS_ROOT_DF} (shared) or ${JOBS_ROOT_LDF} (this machine)
whose header has '# triggers: unlock load every:<seconds>' and any '# cron: m h dom mon dow' lines;
it gets the trigger as \$1. Logs and
success stamps: ${JOBS_STATE_DIR}. The README beside the shared plugins has the contract.

${c_bold}Logs:${c_rst} ${LOG_DIR}/<repo>.log (last run) and .log.bak.1 (the run before).
Pushes are token-pinned to ${DOTFILES_GITHUB_LOGIN}: no gh account switch, no ssh key swap.
Human-only: Claude Code is denied 'dotfiles push'.
EOF
}
