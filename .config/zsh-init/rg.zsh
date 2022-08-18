function vimrg() {
  # After you run a command like 'rg "XYZ"' maybe you want to edit all the
  # files that contain this. So then you should run 'vimrg !!'.

  # Exit early if necessary
  if [ "$1" != "rg" ]; then
    echo "Only forward '!!' to this function if it was an 'rg' command"
    return 1
  fi
  shift

  # Open all the files that rg finds. Additionaly highlight the pattern in vim, if possible.
  vim -c":lgrep '$*'" -c"/$*" $(rg --files-with-matches "$@")
}
