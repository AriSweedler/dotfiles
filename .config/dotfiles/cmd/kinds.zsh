# dotfiles/cmd/kinds.zsh — the kind catalog (lib/kind.zsh): every type of value a dotfiles
# command line holds, declared once, and `dotfiles kinds [KIND]`, which prints the catalog or one
# kind's values. The completion asks this verb for the values of a --lister kind.

# --- The catalog: one line per kind; a new kind of value is a new line here ---
kind::define VERB         'a dotfiles verb'                                          --lister kinds::list_verbs
kind::define KIND         'a kind of value, from this catalog'                       --lister kinds::list_kinds
kind::define STEP         'a step: a file in steps/'                                 --lister kinds::list_steps
kind::define GROUP        'a group of steps'                                         --words '${STEP_GROUPS}'
kind::define PLAN         'a kept --edit plan file, to resume'                       --files
kind::define JOB          'a job plugin'                                             --lister kinds::list_jobs
kind::define DEP          'a dep the job plugins name'                               --lister kinds::list_deps
kind::define TRIGGER      'what set a job run off'                                   --words 'unlock load tick manual screenIsUnlocked'
kind::define REPO         'a repo dotfiles push writes a log for'                    --lister kinds::list_repos
kind::define TIER         'a dotfiles tier'                                          --words 'shared local'
kind::define MACHINE_NAME "this machine's new name: one word of letters, digits, _ or -" --free
kind::define SUITE        'a test suite: a zsh plugin suite or a hermetic one'       --lister kinds::list_suites
kind::define SOURCE_FILE  'a file of this checkout, whose suites to run'             --files
kind::define REV          'a git revision'                                           --free
kind::define BINDING      "a Raycast binding's slug"                                 --lister kinds::list_bindings
kind::define DEEPLINK     'a raycast:// path'                                        --free
kind::define SNIPPET      "a Raycast snippet's name"                                 --lister kinds::list_snippets
kind::define RAYCAST_EXPORT 'a snippets file exported from Raycast'                  --files
kind::define GIT_WORDS    "git's own words, untouched"                               --delegate git

# --- The listers: each prints one value per line, quietly nothing when its source is absent ---
kinds::list_verbs() { verbs; }
kinds::list_kinds() { print -rl -- "${KINDS[@]}"; }
kinds::list_steps() { local -a names=("${ARI_DOTFILES_STEPS}"/*.zsh(N:t:r)); (( ! ${#names} )) || print -rl -- "${names[@]}"; }
kinds::list_jobs() { jobs_discover; (( ! ${#JOB_PATH} )) || print -rl -- "${(@ko)JOB_PATH}"; }
kinds::list_deps() { deps_discover; (( ! ${#DEP_PATH} )) || print -rl -- "${(@ko)DEP_PATH}"; }
kinds::list_repos() { print -rl -- shared local "${SUBMODULES[@]}" "${MIRRORS[@]}"; }
kinds::list_suites() {
  local -a names=("${ARI_DOTFILES_ZSH_PLUGINS}"/*.test.zsh(N:t) "${ARI_DOTFILES_TESTS}"/test_*.sh(N:t:r))
  names=("${(@)names%.test.zsh}"); names=("${(@)names#test_}")
  (( ! ${#names} )) || print -rl -- "${names[@]}"
}
kinds::list_bindings() {
  local line
  raycast::load 2>/dev/null || return 0
  for line in "${(@f)$(ari_raycast link list 2>/dev/null)}"; do [[ -z "${line}" ]] || print -r -- "${line%%  *}"; done
}
kinds::list_snippets() {
  local file
  (( ${+commands[jq]} )) || return 0
  for file in "${ARI_DOTFILES_RAYCAST_SNIPPETS_SHARED_FILE:-${HOME}/dotfiles/.config/raycast-snippets/snippets.json}" \
              "${ARI_DOTFILES_RAYCAST_SNIPPETS_LOCAL_FILE:-${XDG_DATA_HOME}/dotfiles/nix/raycast-snippets.json}"; do
    [[ -r "${file}" ]] || continue
    jq -r '.[].name' "${file}" 2>/dev/null
  done | sort -u
}

# --- The verb ---
verb::define kinds 'the kinds of value a dotfiles command line holds, or the values of one'
verb::usage kinds 'kinds' 'kinds KIND'
verb::about kinds <<'EOF'
A kind is the type of one value: what a flag takes ('--only STEP,..') or
what a position holds ('jobs run JOB'). Without KIND: the catalog, each
kind with where its values come from (words: a fixed set; lister: what
this machine has now; files; free: text nothing can list; delegate:
another command's words). With KIND: its values, one per line, which is
what tab completion offers; a files, free or delegate kind prints nothing.
The catalog is the top of cmd/kinds.zsh; 'dotfiles completion lint'
fails on a declaration that names a kind it lacks.
EOF
verb::arg kinds '[KIND]'
verb::edit kinds --none 'the catalog is the top of cmd/kinds.zsh: a kind is one kind::define line there'

cmd_kinds() {
  local -A opts; local -a args
  verb::parse kinds "$@"
  (( ${#args} <= 1 )) || usage_error "kinds takes at most one KIND | args='${args[*]}'"
  if (( ${#args} )); then
    kind::is_known "${args[1]}" || usage_error "no such kind | kind='${args[1]}' known='${KINDS[*]}'"
    kind::values "${args[1]}"
    return
  fi
  local kind REPLY
  local -i width=0
  for kind in "${KINDS[@]}"; do (( ${#kind} > width )) && width=${#kind}; done
  for kind in "${KINDS[@]}"; do
    kind::source "${kind}"
    printf '%-*s  %-8s  %s\n' "${width}" "${kind}" "${REPLY}" "${KIND_DESC[${kind}]}"
  done
}
