#!/usr/bin/env zsh
# Share one explainer article on explainers.sweedler.com: add or update its front-page card
# in index.html (title and description from the article head, figure count, reading time at
# 230 wpm, three palette swatches whose tokens join the front page :root when missing), render
# its link-preview card (tools/og-image.mjs), run the CLI gates and npm test, commit in the
# house shape, push main with the token of the account that owns the remote (gh auth token -u
# OWNER, never the ambient GITHUB_TOKEN), watch the Pages run for the pushed SHA, then open the
# short URL. Dry-run by default: prints the card diff, the commit message and the push target.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/run_with_timeout.zsh"

# --- Environment variables ---

# The site the Worker serves; the short URL is ${SITE_URL}/<slug>/.
readonly SITE_URL="${EXPLAINERS_SITE_URL:-https://explainers.sweedler.com}"

# --- Constants ---

readonly WORDS_PER_MINUTE=230
readonly SWATCH_COUNT=3
readonly BUDGET="170k"
readonly BRANCH="main"
readonly WORKFLOW_FILE="pages.yml"
readonly CO_AUTHOR="Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
readonly FETCH_TIMEOUT=30
readonly OG_TIMEOUT=180
readonly TEST_TIMEOUT=600
readonly RUN_APPEAR_TIMEOUT=180
readonly RUN_POLL_SECS=5
readonly RUN_WATCH_TIMEOUT=900

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
  local cmd
  local missing=()
  for cmd in git gh node npm awk jq python3; do
    command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
  done
  if (( ${#missing} > 0 )); then
    log::err "Missing required commands | missing='${(j:, :)missing}'"
    return 1
  fi
}

#######################################
# Run a mutating command, or log it under dry-run.
# Globals: DRY_RUN
# Arguments: the command and its args
#######################################
run_mut() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    log::info "would run | cmd='$*'"
    return 0
  fi
  run_cmd "$@"
}

########################################################################
# Article head
########################################################################

#######################################
# The article's <title> text.
# Arguments: $1 - article index.html
#######################################
article_title() {
  awk 'match($0, /<title>[^<]*<\/title>/) { print substr($0, RSTART + 7, RLENGTH - 15); exit }' "${1}"
}

#######################################
# The article's <meta name="description"> content.
# Arguments: $1 - article index.html
#######################################
article_description() {
  awk '/<meta name="description"/ {
    if (match($0, /content="[^"]*"/)) { print substr($0, RSTART + 9, RLENGTH - 10); exit }
  }' "${1}"
}

#######################################
# The card's description: the meta description without a final "N interactive figures." sentence
# (N spelled out or in digits; only the last sentence is stripped).
# sentence, since the card prints the count in its meta row.
# Arguments: $1 - meta description
#######################################
card_description() {
  local description="${1}"
  local stripped
  stripped="$(print -r -- "${description}" | awk '{ sub(/ [A-Za-z0-9-]+ interactive figures?\.$/, ""); print }')"
  if [[ "${stripped}" != "${description}" ]]; then
    log::info "Dropped the figure-count sentence from the card description | dropped='${description#${stripped} }'"
  fi
  print -r -- "${stripped}"
}

#######################################
# How many interactive figures the article holds.
# Arguments: $1 - article index.html
#######################################
figure_count() {
  grep -c '<figure class="x-fig"' "${1}" || true
}

#######################################
# Count the words a reader reads linearly: everything outside <script>, <style>, <svg>,
# <math> and <details> blocks (the glossary is collapsed; the reader opens it on purpose),
# with tags and entities removed.
# Arguments: $1 - article index.html
#######################################
word_count() {
  awk '
    {
      line = $0; out = ""
      while (length(line) > 0) {
        if (block != "") {
          close_tag = "</" block ">"
          p = index(line, close_tag)
          if (p == 0) { line = ""; break }
          line = substr(line, p + length(close_tag)); block = ""
          continue
        }
        best = 0; which = ""
        n = split("script style svg math details", names, " ")
        for (i = 1; i <= n; i++) {
          p = index(line, "<" names[i])
          if (p > 0 && (best == 0 || p < best)) { best = p; which = names[i] }
        }
        if (best == 0) { out = out " " line; line = ""; break }
        out = out " " substr(line, 1, best - 1)
        line = substr(line, best); block = which
      }
      gsub(/<[^>]*>/, " ", out)
      gsub(/&[a-zA-Z#0-9]+;/, " ", out)
      words += split(out, w, " ")
    }
    END { print words + 0 }
  ' "${1}"
}

#######################################
# Reading time in whole minutes at WORDS_PER_MINUTE, at least 1.
# Arguments: $1 - word count
#######################################
reading_minutes() {
  local words="${1}"
  local minutes=$(( (words + WORDS_PER_MINUTE / 2) / WORDS_PER_MINUTE ))
  (( minutes < 1 )) && minutes=1
  echo "${minutes}"
}

#######################################
# The palette tokens of a page's first <style> :root block, one "name<TAB>value" per line,
# in declaration order.
# Arguments: $1 - an index.html
#######################################
palette_tokens() {
  awk '
    /<\/style>/ { exit }
    /:root[ \t]*\{/ { in_root = 1; next }
    in_root && /\}/ { in_root = 0; exit }
    in_root && match($0, /--c-[a-z0-9-]+[ \t]*:/) {
      name = substr($0, RSTART + 4, RLENGTH - 4); sub(/[ \t]*:$/, "", name)
      rest = substr($0, RSTART + RLENGTH); sub(/^[ \t]+/, "", rest); sub(/;.*$/, "", rest)
      print name "\t" rest
    }
  ' "${1}"
}

########################################################################
# Front page
########################################################################

#######################################
# Whether the front page already carries a card for the slug.
# Arguments: $1 - front page index.html, $2 - slug
# Outputs: "insert" or "update"
#######################################
card_action() {
  local front="${1}" slug="${2}"
  if grep -q "href=\"articles/${slug}/\"" "${front}"; then
    log::info "Front page already has a card; it is replaced in place | slug='${slug}' action='update'"
    echo "update"
    return
  fi
  log::info "Front page has no card yet; one is inserted at the top of the list | slug='${slug}' action='insert'"
  echo "insert"
}

#######################################
# Render the card in the house markup.
# Arguments: $1 - slug, $2 - title, $3 - description, $4 - figure count, $5 - minutes,
#            $6.. - swatch token names
#######################################
render_card() {
  local slug="${1}" title="${2}" description="${3}" figures="${4}" minutes="${5}"
  shift 5
  local swatches="" token
  for token in "${@}"; do
    swatches+="<i style=\"background: var(--c-${token})\"></i>"
  done
  local noun="figures"
  (( figures == 1 )) && noun="figure"
  cat <<EOF
  <li><a class="x-card" href="articles/${slug}/">
    <h2>${title}</h2>
    <p>${description}</p>
    <p class="x-meta"><span class="x-swatches" aria-hidden="true">${swatches}</span><span>${figures} interactive ${noun}</span><span class="x-dot"></span><span>${minutes} min</span></p>
  </a></li>
EOF
}

#######################################
# Decide which swatch tokens the front page :root lacks; warn when a shared name carries a
# different value (the front page keeps its own).
# Arguments: $1 - article tokens file, $2 - front tokens file, $3.. - swatch names
# Outputs: "--c-name: value;" lines for the missing tokens
#######################################
missing_tokens() {
  local article_tokens="${1}" front_tokens="${2}"
  shift 2
  local name article_value front_value
  for name in "${@}"; do
    article_value="$(awk -F '\t' -v n="${name}" '$1 == n { print $2; exit }' "${article_tokens}")"
    front_value="$(awk -F '\t' -v n="${name}" '$1 == n { print $2; exit }' "${front_tokens}")"
    if [[ -z "${front_value}" ]]; then
      log::info "Palette token added to the front page | token='--c-${name}' value='${article_value}'"
      print -r -- "    --c-${name}: ${article_value};"
      continue
    fi
    if [[ "${front_value}" != "${article_value}" ]]; then
      log::warn "Palette token differs between article and front page; front page kept | token='--c-${name}' article='${article_value}' front='${front_value}'"
      continue
    fi
    log::debug "Palette token already on the front page | token='--c-${name}'"
  done
}

#######################################
# Write the new front page: the card inserted after <ul class="x-index"> or replacing the
# existing <li> for the slug, and the missing tokens before the :root block's closing brace.
# Arguments: $1 - front page, $2 - action, $3 - slug, $4 - card file, $5 - tokens file, $6 - output
#######################################
write_front_page() {
  local front="${1}" action="${2}" slug="${3}" card_file="${4}" tokens_file="${5}" out="${6}"
  awk -v action="${action}" -v slug="${slug}" -v card_file="${card_file}" -v tokens_file="${tokens_file}" '
    function emit_file(file,   line) { while ((getline line < file) > 0) print line; close(file) }
    !style_done && /:root[ \t]*\{/ { in_root = 1 }
    !style_done && in_root && /^[ \t]*\}/ { emit_file(tokens_file); in_root = 0; style_done = 1 }
    skipping { if (index($0, "</a></li>") > 0) skipping = 0; next }
    index($0, "<li><a class=\"x-card\" href=\"articles/" slug "/\">") > 0 {
      emit_file(card_file); skipping = 1; replaced = 1; next
    }
    { print }
    action == "insert" && !inserted && index($0, "<ul class=\"x-index\">") > 0 { emit_file(card_file); inserted = 1 }
    END {
      if (action == "insert" && !inserted) { print "no <ul class=\"x-index\"> in the front page" > "/dev/stderr"; exit 1 }
      if (action == "update" && !replaced) { print "card for " slug " not found" > "/dev/stderr"; exit 1 }
      if (skipping) { print "card for " slug " has no closing </a></li>; the front page would be truncated" > "/dev/stderr"; exit 1 }
    }
  ' "${front}" > "${out}"
}

#######################################
# Give the front page's stylesheet link the ?v= its hash implies (the first ten
# base64 characters, URL-safe), the same rule `explainers build` applies to the
# articles: the CDN caches dist/ for four hours and HTML for ten minutes, so an
# unversioned link pairs a new page with a cached old stylesheet.
# Arguments: $1 - repo, $2 - front page (edited in place)
#######################################
version_front_stylesheet() {
  local repo="${1}" front="${2}" version
  version="$(python3 - "${repo}/dist/integrity.json" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))['dist/explainers.v1.css']
print(h.split('-', 1)[1][:10].replace('+', '-').replace('/', '_'))
PY
)" || return 1
  sed -i '' "s|href=\"dist/explainers.v1.css[^\"]*\"|href=\"dist/explainers.v1.css?v=${version}\"|" "${front}"
}

########################################################################
# Gates, commit, push, deploy
########################################################################

#######################################
# The read-only CLI gates: validate (with the byte budget), states, budget.
# Arguments: $1 - repo, $2 - article index.html
#######################################
run_read_gates() {
  local repo="${1}" html="${2}"
  local cli="${repo}/tools/explainers.cjs"
  run_cmd node "${cli}" validate "${html}" --budget "${BUDGET}" >&2 || return 1
  run_cmd node "${cli}" states "${html}" >/dev/null || return 1
  run_cmd node "${cli}" budget "${html}" --budget "${BUDGET}" >&2 || return 1
}

#######################################
# Render the article's link-preview card, bounded.
# Arguments: $1 - repo, $2 - article index.html
#######################################
render_og_image() {
  local repo="${1}" html="${2}"
  local err_file exit_code=0
  err_file="$(mktemp)"
  log::info "Rendering the link-preview card | html='${html}'"
  run_with_timeout "${OG_TIMEOUT}" "${err_file}" node "${repo}/tools/og-image.mjs" "${html}" || exit_code=$?
  if (( exit_code != 0 )); then
    log::ERR "$(cat "${err_file}")"
    log::err "og-image failed | rc='${exit_code}' fix='install Playwright chrome-headless-shell or set EXPLAINERS_HEADLESS_SHELL'"
    return 1
  fi
}

#######################################
# npm test, bounded.
# Arguments: $1 - repo
#######################################
run_tests() {
  local repo="${1}"
  local err_file exit_code=0
  err_file="$(mktemp)"
  log::info "Running the test suite | repo='${repo}'"
  (cd "${repo}" && run_with_timeout "${TEST_TIMEOUT}" "${err_file}" npm test >/dev/null) || exit_code=$?
  if (( exit_code != 0 )); then
    log::ERR "$(tail -n 40 "${err_file}")"
    log::err "npm test failed | rc='${exit_code}'"
    return 1
  fi
  log::ok "Tests pass"
}

#######################################
# The commit subject in the house shape, unless --message gave one.
# Arguments: $1 - override, $2 - action, $3 - slug, $4 - title, $5 - figure count
#######################################
commit_subject() {
  local override="${1}" action="${2}" slug="${3}" title="${4}" figures="${5}"
  if [[ -n "${override}" ]]; then
    log::info "Commit subject from --message | subject='${override}'"
    echo "${override}"
    return
  fi
  if [[ "${action}" == "insert" ]]; then
    echo "articles/${slug}: ${title}, ${figures} figures"
    return
  fi
  echo "articles/${slug}: front-page card and link preview refreshed"
}

#######################################
# Parse "owner/repo" out of an https or ssh GitHub remote URL.
# Arguments: $1 - remote URL
# Returns: 1 when the URL is not a GitHub remote
#######################################
owner_repo_from() {
  local url="${1}"
  url="${url%.git}"
  url="${url%/}"
  case "${url}" in
    https://github.com/*) echo "${url#https://github.com/}" ;;
    git@github.com:*)     echo "${url#git@github.com:}" ;;
    ssh://git@github.com/*) echo "${url#ssh://git@github.com/}" ;;
    *) log::err "Remote is not a GitHub URL | url='${url}'"; return 1 ;;
  esac
}

