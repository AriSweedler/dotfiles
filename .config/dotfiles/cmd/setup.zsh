# dotfiles/cmd/setup.zsh — `dotfiles setup`: healthcheck with autofix. Bootstrap ends in it.

help_setup() {
  cat <<EOF
dotfiles setup [--only STEP,..] [--group GROUP] [--dry-run] [--json]   check every step, apply where actionable, re-check

  The healthcheck, then for every step that failed and has an apply::, the apply and a second
  check; a step still failing afterwards is reported as apply_did_not_converge. When the brew
  step fails, the later groups are skipped: their tools come from it.
  Under --dry-run every apply runs with each mutation logged instead of executed, so the plan it
  prints is the real one.

  --only STEP,..   exactly these steps          --group GROUP   one group: ${(j:, :)STEP_GROUPS}
  --dry-run        print the plan, change nothing (also accepted before the verb)
  --json           print summary.json instead of the table

  What the bootstrap one-liner ends in; 'dotfiles apply STEP' is 'setup --only STEP'.
EOF
}

cmd_setup() {
  local -a only=() group=() json=() dry=()
  zparseopts -D -F -K -- -only:=only -group:=group -json=json -dry-run=dry || usage_error "setup: bad flags | args='$*'"
  (( $# == 0 )) || usage_error "setup takes no positional arguments | args='$*'"
  (( ${#dry} )) && export DOTFILES_DRY_RUN=1
  run::main setup "${only[2]:-}" "${group[2]:-}" "${#json}"
}
