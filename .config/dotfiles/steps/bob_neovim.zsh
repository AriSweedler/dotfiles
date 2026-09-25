# step bob_neovim — neovim through bob.
step::declare bob_neovim --group tools --desc "neovim installed through bob"

check::bob_neovim() {
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
