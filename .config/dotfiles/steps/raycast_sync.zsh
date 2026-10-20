# step raycast_sync — Raycast in parity with the dotfiles. `dotfiles raycast sync` walks every
# Raycast subsystem (link allow: the deeplink allow-list; snippets sync: the versioned snippets),
# each idempotent. The check is its --dry-run: pending work fails the step, a subsystem that
# errors fails it with its tail, a binding or snippet without a description fails it as manual
# (`undocumented`, one line per finding with the edit that fixes it), and a `warn` line (a
# snippets placeholder this machine has not filled in) makes it a warn. Compile state of the
# bindings is the karabiner step's verdict.
step::declare raycast_sync --group tools --needs dotfiles_repo \
  --desc "Raycast in parity with the dotfiles: every Karabiner-bound command on its deeplink allow-list, the versioned snippets imported (dotfiles raycast sync), every binding and snippet described"
step::watches raycast_sync '.config/raycast-snippets/**' '.config/karabiner/**' '.config/zsh/plugins/raycast*.zsh'

# Machine inputs: what `raycast sync --dry-run` reads. reply: the raycast plugins, karabiner.ts's
# sources, package files, tsx and node (the bindings generator), karabiner.json, Raycast's
# preferences plist (the allow-list `defaults` reads), the app, and both snippets trees with the
# manifest. 1 when a seam replaces what is read (a bindings command, a `defaults` that is not
# /usr/bin/defaults): its state is not on disk where the cache can see it, so uncached.
step::raycast_sync::inputs() {
  [[ -z "${ARI_DOTFILES_RAYCAST_LINK_BINDINGS_CMD:-}" && "${commands[defaults]:-}" == /usr/bin/defaults ]] || return 1
  local cfg="${XDG_CONFIG_HOME:-${HOME}/.config}" d
  local ts="${ARI_DOTFILES_RAYCAST_LINK_KARABINER_TS:-${cfg}/karabiner/karabiner.ts}"
  local -a dirs=(${(s.:.)${ARI_DOTFILES_RAYCAST_SNIPPETS_DIRS:-${cfg}/raycast-snippets:${HOME}/.local/share/raycast-snippets}})
  reply=("${ARI_DOTFILES_CONFIG}/zsh/plugins" "${ARI_DOTFILES_CONFIG}/zsh/plugins/"raycast*.zsh(N)
         "${ts}" "${ts}/package.json" "${ts}/package-lock.json" "${ts}/node_modules" "${ts}/node_modules/.package-lock.json"
         "${ts}/node_modules/.bin/tsx" "${commands[node]:-/nonexistent/node}"
         "${ARI_DOTFILES_RAYCAST_LINK_KARABINER_JSON:-${cfg}/karabiner/karabiner.json}"
         "${HOME}/Library/Preferences/${ARI_DOTFILES_RAYCAST_LINK_DEFAULTS_DOMAIN:-com.raycast.macos}.plist"
         "${ARI_DOTFILES_RAYCAST_APP:-/Applications/Raycast.app}"
         "${ARI_DOTFILES_RAYCAST_SNIPPETS_MANIFEST:-${dirs[-1]}/manifest.json}")
  cache::tree "${ts}/src" "${dirs[@]}"
  CACHE_ENV=(XDG_CONFIG_HOME ARI_DOTFILES_CONFIG ${(ok)parameters[(I)ARI_DOTFILES_RAYCAST_*]})
}

step::raycast_sync::load() {
  need_lib "${ARI_DOTFILES_CONFIG}/zsh/plugins/raycast.zsh"
}

check::raycast_sync() {
  if [[ ! -d "${ARI_DOTFILES_RAYCAST_APP:-/Applications/Raycast.app}" ]]; then
    verdict skip no_raycast -d "Raycast is not installed"
    return 0
  fi
  local -a reply
  if step::raycast_sync::inputs; then
    cache::check step::raycast_sync::live "${reply[@]}"
  else
    step::raycast_sync::live
  fi
}

step::raycast_sync::live() {
  step::raycast_sync::load
  local out docs rc=0 drc=0
  # One generator run: both subshells below inherit the loaded bindings. A failure here is
  # reported by `link allow` inside sync.
  raycast_link::load_bindings >/dev/null 2>&1
  out="$(ari_raycast sync --dry-run 2>/dev/null)" || rc=$?
  docs="$(ari_raycast undocumented 2>/dev/null)" || drc=$?
  local -a lines=("${(@f)out}")
  local -a failed=(${(M)lines:#FAIL *})
  # A loop, not ${${(M)lines:#…}[1]}: a nested match of one element is a scalar, and [1] its first
  # character, so pending work used to read as none.
  local total=0 line
  for line in "${lines[@]}"; do [[ "${line}" == total_pending=* ]] && total="${line#total_pending=}"; done
  if (( rc )) || (( ${#failed} )); then
    verdict fail raycast_sync_failed -d "a Raycast subsystem could not report | rc='${rc}'"$'\n'"${(F)lines}" -f "run the failing subsystem by hand: ${CLI_NAME} raycast <subsystem> help"
    return 0
  fi
  if (( ${total:-0} > 0 )); then
    verdict fail raycast_pending -d "Raycast is behind the dotfiles | pending='${total}'"$'\n'"${(F)${(M)lines:#ok *}}" -f "${CLI_NAME} apply raycast_sync"
    return 0
  fi
  if (( drc )); then
    verdict fail raycast_sync_failed -d "the undocumented scan could not run | rc='${drc}'" -f "${CLI_NAME} raycast undocumented"
    return 0
  fi
  local -a undoc=(${(M)${(f)docs}:#(binding|snippet) *})
  if (( ${#undoc} )); then
    local first_fix="${${undoc[1]##* fix=\'}%\'}"
    verdict fail undocumented -m -d "a Raycast binding or snippet has no description | undocumented='${#undoc}'"$'\n'"${(F)undoc}" \
      -f "${first_fix/#dotfiles /${CLI_NAME} }"
    return 0
  fi
  local -a warned=(${(M)lines:#warn *})
  if (( ${#warned} )); then
    verdict warn raycast_parity -m -d "${(F)warned}" -f "fill in the local snippets file, then: ${CLI_NAME} raycast snippets fmt"
    return 0
  fi
  verdict ok in_sync -d "$(print -r -- "${(F)${(M)lines:#ok *}}" | tr '\n' ';')"
}

apply::raycast_sync() {
  step::raycast_sync::load
  run_mut ari_raycast sync
}
