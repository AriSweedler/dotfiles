# dotfiles/cmd/steps.zsh — `dotfiles steps`: the registry, in run order; `steps edit` opens one.

verb::define steps 'every step in run order, with its group, needs, tools, apply and docs'
verb::usage steps 'steps [list]'
verb::about steps <<'EOF'
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

'steps edit NAME' opens steps/NAME.zsh in \$EDITOR, vi when unset, as a
draft. On save the draft is checked: zsh -n; then, in a fresh zsh -f with
the kernel and every other step file, the registry loads with the draft in
place of the file (steps::load, watch::validate), the draft declares NAME,
prints nothing when sourced, and meets the documentation rule above. A draft
that passes replaces the file and is committed in the shared tier; one that
does not is reported and kept for the next 'steps edit NAME' (on a
terminal, offered for another edit).
EOF
verb::sub steps list 'the registry (the default)'
verb::edit steps steps::edit 'NAME [--new] [--no-commit]' \
  'the step file in \$EDITOR as a draft: checked on save (zsh -n, the registry loads with it, its watches, the docs rule), then put in place and committed in the shared tier'
verb::flag steps '--new' 'edit: create steps/NAME.zsh from a template (a check and an apply; a check-only step deletes the apply and its --apply)'
verb::flag steps '--no-commit' 'edit: put it in place, leave it uncommitted'
verb::env steps ARI_DOTFILES_STEPS 'the steps directory' '$(help::tilde "${ARI_DOTFILES_STEPS}")'
verb::section steps 'Exit codes (edit)' <<'EOF'
0   saved, or no change
1   the draft did not pass, the editor failed or the commit was refused
64  usage
EOF

steps::edit() { need_lib "${ARI_DOTFILES_CMD}/steps/edit.zsh" || return 3; steps_edit "$@"; }

cmd_steps() {
  local -A opts; local -a args
  verb::parse steps "$@"
  (( ${+opts[--edit]} )) && { steps::edit "${@:#--edit}"; return; }
  local sub="${args[1]:-list}"
  case "${sub}" in
    # `steps --new edit NAME`: the edit with its flags, wherever they were on the line.
    edit) steps::edit "${(@)args[2,-1]}" ${opts[--new]+--new} ${opts[--no-commit]+--no-commit} ;;
    list)
      (( ${#args} <= 1 && ${#opts} == 0 )) || usage_error "steps list takes no arguments | args='$*'"
      steps::load || exit 3
      steps::list ;;
    *) usage_error "Unknown steps subcommand | sub='${sub}' valid='list, edit NAME'" ;;
  esac
}
