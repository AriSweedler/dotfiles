function source_file() {
  local -r file="$1"

  # shellcheck disable=SC1090
  [[ -r "$file" ]] || return
  source "$file"
}

function source_file::timed() {
  local -r file="$1"

  local timer_s timer_e
  timer_s="$(gdate +'%s%N')"
  # shellcheck disable=SC1090
  [[ -r "$file" ]] || return
  source "$file"
  timer_e="$(gdate +'%s%N')"
  echo "$((timer_e-timer_s)) Loading | file='$file' elapsed=$((timer_e-timer_s))"
}

function source_zsh_dir() {
  local optional="false"
  while grep -q "^-" <<< "$1"; do
    case "$1" in
      --optional) optional="true"; shift ;;
    esac
  done

  local -r dir="$1"
  if ! [ -d "$dir" ]; then
    [ "$optional" = "true" ] && return 0
    log::err "'$dir' is not a directory"
    return 1
  fi

  for file in $(find "$dir" -name "*.zsh"); do
    source_file "$file"
  done

  for file in $(find "$dir" -name "*.sh"); do
    log::err "Not sourcing file '$file'"
  done
}

# Put a directory first on PATH, once: one already present moves to the front, so the policy
# below holds in a shell whose inherited PATH (tmux's, an editor's) had it elsewhere.
function prepend_to_path() {
  local -r add_me="$1"
  path=("${add_me}" "${(@)path:#${add_me}}")
}

source_file "${ZDOTDIR}/tab_completion.zsh"
# The plugins of both tiers, in the order a switch lists them (~/.config/dotfiles/nix/zsh-plugins.nix).
# A machine not yet on Nix has no list and scans the two plugin dirs instead; that fallback goes
# once every machine switches (beads-2ly.7.25).
if [[ -r "${ZDOTDIR}/plugins.list.zsh" ]]; then
  source "${ZDOTDIR}/plugins.list.zsh"
else
  source_zsh_dir "${ZDOTDIR}/plugins"
  source_zsh_dir --optional "${XDG_DATA_HOME}/zsh/plugins"
fi

# PATH policy for both dotfile tiers, after every plugin so nothing a plugin prepends (brew
# shellenv's Homebrew dirs, a company bin) lands ahead: this machine's local bins, then the
# shared bins, then everything else.
prepend_to_path "$HOME/.config/bin"
prepend_to_path "$HOME/.local/bin"
prepend_to_path "$XDG_DATA_HOME/bin"
