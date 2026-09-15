---
name: ari-hemingway--lib
description: "Shared workflow patterns for `/ari-hemingway--*` skills: investigation folder, restore context, sources tracking, draft hygiene, permalink resolution, MCP reliability, present/output cadence. Not user-invocable."
user_invocable: false
---

# Hemingway Shared Workflow

Shared workflow patterns for any `/ari-hemingway--*` skill. Siblings follow these procedures; they do not invoke this skill. Formatting rules live in `/ari-hemingway--format-gdoc`.

## Contract for siblings

Siblings MUST:
- Reference lib sections by heading name (e.g., "Follow the `Resolve permalink SHA` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`"). Do NOT invoke this skill.
- Use lib's folder root: `/tmp/hemingway/{skill-name}/{topic-slug}/{timestamp}/`. NEVER define a different root.
- Emit one phase-transition print per workflow step per the format in `## Appendices → Print lines`.
- Follow the Option 3 confirmation gate, Option 2 manual-SHA validation, and Scrap confirmation gate exactly.
- Never renumber Present options 2 or 3, add options 5+, or override the print-line format.

Siblings MAY:
- Extend the `scratchpad.md` baseline schema by appending fields after `Last phase`.
- Enable Present option 4 in specific modes and supply mode-specific labels for option 1.
- Insert a diff summary before the Present menu; siblings own the diff format.
- Rename workflow step names (e.g., "Investigate" instead of "Research").

## Preconditions

Before any workflow step runs, sibling skills MUST verify:

- **CWD is a git worktree.** `git rev-parse --show-toplevel` MUST succeed. If it fails: STOP, ask the user to cd into the relevant repo, or confirm the explainer is for something outside the codebase (in which case all permalinks become `[TODO: add permalink]`).
- **`/ari-hemingway--format-gdoc` and this skill are installed.** Verify `$HOME/.claude/skills/ari-hemingway--format-gdoc/SKILL.md`, `$HOME/.claude/skills/ari-hemingway--lib/bin/git-permalink-info`, and `$HOME/.claude/skills/ari-hemingway--lib/bin/make-investigation-folder` exist.
- **Investigation folder root is writable.** `bin/make-investigation-folder` tries `/tmp/hemingway/` first and falls back to `${TMPDIR:-$HOME/.cache}/hemingway/` automatically. If fallback fires, the script emits a WARN line that surfaces to the user — no extra Print needed.

## Investigation folder

Throughout this skill, `{investigation_folder}` = `/tmp/hemingway/{skill-name}/{topic-slug}/{timestamp}/`.

```
{investigation_folder}/
├── scratchpad.md
├── draft.md
├── sources.md
└── output.md
```

Create it with one script call. The script slugifies the subject deterministically, picks a writable base, checks for concurrent sessions, and stubs `scratchpad.md` + `sources.md` from the canonical schemas:

```zsh
eval "$(zsh $HOME/.claude/skills/ari-hemingway--lib/bin/make-investigation-folder \
    --skill-name <skill-name> --subject "<subject>")"
# exports: base_path, topic_slug, parent_dir, investigation_folder, timestamp, concurrent_sessions
```

- `<skill-name>` = the invoking sibling's short name, e.g., `subsystem-explainer`, `review`.
- `<subject>` = the doc's subject. The script slugifies it (lowercase, non-alphanumeric → `-`, trim to 57 chars, append `-<sha1[0:6]>`). Worked example: `"Widget Cache Invalidation! (v2)"` → `widget-cache-invalidation-v2-ab3f9c`.

**Concurrent-session check.** If `concurrent_sessions` is non-empty, the script did NOT create a new folder — sibling folders with mtime in the last 5 minutes were detected. STOP and ask: `Another session at <first path> is active. (1) Share session (resume it), (2) New timestamp, (3) Abort.` No default. On (2), re-run the script with `--force-new`.

### scratchpad.md baseline schema

Permalink template tokens `{owner_repo}` and `{sha}` are defined in `## Resolve permalink SHA` below.

Required fields, in order:
- **Subject**: string
- **Mode**: sibling-defined (e.g., `research | distill | update`)
- **Pointers**: bullet list of user-provided strings (paths, URLs, PRs)
- **Key findings**: bullet list; each bullet is one verified fact with inline permalink
- **Open questions**: bullet list; each blocks drafting if unanswered
- **Last phase**: the name of the last-completed workflow step (used by `Restore context`)

Siblings MAY append mode-specific fields after `Last phase`.

