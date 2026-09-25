# step brew_drift — nothing installed on request is undeclared, orphaned or declared twice.
# No apply: a human settles drift with `brew triage` / `brew decree`.
step::declare brew_drift --group brew --needs brew --tools brew \
  --desc "nothing installed on request is undeclared, orphaned, or declared twice (${CLI_NAME} brew triage)"

check::brew_drift() {
  need_lib "${DOTFILES_BREW_LIB}"
  brew::check_drift_verdict
}
