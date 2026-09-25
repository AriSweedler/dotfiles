# raycast — the router behind `dotfiles raycast`, and the interactive function `ari_raycast`:
#   dotfiles raycast link <slug|path> [--plain]   the widget: <[Raycast: Title | key: '✦4'](raycast://…)>
#   dotfiles raycast link list | check | allow [--dry-run]
#   dotfiles raycast snippets sync [--dry-run] | list | check | adopt | pull FILE | diff FILE
#                             | move NAME --to shared|local | fmt | reset-manifest [NAME...]
#   dotfiles raycast sync [--dry-run]             every subsystem's sync, in order
#   dotfiles raycast help | <subsystem> help
# Each subsystem is its own plugin (raycast_link.zsh, raycast_snippets.zsh) with a function that is
# callable on its own; this file only routes, and holds the one array `sync` walks, so adding a
# subsystem is a line here plus its plugin. The raycast_sync step runs `sync --dry-run`; bake
# calls `link allow`, because a bindings change only touches the allow-list.
# Env: ARI_RAYCAST_APP (Raycast's app bundle; absent = `sync` skips, exit 0).

(( ${+functions[log::info]} )) || source "${${(%):-%x}:A:h}/log.zsh"
(( ${+functions[raycast_link]} )) || source "${${(%):-%x}:A:h}/raycast_link.zsh"
(( ${+functions[raycast_snippets]} )) || source "${${(%):-%x}:A:h}/raycast_snippets.zsh"

# Guarded so re-sourcing (plugin loader plus the dispatcher) never trips "read-only variable".
(( ${+ARI_RAYCAST_SUBSYSTEMS} )) || typeset -gra ARI_RAYCAST_SUBSYSTEMS=(link snippets)
# What `ari-raycast sync` runs, in order. Each step accepts --dry-run and prints its work as
# key=value counters (would_add=, pending=, added=, imported=, changed=), which sync reports and
# sums, plus `warn <text>` lines, which sync forwards (the raycast_sync step shows them as a warn).
typeset -ga ARI_RAYCAST_SYNC_STEPS=("link allow" "snippets sync")
: "${ARI_RAYCAST_APP:=/Applications/Raycast.app}"

function ari_raycast::help() {
  cat >&2 <<EOF
dotfiles raycast — keep Raycast in parity with the dotfiles

Usage:
  dotfiles raycast link <slug|path> [--plain]     a Raycast action as a link with its Karabiner key
  dotfiles raycast link list | check | allow [--dry-run]
  dotfiles raycast snippets sync [--dry-run] | list | check | adopt | pull FILE | diff FILE
                          | move NAME --to shared|local | fmt | reset-manifest [NAME...]
  dotfiles raycast sync [--dry-run]               every subsystem's sync, in order: ${(j:, :)ARI_RAYCAST_SYNC_STEPS}
  dotfiles raycast <subsystem> help               that subsystem's usage

Subsystems: ${(j:, :)ARI_RAYCAST_SUBSYSTEMS}. Bindings live in karabiner.ts's tables and compile
through bake. Snippets live in two files, merged with local winning by name:
  shared  ~/.config/raycast-snippets/snippets.json (git df, public remote)
  local   ~/.local/share/raycast-snippets/snippets.json (git ldf, private remote), manifest beside it
One rule: personal data stays in the local tier; shared is for snippets safe in a public repo,
plus fmt's placeholders. Interactive shells have the same router as the function ari_raycast.
EOF
}

# `link` verbs map onto raycast_link's flags; anything else is a slug or path for the widget.
# Flags pass through untouched; a read-only mode under --dry-run is the read-only run.
function ari_raycast::link() {
  local verb="${1:-help}"
  (( $# > 0 )) && shift
  case "${verb}" in
    help|-h|--help) raycast_link --help ;;
    list)           raycast_link --list "$@" ;;
    check)          raycast_link --check "$@" ;;
    allow)          raycast_link --allow "$@" ;;
    -*)             log::err "Unknown link verb | verb='${verb}' valid='<slug|path> [--plain], list, check, allow [--dry-run], help'"; return 1 ;;
    *)              raycast_link "${verb}" "$@" ;;
  esac
}

function ari_raycast::snippets() {
  local verb="${1:-help}"
  (( $# > 0 )) && shift
  case "${verb}" in
    help|-h|--help) raycast_snippets --help ;;
    sync)           raycast_snippets --sync "$@" ;;
    adopt)          raycast_snippets --adopt "$@" ;;
    list)           raycast_snippets --list "$@" ;;
    check)          raycast_snippets --check "$@" ;;
    fmt)            raycast_snippets --fmt "$@" ;;
    pull)           raycast_snippets --pull "$@" ;;
    diff)           raycast_snippets --diff "$@" ;;
    move)           raycast_snippets --move "$@" ;;
    reset-manifest) raycast_snippets --reset-manifest "$@" ;;
    *)              log::err "Unknown snippets verb | verb='${verb}' valid='sync [--dry-run], list, check, adopt [--dry-run], pull FILE, diff FILE, move NAME --to shared|local, fmt [--dry-run], reset-manifest [NAME...], help'"; return 1 ;;
  esac
}

# Input: a step's output. Output: the sum of its pending/changed counters.
function ari_raycast::pending_of() {
  print -r -- "${1}" | awk -F= '/^(would_add|pending|added|imported|changed)=/ { s += $2 } END { print s + 0 }'
}

# One line per step (ok|FAIL <step> | pending='N'), a step's `warn` lines as `warn <step> |
# <text>`, then total_pending=N. Exit 1 if any step failed; exit 0 with one `skip` line when
# Raycast is not installed.
function ari_raycast::sync() {
  local step out sub_rc rc=0 pending line
  local -i total_pending=0
  local -a words extra
  while (( $# > 0 )); do case "${1}" in
    -h|--help) ari_raycast::help; return 0 ;;
    --dry-run) extra=(--dry-run); shift ;;
    *)         log::err "Unknown sync argument | argument='${1}' valid='--dry-run'"; return 1 ;;
  esac; done
  if [[ ! -d "${ARI_RAYCAST_APP}" ]]; then
    print -r -- "skip raycast not installed | app='${ARI_RAYCAST_APP}'"
    return 0
  fi
  for step in "${ARI_RAYCAST_SYNC_STEPS[@]}"; do
    words=(${=step})
    sub_rc=0
    out="$(ari_raycast "${words[@]}" "${extra[@]}" 2>&1)" || sub_rc=$?
    if (( sub_rc )); then
      print -r -- "FAIL ${step} | rc='${sub_rc}'"
      print -r -- "${out}" | tail -n 5 | sed 's/^/    /'
      rc=1
      continue
    fi
    pending="$(ari_raycast::pending_of "${out}")"
    total_pending+=pending
    print -r -- "ok ${step} | pending='${pending}'"
    for line in "${(@f)out}"; do
      [[ "${line}" == warn\ * ]] && print -r -- "warn ${step} | ${line#warn }"
    done
  done
  print -r -- "total_pending=${total_pending}"
  return "${rc}"
}

function ari_raycast() {
  local subsystem="${1:-help}"
  (( $# > 0 )) && shift
  case "${subsystem}" in
    help|-h|--help) ari_raycast::help; return 0 ;;
    sync)           ari_raycast::sync "$@" ;;
    link)           ari_raycast::link "$@" ;;
    snippets)       ari_raycast::snippets "$@" ;;
    *)              log::err "Unknown subsystem | subsystem='${subsystem}' valid='${(j:, :)ARI_RAYCAST_SUBSYSTEMS}, sync, help'"; ari_raycast::help; return 1 ;;
  esac
}
