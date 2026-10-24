#!/usr/bin/env zsh
# Screenshot one figure: mount its spec alone in the hero slot of a scratch page under the
# repo's articles/, build it, render it headlessly from the local server, delete the page.
# A fragment deep link (#fig-x=state) on the full article screenshots blank in headless
# Chromium; one scratch page per figure is the recipe that works.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

readonly DEFAULT_REPO="${HOME}/Desktop/workspace/explainers"
readonly DEFAULT_PORT=8765

help() {
  cat <<EOF
${c_green}shot.zsh${c_rst} — screenshot one figure spec on a scratch page served from the explainers repo

${c_bold}Usage:${c_rst}
  zsh \$HOME/.claude/skills/ari-hemingway--structure-ciechanowski/bin/shot.zsh \\
      [--repo DIR] [--port N] [--state NAME] <fig-id> <spec.json> <W:H> <out.png>

${c_bold}Arguments:${c_rst}
  fig-id      the figure id, e.g. fig-sec
  spec.json   the figure spec to mount
  W:H         the aspect, e.g. 16:9
  out.png     where the screenshot goes

${c_bold}Options:${c_rst}
  --repo DIR   explainers repo (default: \$EXPLAINERS_REPO, then ${DEFAULT_REPO})
  --port N     port of the http.server already running at the repo root (default: \$SHOT_PORT or ${DEFAULT_PORT})
  --state NAME render a named notice state instead of the default
  -h, --help   show this help

${c_bold}Environment:${c_rst}
  CHROME_BIN   headless Chromium binary (default: newest playwright chrome-headless-shell)

Start the server once: cd <repo> && python3 -m http.server ${DEFAULT_PORT}
EOF
}

#######################################
# Find a headless Chromium binary.
# Globals: CHROME_BIN (optional)
# Returns: the path on stdout; exits 1 when none exists
#######################################
find_chrome() {
  if [[ -n "${CHROME_BIN:-}" ]]; then
    log::info "Using CHROME_BIN | CHROME_BIN='${CHROME_BIN}'"
    echo "${CHROME_BIN}"
    return
  fi
  local -a candidates
  candidates=("${HOME}"/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-*/chrome-headless-shell(N))
  if (( ${#candidates} == 0 )); then
    log::err "no headless Chromium found | hint='npx playwright install chromium or set CHROME_BIN'"
    exit 1
  fi
  echo "${candidates[-1]}"
}

main() {
  local repo="${EXPLAINERS_REPO:-${DEFAULT_REPO}}"
  local port="${SHOT_PORT:-${DEFAULT_PORT}}"
  local state_name=""
  while (( $# > 0 )); do
    case "${1}" in
      --repo) repo="${2}"; shift 2 ;;
      --port) port="${2}"; shift 2 ;;
      --state) state_name="${2}"; shift 2 ;;
      -h|--help) help; exit 0 ;;
      --*) log::err "unknown flag | flag='${1}'"; help; exit 1 ;;
      *) break ;;
    esac
  done
  if (( $# != 4 )); then
    log::err "expected four positional arguments | got=${#} expected='fig-id spec.json W:H out.png'"
    help
    exit 1
  fi
  local fid="${1}" spec="${2}" aspect="${3}" out="${4}"
  if [[ ! -f "${spec}" ]]; then
    log::err "spec missing | spec='${spec}'"
    exit 1
  fi
  if [[ ! -f "${repo}/template/article.html" ]]; then
    log::err "not an explainers repo | repo='${repo}'"
    exit 1
  fi
  if ! curl -fs -o /dev/null "http://127.0.0.1:${port}/" ; then
    log::err "no server at the repo root | url='http://127.0.0.1:${port}/' hint='cd ${repo} && python3 -m http.server ${port}'"
    exit 1
  fi
  local chrome
  chrome="$(find_chrome)"
  local dir="${repo}/articles/_shot-${fid}-$$"
  rm -rf "${dir}"
  mkdir -p "${dir}"
  trap 'rm -rf "${dir}"' EXIT INT TERM
  python3 "${SCRIPT_DIR}/scratch_page.py" --repo "${repo}" --out "${dir}/index.html" "${fid}=${spec}:${aspect}" >/dev/null
  node "${repo}/tools/explainers.cjs" build "${dir}/index.html" >/dev/null 2>&1 || log::warn "build reported errors; rendering anyway | page='${dir}/index.html'"
  local frag=""
  if [[ -n "${state_name}" ]]; then
    frag="#${fid}=${state_name}"
  fi
  mkdir -p "${out:h}"
  "${chrome}" --headless --no-sandbox --hide-scrollbars --window-size=1100,1000 --virtual-time-budget=4000 \
    --screenshot="${out}" "http://127.0.0.1:${port}/articles/_shot-${fid}-$$/index.html${frag}" 2>/dev/null
  if [[ ! -s "${out}" ]]; then
    log::err "no screenshot written | out='${out}' hint='is the spec valid and the server serving ${repo}?'"
    exit 1
  fi
  cat <<EOF
screenshot=${out}
EOF
}

main "${@}"
