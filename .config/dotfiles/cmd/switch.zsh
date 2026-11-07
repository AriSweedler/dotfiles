# dotfiles/cmd/switch.zsh — `dotfiles switch`: lock the local flake's shared input at the clone's
# HEAD, commit the lock in the local tier, then darwin-rebuild switch (Ari's sudo) or, with
# --build, only build the system.

verb::define switch "lock the shared flake at the clone's HEAD and switch this machine to it"
verb::usage switch 'switch [--build] [--dry-run] [--no-commit]'
verb::about switch <<'EOF'
The local flake takes the shared one from the plain clone (a git+file input),
and Nix sees only what git has committed there. switch locks that input at
the clone's HEAD (uncommitted changes under its nix directory are named, and
left out), commits flake.lock in the local tier when the lock moved, then
runs 'sudo darwin-rebuild switch' on the local flake: one sudo prompt, and the
machine is the flake. A file edited through its HOME link is live without a
switch; a new file, and any change to the nix directory, needs a commit and
then a switch.

--build builds the system and prints its store path, with no sudo and no
activation: what Claude runs to check a change before Ari switches.
EOF
verb::edit switch --none 'it applies the flakes; edit them as files in the clone and the local tier'
verb::flag switch '--build' 'build the system and print its store path; no sudo, nothing activated'
verb::flag switch '--dry-run' 'print the lock, commit and switch it would run; change nothing'
verb::flag switch '--no-commit' 'leave a moved flake.lock uncommitted'
verb::env switch ARI_DOTFILES_NIX_FLAKE 'the local flake' '$(help::tilde "${ARI_DOTFILES_NIX_FLAKE}")'
verb::env switch ARI_DOTFILES_NIX_HOST "the local flake's darwinConfigurations entry; empty: its only one" '${ARI_DOTFILES_NIX_HOST}'
verb::section switch 'Exit codes' <<'EOF'
0   switched, built, or (--dry-run) printed
1   the lock, the commit, the build or the switch failed
64  usage, the shared tier is not a plain clone, or no single host to pick
EOF

cmd_switch() {
  local -A opts; local -a args
  verb::parse switch "$@"
  (( ${#args} == 0 )) || usage_error "switch takes no arguments | args='${args[*]}'"
  (( ${+opts[--dry-run]} )) && export ARI_DOTFILES_DRY_RUN=1
  local clone="${ARI_DOTFILES_DF_WORK_TREE}" flake="${ARI_DOTFILES_NIX_FLAKE}"
  [[ "${ARI_DOTFILES_DF_GIT_DIR:t}" == .git ]] \
    || usage_error "switch needs the shared tier as a plain clone | git_dir='${ARI_DOTFILES_DF_GIT_DIR}'"
  [[ -f "${flake}/flake.nix" ]] || usage_error "no local flake | flake='${flake}'"
  local host
  host="$(switch::host "${flake}")" || return $?

  local dirty
  dirty="$(repo_git shared status --porcelain -- .config/dotfiles/nix)"
  [[ -z "${dirty}" ]] \
    || log::warn "uncommitted under the nix directory; not in this switch | paths='${(j:, :)${(f)dirty}#???}'"
  local rev
  rev="$(repo_git shared rev-parse HEAD)" || return 1
  local input="git+file://${clone}?dir=.config/dotfiles/nix&rev=${rev}"
  if is_dry_run; then
    print -r -- "would run: nix flake lock --override-input dotfiles '${input}' (in ${flake})"
  else
    nix flake lock --override-input dotfiles "${input}" "path:${flake}" || {
      log::err "locking the shared input failed | flake='${flake}' rev='${rev}'"
      return 1
    }
  fi
  if [[ -n "$(tier::git local status --porcelain -- "${flake}/flake.lock")" ]]; then
    if (( ${+opts[--no-commit]} )); then
      log::info "flake.lock moved; left uncommitted | file='${flake}/flake.lock'"
    else
      tier::commit local "nix: lock the shared flake at ${rev[1,7]}" "${flake}/flake.lock" || return 1
    fi
  fi

  if (( ${+opts[--build]} )); then
    run_mut nix build "path:${flake}#darwinConfigurations.${host}.system" --no-link --print-out-paths
    return
  fi
  run_mut sudo /run/current-system/sw/bin/darwin-rebuild switch --flake "${flake}#${host}"
}

# switch::host FLAKE: the darwinConfigurations entry to switch to, on stdout: ARI_DOTFILES_NIX_HOST,
# else the flake's only one.
switch::host() {
  if [[ -n "${ARI_DOTFILES_NIX_HOST}" ]]; then
    print -r -- "${ARI_DOTFILES_NIX_HOST}"
    return 0
  fi
  local -a hosts
  hosts=(${(f)"$(nix eval --raw "path:${1}#darwinConfigurations" \
    --apply 'c: builtins.concatStringsSep "\n" (builtins.attrNames c)' 2>/dev/null)"})
  if (( ${#hosts} != 1 )); then
    log::err "set ARI_DOTFILES_NIX_HOST: the local flake has ${#hosts} hosts | flake='${1}' hosts='${(j:, :)hosts}'"
    return 64
  fi
  print -r -- "${hosts[1]}"
}
