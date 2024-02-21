function www() {
  python3 -m http.server "${1:-8000}"
}

function browses() {
  _browse https "$@"
}
function browse() {
  _browse http "$@"
}
function _browse() {
  open "${1:-http}://localhost:${2:-8000}"
}

