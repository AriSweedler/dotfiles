# step raycast_sync — Raycast in parity with the dotfiles. `dotfiles raycast sync` walks every
# Raycast subsystem (link allow: the deeplink allow-list; snippets sync: the versioned snippets),
# each idempotent. The check is its --dry-run: pending work fails the step, a subsystem that
# errors fails it with its tail, and a `warn` line (a snippets placeholder this machine has not
# filled in) makes it a warn. Compile state of the bindings is the karabiner step's verdict.
step::declare raycast_sync --group tools --needs dotfiles_repo \
  --desc "Raycast in parity with the dotfiles: every Karabiner-bound command on its deeplink allow-list, the versioned snippets imported (dotfiles raycast sync)"

step::raycast_sync::load() {
  need_lib "${DOTFILES_CONFIG}/zsh/plugins/raycast.zsh"
}

check::raycast_sync() {
  if [[ ! -d "${ARI_RAYCAST_APP:-/Applications/Raycast.app}" ]]; then
    verdict skip no_raycast -d "Raycast is not installed"
    return 0
  fi
  step::raycast_sync::load
  local out rc=0
  out="$(ari_raycast sync --dry-run 2>/dev/null)" || rc=$?
  local -a lines=("${(@f)out}")
  local -a failed=(${(M)lines:#FAIL *})
  local total="${${(M)lines:#total_pending=*}[1]#total_pending=}"
  if (( rc )) || (( ${#failed} )); then
    verdict fail raycast_sync_failed -d "a Raycast subsystem could not report | rc='${rc}'"$'\n'"${(F)lines}" -f "run the failing subsystem by hand: ${CLI_NAME} raycast <subsystem> help"
    return 0
  fi
  if (( ${total:-0} > 0 )); then
    verdict fail raycast_pending -d "Raycast is behind the dotfiles | pending='${total}'"$'\n'"${(F)${(M)lines:#ok *}}" -f "${CLI_NAME} apply raycast_sync"
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
