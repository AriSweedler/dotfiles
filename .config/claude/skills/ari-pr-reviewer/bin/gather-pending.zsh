#!/usr/bin/env zsh
# Find the viewer's pending review on a PR, fetch its comments and thread ids, merge into state.
# Pending review comments are invisible to pulls/{pr}/comments (404); they live under the review.
# Run: zsh $HOME/.claude/skills/ari-pr-reviewer/bin/gather-pending.zsh --pr <number>

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"

# --- Help ---

help() {
    cat <<EOF
${c_green}gather-pending${c_rst} — fetch the viewer's pending review comments on a PR into state

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-pr-reviewer/bin/gather-pending.zsh --pr <number> [--repo owner/repo]

${c_bold}Options:${c_rst}
  --pr NUMBER        Pull request number or URL (required)
  --repo OWNER/REPO  Repository; defaults to the current directory's GitHub repo
  --verbose          Enable debug logging
  -h, --help         Show this help

${c_bold}Output:${c_rst}
  Sections to stdout: PR, META, PENDING_COMMENTS.
  State persisted in /tmp/ari-pr-patrol-<pr>/comments/.
EOF
}

# --- Prerequisites ---

#######################################
# Check that required binaries are installed.
# Globals: None
# Arguments: None
# Returns: 1 if any are missing
#######################################
check_prerequisites() {
    local missing=()
    for cmd in gh jq; do
        command -v "${cmd}" >/dev/null 2>&1 || missing+=("${cmd}")
    done
    if (( ${#missing} > 0 )); then
        log::err "Missing required commands | missing='${(j:, :)missing}'"
        return 1
    fi
}

# --- Helpers ---

#######################################
# Resolve the repository, preferring the flag over the current directory.
# Globals: PWD
# Arguments:
#   $1 - --repo value, or empty
# Stdout: owner/repo
# Returns: 1 when neither source yields a repo
#######################################
resolve_repo() {
    local flag="${1}"
    if [[ -n "${flag}" ]]; then
        log::info "Using --repo | repo='${flag}'"
        echo "${flag}"
        return
    fi
    local detected
    if ! detected="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)"; then
        log::err "No GitHub repo in the current directory; pass --repo | cwd='${PWD}'"
        return 1
    fi
    log::info "Detected repo from cwd | repo='${detected}'"
    echo "${detected}"
}

#######################################
# Reset a JSON state file to an empty array when missing or corrupt.
# Arguments:
#   $1 - file path
#######################################
ensure_valid_json_array() {
    local file="${1}"
    if [[ -f "${file}" ]] && jq empty "${file}" 2>/dev/null; then
        return
    fi
    log::warn "Resetting state file | file='${file}'"
    echo '[]' > "${file}"
}

#######################################
# Fetch a paginated REST array endpoint into one JSON array.
# gh streams one object per line under --paginate --jq; jq -s rebuilds the array.
# Arguments:
#   $1 - endpoint path
# Stdout: JSON array
#######################################
fetch_array() {
    local endpoint="${1}"
    gh api --paginate --jq '.[]' "${endpoint}" | jq -s '.'
}

#######################################
# Fetch every review thread on the PR with its first comment's databaseId.
# Pending threads are listed for their author, so the viewer's own show up here.
# Arguments:
#   $1 - owner
#   $2 - repo name
#   $3 - PR number
# Stdout: JSON array of {id, comments: {nodes: [{databaseId}]}}
#######################################
fetch_threads() {
    local owner="${1}" repo_name="${2}" pr="${3}"
    gh api graphql \
        -f query='query($owner:String!,$repo:String!,$pr:Int!) {
          repository(owner:$owner, name:$repo) {
            pullRequest(number:$pr) {
              reviewThreads(first:250) {
                nodes { id comments(first:1) { nodes { databaseId } } }
              }
            }
          }
        }' \
        -f owner="${owner}" -f repo="${repo_name}" -F pr="${pr}" \
        --jq '.data.repository.pullRequest.reviewThreads.nodes'
}

#######################################
# Merge the pending review's comments into the state file, keeping prior status,
# verdict and reply ids. A reply already in the review marks its parent addressed.
# Arguments:
#   $1 - state file
#   $2 - comments JSON (array)
#   $3 - threads JSON (array)
#   $4 - viewer login
#######################################
merge_state() {
    local state_file="${1}" comments_json="${2}" threads_json="${3}" viewer="${4}"
    local tmp="${state_file}.tmp"
    jq -n \
        --slurpfile old "${state_file}" \
        --argjson incoming "${comments_json}" \
        --argjson threads "${threads_json}" \
        --arg viewer "${viewer}" \
        '
        ($old[0] | map({(.id|tostring): .}) | add // {}) as $old_by_id
        | ($threads | map({(.comments.nodes[0].databaseId|tostring): .id}) | add // {}) as $thread_by_id
        | ($incoming | map(select(.in_reply_to_id != null))
            | map({(.in_reply_to_id|tostring): .}) | add // {}) as $reply_by_parent
        | [ $incoming[]
            | select(.in_reply_to_id == null and .user.login == $viewer)
            | . as $c
            | ($old_by_id[$c.id|tostring] // {}) as $prev
            | ($reply_by_parent[$c.id|tostring]) as $reply
            | {
                id: $c.id,
                node_id: $c.node_id,
                type: "review",
                path: $c.path,
                line: ($c.line // $c.original_line),
                body: $c.body,
                diff_hunk: $c.diff_hunk,
                user: $c.user.login,
                created_at: $c.created_at,
                updated_at: $c.updated_at,
                html_url: $c.html_url,
                thread_id: ($thread_by_id[$c.id|tostring] // null),
                status: (if $reply != null then "addressed" else ($prev.status // "pending") end),
                verdict: ($prev.verdict // null),
                reply_id: ($reply.id // $prev.reply_id // null),
                reply_node_id: ($reply.node_id // $prev.reply_node_id // null)
              }
          ]
        ' > "${tmp}"
    mv "${tmp}" "${state_file}"
}

# --- Main ---

main() {
    check_prerequisites || exit 1

    # === PARSE ===
    local pr="" repo_flag="" verbose=false

    while (( $# > 0 )); do case "${1}" in
        -h|--help)  help; return 0 ;;
        --pr)       pr="${2:?--pr requires a value}"; shift 2 ;;
        --repo)     repo_flag="${2:?--repo requires a value}"; shift 2 ;;
        --verbose)  verbose=true; shift ;;
        -*)         log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
        *)          log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
    esac; done

    export VERBOSE="${verbose}"

    # === MASSAGE ===

    # Accept a PR URL: keep the digits after /pull/.
    pr="${pr##*/pull/}"
    pr="${pr%%[^0-9]*}"

    # === VALIDATE ===

    [[ -n "${pr}" ]] || { log::err "Missing --pr | expected='a PR number or URL'"; help; return 1; }
    [[ "${pr}" == <-> ]] || { log::err "Invalid --pr | pr='${pr}' expected='digits'"; return 1; }

    local repo
    repo="$(resolve_repo "${repo_flag}")" || return 1
    local owner="${repo%%/*}" repo_name="${repo##*/}"

    # === LOGIC ===

    local viewer
    if ! viewer="$(gh api user --jq '.login')"; then
        log::err "Cannot determine the GitHub viewer | hint='gh auth status'"
        return 1
    fi

    local pr_json
    if ! pr_json="$(gh api "repos/${repo}/pulls/${pr}" --jq '{head_sha: .head.sha, base_ref: .base.ref, node_id: .node_id}')"; then
        log::err "PR not found | repo='${repo}' pr='${pr}'"
        return 1
    fi
    local head_sha base_ref pr_node_id
    head_sha="$(jq -r '.head_sha' <<<"${pr_json}")"
    base_ref="$(jq -r '.base_ref' <<<"${pr_json}")"
    pr_node_id="$(jq -r '.node_id' <<<"${pr_json}")"

    local base_sha
    if ! base_sha="$(gh api "repos/${repo}/branches/${base_ref}" --jq '.commit.sha')"; then
        log::err "Base branch not found | repo='${repo}' base_ref='${base_ref}'"
        return 1
    fi

    local reviews_json
    reviews_json="$(fetch_array "repos/${repo}/pulls/${pr}/reviews")" || return 1
    local pending_json
    pending_json="$(jq --arg viewer "${viewer}" \
        '[.[] | select(.state == "PENDING" and .user.login == $viewer)]' <<<"${reviews_json}")"
    local pending_count
    pending_count="$(jq 'length' <<<"${pending_json}")"
    if (( pending_count == 0 )); then
        log::err "No pending review by the viewer | repo='${repo}' pr='${pr}' viewer='${viewer}' hint='start a review in the GitHub UI first'"
        return 1
    fi
    local review_id review_node_id
    review_id="$(jq -r '.[0].id' <<<"${pending_json}")"
    review_node_id="$(jq -r '.[0].node_id' <<<"${pending_json}")"
    log::info "Found pending review | review_id='${review_id}' viewer='${viewer}'"

    local comments_json
    comments_json="$(fetch_array "repos/${repo}/pulls/${pr}/reviews/${review_id}/comments")" || return 1
    local threads_json
    threads_json="$(fetch_threads "${owner}" "${repo_name}" "${pr}")" || return 1

    # --- State ---

    local comments_dir="/tmp/ari-pr-patrol-${pr}/comments"
    local replies_dir="/tmp/ari-pr-patrol-${pr}/replies"
    local state_file="${comments_dir}/review.json"
    local meta_file="${comments_dir}/pending_review.json"
    mkdir -p "${comments_dir}" "${replies_dir}"
    ensure_valid_json_array "${state_file}"

    jq -n \
        --arg pr "${pr}" --arg repo "${repo}" --arg owner "${owner}" --arg repo_name "${repo_name}" \
        --arg pr_node_id "${pr_node_id}" --arg review_id "${review_id}" \
        --arg review_node_id "${review_node_id}" --arg viewer "${viewer}" \
        --arg head_sha "${head_sha}" --arg base_ref "${base_ref}" --arg base_sha "${base_sha}" \
        '{pr: ($pr|tonumber), repo: $repo, owner: $owner, repo_name: $repo_name,
          pr_node_id: $pr_node_id, review_id: ($review_id|tonumber), review_node_id: $review_node_id,
          viewer: $viewer, head_sha: $head_sha, base_ref: $base_ref, base_sha: $base_sha}' \
        > "${meta_file}"

    merge_state "${state_file}" "${comments_json}" "${threads_json}" "${viewer}"

    local total pending addressed
    total="$(jq 'length' "${state_file}")"
    pending="$(jq '[.[] | select(.status == "pending")] | length' "${state_file}")"
    addressed="$(jq '[.[] | select(.status == "addressed")] | length' "${state_file}")"
    log::info "Merged | total='${total}' pending='${pending}' addressed='${addressed}'"

    cat <<EOF
=== start PR ===
pr=${pr}
repo=${repo}
review_id=${review_id}
review_node_id=${review_node_id}
viewer=${viewer}
head_sha=${head_sha}
base_ref=${base_ref}
base_sha=${base_sha}
comments_dir=${comments_dir}
replies_dir=${replies_dir}
=== end PR ===
=== start META ===
total_comments: ${total}
pending_comments: ${pending}
addressed_comments: ${addressed}
=== end META ===
=== start PENDING_COMMENTS ===
$(jq '[.[] | select(.status == "pending")]' "${state_file}")
=== end PENDING_COMMENTS ===
EOF
}

main "${@}"
