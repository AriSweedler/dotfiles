# dotfiles/cmd/switch.zsh — `dotfiles switch`: lock the local flake's shared input at the clone's
# HEAD, commit the lock in the local tier, then darwin-rebuild switch (sudo) or, with
# --build, only build the system. macOS only: elsewhere the machine's own host flake builds
# its user layer, so --remote REMOTE deploys it from here, by the recipe the local tier keeps.

verb::define switch "lock the shared flake at the clone's HEAD and switch this machine to it"
verb::usage switch 'switch [--build] [--dry-run] [--no-commit] | switch --remote REMOTE [--execute]'
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
activation: what Claude runs to check a change before it switches.

Only on macOS. On NixOS the user layer is built by the flake that builds the
machine, which takes the shared tier from GitHub as its own input, so switch
refuses there and names the command that deploys it.

--remote REMOTE deploys such a machine from here, by the recipe the local tier
keeps in $ARI_DOTFILES_REMOTES_DIR/REMOTE. It is a dry run unless --execute is
given. It refuses while the shared tier has unpushed commits, then locks the
host flake's dotfiles input at that commit, commits and pushes the lock (and
the pointer in the repo holding that flake), runs the recipe's deploy and
check, and over ssh pulls the host's clone and reloads its running tmux. A
recipe is key=value lines:
  flake=~/workspace/homelab/hosts/web   the host flake (a git repo)
  repo=~/workspace/homelab              optional: the repo whose pointer to it moves
  deploy=bin/deploy web --apply         run in repo (else flake)
  check=bin/deploy web check            optional, run after deploy
  ssh=me@192.0.2.10                     the host, for the pull and the tmux reload
EOF
verb::edit switch --none 'it applies the flakes; edit them as files in the clone and the local tier'
verb::flag switch '--build' 'build the system and print its store path; no sudo, nothing activated'
verb::flag switch '--dry-run' 'print the lock, commit and switch it would run; change nothing'
verb::flag switch '--no-commit' 'leave a moved flake.lock uncommitted'
verb::flag switch '--remote REMOTE' 'deploy REMOTE by its recipe in the local tier; a dry run unless --execute'
verb::flag switch '--execute' 'with --remote: deploy for real'
verb::env switch ARI_DOTFILES_NIX_FLAKE 'the local flake' '$(help::tilde "${ARI_DOTFILES_NIX_FLAKE}")'
verb::env switch ARI_DOTFILES_NIX_HOST "the local flake's darwinConfigurations entry; empty: its only one" '${ARI_DOTFILES_NIX_HOST}'
verb::env switch ARI_DOTFILES_REMOTES_DIR 'the --remote recipes, one file per host' '$(help::tilde "${ARI_DOTFILES_REMOTES_DIR}")'
verb::section switch 'Exit codes' <<'EOF'
0   switched, built, deployed, or (a dry run) printed
1   the lock, the commit, the build, the switch, a push or a deploy step
    failed, or (--remote) the shared tier has unpushed commits
64  usage, the shared tier is not a plain clone, no single host to pick, or
    (--remote) no recipe for the host or a recipe missing a key
EOF

