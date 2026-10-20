# dotfiles/cmd/steps.zsh — `dotfiles steps`: the registry, in run order; `steps edit` opens one.

help_steps() {
  cat <<EOF
every step in run order, with its group, needs, tools, apply and docs

${c_bold}Usage${c_rst}
  ${DF} steps [list]
  ${DF} steps edit NAME [--new] [--no-commit]

  A step is one file under $(help::tilde "${ARI_DOTFILES_STEPS}") that declares itself,
    # step NAME — <summary>
    step::declare NAME --group G [--needs a,b] [--tools t] --desc D \\
      [--apply "<what the apply changes>"]
    step::watches NAME <glob>..   (or: step::watches NAME --none "<why>")
  and defines check::NAME and, when it can fix what it finds, apply::NAME.
  Adding the file adds the step. Run order: the groups in order
  (${(j:, :)STEP_GROUPS}); inside a group, a step runs after the steps its
  --needs names (each must have ended ok or warn, or the step is skipped);
  ties by name. 'tools' names binaries the runner probes before the check.
  The watches name the repo paths a pull maps to the step.

  The docs column is ok, or what the step lacks: its line 1 (header), a
  --desc, an --apply exactly when it has an apply, its watches. A step that
  lacks one fails the dotfiles_docs step.

${c_bold}Subcommands${c_rst}
  list        the registry (the default)
  edit NAME   the step file in \$EDITOR as a draft: checked on save (zsh -n,
              the registry loads with it, its watches, the docs rule), then
              put in place and committed in the shared tier; --new starts one
              from a template (also: steps --edit NAME)

${c_bold}Flags${c_rst}
  --new         edit: create steps/NAME.zsh from a template
  --no-commit   edit: put it in place, leave it uncommitted

${c_bold}Env${c_rst}
  $(ENV ARI_DOTFILES_STEPS)
      the steps directory (default $(help::tilde "${ARI_DOTFILES_STEPS}"))
EOF
}

cmd_steps() {
  local sub="${1:-list}"
  (( $# > 0 )) && shift
  case "${sub}" in
    edit|--edit)
      need_lib "${ARI_DOTFILES_CMD}/steps/edit.zsh" || return 3
      steps_edit "$@" ;;
    list)
      (( $# == 0 )) || usage_error "steps list takes no arguments | args='$*'"
      steps::load || exit 3
      steps::list ;;
    *) usage_error "Unknown steps subcommand | sub='${sub}' valid='list, edit NAME'" ;;
  esac
}
