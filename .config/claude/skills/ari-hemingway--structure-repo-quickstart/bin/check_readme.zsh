#!/usr/bin/env zsh
# check_readme.zsh — the mechanical gate of `/ari-hemingway--structure-repo-quickstart`: word cap, an early
# run block, links and images that resolve, no placeholders inside fenced blocks, no scar words,
# every docs page linked. Read-only; exits 1 on any FAIL.

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

readonly WORD_CAP=500
readonly FIRST_BLOCK_LINE_CAP=40
readonly SCAR_WORDS=("previously" "used to" "no longer" "legacy" "renamed from" "formerly" "deprecated" "changelog")
readonly EMAIL_RE='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
readonly SKIP_DIRS=(".git" "node_modules" ".venv" "data" "smoke")

# --- Help ---

help() {
  cat <<EOH
${c_green}check_readme${c_rst} — mechanical check of a quick-start README

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--structure-repo-quickstart/bin/check_readme.zsh --repo DIR

${c_bold}Options:${c_rst}
  --repo DIR    repository root holding README.md (default: current directory)
  --cap N       word cap (default: ${WORD_CAP})
  -h, --help    Show this help

${c_bold}Checks:${c_rst} word count, first fenced block line, relative links and images, placeholders in
fenced blocks, scar words, docs/*.md pages missing from "## Docs". Exit 1 on any FAIL.
EOH
}

#######################################
# Count words outside fenced blocks.
# Arguments: readme path
#######################################
prose_words() {
  awk 'BEGIN{f=0} /^```/{f=!f; next} !f{print}' "${1}" | wc -w | tr -d ' '
}

#######################################
# Line number of the first fenced block, or 0.
#######################################
first_block_line() {
  awk '/^```/{print NR; exit}' "${1}"
}

#######################################
# Relative link and image targets that do not exist. One per line.
# Arguments: readme path, repo dir
#######################################
broken_targets() {
  local readme="${1}" dir="${2}" target
  { grep -oE '\]\([^)#]+' "${readme}" | awk '{print substr($0,3)}' || true;
    grep -oE 'src="[^"]+"' "${readme}" | awk -F'"' '{print $2}' || true; } \
  | awk '!/^https?:\/\// && !/^mailto:/' | sort -u | while IFS= read -r target; do
      [[ -e "${dir}/${target}" ]] || print -- "${target}"
    done
}

#######################################
# Placeholders (<like-this>, {like-this}) in the first fenced block, the run block, and a leading
# $ prompt in any block. Later blocks may hold route tables, where <id> is the honest notation.
#######################################
block_placeholders() {
  awk 'BEGIN{f=0; n=0} /^```/{f=!f; if(f) n++; next}
       f && n==1 && (/<[a-zA-Z][^>]*>/ || /\{[a-zA-Z][^}]*\}/){print NR": "$0}
       f && /^\$ /{print NR": "$0}' "${1}"
}

#######################################
# README.md#anchor references the code emits whose anchor is not a heading of the README.
# Arguments: repo dir, readme path
#######################################
dangling_anchors() {
  local dir="${1}" readme="${2}" anchor slugs excl=()
  local d; for d in "${SKIP_DIRS[@]}"; do excl+=(--exclude-dir="${d}"); done
  slugs="$(awk '/^#+ /{sub(/^#+ /,""); s=tolower($0); gsub(/[^a-z0-9 -]/,"",s); gsub(/ /,"-",s); print s}' "${readme}")"
  local refs; refs="$(grep -rhoE 'README\.md#[A-Za-z0-9_-]+' "${dir}" "${excl[@]}" 2>/dev/null || true)"
  [[ -n "${refs}" ]] || return 0
  print -- "${refs}" | awk -F'#' '{print $2}' | sort -u \
  | while IFS= read -r anchor; do
      print -- "${slugs}" | grep -qx -- "${anchor}" || print -- "${anchor}"
    done
}

#######################################
# Email addresses outside fenced blocks (a WARN: personal data in a public README).
#######################################
email_lines() {
  awk 'BEGIN{f=0} /^```/{f=!f; next} !f{print NR": "$0}' "${1}" | grep -E "${EMAIL_RE}" || true
}

#######################################
# Scar words outside fenced blocks, case-insensitive.
#######################################
scar_lines() {
  local readme="${1}" word
  for word in "${SCAR_WORDS[@]}"; do
    awk -v w="${word}" 'BEGIN{f=0; IGNORECASE=1} /^```/{f=!f; next} !f && tolower($0) ~ w {print NR": "$0}' "${readme}"
  done
}

#######################################
# docs/*.md pages not linked anywhere in the README.
#######################################
unlinked_docs() {
  local dir="${1}" readme="${2}" page
  [[ -d "${dir}/docs" ]] || return 0
  for page in "${dir}"/docs/*.md(N); do
    grep -q "docs/${page:t}" "${readme}" || print -- "docs/${page:t}"
  done
}

main() {
  local repo_dir="." cap="${WORD_CAP}"
  while (( $# > 0 )); do case "${1}" in
    -h|--help) help; return 0 ;;
    --repo) repo_dir="${2:?--repo requires a value}"; shift 2 ;;
    --cap)  cap="${2:?--cap requires a value}"; shift 2 ;;
    -*) log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)  log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  local readme="${repo_dir}/README.md"
  if [[ ! -f "${readme}" ]]; then
    log::err "No README | readme='${readme}'"
    return 1
  fi

  local fails=0 words line out
  words="$(prose_words "${readme}")"
  if (( words > cap )); then print "FAIL words      ${words} > ${cap}"; fails=$((fails+1)); else print "PASS words      ${words} (cap ${cap})"; fi

  line="$(first_block_line "${readme}")"
  if [[ -z "${line}" ]] || (( line > FIRST_BLOCK_LINE_CAP )); then print "FAIL run-block  first fenced block at line ${line:-none} (cap ${FIRST_BLOCK_LINE_CAP})"; fails=$((fails+1)); else print "PASS run-block  first fenced block at line ${line}"; fi

  out="$(broken_targets "${readme}" "${repo_dir}")"
  if [[ -n "${out}" ]]; then print "FAIL links      missing: ${(j:, :)${(f)out}}"; fails=$((fails+1)); else print "PASS links      every relative link and image resolves"; fi

  out="$(block_placeholders "${readme}")"
  if [[ -n "${out}" ]]; then print "FAIL blocks     placeholder or prompt inside a fenced block:"; print -- "${out}" | awk '{print "  -> "$0}'; fails=$((fails+1)); else print "PASS blocks     every command copy-pasteable"; fi

  out="$(scar_lines "${readme}")"
  if [[ -n "${out}" ]]; then print "FAIL scars      history words:"; print -- "${out}" | awk '{print "  -> "$0}'; fails=$((fails+1)); else print "PASS scars      no history words"; fi

  out="$(unlinked_docs "${repo_dir}" "${readme}")"
  if [[ -n "${out}" ]]; then print "FAIL docs       not linked from the README: ${(j:, :)${(f)out}}"; fails=$((fails+1)); else print "PASS docs       every docs/*.md page is linked"; fi

  out="$(dangling_anchors "${repo_dir}" "${readme}")"
  if [[ -n "${out}" ]]; then print "FAIL anchors    code points at README.md#… that is no heading: ${(j:, :)${(f)out}}"; fails=$((fails+1)); else print "PASS anchors    every README.md# anchor the code emits is a heading"; fi

  out="$(email_lines "${readme}")"
  if [[ -n "${out}" ]]; then print "WARN personal   email address in the README (fine in a private repo):"; print -- "${out}" | awk '{print "  -> "$0}'; else print "PASS personal   no email address"; fi

  if (( fails > 0 )); then
    log::err "README check failed | fails='${fails}'"
    return 1
  fi
  log::info "README check passed | words='${words}'"
}

main "${@}"