cmd_switch() {
  local -A opts; local -a args
  verb::parse switch "$@"
  (( ${#args} == 0 )) || usage_error "switch takes no arguments | args='${args[*]}'"
  if (( ${+opts[--remote]} )); then
    switch::remote "${opts[--remote]}" "${+opts[--execute]}" "${+opts[--dry-run]}"
    return
  fi
  (( ! ${+opts[--execute]} )) || usage_error "--execute goes with --remote REMOTE"
  if [[ "${OSTYPE}" != darwin* ]]; then
    local REPLY name='<this machine>'
    machine_name::read && name="${REPLY}"
    log::err "switch is darwin-rebuild, which this machine has not | fix='deploy it from the machine that keeps its recipe: dotfiles switch --remote ${name}'"
    return 1
  fi
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
  # Each dev repo checked out here builds from its HEAD, unpushed commits included; one that is
  # not checked out builds from the shared flake's lock.
  local -a overrides=(--override-input dotfiles "${input}")
  local sub head
  for sub in "${SUBMODULES[@]}"; do
    head="$(git -C "${clone}/${sub}" rev-parse -q --verify HEAD 2>/dev/null)" || continue
    overrides+=(--override-input "dotfiles/${SUBMODULE_INPUT[${sub}]}" "git+file://${clone}/${sub}?rev=${head}")
  done
  if is_dry_run; then
    print -r -- "would run: nix flake lock ${(j: :)${(@q-)overrides}} (in ${flake})"
  else
    nix flake lock "${overrides[@]}" "path:${flake}" || {
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

# switch::remote HOST EXECUTE DRY_RUN: deploy HOST by its recipe (see the verb's about text): a dry
# run unless EXECUTE is 1 and DRY_RUN is 0. Each step stops the deploy when it fails.
switch::remote() {
  setopt localoptions extendedglob
  local host="${1}" execute="${2}" dry="${3}"
  [[ "${host}" == [a-z0-9][a-z0-9-]# ]] || usage_error "--remote takes a host name | host='${host}'"
  local -A r
  switch::recipe "${ARI_DOTFILES_REMOTES_DIR}/${host}" || return 64
  if (( ! execute || dry )); then
    export ARI_DOTFILES_DRY_RUN=1
    switch::dry_run_banner "${host}"
  fi

  # 1. The host builds from GitHub: refuse while the shared tier has commits it cannot see.
  repo_git shared fetch -q origin main || { log::err "fetching the shared tier failed"; return 1; }
  local ahead rev
  ahead="$(repo_git shared rev-list --count origin/main..HEAD)" || return 1
  if (( ahead )); then
    log::err "${ahead} shared commit(s) not on GitHub, which ${host} builds from | fix='dotfiles push'"
    return 1
  fi
  rev="$(repo_git shared rev-parse origin/main)" || return 1
  log::info "deploying the shared tier to ${host} | rev='${rev[1,7]}'"

  # 2. Lock the host flake's dotfiles input at that commit; commit and push the lock.
  local flake="${r[flake]}"
  run_mut nix flake update dotfiles --refresh --flake "${flake}" || { log::err "nix flake update failed | flake='${flake}'"; return 1; }
  if ! is_dry_run; then
    local locked
    locked="$(jq -r '.nodes.dotfiles.locked.rev' "${flake}/flake.lock")"
    [[ "${locked}" == "${rev}" ]] || {
      log::err "the lock did not land on the pushed commit | locked='${locked}' pushed='${rev}' flake='${flake}'"
      return 1
    }
  fi
  if is_dry_run || [[ -n "$(git -C "${flake}" status --porcelain -- flake.lock)" ]]; then
    run_mut git -C "${flake}" commit -q -m "dotfiles: bump to ${rev[1,7]}" -- flake.lock || return 1
    run_mut git -C "${flake}" push -q origin HEAD || { log::err "pushing the host flake failed | repo='${flake}'"; return 1; }
  else
    log::info "the host flake already locks this commit | flake='${flake}'"
  fi

  # 3. Move the pointer in the repo that holds the host flake, when the recipe names one.
  local repo="${r[repo]:-}"
  if [[ -n "${repo}" ]]; then
    local rel="${flake#${repo}/}"
    if is_dry_run || [[ -n "$(git -C "${repo}" status --porcelain -- "${rel}")" ]]; then
      run_mut git -C "${repo}" commit -q -m "${rel}: bump (dotfiles ${rev[1,7]})" -- "${rel}" || return 1
      run_mut git -C "${repo}" push -q origin HEAD || { log::err "pushing the pointer failed | repo='${repo}'"; return 1; }
    fi
  fi

  # 4. Pull the host's clone first, so the files the new generation links into it exist. By path: a login
  # shell over ssh reads no .zshrc, which is what puts ~/.config/bin on PATH (co2, 2026-11-16: exit 127).
  local -a ssh_to=(ssh -o BatchMode=yes -o ConnectTimeout=10 "${r[ssh]}")
  run_mut "${ssh_to[@]}" "zsh -lc '\"\$HOME/.config/bin/dotfiles\" pull'" \
    || { log::err "pulling the host's clone failed | host='${host}' ssh='${r[ssh]}'"; return 1; }

  # 5. Deploy, then check, from the repo (else the flake).
  local dir="${repo:-${flake}}"
  run_mut zsh -c "cd ${(q)dir} && ${r[deploy]}" || { log::err "the deploy failed | host='${host}' cmd='${r[deploy]}'"; return 1; }
  if [[ -n "${r[check]:-}" ]]; then
    run_mut zsh -c "cd ${(q)dir} && ${r[check]}" || { log::err "the check failed | host='${host}' cmd='${r[check]}'"; return 1; }
  fi

  # 6. Reload the host's running tmux, if any: /etc/tmux.conf first, as at server start.
  local reload='if tmux ls >/dev/null 2>&1; then { [ ! -f /etc/tmux.conf ] || tmux source-file /etc/tmux.conf; } && tmux source-file ~/.config/tmux/tmux.conf; fi'
  run_mut "${ssh_to[@]}" "zsh -lc ${(qq)reload}" \
    || { log::err "reloading tmux on the host failed | host='${host}' ssh='${r[ssh]}'"; return 1; }

  if is_dry_run; then
    log::warn "that was a dry run: nothing changed | fix='dotfiles switch --remote ${host} --execute'"
  else
    log::info "${host} runs the shared tier at ${rev[1,7]}"
  fi
}

# switch::recipe FILE: fill the caller's r from FILE's key=value lines (# comments, blank lines and
# a leading ~/ allowed); 64 with the missing key or file named.
switch::recipe() {
  local file="${1}" line key value
  if [[ ! -r "${file}" ]]; then
    log::err "no recipe for this host | file='${file}' keys='flake deploy ssh, optional repo check'"
    return 64
  fi
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ -z "${line// }" || "${line}" == [[:space:]]#\#* ]] && continue
    key="${line%%=*}" value="${line#*=}"
    [[ "${value}" == '~/'* ]] && value="${HOME}/${value#\~/}"
    r[${key}]="${value}"
  done < "${file}"
  local k
  for k in flake deploy ssh; do
    [[ -n "${r[${k}]:-}" ]] || { log::err "the recipe lacks ${k} | file='${file}'"; return 64; }
  done
}

# switch::dry_run_banner HOST: the warning at the top of a --remote dry run, on stderr.
switch::dry_run_banner() {
  local bar="${(l:72::!:)${:-}}"
  local -a lines=(
    "${bar}"
    "!!  DRY RUN: nothing is locked, committed, pushed, deployed or reloaded."
    "!!  Each step prints what it would run on ${1}. To deploy for real:"
    "!!"
    "!!      dotfiles switch --remote ${1} --execute"
    "${bar}"
  )
  if [[ -t 2 ]]; then print -u2 -P -- "%B%F{yellow}${(pj:\n:)lines}%f%b"; else print -u2 -l -- "${lines[@]}"; fi
}
