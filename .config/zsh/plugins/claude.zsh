# Old name kept as an alias; open_link is the opener.
function claude-link() {
  (( ${+functions[open_link]} )) || source "${HOME}/.config/zsh/plugins/open_link.zsh"
  open_link "$@"
}

function vi_::claude_settings_local() {
  local f=.claude/settings.local.json
  # Land on the last entry of .permissions.allow[] so a new one is easy to append.
  local line
  line=$(awk '
    /"allow"[[:space:]]*:[[:space:]]*\[/ {
      inblock = 1
      next
    }
    inblock && /^[[:space:]]*\]/ {
      print NR - 1
      exit
    }
  ' "$f" 2>/dev/null)
  "${EDITOR}" ${line:++$line} -c 'set foldlevel=99' "$f"
}
alias vi_cset=vi_::claude_settings_local

# Notification hook wiring is new-machine's claude_notifications step; the Monday
# launchd verify runs it in the background, so nothing here runs at shell startup.
function claude::hook::check() {
  new-machine check --only claude_notifications "$@"
}
function claude::hook::register() {
  new-machine apply claude_notifications "$@"
}
