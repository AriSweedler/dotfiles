#!/usr/bin/env zsh
# Reply inside the viewer's pending review thread. Nothing publishes until the review is submitted.
# Run: zsh $HOME/.claude/skills/ari-pr-reviewer/bin/post-pending-reply.zsh --pr <number> --comment-id <id> --body-file <path>

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

readonly VALID_VERDICTS=(holds partially disproved answered)
# Replies ship under Ari's name; a generated-by footer would misattribute them.
readonly FOOTER_MARKERS=('Generated with Claude Code' 'Drafted by Claude Code')

# --- Help ---

help() {
    cat <<EOF
${c_green}post-pending-reply${c_rst} — reply under one of the viewer's pending review comments

${c_bold}Usage:${c_rst}
  zsh $HOME/.claude/skills/ari-pr-reviewer/bin/post-pending-reply.zsh --pr <number> --comment-id <id> --body-file <path> [--verdict <verdict>] [--dry-run]

${c_bold}Options:${c_rst}
  --pr NUMBER          Pull request number or URL (required)
  --comment-id ID      Numeric id of the viewer's top-level comment (required)
  --body-file PATH     Markdown reply body; no footer allowed (required)
  --verdict VERDICT    Record the fact-check verdict: ${(j:, :)VALID_VERDICTS}
  --dry-run            Log the reply without posting or writing state
  --verbose            Enable debug logging
  -h, --help           Show this help

${c_bold}Requires:${c_rst}
  State from gather-pending.zsh under /tmp/ari-pr-patrol-<pr>/comments/.
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

# --- Validation helpers ---

#######################################
# Check if a value is in an array of valid options.
# Arguments:
#   $1 - value to check
#   $2.. - valid options
# Returns: 0 if valid, 1 if not
#######################################
is_valid_option() {
    local val="${1}"; shift
    for opt in "${@}"; do
        [[ "${val}" == "${opt}" ]] && return 0
    done
    return 1
}

#######################################
# Refuse a body that carries a footer.
# Globals: FOOTER_MARKERS
# Arguments:
#   $1 - body file
# Returns: 1 when a marker is present
#######################################
reject_footer() {
    local body_file="${1}"
    for marker in "${FOOTER_MARKERS[@]}"; do
        if grep -q -F -- "${marker}" "${body_file}"; then
            log::err "Body carries a footer; remove it | body_file='${body_file}' marker='${marker}'"
            return 1
        fi
    done
}

# --- State helpers ---

#######################################
# Read one field of a comment's state record.
# Arguments:
#   $1 - state file
#   $2 - comment id
#   $3 - field name
# Stdout: the field value, or empty
#######################################
state_field() {
    local state_file="${1}" id="${2}" field="${3}"
    jq -r --argjson id "${id}" --arg field "${field}" \
        '.[] | select(.id == $id) | .[$field] // empty' "${state_file}"
}

#######################################
# Record the reply and verdict on the comment's state record. Atomic write.
# Arguments:
#   $1 - state file
#   $2 - comment id
#   $3 - reply id
#   $4 - reply node id
#   $5 - verdict, or empty to leave it
#######################################
mark_addressed() {
    local state_file="${1}" id="${2}" reply_id="${3}" reply_node_id="${4}" verdict="${5}"
    local tmp="${state_file}.tmp"
    jq --argjson id "${id}" --argjson reply_id "${reply_id}" \
        --arg reply_node_id "${reply_node_id}" --arg verdict "${verdict}" \
        '(.[] | select(.id == $id))
            |= . + {status: "addressed", reply_id: $reply_id, reply_node_id: $reply_node_id}
             + (if $verdict == "" then {} else {verdict: $verdict} end)' \
        "${state_file}" > "${tmp}"
    mv "${tmp}" "${state_file}"
}

# --- GitHub ---

#######################################
# Post the reply into the pending review thread.
# Arguments:
#   $1 - thread node id
#   $2 - review node id
#   $3 - body file
# Stdout: raw GraphQL response
#######################################
post_reply() {
    local thread_id="${1}" review_node_id="${2}" body_file="${3}"
    gh api graphql \
        -f query='mutation($threadId:ID!,$reviewId:ID!,$body:String!) {
          addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, pullRequestReviewId:$reviewId, body:$body}) {
            comment { id databaseId url pullRequestReview { state } }
          }
        }' \
        -f threadId="${thread_id}" -f reviewId="${review_node_id}" -F body="@${body_file}"
}

# --- Main ---

