# step home_strays — $HOME holds none of the shell files these dotfiles do not use (~/.profile,
# ~/.bash_aliases). Installers (rustup, nvm, conda) write into them; what they wanted is ported by
# hand into the dotfiles' own files (a zsh plugin, PATH policy), then the stray is removed. So the
# fail is manual and there is no apply: removing one unread would drop what an installer asked for.
step::declare home_strays --group repo \
  --desc "\$HOME has none of the shell files these dotfiles do not use: ~/.profile, ~/.bash_aliases (port what they hold into ~/.config, then delete them)"
step::watches home_strays --none "reads only \$HOME's top level, which no repo file describes"

typeset -ga HOME_STRAYS=(.profile .bash_aliases)

check::home_strays() {
  local name
  local -a found=()
  for name in "${HOME_STRAYS[@]}"; do
    [[ -e "${HOME}/${name}" || -L "${HOME}/${name}" ]] && found+=("~/${name}")
  done
  if (( ${#found} )); then
    verdict fail stray_files -m \
      -d "files these dotfiles do not use: ${(j:, :)found}; an installer may have written to them" \
      -f "port what they hold into ~/.config (a zsh plugin, prepend_to_path), then: rm ${(j: :)found}"
    return 0
  fi
  verdict ok none -d "none of ${(j:, :)HOME_STRAYS} in \$HOME"
}
