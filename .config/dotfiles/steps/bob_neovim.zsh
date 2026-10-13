# step bob_neovim — neovim through bob.
step::declare bob_neovim --group tools --desc "neovim installed through bob"
# Machine inputs: what `bob ls` reads. reply: the Homebrew-installed bob binary and bob's config
# and version dirs (macOS and XDG locations), two levels deep. 1 when bob is not a Homebrew keg
# (a wrapper, a test shim) or its config moves the downloads elsewhere: then uncached.
step::bob_neovim::inputs() {
  local bin="${commands[bob]:-}" dir
  bin="${bin:A}"
  [[ "${bin}" == */Cellar/bob/* ]] || return 1
  reply=("${bin}")
  [[ -z "${BOB_CONFIG:-}" ]] || reply+=("${BOB_CONFIG}")
  for dir in "${HOME}/Library/Application Support/bob" "${XDG_DATA_HOME:-${HOME}/.local/share}/bob" "${XDG_CONFIG_HOME:-${HOME}/.config}/bob"; do
    reply+=("${dir}" "${dir}"/*(ND) "${dir}"/*/*(ND))
  done
  local f
  for f in "${BOB_CONFIG:-}" "${HOME}/Library/Application Support/bob/config."(json|toml)(N) "${XDG_CONFIG_HOME:-${HOME}/.config}/bob/config."(json|toml)(N); do
    [[ -r "${f}" && "${mapfile[${f}]}" == *(downloads_location|installation_location)* ]] && return 1
  done
  return 0
}

check::bob_neovim() {
  local -a reply
  if step::bob_neovim::inputs; then
    CACHE_ENV=(BOB_CONFIG XDG_DATA_HOME XDG_CONFIG_HOME)
    cache::check step::bob_neovim::live "${reply[@]}"
  else
    step::bob_neovim::live
  fi
}

step::bob_neovim::live() {
  if ! command -v bob >/dev/null 2>&1; then
    verdict fail bob_missing -m -d "bob not on PATH (the Brewfile lists it)" -f "${CLI_NAME} apply brew_pkgs"
    return 0
  fi
  # Read all of `bob ls` rather than `| grep -q`: bob panics on a closed pipe.
  local listing
  listing="$(bob ls 2>/dev/null || true)"
  if [[ "${listing}" == *Used* ]]; then
    verdict ok installed -d "neovim installed via bob"
    return 0
  fi
  verdict fail nvim_missing -d "bob ls shows no version in use" -f "${CLI_NAME} apply bob_neovim"
}

apply::bob_neovim() {
  run_mut bob install latest && run_mut bob use latest
}
