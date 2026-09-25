---
name: ari-hemingway--structure-pr-summary
description: "Distill a PR we own into its `## Summary` for review ('ari pr prep summary'): record Ari's intent verbatim, then draft 1–3 sentences faithful to it. A summary that needs length means the PR should be split — propose the split instead of writing more."
---

# PR Summary

Produce the `## Summary` of a PR we own, for its reviewers. The summary says why the change exists and what it changes, in as few words as that takes. A PR whose summary cannot be short does more than one thing; the fix is a split, not a longer summary.

Formatting and body structure: `.cursor/rules/pull_requests.mdc` in the repo and `/ari-pr`. Workflow patterns (restore context, fact-check, present): `/ari-hemingway--lib`.

## Document structure

Required, in order:
1. **Why** — the defect or need, with the one concrete fact that motivates it (an entity, a measurement, an incident).
2. **What** — the change, by mechanism, naming the key identifier to grep.

Optional:
3. **The one thing the diff hides** — an ordering constraint, a behavior change for existing callers, a deliberate non-goal. One clause.

## Rules

### Length is a split signal

- Target 1–3 sentences, under ~400 characters.
- Over that, or needing a second "and also", means two outcomes: stop drafting and propose a split — which commits or files go to which PR, and the stack order (`/ari-listable-pr-stack`).
- Never trim meaning to fit; split instead.

### Intent is the source of truth

- Ari's own words, recorded verbatim in `/tmp/pr/<branch>-intent.md`, define what the PR is for. The draft MUST stay faithful to them: no claim they do not support, no purpose they do not state.
- His exact words need not appear in the Summary; his meaning must.
- If the diff contradicts the intent, say so and ask — never silently reconcile.

### Content

- Kernighan & Ritchie: no marketing, no hedging, no investigation narrative (link the thread instead).
- Real identifiers, full cluster names, PR/listable links as `[text](url)`.
- Nothing the other body sections own: risks, guard, test evidence.

## Workflow

### Gather

Read the diff (`gh pr diff <n>`), the commit messages, the listable Notes (`/ari-listable`), and the motivating thread when one is linked.

### Record intent

Ask Ari in one line for the PR's purpose in his own words. Write his reply verbatim to `/tmp/pr/<branch>-intent.md` (Write tool; `/` in the branch → `_`). If the file already exists from an earlier pass, show it and ask whether it still holds.

### Distill

Write 3–5 candidate one-liners from different angles (defect-first, mechanism-first, reader-impact-first, shortest), then synthesize one Summary from them. Check it against the length rule; on overflow, go to the split proposal instead.

### Fact-check

Every claim traces to the diff or the intent file. Run `/ari-hemingway--review-brevity` and `/ari-hemingway--review-factual` on the draft and apply their findings.

### Present

Show, in chat: the intent file's text, the draft Summary, and its character count. Apply only on Ari's approval — his edits verbatim — by replacing the `## Summary` content in the PR body file and running `gh pr edit <n> --body-file <file>`.