main() {
    check_prerequisites || exit 1

    # === PARSE ===
    local pr="" comment_id="" body_file="" verdict="" dry_run=false verbose=false

    while (( $# > 0 )); do case "${1}" in
        -h|--help)     help; return 0 ;;
        --pr)          pr="${2:?--pr requires a value}"; shift 2 ;;
        --comment-id)  comment_id="${2:?--comment-id requires a value}"; shift 2 ;;
        --body-file)   body_file="${2:?--body-file requires a value}"; shift 2 ;;
        --verdict)     verdict="${2:?--verdict requires a value}"; shift 2 ;;
        --dry-run)     dry_run=true; shift ;;
        --verbose)     verbose=true; shift ;;
        -*)            log::err "Unknown flag | flag='${1}'"; help; return 1 ;;
        *)             log::err "Unexpected argument | argument='${1}'"; help; return 1 ;;
    esac; done

    export VERBOSE="${verbose}"

    # === MASSAGE ===

    pr="${pr##*/pull/}"
    pr="${pr%%[^0-9]*}"
    verdict="${verdict:l}"

    # === VALIDATE ===

    [[ -n "${pr}" ]] || { log::err "Missing --pr | expected='a PR number or URL'"; help; return 1; }
    [[ "${pr}" == <-> ]] || { log::err "Invalid --pr | pr='${pr}' expected='digits'"; return 1; }
    [[ -n "${comment_id}" ]] || { log::err "Missing --comment-id"; help; return 1; }
    [[ "${comment_id}" == <-> ]] || { log::err "Invalid --comment-id | comment_id='${comment_id}' expected='digits'"; return 1; }
    [[ -n "${body_file}" ]] || { log::err "Missing --body-file"; help; return 1; }
    [[ -f "${body_file}" ]] || { log::err "Body file does not exist | body_file='${body_file}'"; return 1; }
    [[ -s "${body_file}" ]] || { log::err "Body file is empty | body_file='${body_file}'"; return 1; }
    reject_footer "${body_file}" || return 1
    if [[ -n "${verdict}" ]] && ! is_valid_option "${verdict}" "${VALID_VERDICTS[@]}"; then
        log::err "Invalid --verdict | verdict='${verdict}' valid_verdicts='${(j:, :)VALID_VERDICTS}'"
        return 1
    fi

    local comments_dir="/tmp/ari-pr-patrol-${pr}/comments"
    local state_file="${comments_dir}/review.json"
    local meta_file="${comments_dir}/pending_review.json"
    for file in "${state_file}" "${meta_file}"; do
        if [[ ! -f "${file}" ]]; then
            log::err "State missing; run gather-pending.zsh first | file='${file}' pr='${pr}'"
            return 1
        fi
    done

    local thread_id review_node_id existing_reply_id
    thread_id="$(state_field "${state_file}" "${comment_id}" thread_id)"
    review_node_id="$(jq -r '.review_node_id // empty' "${meta_file}")"
    existing_reply_id="$(state_field "${state_file}" "${comment_id}" reply_id)"
    if [[ -z "${thread_id}" ]]; then
        log::err "Comment has no thread in state; re-run gather-pending.zsh | comment_id='${comment_id}' state_file='${state_file}'"
        return 1
    fi
    if [[ -z "${review_node_id}" ]]; then
        log::err "Meta has no review_node_id; re-run gather-pending.zsh | meta_file='${meta_file}'"
        return 1
    fi

    # === LOGIC ===

    if [[ -n "${existing_reply_id}" ]]; then
        log::warn "Comment already has a reply; nothing posted | comment_id='${comment_id}' reply_id='${existing_reply_id}'"
        cat <<EOF
comment_id=${comment_id}
reply_id=${existing_reply_id}
review_state=unchanged
state_updated=false
EOF
        return 0
    fi

    if [[ "${dry_run}" == "true" ]]; then
        log::info "Dry run — would post reply | pr='${pr}' comment_id='${comment_id}' thread_id='${thread_id}' verdict='${verdict:-unset}'"
        log::INFO "$(cat "${body_file}")"
        cat <<EOF
comment_id=${comment_id}
reply_id=dry-run
review_state=dry-run
state_updated=false
EOF
        return 0
    fi

    log::info "Posting reply into pending review | pr='${pr}' comment_id='${comment_id}' thread_id='${thread_id}'"
    local response
    if ! response="$(post_reply "${thread_id}" "${review_node_id}" "${body_file}")"; then
        log::err "Reply failed | response='${response}'"
        return 1
    fi

    local reply_id reply_node_id reply_url review_state
    reply_id="$(jq -r '.data.addPullRequestReviewThreadReply.comment.databaseId // empty' <<<"${response}")"
    reply_node_id="$(jq -r '.data.addPullRequestReviewThreadReply.comment.id // empty' <<<"${response}")"
    reply_url="$(jq -r '.data.addPullRequestReviewThreadReply.comment.url // empty' <<<"${response}")"
    review_state="$(jq -r '.data.addPullRequestReviewThreadReply.comment.pullRequestReview.state // empty' <<<"${response}")"
    if [[ -z "${reply_id}" ]]; then
        log::err "Reply response has no comment | response='${response}'"
        return 1
    fi

    mark_addressed "${state_file}" "${comment_id}" "${reply_id}" "${reply_node_id}" "${verdict}"

    if [[ "${review_state}" != "PENDING" ]]; then
        log::err "Reply is PUBLIC, not pending; tell Ari now | reply_url='${reply_url}' review_state='${review_state}'"
        cat <<EOF
comment_id=${comment_id}
reply_id=${reply_id}
reply_node_id=${reply_node_id}
reply_url=${reply_url}
review_state=${review_state}
state_updated=true
EOF
        return 1
    fi

    log::ok "Reply posted, review still pending | reply_id='${reply_id}'"
    cat <<EOF
comment_id=${comment_id}
reply_id=${reply_id}
reply_node_id=${reply_node_id}
reply_url=${reply_url}
review_state=${review_state}
state_updated=true
EOF
}

main "${@}"
