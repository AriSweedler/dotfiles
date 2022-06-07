function init_groot() {
  local -r groot_root="/Users/arisweedler/devenv/groot"
  export PATH="$groot_root/bin:$PATH"
  # for a in $(compgen -G "$groot_root/autocomplete/*.bash"); do . "$a"; done
}
init_groot