#######################################
# Push main with a one-shot credential helper carrying the owner's gh token. The ambient
# GITHUB_TOKEN is never consulted.
# Arguments: $1 - repo, $2 - owner, $3 - token
#######################################
push_as_owner() {
  local repo="${1}" owner="${2}" token="${3}"
  log::info "Pushing | remote='origin' branch='${BRANCH}' as='${owner}' helper='one-shot, gh auth token -u ${owner}'"
  TOKEN="${token}" GIT_TERMINAL_PROMPT=0 git -C "${repo}" \
    -c credential.helper= \
    -c "credential.helper=!f() { echo username=${owner}; echo password=\$TOKEN; }; f" \
    push origin "${BRANCH}"
}

#######################################
# Wait for the Pages run of a SHA to appear, then watch it to completion.
# Globals: GH_TOKEN (set by the caller to the owner's token)
# Arguments: $1 - owner/repo, $2 - sha
# Outputs: the run id on stdout
#######################################
watch_pages_run() {
  local owner_repo="${1}" sha="${2}"
  local run_id="" waited=0
  log::info "Waiting for the Pages run | workflow='${WORKFLOW_FILE}' sha='${sha}'"
  while [[ -z "${run_id}" ]]; do
    run_id="$(gh run list -R "${owner_repo}" --workflow "${WORKFLOW_FILE}" --limit 20 --json databaseId,headSha \
      | jq -r --arg sha "${sha}" '[.[] | select(.headSha == $sha)][0].databaseId // empty')"
    [[ -n "${run_id}" ]] && break
    if (( waited >= RUN_APPEAR_TIMEOUT )); then
      log::err "No Pages run for the pushed SHA | sha='${sha}' waited_secs='${waited}' fix='gh run list -R ${owner_repo} --workflow ${WORKFLOW_FILE}'"
      return 1
    fi
    sleep "${RUN_POLL_SECS}"
    waited=$(( waited + RUN_POLL_SECS ))
  done
  log::info "Pages run found | run_id='${run_id}' url='https://github.com/${owner_repo}/actions/runs/${run_id}'"
  local err_file exit_code=0
  err_file="$(mktemp)"
  run_with_timeout "${RUN_WATCH_TIMEOUT}" "${err_file}" gh run watch -R "${owner_repo}" "${run_id}" --exit-status --interval 10 --compact >&2 || exit_code=$?
  if (( exit_code != 0 )); then
    log::ERR "$(tail -n 20 "${err_file}")"
    log::err "Pages run did not succeed | run_id='${run_id}' rc='${exit_code}' url='https://github.com/${owner_repo}/actions/runs/${run_id}'"
    return 1
  fi
  log::ok "Pages run succeeded | run_id='${run_id}'"
  echo "${run_id}"
}

