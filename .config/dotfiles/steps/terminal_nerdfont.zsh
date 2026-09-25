# step terminal_nerdfont — a Nerd Font cask installed and at least one Terminal.app profile
# using one. Setting the font is a hand step; the verdicts say so.
step::declare terminal_nerdfont --group brew --needs brew --tools brew \
  --desc "a Nerd Font cask is installed and at least one Terminal.app profile uses a Nerd Font"

check::terminal_nerdfont() {
  local casks
  casks="$("${ARI_DOTFILES_BREW}" list --cask 2>/dev/null || true)"
  local -a fonts=(${(M)${(f)casks}:#*nerd-font*})
  if (( ${#fonts} == 0 )); then
    verdict fail font_missing -m -d "no *nerd-font* cask installed (the Brewfile lists font-caskaydia-mono-nerd-font)" \
      -f "${CLI_NAME} apply brew_pkgs"
    return 0
  fi
  local howto="Set a Nerd Font in Terminal.app: Settings -> Profiles -> Text -> Font"$'\n'"Installed: ${(j:, :)fonts}"
  if [[ ! -r "${ARI_DOTFILES_TERMINAL_PLIST}" ]]; then
    verdict warn manual_font -m -d "no Terminal.app preferences yet | plist='${ARI_DOTFILES_TERMINAL_PLIST}'"$'\n'"${howto}"
    return 0
  fi
  local -a names=(${(f)"$(step::terminal_nerdfont::names "${ARI_DOTFILES_TERMINAL_PLIST}")"})
  if (( ${#names} == 0 )); then
    verdict fail font_not_set -m -d "no Terminal.app profile uses a Nerd Font | plist='${ARI_DOTFILES_TERMINAL_PLIST}'"$'\n'"${howto}"
    return 0
  fi
  verdict ok font_set -d "fonts='${(j:, :)names}' plist='${ARI_DOTFILES_TERMINAL_PLIST}'"
}

# Terminal.app stores each profile's font as a base64 NSKeyedArchiver blob, so the PostScript
# name is not greppable in the plist itself. Decode every <data> blob and pull Nerd Font names
# (CaskaydiaMonoNFM-Regular, JetBrainsMonoNF-Bold, HackNerdFont-Regular) out of the bytes.
# Prints unique names, one per line; nothing when no profile uses one.
step::terminal_nerdfont::names() {
  local plist="${1}" xml joined blob
  xml="$(plutil -convert xml1 -o - "${plist}" 2>/dev/null || true)"
  joined="$(print -r -- "${xml}" | tr -d '\n\t ')"
  local -a blobs=(${(s:<data>:)joined})
  local -a names=()
  for blob in "${blobs[@]:1}"; do
    blob="${blob%%</data>*}"
    names+=(${(f)"$(print -r -- "${blob}" | base64 -d 2>/dev/null | grep -aoE '[A-Za-z0-9]+(NerdFont|NF[MP]?)-[A-Za-z]+' || true)"})
  done
  print -rl -- "${(u)names[@]}"
}
