---
name: ari-pr-reviewer
description: Reviewer side of a PR. Reads Ari's PENDING review comments on someone else's PR, tries to disprove each one, and replies under each inside the same pending review — a fenced code block, a placement rec and precedent permalinks when the comment holds, a delete-this-thread note when it fails. Never edits code or touches the author's branch; Ari submits. Use when Ari says "I am reviewing <PR>", "fact-check my comments", or "reply to my review comments". Author-side triage is /ari-pr-patrol-comments.
---

# PR Reviewer

Ari reviews another engineer's PR by leaving terse comments in a pending GitHub review. This skill turns each comment into a reply Ari can submit: it fact-checks the comment against the codebase, then replies in the same pending review with the concrete recommendation, or with a note to delete the thread. Nothing publishes until Ari submits.

## Rules

- **Comments only.** Never check out, edit, typecheck, or test the author's branch. "Implement my comments" means "work out the concrete recommendation", not "edit the repo". The author drives the change.
- **Stay pending.** Post only through `post-pending-reply.zsh`; it fails unless GitHub reports the review still `PENDING`. Never post through another skill's reply script (for example `/ari-pr-patrol-comments`'s `post-reply.zsh`): those publish, resolve the thread, and append a footer. Replies here carry no footer.
- **Ari's voice.** First person, claims scoped to their preconditions, no rhetoric, no borrowed authority. Assert only what the codebase shows, and flag anything Ari would have to defend so he can restate it.
- **Links.** `[what is there](url)`, line numbers only in the fragment, PRs as `#NNNN`. Permalink existing code at `base_sha` and PR files at `head_sha`; the gather script prints both.
- **Re-gather before every pass.** Ari adds comments while you work. The gather script merges and keeps each comment's status.
- **Disprove first.** A comment earns a recommendation only after you looked for the reason it is wrong.

## Input

A PR number or URL. Ari has a pending review on it with at least one comment. Pass `--repo owner/repo` when the working directory is not the PR's repo.

## Investigation folder

One state directory per PR, under the same root `/ari-pr-patrol-comments` uses where that skill is installed.

```
/tmp/ari-pr-patrol-<pr>/
├── comments/
│   ├── pending_review.json   # review ids, viewer, head_sha, base_sha
│   └── review.json           # one record per top-level comment
└── replies/<comment-id>.md   # reply bodies, no footer
```

Each `review.json` record: `id`, `node_id`, `thread_id` (GitHub ids), `type` (always `review`), `path`, `line`, `diff_hunk`, `body`, `user`, `created_at`, `updated_at`, `html_url`, `status` (`pending` or `addressed`), `verdict` (see **Fact-check**), `reply_id`, `reply_node_id`.

## File storage

- `bin/gather-pending.zsh` — finds Ari's pending review, fetches its comments and thread ids, merges them into state, prints `PR`, `META`, `PENDING_COMMENTS`.
- `bin/post-pending-reply.zsh` — posts one reply into a pending review thread, refuses a footer, verifies the review is still `PENDING`, records the verdict and reply id.

## Workflow

### Gather

```zsh
zsh $HOME/.claude/skills/ari-pr-reviewer/bin/gather-pending.zsh --pr <number>
```

`PR` gives `review_node_id`, `head_sha`, `base_sha`; `PENDING_COMMENTS` lists the comments with no reply yet, each with its `diff_hunk`. If the script reports no pending review, stop and say so: Ari has not started one.

### Fact-check

Read the code each comment points at on the PR head (the PR diff, or `gh api repos/{owner}/{repo}/contents/<path>?ref=<head_sha>`), then try to disprove the comment. Record one verdict per comment:

| Verdict | Meaning |
|---|---|
| holds | the comment is right; a concrete change follows |
| partially | part of it is right; say which part |
| disproved | the comment is wrong; Ari should delete the thread |
| answered | the comment was a question; the reply gives the fact |

For a "this could be a type" comment: types bind only when every value is a literal in the code (configs, lookup tables), never for values read at runtime. In a statically typed codebase, TypeScript for example, tuples, non-empty arrays, literal unions and `never` are expressible; regex-shaped strings, uniqueness, numeric ranges and joins across records are not, so those become a test recommendation. Find the codebase precedent to link. Check whether an existing test already exercises the runtime assert, and whether it runs on every PR build or only after merge.

### Draft

Write `/tmp/ari-pr-patrol-<pr>/replies/<comment-id>.md`. One idea per reply; the code block carries the detail.

- **holds / partially:** one placement sentence (file, next to what), a fenced block with the types or code, one precedent permalink, one cost if there is one.
- **disproved:** `**Note to self, delete this thread before submitting.**` then one sentence with the reason and, if any, where the check belongs instead.
- **answered:** the fact with its permalink, then at most one line of suggestion.

### Post

```zsh
zsh $HOME/.claude/skills/ari-pr-reviewer/bin/post-pending-reply.zsh --pr <number> --comment-id <id> --body-file /tmp/ari-pr-patrol-<pr>/replies/<id>.md --verdict <verdict>
```

`review_state=PENDING` in the output is the success condition. Anything else means the reply went public; tell Ari at once. After the batch, run **Gather** again to catch comments Ari added meanwhile.

### Report

One table, then stop. Ari edits in the UI and submits.

```
| Comment | Verdict | Reply |
|---|---|---|
| <first words> | holds | <what the reply recommends> |
```

Below it: any claim Ari should sanity-check before submitting, and the replies directory. Do not offer to submit, approve, or push.
