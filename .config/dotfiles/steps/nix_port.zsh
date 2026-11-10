# step nix_port — this machine is on the Nix port: Nix is installed, the shared tier is the
# ~/dotfiles clone, the local flake exists, no local data waits in a place the shared tier stopped
# reading (it moved into the local flake), nix-darwin has switched to it, and the bare repo is
# retired. One verdict names every item still open, in the order they must be done; the apply does
# them in that order, so `dotfiles init` takes a fresh machine (or one on the pre-Nix bare layout)
# onto the port. It sits after brew: the first switch's Homebrew bundle needs Homebrew.
#
# The apply, item by item (each a no-op once done; /ari-dotfiles-nix › Install and first switch):
#   Nix        NixOS's nix-installer, flakes on, after a sudo prompt.
#   clone      ~/dotfiles cloned from the bare repo (unpushed commits come along; origin then points
#              at the remote), submodules checked out, and what the bare checkout holds that the
#              switch's links would hide carried in: uncommitted edits to tracked files, and the
#              untracked and ignored files of the directories bridge.nix links whole.
#   flake      with none, one written from this machine's Homebrew state (every tap, leaf and cask,
#              so the first switch's Homebrew cleanup removes nothing).
#   local data each tmuxinator project and the Raycast snippets moved into the flake; an original
#              whose flake copy is identical and referenced is removed.
#   switch     the shared input locked at the clone's HEAD, the /etc files nix-darwin replaces moved
#              aside (put back if the switch fails), then nix-darwin's first switch; after it the
#              local flake is committed in the local tier. `dotfiles switch` from then on.
#   bare repo  ~/dotfiles.git renamed ~/dotfiles.git.retired (HOME is no longer a work tree), and
#              every <file>.before-nix backup of a file identical to the clone's copy removed.
step::declare nix_port --group brew --needs brew \
  --desc "on the Nix port: Nix installed, the ~/dotfiles clone, a local flake, no local data left where the shared tier stopped reading, nix-darwin switched to it, the bare repo retired" \
  --apply "installs Nix, clones ~/dotfiles from the bare repo, writes the local flake, moves the local data into it, runs nix-darwin's first switch and retires ~/dotfiles.git; sudo prompts for the install and the switch"
step::watches nix_port '.config/dotfiles/nix/**'

: "${ARI_DOTFILES_NIX_SYSTEM:=/run/current-system}"   # nix-darwin's active system; absent before the first switch
: "${ARI_DOTFILES_NIX_CLONE:=${HOME}/dotfiles}"        # the plain clone the shared flake input reads
: "${ARI_DOTFILES_NIX_BARE:=${HOME}/dotfiles.git}"     # the pre-Nix bare repo the port retires
typeset -g NIX_PORT_INSTALLER="https://artifacts.nixos.org/nix-installer"
typeset -g NIX_PORT_BARE="${ARI_DOTFILES_NIX_BARE}"
typeset -g NIX_PORT_RETIRED="${ARI_DOTFILES_NIX_BARE}.retired"
# bridge.nix's wholeDirs: linked as one directory, so a file the clone lacks is hidden by the link.
typeset -ga NIX_PORT_WHOLE_DIRS=(.config/claude .config/chrome-exoskeleton .config/plugged)
# The files nix-darwin manages and refuses to replace when they are not its own.
typeset -ga NIX_PORT_ETC=(/etc/bashrc /etc/zshrc /etc/zshenv /etc/zprofile /etc/nix/nix.conf /etc/nix/nix.custom.conf)

