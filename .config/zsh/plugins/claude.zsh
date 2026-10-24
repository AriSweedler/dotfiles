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

# Notification hook wiring is the dotfiles' claude_notifications step; the Monday
# launchd verify runs it in the background, so nothing here runs at shell startup.
function claude::hook::check() {
  dotfiles healthcheck --only claude_notifications "$@"
}
function claude::hook::register() {
  dotfiles apply claude_notifications "$@"
}

# Claude Code prints "Resume this session with: claude --resume <uuid>" on exit. Pull the
# last such id out of a text stream. Pure stdin → stdout; rc 1 when there is none.
function claude::resume_id_from_text() {
  local id
  id=$(grep -oE 'claude --resume [0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}' | tail -1 | awk '{print $3}')
  [[ -n "$id" ]] || return 1
  print -r -- "$id"
}

# ~/.claude/projects/<slug>: the absolute path with every / and . turned into -.
function claude::project_slug() {
  local p="${1:-$PWD}"
  p="${p//\//-}"
  print -r -- "${p//./-}"
}

function claude::newest_session_for_cwd() {
  local dir="${HOME}/.claude/projects/$(claude::project_slug)"
  local -a files=("${dir}"/*.jsonl(Nom))
  (( ${#files} )) || return 1
  print -r -- "${files[1]:t:r}"
}

# reclaude — resume the Claude session this pane just left. The id comes from the pane's
# own scrollback (the same capture tcap reads, never the clipboard), else the newest
# session file for this directory. `-n` prints the command instead of running it;
# anything else is passed through to claude.
function claude::resume_recent() {
  local dry_run=false
  [[ "${1:-}" == "-n" ]] && { dry_run=true; shift; }
  local id source
  if [[ -n "$TMUX" ]]; then
    id=$(tmux capture-pane -p -J -S - | claude::resume_id_from_text) && source="scrollback"
  fi
  if [[ -z "$id" ]]; then
    id=$(claude::newest_session_for_cwd) && source="newest session for $(claude::project_slug)"
  fi
  if [[ -z "$id" ]]; then
    log::err "No resumable session found | tmux='${TMUX:+yes}' cwd='${PWD}'"
    return 1
  fi
  log::info "Resuming | id='${id}' source='${source}'"
  if $dry_run; then
    print -r -- "claude --resume ${id} $*"
    return 0
  fi
  claude --resume "$id" "$@"
}
alias reclaude='claude::resume_recent'