Filled example:
```markdown
- **Subject**: Widget Cache Invalidation
- **Mode**: research
- **Pointers**: server/widget_cache.tsx, PR #198432
- **Key findings**:
  - Redis channel is `widget:invalidate:{appId}` at [widget_cache.tsx L42](https://github.com/Hyperbase/hyperbase/blob/a1b2c3d4e5f67890abcdef1234567890abcdef12/server/widget_cache.tsx#L42)
  - LRU max entries = 500; TTL = 60s
- **Open questions**:
  - Is dual eviction (TTL + LRU) intentional?
- **Last phase**: Investigate
- **Bucket**: 600-1800
```

### sources.md schema

```markdown
## Files read
| Path | Relevant finding |
|---|---|
| [`server/widget_cache.tsx`](https://github.com/Hyperbase/hyperbase/blob/a1b2c3d4e5f67890abcdef1234567890abcdef12/server/widget_cache.tsx#L1-L50) | LRU cache with 500-entry cap and 60s TTL |

## Grep queries
| Pattern | Scope | Hits | Finding |
|---|---|---|---|
| `WIDGET_INVALIDATE` | server/ | 3 | Emit at 1 callsite, handle at 2 consumers |

## Git log
| Range | Finding |
|---|---|
| `HEAD~30 -- server/widget_cache.tsx` | Last change 2026-02-14 (#198432): race-condition fix |

## External docs
| Source | Finding |
|---|---|
| https://docs.google.com/document/d/1abc...widget_cache_design | Original design doc, last edited 2025-11 |

## Background ops
| Command | Exit | Stderr (first line) | Action taken |
|---|---|---|---|
| `git fetch origin main` | 128 | fatal: Authentication failed for ... | Proceeded with local origin/main (300s old) |

## Call graphs (optional — populated when /code-trace runs)
| Artifact path | Entry point | Notes |
|---|---|---|
```

If a table has no rows, keep the header and add a single row `| _none_ | _none_ |`. Do NOT delete empty tables.

**Update cadence.** Append to `sources.md` after every batch of ≤3 Read/Grep/Bash calls. NEVER let more than 3 uncaptured source operations accumulate. The cadence rule applies during investigation AND fact-checking — each verification (including each `git cat-file -p {sha}:{path}` call) counts as a source operation.

## Restore context

