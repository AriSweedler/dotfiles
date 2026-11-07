# step neovim — the nvim on PATH is the shared flake's pinned build and starts headless with the
# user's config without an error. Nix installs it (a switch applies the pin); no apply here.
step::declare neovim --group tools \
  --desc "nvim comes from the Nix flake's pinned build and starts headless with the config without an error"
step::watches neovim --none "reads the nvim on PATH and the nvim config it starts with, no repo file"

# Cached on the binary and every config file the start reads, so an unchanged machine forks
# nothing; only a build in the real Nix store, which never changes in place, is cached.
check::neovim() {
  local bin="${commands[nvim]:-}" conf="${XDG_CONFIG_HOME:-${HOME}/.config}/nvim"
  [[ "${bin:A}" == /nix/store/* ]] || { step::neovim::live; return 0; }
  local -a inputs=("${bin}" "${bin:A}" "${conf}" "${conf}"/**/*(N.))
  CACHE_ENV=(XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME ARI_DOTFILES_NIX_STORE)
  cache::check step::neovim::live "${inputs[@]}"
}

step::neovim::live() {
  local bin="${commands[nvim]:-}"
  if [[ -z "${bin}" ]]; then
    verdict fail nvim_missing -m -d "nvim not on PATH (the shared flake's home.nix installs it)" \
      -f "sudo darwin-rebuild switch (the local flake; /ari-dotfiles-nix)"
    return 0
  fi
  if [[ "${bin:A}" != "${ARI_DOTFILES_NIX_STORE}"/* ]]; then
    verdict fail nvim_not_nix -m -d "nvim on PATH is not the flake's | path='${bin}' resolved='${bin:A}'" \
      -f "remove what puts '${bin:h}' ahead of the Nix profile on PATH"
    return 0
  fi
  local version log errors rc=0
  version="$("${bin}" --version 2>/dev/null | head -n 1)"
  log="${XDG_STATE_HOME:-${HOME}/.local/state}/nvim/headless-start.log"
  mkdir -p "${log:h}"
  # A clean start prints nothing, so every message the config prints is an error to surface. The
  # timeout keeps a hung plugin from holding the check.
  errors="$(with_timeout 20 "${bin}" --headless '+lua vim.defer_fn(function() vim.cmd("qa!") end, 500)' 2>&1 >/dev/null)" || rc=$?
  if (( rc != 0 )) || [[ -n "${errors}" ]]; then
    print -r -- "# $(date -u +%FT%TZ) ${version} rc=${rc}"$'\n'"${errors}" >| "${log}"
    verdict fail nvim_start_errors -m -d "nvim --headless printed errors or exited ${rc} | version='${version}' log='${log}'"$'\n'"${errors%%$'\n'*}" \
      -f "${EDITOR:-nvim} ${log}"
    return 0
  fi
  verdict ok started -d "version='${version}' path='${bin}'"
}
