function double_cd() {
  # First arg is required
  local target="${1:?You must set the first target for double_cd}"
  shift

  local action=dcd
  while (( $# > 0 )); do
    case "${1}"; in
      --list) action=list; shift;;
      *) break;;
    esac
  done

  "_dcd::action::${action}" "${target}" "$@"
}

function _dcd::action::list() (
  while (( $# > 0 )); do
    [ -d "$1" ] || break
    cd "$1" && shift
  done
  case $# in
    0) echo */ | tr -d '/';;
    1) echo *$1*/ | tr -d '/';;
    2) log::err "Too many arguments for _dcd::action::list"; return 1;;
  esac
)

function _dcd::action::dcd() {
  cd "${(j:/:)@}"
  b_echo "$(pwd)"
  ls -G

  # Rename the tmux window. Provide a default and allow user to override it
  local caller="${funcstack[3]}"
  # THe last arg is printed in the log
  if [ -n "$TMUX" ]; then
    if type -f "$caller::tmux_rename" &> /dev/null; then
      "$caller::tmux_rename" "$target"
    else
      tmux rename-window "${caller#c}: '${*:2}'"
    fi
  fi
}

function double_cd::generate() {
  local dcd_functions="${XDG_DATA_HOME}/zsh/functions"
  mkdir -p "${dcd_functions}"

  local dcd_completions="${XDG_DATA_HOME}/zsh/completions"
  mkdir -p "${dcd_completions}"

  local repo_suffix="otto/double_cd"
  local repo_base repository
  local y y_abs y_expand
  for repo_base in "${XDG_DATA_HOME}" "${XDG_CONFIG_HOME}"; do
    repository="${repo_base}/${repo_suffix}"

    for y_abs in $(find "${repository}" -type f); do
      y="${y_abs##*/}"
      y_expand="$(eval echo "$(cat "${y_abs}")")"

      # cX function
      cat << EOF > "${dcd_functions}/c$y"
if (( \$# == 0 )); then
  choice="\$( (ls '$y_expand'; echo ".") | fzf)"
  double_cd '$y_expand' "\${choice}"
  return
fi
double_cd '$y_expand' "\$@"
EOF

      # cX completion function
      cat << EOF > "${dcd_completions}/_c$y"
#compdef c$y

function _c$y() {
  local dir_list
  dir_list=(\$(double_cd "$y_expand" --list "\${words[@]:1}"))
  _wanted dirs expl '$y directories' compadd -a dir_list
}

compdef _c$y c$y
EOF
    done
  done
}
