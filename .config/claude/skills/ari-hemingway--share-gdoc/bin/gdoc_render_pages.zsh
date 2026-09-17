#!/usr/bin/env zsh
# Render every page of a Google Docs PDF export to PNG so a caller can inspect the layout
# (table wraps, mid-word breaks) that heights alone do not reveal. Uses PDFKit through `swift`,
# which ships with Xcode's command line tools; nothing to install with brew.
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Constants ---

readonly RENDERER="${SCRIPT_DIR}/gdoc_render_pages.swift"
readonly DEFAULT_SCALE="1.4"

# --- Prerequisites ---

#######################################
# Check that swift and the renderer source are present.
# Globals: RENDERER
# Returns: 1 if anything is missing
#######################################
check_prerequisites() {
  local missing=()
  command -v swift >/dev/null 2>&1 || missing+=("swift (Xcode command line tools)")
  [[ -f "${RENDERER}" ]] || missing+=("${RENDERER}")
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands or files | missing='${(j:, :)missing}'"
    return 1
  fi
}

# --- Help ---

help() {
  cat <<EOH
${c_green}gdoc_render_pages${c_rst} — render a PDF export to one PNG per page (PDFKit via swift)

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_render_pages.zsh --pdf FILE.pdf --out DIR [--scale N]

${c_bold}Options:${c_rst}
  --pdf FILE.pdf   PDF exported from Google Docs (required)
  --out DIR        Directory for page-N.png files; created if missing (required)
  --scale N        Render scale, 1.0 = 72 dpi (default ${DEFAULT_SCALE})
  -h, --help       Show this help

${c_bold}Output:${c_rst} one PNG path per page on stdout.
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local pdf="" out="" scale="${DEFAULT_SCALE}"
  while (( $# > 0 )); do case "${1}" in
    -h|--help) help; return 0 ;;
    --pdf)     pdf="${2:?--pdf requires a value}"; shift 2 ;;
    --out)     out="${2:?--out requires a value}"; shift 2 ;;
    --scale)   scale="${2:?--scale requires a value}"; shift 2 ;;
    -*)        log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)         log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  # === VALIDATE ===
  [[ -n "${pdf}" ]] || { log::err "Missing --pdf"; help; return 1; }
  [[ -f "${pdf}" ]] || { log::err "PDF not found | pdf='${pdf}'"; return 1; }
  [[ -n "${out}" ]] || { log::err "Missing --out"; help; return 1; }
  [[ "${scale}" =~ '^[0-9]+(\.[0-9]+)?$' ]] || { log::err "Invalid scale | scale='${scale}' expected='a positive number'"; return 1; }

  # === LOGIC ===
  local listing count
  listing="$(mktemp)"
  swift "${RENDERER}" "${pdf}" "${out}" "${scale}" > "${listing}"
  count="$(wc -l < "${listing}" | tr -d ' ')"
  cat "${listing}"
  log::ok "Rendered pages | pdf='${pdf}' out='${out}' pages='${count}' scale='${scale}'"
}

main "${@}"