# Local data the shared tier no longer reads, as <original>\t<path in the flake>\t<home.nix line>.
# A glob that matches nothing adds nothing.
nix_port::legacy() {
  local d="${XDG_DATA_HOME:-${HOME}/.local/share}" f
  for f in "${d}"/tmuxinator/*.yml(N); do
    print -r -- "${f}"$'\t'"tmuxinator/${f:t}"$'\t'"programs.tmuxinatorProjects.${f:t:r} = ./tmuxinator/${f:t};"
  done
  f="${d}/raycast-snippets/snippets.json"
  [[ -f "${f}" ]] && print -r -- "${f}"$'\t'"raycast-snippets.json"$'\t'"programs.raycastSnippets.localFile = ./raycast-snippets.json;"
  return 0
}

nix_port::nix() {
  local n
  for n in /run/current-system/sw/bin/nix /nix/var/nix/profiles/default/bin/nix; do
    [[ -x "${n}" ]] && { print -r -- "${n}"; return 0; }
  done
  return 1
}
nix_port::submodules() { git config -f "${1}/.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}' || true; }
nix_port::ldf() { git --git-dir="${ARI_DOTFILES_LDF_GIT_DIR}" --work-tree="${HOME}/.local" "$@"; }
nix_port::is_ldf_tracked() { nix_port::ldf ls-files --error-unmatch -- "${1}" >/dev/null 2>&1; }

check::nix_port() {
  local flake="${ARI_DOTFILES_NIX_FLAKE}" clone="${ARI_DOTFILES_NIX_CLONE}" line
  local -a open=()
  [[ -d "${ARI_DOTFILES_NIX_STORE}" ]] || open+=("Nix is not installed")
  [[ -d "${clone}/.git" ]] || open+=("the shared tier is not the ~/dotfiles clone; the flake reads the clone | git_dir='${ARI_DOTFILES_DF_GIT_DIR}'")
  [[ -f "${flake}/flake.nix" ]] || open+=("no local flake | path='${flake}/flake.nix'")
  local -a fields
  for line in "${(@f)$(nix_port::legacy)}"; do
    [[ -n "${line}" ]] || continue
    fields=("${(@ps:\t:)line}")
    open+=("local data the shared tier no longer reads | path='${fields[1]}' moves_to='${flake}/${fields[2]}' option='${fields[3]}'")
  done
  [[ -e "${ARI_DOTFILES_NIX_SYSTEM}" ]] || open+=("nix-darwin has never switched here | path='${ARI_DOTFILES_NIX_SYSTEM}'")
  [[ -f "${NIX_PORT_BARE}/HEAD" && -d "${clone}/.git" ]] && open+=("the bare repo still stands beside the clone | bare='${NIX_PORT_BARE}'")
  if (( ${#open} )); then
    local detail="${#open} transition item(s) open, in order:" i
    for (( i = 1; i <= ${#open}; i++ )); do detail+=$'\n'"  ${i}. ${open[i]}"; done
    verdict fail transition_open -d "${detail}" -f "${CLI_NAME} apply nix_port   (sudo prompts for the install and the first switch)"
    return 0
  fi
  verdict ok on_nix -d "Nix, the clone, a local flake, nix-darwin switched, the bare repo retired; no local data left behind"
}

# --- apply, item by item ---

nix_port::install() {
  [[ -d "${ARI_DOTFILES_NIX_STORE}" ]] && nix_port::nix >/dev/null && return 0
  # --no-confirm: the step's stdout is a log file, so the installer's prompt would look like a
  # hang. sudo asks first on /dev/tty, which the backgrounded step can still read; the installer's
  # own sudo then reuses the ticket.
  local installer="${TMPDIR:-/tmp}/dotfiles-nix-installer.$$" rc
  run_mut sudo -v || return 1
  run_mut curl -sSfL -o "${installer}" "${NIX_PORT_INSTALLER}" || return 1
  run_mut sh "${installer}" install --no-confirm --enable-flakes
  rc=$?
  run_mut rm -f "${installer}"
  return "${rc}"
}

nix_port::clone() {
  local clone="${ARI_DOTFILES_NIX_CLONE}" bare="${NIX_PORT_BARE}" sub d
  [[ -d "${clone}/.git" ]] && return 0
  if [[ -e "${clone}" ]]; then
    log::err "something already stands where the clone goes; move it aside and re-run | path='${clone}'"
    return 1
  fi
  if [[ -f "${bare}/HEAD" ]]; then
    # A submodule commit not on its origin would be lost: the clone's submodules come from origin.
    for sub in "${(@f)$(nix_port::submodules "${HOME}")}"; do
      [[ -n "${sub}" && -e "${HOME}/${sub}/.git" ]] || continue
      if [[ -n "$(git -C "${HOME}/${sub}" log --oneline origin/main..HEAD 2>/dev/null)" ]]; then
        log::err "submodule has commits origin lacks; push them first | path='~/${sub}'"
        return 1
      fi
    done
    run_mut git clone -q "${bare}" "${clone}" || return 1
  else
    run_mut git clone -q "${ARI_DOTFILES_REMOTE}" "${clone}" || return 1
  fi
  if is_dry_run; then
    log::info "dry-run, would point origin at the remote, fetch it, check out submodules and carry the bare checkout's edits | clone='${clone}'"
    return 0
  fi
  run_mut git -C "${clone}" remote set-url origin "${ARI_DOTFILES_REMOTE}" || return 1
  if [[ -n "${ARI_DOTFILES_PUSH_URL}" && "${ARI_DOTFILES_PUSH_URL}" != "${ARI_DOTFILES_REMOTE}" ]]; then
    run_mut git -C "${clone}" remote set-url --push origin "${ARI_DOTFILES_PUSH_URL}" || return 1
  fi
  run_mut git -C "${clone}" fetch -q origin || { log::err "fetch failed | url='${ARI_DOTFILES_REMOTE}'"; return 1; }
  # origin/main's reflog still starts at the bare repo's main; a `git pull --rebase` would take that
  # as the fork-point and drop every local commit up to it.
  run_mut git -C "${clone}" reflog expire --expire=now refs/remotes/origin/main || return 1
  run_mut git -C "${clone}" branch -q --set-upstream-to=origin/main main || return 1
  run_mut git -C "${clone}" config core.hooksPath "${ARI_DOTFILES_DF_HOOKS}" || return 1
  # The repo is public: the personal identity, as dotfiles_repo sets it on the bare repo.
  tier::submodule_identity_apply "${clone}/.git" || return 1
  run_mut git -C "${clone}" submodule update -q --init || return 1
  # What the bare checkout holds that the switch's links would hide.
  if [[ -f "${bare}/HEAD" ]]; then
    local patch="${TMPDIR:-/tmp}/dotfiles-nix-port.$$.patch"
    git --git-dir="${bare}" --work-tree="${HOME}" diff --binary --ignore-submodules=all HEAD > "${patch}" 2>/dev/null || true
    if [[ -s "${patch}" ]]; then
      if ! run_mut git -C "${clone}" apply --whitespace=nowarn "${patch}"; then
        log::err "the bare checkout's uncommitted edits did not apply to the clone | patch='${patch}'"
        return 1
      fi
      log::info "carried the bare checkout's uncommitted edits into the clone | files='$(git -C "${clone}" diff --name-only | tr '\n' ' ')'"
    fi
    run_mut rm -f "${patch}"
  fi
  for d in "${NIX_PORT_WHOLE_DIRS[@]}"; do
    [[ -d "${HOME}/${d}" && ! -L "${HOME}/${d}" ]] || continue
    run_mut rsync -a --ignore-existing --exclude .git "${HOME}/${d}/" "${clone}/${d}/" || return 1
  done
}

nix_port::write_flake() {
  local flake="${ARI_DOTFILES_NIX_FLAKE}" brew="${ARI_DOTFILES_BREW}" host="" line tmp q='"'
  [[ -f "${flake}/flake.nix" ]] && return 0
  [[ -r "${ARI_DOTFILES_MACHINE_NAME_FILE}" ]] && host="$(<"${ARI_DOTFILES_MACHINE_NAME_FILE}")"
  host="${${host//[^A-Za-z0-9-]/-}:-this}"
  local -a taps=() brews=() casks=() homelines=()
  if [[ -n "${brew}" ]]; then
    taps=("${(@f)$(HOMEBREW_NO_AUTO_UPDATE=1 "${brew}" tap 2>/dev/null)}")
    brews=("${(@f)$(HOMEBREW_NO_AUTO_UPDATE=1 "${brew}" leaves --installed-on-request 2>/dev/null)}")
    casks=("${(@f)$(HOMEBREW_NO_AUTO_UPDATE=1 "${brew}" info --json=v2 --installed 2>/dev/null | jq -r '.casks[].full_token')}")
  fi
  for line in "${(@f)$(nix_port::legacy)}"; do [[ -n "${line}" ]] && homelines+=("  ${line##*$'\t'}"); done
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nix-flake.XXXXXX")" || return 1
  {
    print -r -- "# Local tier of the Nix port for the machine named ${host}: the shared modules from the"
    print -r -- "# ~/dotfiles clone, then this machine's darwin.nix and home.nix. Written by \`dotfiles init\`;"
    print -r -- "# edit freely. Never \`nix flake update\` here (/ari-dotfiles-nix)."
    print -r -- "{"
    print -r -- "  description = ${q}Ari's dotfiles: the ${host} machine${q};"
    print -r -- ""
    print -r -- "  # submodules=1: claude-skills.nix links the skills the submodules carry (as \`dotfiles switch\` locks it)."
    print -r -- "  inputs.dotfiles.url = ${q}git+file://${ARI_DOTFILES_NIX_CLONE}?dir=.config/dotfiles/nix&submodules=1${q};"
    print -r -- ""
    print -r -- "  outputs = { self, dotfiles }: {"
    print -r -- "    darwinConfigurations.${host} = dotfiles.lib.darwinSystem {"
    print -r -- "      user = ${q}${USER}${q};"
    print -r -- "      modules = [ ./darwin.nix ];"
    print -r -- "      homeModules = [ ./home.nix ];"
    print -r -- "    };"
    print -r -- "  };"
    print -r -- "}"
  } > "${tmp}/flake.nix"
  {
    print -r -- "# This machine's system layer: the taps, brews and casks only it wants. A switch uninstalls"
    print -r -- "# every formula and cask that neither this file nor the shared darwin.nix declares, so this"
    print -r -- "# lists everything Homebrew had installed when \`dotfiles init\` wrote it ($(date +%F))."
    print -r -- "{ ... }:"
    print -r -- "{"
    print -r -- "  homebrew = {"
    print -r -- "    taps = ["; for line in "${(@)taps:#}"; do print -r -- "      ${q}${line}${q}"; done; print -r -- "    ];"
    print -r -- "    brews = ["; for line in "${(@)brews:#}"; do print -r -- "      ${q}${line}${q}"; done; print -r -- "    ];"
    print -r -- "    casks = ["; for line in "${(@)casks:#}"; do print -r -- "      ${q}${line}${q}"; done; print -r -- "    ];"
    print -r -- "  };"
    print -r -- "}"
  } > "${tmp}/darwin.nix"
  {
    print -r -- "# This machine's user layer: its packages, and the local data the shared modules place."
    print -r -- "{ ... }:"
    print -r -- "{"
    for line in "${homelines[@]}"; do print -r -- "${line}"; done
    print -r -- "}"
  } > "${tmp}/home.nix"
  run_mut mkdir -p "${flake}" && run_mut cp "${tmp}/flake.nix" "${tmp}/darwin.nix" "${tmp}/home.nix" "${flake}/"
  local rc=$?
  rm -rf "${tmp}"
  (( rc == 0 )) && log::info "wrote the local flake | flake='${flake}' host='${host}' taps='${#${(@)taps:#}}' brews='${#${(@)brews:#}}' casks='${#${(@)casks:#}}'"
  return "${rc}"
}

nix_port::move_legacy() {
  local flake="${ARI_DOTFILES_NIX_FLAKE}" line orig rel target
  for line in "${(@f)$(nix_port::legacy)}"; do
    [[ -n "${line}" ]] || continue
    orig="${line%%$'\t'*}"; rel="${${line#*$'\t'}%%$'\t'*}"; target="${flake}/${rel}"
    if [[ -e "${target}" ]]; then
      # The flake has it already: remove the original only when the copy is the same file and
      # home.nix uses it; anything else is a human's merge.
      if ! cmp -s "${orig}" "${target}"; then
        log::err "the flake's copy differs from the original; merge by hand, then delete the original | original='${orig}' flake='${target}'"
        return 1
      fi
      if ! grep -qF "./${rel}" "${flake}/home.nix" 2>/dev/null; then
        log::err "home.nix does not use the flake's copy; add the line, then re-run | file='${flake}/home.nix' line='${line##*$'\t'}'"
        return 1
      fi
      if nix_port::is_ldf_tracked "${orig}"; then run_mut nix_port::ldf rm -q -- "${orig}" || return 1
      else run_mut rm -f "${orig}" || return 1; fi
    else
      run_mut mkdir -p "${target:h}" || return 1
      if nix_port::is_ldf_tracked "${orig}"; then run_mut nix_port::ldf mv -- "${orig}" "${target}" || return 1
      else run_mut mv "${orig}" "${target}" || return 1; fi
    fi
    # A directory the move emptied would still be read (TMUXINATOR_CONFIG follows it while it exists).
    [[ -d "${orig:h}" && -z "$(ls -A "${orig:h}" 2>/dev/null)" ]] && run_mut rmdir "${orig:h}"
  done
  return 0
}

nix_port::restore_etc() {
  local f
  for f in "$@"; do run_mut sudo mv "${f}.before-nix-darwin" "${f}" || log::err "put it back by hand | file='${f}'"; done
}

nix_port::first_switch() {
  [[ -e "${ARI_DOTFILES_NIX_SYSTEM}" ]] && return 0
  local clone="${ARI_DOTFILES_NIX_CLONE}" flake="${ARI_DOTFILES_NIX_FLAKE}" nix host rev f
  local -a hosts moved=()
  if ! nix="$(nix_port::nix)"; then
    if is_dry_run; then
      log::info "dry-run, would lock the shared input, move aside the /etc files nix-darwin replaces and run its first switch | flake='${flake}'"
      return 0
    fi
    log::err "no nix to run"; return 1
  fi
  if [[ -n "${ARI_DOTFILES_NIX_HOST}" ]]; then host="${ARI_DOTFILES_NIX_HOST}"
  else
    hosts=(${(f)"$("${nix}" --extra-experimental-features 'nix-command flakes' eval --raw "path:${flake}#darwinConfigurations" \
      --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c)' 2>/dev/null)"})
    if (( ${#hosts} != 1 )); then
      log::err "set ARI_DOTFILES_NIX_HOST: the local flake has ${#hosts} hosts | flake='${flake}' hosts='${(j:, :)hosts}'"
      return 1
    fi
    host="${hosts[1]}"
  fi
  rev="$(git -C "${clone}" rev-parse HEAD)" || return 1
  run_mut sudo -v || return 1
  run_mut "${nix}" --extra-experimental-features 'nix-command flakes' flake lock \
    --override-input dotfiles "git+file://${clone}?dir=.config/dotfiles/nix&submodules=1&rev=${rev}" "path:${flake}" \
    || { log::err "locking the shared input failed | flake='${flake}' rev='${rev}'"; return 1; }
  for f in "${NIX_PORT_ETC[@]}"; do
    [[ -f "${f}" && ! -L "${f}" ]] || continue
    if [[ -e "${f}.before-nix-darwin" ]]; then
      log::err "a backup is already there; compare and remove one, then re-run | file='${f}' backup='${f}.before-nix-darwin'"
      nix_port::restore_etc "${moved[@]}"; return 1
    fi
    run_mut sudo mv "${f}" "${f}.before-nix-darwin" || { nix_port::restore_etc "${moved[@]}"; return 1; }
    moved+=("${f}")
  done
  if ! run_mut sudo "${nix}" --extra-experimental-features 'nix-command flakes' run nix-darwin/master#darwin-rebuild -- \
       switch --flake "${flake}#${host}"; then
    log::err "the first switch failed; the /etc files moved aside are put back | host='${host}' rev='${rev[1,7]}'"
    nix_port::restore_etc "${moved[@]}"; return 1
  fi
  # A refused commit (a signing prompt with no terminal) leaves the flake uncommitted; the switch stands.
  tier::commit local "nix: the local flake for ${host}, first switch at ${rev[1,7]}" "${flake}" \
    || log::warn "the local flake is not committed; commit it per /ari-dotfiles | flake='${flake}'"
}

# The backups the switch made of files identical to the clone's are noise, so removed; a differing
# one stays for a human (/ari-dotfiles-nix › Troubleshooting).
nix_port::retire_bare() {
  local clone="${ARI_DOTFILES_NIX_CLONE}" p b d
  local -i removed=0
  local -a left=()
  if [[ -f "${NIX_PORT_BARE}/HEAD" && -d "${clone}/.git" ]]; then
    if [[ -e "${NIX_PORT_RETIRED}" ]]; then
      log::err "a retired bare repo is already there; remove one | bare='${NIX_PORT_BARE}' retired='${NIX_PORT_RETIRED}'"
      return 1
    fi
    run_mut mv "${NIX_PORT_BARE}" "${NIX_PORT_RETIRED}" || return 1
  fi
  is_dry_run && return 0
  for p in "${(@f)$(git -C "${clone}" ls-files)}"; do
    b="${HOME}/${p}.before-nix"
    [[ -f "${b}" && ! -L "${b}" ]] || continue
    if cmp -s "${b}" "${clone}/${p}"; then run_mut rm -f "${b}" && removed+=1; else left+=("${b}"); fi
  done
  for d in "${NIX_PORT_WHOLE_DIRS[@]}"; do
    b="${HOME}/${d}.before-nix"
    [[ -d "${b}" ]] || continue
    if diff -rq --exclude .git "${b}" "${clone}/${d}" >/dev/null 2>&1; then run_mut rm -rf "${b}" && removed+=1; else left+=("${b}"); fi
  done
  log::info "removed the .before-nix backups identical to the clone's | removed='${removed}' left='${#left}'"
  (( ${#left} )) && log::warn "these backups differ from the clone; compare each by hand | files='${(j:, :)left}'"
  return 0
}

apply::nix_port() {
  nix_port::install || return 1
  nix_port::clone || return 1
  nix_port::write_flake || return 1
  nix_port::move_legacy || return 1
  nix_port::first_switch || return 1
  nix_port::retire_bare
}
