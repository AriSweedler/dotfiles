# step tmux_server — the running tmux server is the tmux on PATH. A switch that moves tmux (brew
# to Nix, one store path to the next) leaves the old server running from the old binary; once
# that file is gone, macOS TCC denies ~/Desktop to every process in tmux. Restarting the server
# is a hand step: it ends every session, so the check never applies it.
step::declare tmux_server --group tools \
  --desc "the running tmux server runs the tmux on PATH, not a binary a switch replaced or removed"
step::watches tmux_server --none "reads the running tmux server and the tmux on PATH, no repo file"

check::tmux_server() {
  local bin="${commands[tmux]:-}"
  if [[ -z "${bin}" ]]; then
    verdict skip no_tmux -d "tmux not on PATH"
    return 0
  fi
  local pid
  pid="$("${bin}" display-message -p '#{pid}' 2>/dev/null || true)"
  if [[ "${pid}" != <-> ]]; then
    verdict skip no_server -d "no tmux server running | tmux='${bin:A}'"
    return 0
  fi
  local fix="restart tmux: ${bin:t} kill-server, then start it again"
  # The first txt entry lsof reports for a process is its executable.
  local -a names=(${(M)${(f)"$(lsof -a -p "${pid}" -d txt -Fn 2>/dev/null || true)"}:#n*})
  local server="${${names[1]:-}#n}"
  if [[ -z "${server}" ]]; then
    verdict warn server_unread -d "lsof read no executable for the tmux server | pid='${pid}'"
    return 0
  fi
  if [[ ! -e "${server}" ]]; then
    verdict fail server_binary_gone -m -d "the tmux server runs from a deleted binary | pid='${pid}' server='${server}' path='${bin:A}'" -f "${fix}"
    return 0
  fi
  if [[ "${server:A}" != "${bin:A}" ]]; then
    verdict warn server_stale -m -d "the tmux server runs another tmux than PATH's | pid='${pid}' server='${server}' path='${bin:A}'" -f "${fix}"
    return 0
  fi
  verdict ok server_current -d "pid='${pid}' tmux='${bin:A}'"
}
