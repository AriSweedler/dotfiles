# step nix_port — this machine is on the Nix port: the shared tier is the ~/dotfiles clone, Nix
# is installed, the local flake exists, nix-darwin has switched to it, and no local
# data waits in a place the shared tier stopped reading (it moved into the local flake). Each item
# is a manual step, often with sudo (/ari-dotfiles-nix › Install and first switch), so the fail
# is manual and there is no apply. One verdict names every item still open, in the order they
# must be done; the fix is the first one's.
step::declare nix_port --group repo --needs dotfiles_repo \
  --desc "on the Nix port: the ~/dotfiles clone, Nix installed, a local flake that nix-darwin switched to, no local data left where the shared tier stopped reading"
step::watches nix_port '.config/dotfiles/nix/**'

: "${ARI_DOTFILES_NIX_SYSTEM:=/run/current-system}"   # nix-darwin's active system; absent before the first switch
: "${ARI_DOTFILES_NIX_CLONE:=${HOME}/dotfiles}"        # the plain clone the shared flake input reads

# Local data the shared tier no longer reads, as path<TAB>what to do. A glob that matches
# nothing adds nothing.
nix_port::legacy() {
  local d="${XDG_DATA_HOME:-${HOME}/.local/share}" flake="${ARI_DOTFILES_NIX_FLAKE}" f
  for f in "${d}"/tmuxinator/*.yml(N); do
    print -r -- "${f}"$'\t'"move it to ${flake}/tmuxinator/${f:t} and add programs.tmuxinatorProjects.${f:t:r} = ./tmuxinator/${f:t}; to its home.nix"
  done
  f="${d}/raycast-snippets/snippets.json"
  [[ -f "${f}" ]] && print -r -- "${f}"$'\t'"git ldf mv it to ${flake}/raycast-snippets.json and set programs.raycastSnippets.localFile = ./raycast-snippets.json; in its home.nix"
  return 0
}

check::nix_port() {
  local flake="${ARI_DOTFILES_NIX_FLAKE}" clone="${ARI_DOTFILES_NIX_CLONE}" line
  local -a open=() fixes=()
  if [[ ! -d "${clone}/.git" ]]; then
    open+=("the shared tier is not the ~/dotfiles clone; the flake reads the clone | git_dir='${ARI_DOTFILES_DF_GIT_DIR}'")
    fixes+=("git clone ${ARI_DOTFILES_REMOTE} ~/dotfiles, then retire ~/dotfiles.git (/ari-dotfiles-nix › Install and first switch)")
  fi
  if [[ ! -d "${ARI_DOTFILES_NIX_STORE}" ]]; then
    open+=("Nix is not installed")
    fixes+=("curl -sSfL -o /tmp/nix-installer https://artifacts.nixos.org/nix-installer && sh /tmp/nix-installer install --enable-flakes")
  fi
  if [[ ! -f "${flake}/flake.nix" ]]; then
    open+=("no local flake | path='${flake}/flake.nix'")
    fixes+=("write ${flake}/flake.nix, darwin.nix and home.nix (the personal laptop's are the model: user, its own darwinConfigurations name, this machine's brews, casks and packages)")
  fi
  if [[ ! -e "${ARI_DOTFILES_NIX_SYSTEM}" ]]; then
    open+=("nix-darwin has never switched here | path='${ARI_DOTFILES_NIX_SYSTEM}'")
    fixes+=("sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin/master#darwin-rebuild -- switch --flake ${flake}#<host>; then dotfiles switch from then on")
  fi
  for line in "${(@f)$(nix_port::legacy)}"; do
    [[ -n "${line}" ]] || continue
    open+=("local data the shared tier no longer reads | path='${line%%$'\t'*}'")
    fixes+=("${line#*$'\t'}")
  done
  if (( ${#open} )); then
    local detail="${#open} transition item(s) open, in order:" i
    for (( i = 1; i <= ${#open}; i++ )); do detail+=$'\n'"  ${i}. ${open[i]}"$'\n'"     fix: ${fixes[i]}"; done
    verdict fail transition_open -m -d "${detail}" -f "${fixes[1]}"
    return 0
  fi
  verdict ok on_nix -d "clone, Nix, a local flake, nix-darwin switched; no local data left behind"
}