Run AFTER `{topic-slug}` is known (i.e., after the sibling's pointer-gathering step).

1. List `/tmp/hemingway/{skill-name}/{topic-slug}/` subfolders by timestamp, descending.
2. If none: start a new `{timestamp}` folder. Done.
3. If one or more exist: read the latest `scratchpad.md`. Print the header: `{timestamp}, mode={mode}, pointers=[...], last phase={last phase}`.
4. Ask: `(1) Resume latest, (2) Start new timestamp, (3) Show full scratchpad contents first`. NEVER apply a default — always wait for an explicit choice. NEVER resume silently.

If the user picks (3), print the full scratchpad and re-ask (1) vs (2).

## Resolve permalink SHA

Run exactly once per drafting session, BEFORE writing the first permalink:

```zsh
eval "$(zsh $HOME/.claude/skills/ari-hemingway--lib/bin/git-permalink-info)"
# exports: owner_repo, sha, ref, host, fetch_status, local_age_seconds
```

The script synchronously runs `git fetch origin main` first, then resolves the SHA. Fetch failures log to stderr but do not abort — resolution proceeds with whatever the local ref points at, and `fetch_status=failed` is emitted so the post-resolve print line can surface staleness.

Sample output:
```
owner_repo=Hyperbase/hyperbase
sha=a1b2c3d4e5f67890abcdef1234567890abcdef12
ref=origin/main
host=github.com
fetch_status=ok
local_age_seconds=120
```

Use the full 40-char SHA. Cache the values for the session — SHA MUST be stable across every permalink in the doc.

After resolving, MUST print exactly one line:
- `fetch_status=ok` → `Resolved permalinks against ${owner_repo} @ ${sha:0:7} (${ref}).`
- `fetch_status=failed` → `Resolved permalinks against ${owner_repo} @ ${sha:0:7} (${ref}; local from ${local_age_seconds}s ago — fetch failed, see stderr).` AND append a row to `sources.md` under `## Background ops`.
- `fetch_status=skipped` → `Resolved permalinks against ${owner_repo} @ ${sha:0:7} (${ref}; local from ${local_age_seconds}s ago — fetch skipped).`

### Ref selection

ALWAYS resolve against `origin/main`. Do not prompt. Do not honor "use HEAD" or "use branch <name>" requests — the doc must point at mainline code that other reviewers can read.

### Refresh rule

The resolved SHA is pinned for the entire session. Working-tree reads belong in `Investigate` only. `Fact-check` MUST use `git cat-file -p "${sha}:${path}"` against the pinned SHA.

Re-resolve only on explicit user request (e.g., "main moved, refresh permalinks"). On re-resolve: re-run `git-permalink-info`, then rewrite every occurrence of the old SHA in `draft.md` AND `sources.md` with this OS-portable replacement:

```zsh
inplace_replace() {
    if [[ "${OSTYPE}" == darwin* ]]; then
        sed -i '' "s/${1}/${2}/g" "${3}"
    else
        sed -i "s/${1}/${2}/g" "${3}"
    fi
}
inplace_replace "${old_sha}" "${new_sha}" "${investigation_folder}/draft.md"
inplace_replace "${old_sha}" "${new_sha}" "${investigation_folder}/sources.md"
```

### On non-zero exit

STOP. Do not write any permalinks. Print the script's stderr verbatim, then present three options and wait:
1. Retry the script.
2. User provides a SHA manually.
3. Proceed with `[TODO: add permalink]` on every code reference.

NEVER pick autonomously — if unclear, re-ask.

- **Option 2 validation.** Manually-provided SHA MUST match `^[0-9a-f]{7,40}$` AND `git rev-parse --verify "${sha}^{commit}"` MUST succeed (rejects non-commit objects). On failure, surface the error and re-prompt.
- **Option 3 confirmation.** Before proceeding: `Proceeding without permalinks — every code reference will be tagged [TODO: add permalink]. Confirm? (y/N)`. Default N.
- **Option 3 retry escape.** If resolution becomes possible later (network restored, missing ref fetched), the user may say "retry permalinks" at any phase. Re-run the script and backfill `[TODO: add permalink]` markers across `draft.md` and `sources.md`.

## MCP reliability

Pattern for MCP tool calls that can fail transiently (auth, rate limits, network). Used by any sibling that fetches external state — e.g., `mcp__escalation_mcp_server__google_docs_read_document`.

On non-zero return or missing expected fields, STOP and present three options:
1. **Retry** — re-run the MCP call.
2. **Paste content directly** — user supplies the content in chat; sibling treats it as the fetched payload.
3. **Abort OR switch mode** — sibling-defined fallback (e.g., research mode instead of update mode).

Print the underlying MCP error verbatim before the prompt. NEVER pick autonomously.

Siblings MAY add additional options (e.g., "switch to research mode") as option 3's behavior, but options 1 and 2 are required.

## Drafting

**Each iteration: overwrite `draft.md` entirely. NEVER append or merge.** Do not carry over sentences verbatim unless they still belong in the new structure. Use the Write tool (full file), not Edit.

BAD — preserving a stale claim next to a correction:
```markdown
# How it works
The service uses Redis for the cache.
# How it works (updated)
The service uses Memcached for the cache per the recent rewrite.
```

GOOD — full rewrite with the correct claim only:
```markdown
# How it works
The service uses Memcached for the cache.
```

## Fact-check gate

Cadence rule from `## Investigation folder` applies here: each verification is a source operation; append to `sources.md` after every batch of ≤3.

Verify every concrete claim against the codebase:
- File paths exist.
- Commands have correct flags.
- Config values match source files.
- Flow descriptions match the code.
- **Permalinks MUST be verified against the pinned SHA — NEVER the working tree.** Batch-verify every line-anchored code reference with the helper instead of running `git cat-file` by hand:
  ```zsh
  zsh $HOME/.claude/skills/ari-hemingway--lib/bin/verify-claims-at-sha \
      --sha "${sha}" \
      --claim 'path/to/file.tsx:42:expectedSymbol' \
      --claim 'path/to/other.tsx:108'
  ```
  Each `--claim` is `path:line` or `path:line:expected-substring` (the substring pins the line's content, not just its existence — prefer it for every claim). The script runs `git cat-file -p "${sha}:${path}"` per claim, prints a PASS/FAIL table to stdout, and exits non-zero if any claim fails; feed it every permalink in the draft, or pass `--claims-file` a file with one `path:line[:expected]` per line. A FAIL means the path/line is absent at the resolved SHA (or the substring drifted): re-run `git-permalink-info` against a ref that includes the file, fix the line number, OR mark the reference `[TODO: verify — path not present at resolved SHA]`.

If a claim is wrong, fix the draft and record the correction in `sources.md`. If the right value is unknown, mark the claim `[TODO: verify — reason]` per `/ari-hemingway--format-gdoc`.

**Before marking `[TODO: verify]`, MUST have tried ALL of:**
1. Grep for the exact string.
2. `zsh $HOME/.claude/skills/ari-hemingway--lib/bin/verify-claims-at-sha --sha "${sha}" --claim "${path}:${line}"` (wraps `git cat-file` against the pinned SHA — never the working tree, since line numbers drift on feature branches).
3. `git log -S` for the value over the last 90 days.

Record which ran in `sources.md` next to the TODO, formatted as `[TODO: verify | tried: grep,read,log]`.

**Denominator for the 20% threshold:** count one claim per table row, per numbered flow step, per bullet. Sentences in prose paragraphs do not count.

**Lint self-audit (required).** Before leaving Fact-check, grep `draft.md` for `[TODO: verify` and verify every hit has a matching `| tried: ...` annotation. Any bare `[TODO: verify]` → STOP, add attempts or remove the marker.

If `[TODO: verify]` count exceeds 20% of counted claims, STOP and present four options:
1. Re-research the flagged claims.
2. User answers the TODOs inline.
3. Accept the high-TODO draft and mark the title `[🤖 AI generated — draft, needs SME review]`.
4. Abort.

## Present

After Draft + Fact-check, print ONLY the draft file path and the menu. Do NOT re-display the draft body, paraphrase it, show section headers, embed a stats panel (`words/sections/TODOs`), or any "here's what I wrote" framing. The draft is on disk; the user can open it.

```
{path to draft.md}

## Next step

1. Finalize — write output.md
2. Keep editing — tell me what to change (specific sections, tone, missing details)
3. Scrap and restart
4. No changes needed — the doc is already accurate (sibling-enabled only)
```

Rules:
- **Option 3 MUST confirm.** Prompt `Discard current draft (investigation folder preserved)? (y/N)`. On yes, rename the `{timestamp}` folder to `{timestamp}-scrapped-$(openssl rand -hex 2)` (random suffix prevents collision on repeat scraps), then restart from the sibling's first workflow step.
- **Option 2 post-selection:** apply edits via full rewrite of `draft.md`, re-run Fact-check on changed sections, re-enter Present. Do NOT skip Fact-check or drop to Output silently.
- **Empty-diff default (siblings with diff support):** when the diff is empty in update-like modes, reorder so option 4 leads and is the default.
- **Numbering when option 4 is hidden:** renumber to 1-3; do NOT leave a `(4)` gap.

Sibling customizations:
- MAY rename option 1 per mode. Example (from `ari-hemingway--structure-subsystem-explainer` update mode): `Finalize — write updated output.md, then update the Doc in place via /ari-hemingway--share-gdoc`.
- MAY enable option 4 in specific modes only.
- MAY insert a diff summary BEFORE the menu.

## Output

Write the final document to `{investigation_folder}/output.md`.

**Overwrite gate.** If `output.md` already exists, print a diff preview before asking:
```
Existing: {mtime} · {words} words · {first_80_chars}...{last_80_chars}
New:                · {words} words · {first_80_chars}...{last_80_chars}
Word delta: {new_words - old_words}
Overwrite? (y/N)
```
Default N.

**Publish (gdoc destination).** Do not paste. Invoke `/ari-hemingway--share-gdoc`: it creates the Doc from `output.md` (or updates an existing one in place with `--doc`) and styles every table's header row and checks each image fits one page in the same run. Record the URL in `scratchpad.md`, then skip Transfer.

**Transfer (other destinations).** Run `zsh $HOME/.claude/skills/ari-hemingway--lib/bin/detect-transfer`. It prints one word to stdout: the transfer method.

Act on the output:
- `pbcopy` / `wl-copy` / `xclip` — pipe `output.md` to it. Print the first and last 80 chars so the user can verify.
- `gh_gist` — ask: `Clipboard unavailable. Create a secret gist to transfer the file to your local machine? (y/N)`. On yes, run `gh gist create --desc "{subject}" {investigation_folder}/output.md`. NEVER pass `--public` — drafts contain internal details (Slack channels, employee names, vendor names).
- `none` — print the path only.

Print: `Output complete — {path}, {lines} lines, {words} words. Transfer: {method}.`

## Appendices

### Sub-skill failure contracts

- **`/code-trace` failure or unavailability:** fall back to manual per-file trace; record the gap in `sources.md`. If `/code-trace` partially succeeded (zero exit but missing artifacts), still record its artifact path in `sources.md` under `## Call graphs` with a `partial` note.
- **`/mermaid-diagram` failure:** embed the raw Mermaid source in a fenced ` ```mermaid ` block inside `draft.md`; mark with `[TODO: render diagram]`. Do NOT block drafting on image generation.
- **MCP call failure:** see `## MCP reliability` above for the three-option pattern.

### Print lines

Every phase transition MUST print exactly one line in this format:
```
{phase} complete — {metrics}. Next: {next-phase}.
```

Rendered sequence across a typical session:
```
Investigate complete — 14 files read, 6 grep queries. Next: Draft.
Draft complete — 5 sections, 1247 words. Next: Fact-check.
Fact-check complete — 18 claims verified, 2 marked [TODO: verify]. Next: Present.
Draft ready — awaiting your choice.
Output complete — /tmp/hemingway/subsystem-explainer/widget-cache-invalidation-ab3f9c/20260416-164200-7a3c/output.md, 127 lines, 1247 words. Transfer: wl-copy.
```

Skipping the print signals the step did not run. The terminal phase omits `Next:`.