#######################################
# Open the short URL with the system opener, unless --no-open.
# Arguments: $1 - url, $2 - no_open
#######################################
open_url() {
  local url="${1}" no_open="${2}"
  if [[ "${no_open}" == "true" ]]; then
    log::info "Not opening; the caller opens it | url='${url}'"
    return 0
  fi
  if ! command -v open >/dev/null 2>&1; then
    log::warn "No opener on this platform | url='${url}'"
    return 0
  fi
  run_mut open "${url}"
}

# --- Help ---

help() {
  cat <<EOH
${c_green}share${c_rst} — publish one explainer article: front-page card, link preview, gates, commit, push, Pages run, open

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-hemingway--share-explainer/bin/share.zsh --article articles/<slug> [OPTIONS]

${c_bold}Options:${c_rst}
  --article DIR    The article directory, articles/<slug> inside the explainers repo (required)
  --message TEXT   Commit subject; default is the house shape (articles/<slug>: <title>, <n> figures)
  --apply          Do it: build, og-image, gates, npm test, commit, push, watch, open
  --no-open        Print the short URL instead of opening it (the caller opens it, e.g. with Chrome)
  --verbose        Enable debug logging
  -h, --help       Show this help

${c_bold}Dry run (default):${c_rst} runs the read-only gates (validate, states, budget), prints the card as a
diff against index.html, the commit message, what git would stage, and the push target (remote,
owner, the gh account whose token would be used). Nothing is written, committed or pushed.

${c_bold}Environment:${c_rst}
  EXPLAINERS_SITE_URL  The short-URL origin (default https://explainers.sweedler.com)
  GITHUB_TOKEN         Ignored for the push and the run watch; the token comes from gh auth token -u <owner>

${c_bold}Output:${c_rst} key=value lines on stdout: slug, action (insert|update), figures, minutes, sha, run_id, url.
EOH
}

# --- Main ---

main() {
  check_prerequisites || exit 1

  # === PARSE ===
  local article="" message="" apply=false no_open=false verbose=false
  while (( $# > 0 )); do case "${1}" in
    -h|--help)  help; return 0 ;;
    --article)  article="${2:?--article requires a value}"; shift 2 ;;
    --message)  message="${2:?--message requires a value}"; shift 2 ;;
    --apply)    apply=true; shift ;;
    --no-open)  no_open=true; shift ;;
    --verbose)  verbose=true; shift ;;
    -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
    *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
  esac; done

  export VERBOSE="${verbose}"
  if [[ "${apply}" == "true" ]]; then DRY_RUN=false; else DRY_RUN=true; fi
  typeset -g DRY_RUN

  # === MASSAGE ===
  [[ -n "${article}" ]] && article="${article:A}"
  article="${article%/}"
  local slug="${article:t}"
  local html="${article}/index.html"

  # === VALIDATE ===
  [[ -n "${article}" ]] || { log::err "Missing --article"; help; return 1; }
  [[ -f "${html}" ]] || { log::err "Article not found | html='${html}'"; return 1; }
  local repo
  repo="$(git -C "${article}" rev-parse --show-toplevel 2>/dev/null)" || { log::err "Article is not inside a git repo | article='${article}'"; return 1; }
  [[ "${article}" == "${repo}/articles/${slug}" ]] || { log::err "Article must be <repo>/articles/<slug> | article='${article}' repo='${repo}'"; return 1; }
  local front="${repo}/index.html"
  local file
  for file in "${front}" "${repo}/tools/explainers.cjs" "${repo}/tools/og-image.mjs" "${repo}/.github/workflows/${WORKFLOW_FILE}"; do
    [[ -f "${file}" ]] || { log::err "Not an explainers repo; file missing | file='${file}'"; return 1; }
  done
  local branch
  branch="$(git -C "${repo}" symbolic-ref --short HEAD)"
  [[ "${branch}" == "${BRANCH}" ]] || { log::err "Pages deploys only main; check it out first | branch='${branch}' expected='${BRANCH}'"; return 1; }

  local remote_url owner_repo owner
  remote_url="$(git -C "${repo}" remote get-url origin)"
  owner_repo="$(owner_repo_from "${remote_url}")" || return 1
  owner="${owner_repo%%/*}"
  [[ "${remote_url}" == https://* ]] || { log::err "The one-shot credential helper needs an https remote | url='${remote_url}'"; return 1; }
  local token
  if ! token="$(gh auth token -u "${owner}" 2>/dev/null)"; then
    log::err "gh has no login for the remote's owner | owner='${owner}' fix='gh auth login -u ${owner}' accounts='$(gh auth status 2>&1 | awk '/Logged in to/ {print $(NF-1)}' | paste -sd, -)'"
    return 1
  fi
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    log::info "GITHUB_TOKEN is set in the env and ignored; pushing as the remote owner | owner='${owner}'"
  fi
  local url="${SITE_URL}/${slug}/"

  # === LOGIC ===
  local work
  work="$(mktemp -d /tmp/share_explainer.XXXXXX)"
  log::info "Sharing | slug='${slug}' repo='${repo}' dry_run='${DRY_RUN}' work='${work}'"

  # The article head feeds the card.
  local title description figures words minutes
  title="$(article_title "${html}")"
  [[ -n "${title}" ]] || { log::err "Article has no <title> | html='${html}'"; return 1; }
  description="$(card_description "$(article_description "${html}")")"
  [[ -n "${description}" ]] || { log::err "Article has no meta description | html='${html}'"; return 1; }
  figures="$(figure_count "${html}")"
  (( figures > 0 )) || { log::err "Article has no <figure class=\"x-fig\"> | html='${html}'"; return 1; }
  words="$(word_count "${html}")"
  minutes="$(reading_minutes "${words}")"
  log::info "Article head | title='${title}' figures='${figures}' words='${words}' minutes='${minutes}' wpm='${WORDS_PER_MINUTE}'"

  palette_tokens "${html}" > "${work}/article_tokens.tsv"
  palette_tokens "${front}" > "${work}/front_tokens.tsv"
  local -a swatches
  swatches=("${(@f)$(awk -F '\t' '{ print $1 }' "${work}/article_tokens.tsv" | head -n "${SWATCH_COUNT}")}")
  (( ${#swatches} > 0 )) || { log::err "Article :root declares no --c- tokens | html='${html}'"; return 1; }
  log::info "Swatches | tokens='${(j: :)swatches}'"
  missing_tokens "${work}/article_tokens.tsv" "${work}/front_tokens.tsv" "${swatches[@]}" > "${work}/tokens.css"

  local action
  action="$(card_action "${front}" "${slug}")"
  render_card "${slug}" "${title}" "${description}" "${figures}" "${minutes}" "${swatches[@]}" > "${work}/card.html"
  write_front_page "${front}" "${action}" "${slug}" "${work}/card.html" "${work}/tokens.css" "${work}/index.html" || return 1
  version_front_stylesheet "${repo}" "${work}/index.html" || return 1

  local diff_out
  diff_out="$(diff -u "${front}" "${work}/index.html" || true)"
  if [[ -z "${diff_out}" ]]; then
    log::info "Front page already carries this card; no change | slug='${slug}'"
  else
    log::INFO "${diff_out}"
  fi

  local subject
  subject="$(commit_subject "${message}" "${action}" "${slug}" "${title}" "${figures}")"
  local noun="figures"
  (( figures == 1 )) && noun="figure"
  cat > "${work}/commit.txt" <<EOF
${subject}

Front-page card (${figures} interactive ${noun}, ${minutes} min, swatches ${(j:, :)swatches})
and the link-preview card assets/og.png. The Pages workflow deploys it to
${url}

${CO_AUTHOR}
EOF
  log::INFO "$(cat "${work}/commit.txt")"

  # Gates. Build, the preview card and npm test change files or take seconds, so only --apply runs them.
  if [[ "${DRY_RUN}" == "false" ]]; then
    run_cmd node "${repo}/tools/explainers.cjs" build "${html}" >&2
    render_og_image "${repo}" "${html}" || return 1
    cp "${work}/index.html" "${front}"
    log::ok "Front page written | front='${front}' action='${action}'"
  else
    run_mut node "${repo}/tools/explainers.cjs" build "${html}"
    run_mut node "${repo}/tools/og-image.mjs" "${html}"
  fi
  run_read_gates "${repo}" "${html}" || return 1
  if [[ "${DRY_RUN}" == "false" ]]; then
    run_tests "${repo}" || return 1
  else
    run_mut npm test
  fi

  # Commit. Everything under the article plus the front page; the status shows what that is.
  local staged
  staged="$(git -C "${repo}" status --short -- index.html "articles/${slug}")"
  if [[ -n "${staged}" ]]; then
    log::info "Paths to commit | paths='index.html articles/${slug}'"
    log::INFO "${staged}"
  else
    log::info "Nothing to commit under the article or the front page | slug='${slug}'"
  fi
  local sha
  sha="$(git -C "${repo}" rev-parse HEAD)"
  if [[ "${DRY_RUN}" == "false" && -n "${staged}" ]]; then
    run_cmd git -C "${repo}" add -A -- index.html "articles/${slug}"
    run_cmd git -C "${repo}" commit -q -F "${work}/commit.txt"
    sha="$(git -C "${repo}" rev-parse HEAD)"
    log::ok "Committed | sha='${sha}'"
  fi

  # Push target. Fetch first so a diverged main fails here, not on the remote.
  local err_file fetch_rc=0
  err_file="$(mktemp)"
  run_with_timeout "${FETCH_TIMEOUT}" "${err_file}" git -C "${repo}" fetch -q origin "${BRANCH}" || fetch_rc=$?
  (( fetch_rc == 0 )) || { log::ERR "$(cat "${err_file}")"; log::err "git fetch failed | rc='${fetch_rc}' remote='${remote_url}'"; return 1; }
  if ! git -C "${repo}" merge-base --is-ancestor "origin/${BRANCH}" HEAD; then
    log::err "Local main has diverged from origin; rebase first | branch='${BRANCH}' remote='${remote_url}'"
    return 1
  fi
  local ahead
  ahead="$(git -C "${repo}" rev-list --count "origin/${BRANCH}..HEAD")"
  log::info "Push target | remote='${remote_url}' owner='${owner}' branch='${BRANCH}' account='${owner}' token_source='gh auth token -u ${owner}' commits_ahead='${ahead}'"

  local run_id=""
  if [[ "${DRY_RUN}" == "true" ]]; then
    log::ok "Dry run; nothing written, committed or pushed | slug='${slug}' action='${action}' url='${url}' rerun='--apply'"
  elif (( ahead == 0 )); then
    log::info "Origin already has HEAD; nothing to push | sha='${sha}'"
  else
    push_as_owner "${repo}" "${owner}" "${token}" || return 1
    log::ok "Pushed | sha='${sha}' remote='${remote_url}'"
    run_id="$(GH_TOKEN="${token}" watch_pages_run "${owner_repo}" "${sha}")" || return 1
  fi

  open_url "${url}" "${no_open}"

  cat <<EOF
slug=${slug}
action=${action}
figures=${figures}
minutes=${minutes}
sha=${sha}
run_id=${run_id}
url=${url}
EOF
}

main "${@}"
