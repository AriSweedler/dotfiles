---
name: ari-hemingway--review-gdoc
description: "Review a Google Doc draft (markdown file, gdoc URL, or inline paste). Composes gdoc-specific reviewers (formatting, links, typography, scaffolding, sibling) with the universal axis reviewers (brevity, clarity, factual, kr, audience-fit). Fans out specialists, challenges findings, produces an ordered list. READ-ONLY — never edits the draft."
---

# Google Doc Review

Destination bundle for gdoc drafts. Composes:

- **gdoc-specific reviewers** (formatting, links, typography, scaffolding, sibling) — defined in this skill's panel; rules live in `/ari-hemingway--format-gdoc` and the loaded sibling's `review-rules.md`.
- **universal axis reviewers** (brevity, clarity, factual, kr, audience-fit) — delegated to the dedicated `ari-hemingway--review-{axis}` skills.

All reviewers write to the same investigation folder. Challenge → Rank → Present run once over the union.

## Rules

- **READ-ONLY.** This skill NEVER modifies the input draft. Reviewers emit findings; they MUST NOT call Edit, Write, or NotebookEdit on the source. Standalone mode presents findings for the user to apply manually. Called-from-another-skill mode returns the approved list; the caller edits.
- **Valid rule sources:** `/ari-hemingway--format-gdoc`, the loaded sibling `review-rules.md` (if present), and any of the loaded axis skills (`/ari-hemingway--review-brevity`, `--review-clarity`, `--review-factual`, `--review-kr`, `--review-audience-fit`). Reviewers citing rules outside these sources have findings dropped at Challenge.
- **`/ari-hemingway--format-gdoc` is the floor for gdoc-specific behavior.** Sibling rules ADD constraints; they MUST NOT override format rules. If a sibling rule contradicts format, the format rule wins and reviewers flag the contradiction as a meta-finding.
- **Write like Kernighan & Ritchie.** Terse, precise, no filler. Applies to findings text too.
- **Reviewer rewrites MUST themselves be rule-compliant.** A fix that hardcodes a SHA, uses `/blob/main/`, or wraps a gdoc URL in markdown syntax is a broken fix. Challenge catches these.

## Preconditions

Before any workflow step runs, verify per `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` `## Preconditions`:
- CWD is a git worktree.
- `/ari-hemingway--format-gdoc` and `/ari-hemingway--lib` are installed.
- Each axis skill is installed: `review-brevity`, `review-clarity`, `review-factual`, `review-kr`, `review-audience-fit`.
- Investigation folder root is writable (`/tmp/hemingway/` or fallback).

Honor lib's `## Concurrent-session check` when creating the timestamp folder.

## Investigation folder

Root and derivation follow `/ari-hemingway--lib` (skill-name = `review`):

```
/tmp/hemingway/review/{topic-slug}/{timestamp}/
├── scratchpad.md          # lib baseline schema, adapted
├── source.md              # frozen copy of the input (all input types)
├── target.md              # input provenance (path/URL/inline)
├── formatting.md          # gdoc-specific reviewer output
├── links.md               # gdoc-specific
├── typography.md          # gdoc-specific
├── scaffolding.md         # gdoc-specific
├── sibling.md             # only when sibling identified and review-rules.md loaded
├── brevity.md             # axis (delegated)
├── clarity.md             # axis (delegated)
├── factual.md             # axis (delegated)
├── kr.md                  # axis (delegated)
├── audience-fit.md        # axis (destination = gdoc)
├── challenge-log.md       # per-finding verdict from Challenge step
├── challenge-summary.md   # short summary of drops/merges
├── findings.md            # deduplicated, scored, ordered list
└── spec-questions.md      # items that touch the doc's purpose/scope
```

Follow lib's `Restore context` procedure so users can resume an iterated review.

### scratchpad.md (lib baseline + review fields)

```markdown
- **Subject**: {doc title, or first non-blank line if titleless}
- **Mode**: review
- **Pointers**: {input source — path, URL, or "inline paste"}
- **Key findings**: {post-dispatch: per-reviewer counts}
- **Open questions**: {spec questions that emerged}
- **Last phase**: {Accept input | Identify sibling | Dispatch | Challenge | Rank | Present}
- **Input type**: path | gdoc-url | inline
- **Word count**: N
- **Producing sibling**: {skill-name or "generic"}
- **Rules loaded**: ari-hemingway--format-gdoc + {sibling review-rules.md path or "none"} + {axis skills loaded}
```

### Per-reviewer output file

Every reviewer (gdoc-specific or axis) writes ONLY this format. Dispatch prompts mandate it verbatim:

```markdown
## Checklist
- [ ] {bullet 1}: PASS | FAIL (see Finding #N) | N/A
- [ ] {bullet 2}: ...

## Finding 1

- **Rule violated**: {rule section name from /ari-hemingway--format-gdoc, sibling review-rules.md, or an axis skill}
- **Location**: {line number or section heading in source.md}
- **Severity**: blocker | major | polish
- **Problem**: {one sentence}
- **Fix**: {concrete rewrite or action, itself rule-compliant}

## Finding 2
...
```

If a reviewer has zero findings, it MUST still emit the Checklist (all PASS/N-A) and write `## Findings\n_none_` as the body.

### findings.md entry

```markdown
## N. {Short title}

**Flagged by:** {reviewer names, comma-separated}
**Rule:** {rule name + source skill}
**Location:** {line or section reference}
**Severity:** blocker | major | polish
**Score:** {N — see Rank step}
**Problem:** {one sentence}
**Fix:** {concrete action}
```

### spec-questions.md entry

```markdown
## SQN. {Short title}

**Surfaced by:** {reviewer names}
**Touches:** purpose | scope | API
**Tradeoff:** {option A} vs {option B}
**Manager recommendation:** A | B | defer
```

## Workflow

### Accept input

Accept one of:
- **Markdown path** — validate `[[ -f "${path}" && -r "${path}" ]]`; `file "${path}"` reports `ASCII` or `UTF-8`; size >0 bytes. On failure STOP and print reason.
- **Google Doc URL** — validate `^https://docs\.google\.com/document/d/[A-Za-z0-9_-]+`. Fetch via `mcp__escalation_mcp_server__google_docs_read_document`.
  - On MCP fetch failure, STOP and present three options inline: (1) Retry the fetch, (2) Paste content directly, (3) Abort. Print the MCP error verbatim before the prompt. See `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` `## MCP reliability` for error-printing conventions.
- **Inline paste** — require length >50 chars; reject token-stubs and empty strings.

Copy the content to `{investigation_folder}/source.md` for ALL input types (not just gdoc URLs). Reviewers read from `source.md`. Record provenance in `target.md`:
```
input_type: path | gdoc-url | inline
source: {path or URL or "(inline paste captured in source.md)"}
captured_at: {iso8601}
source_sha1: {hash}  # openssl dgst -sha1
```

**Topic-slug derivation** (per lib) uses a fallback chain for title-less drafts:
1. Doc title if present (plain-text first line after the leading `[🤖 AI generated]` marker).
2. First non-blank line of `source.md`, trimmed.
3. Input filename stem.
4. `anonymous-$(openssl rand -hex 3)`.
Print: `Slug derived from: {source — title | first-line | filename | anonymous}.`

**Word-count gate.** Count words in `source.md`. If >8000:
```
Source: {n} words — exceeds reviewer context budget (8000).
(1) Split the draft into sections and review each separately
(2) Proceed anyway with a warning banner in reviewer prompts
(3) Abort
```

Print: `Accept input complete — {n} words, slug={topic-slug}. Next: Identify sibling.`

### Identify producing sibling

Auto-detect: if the input path is under `/tmp/hemingway/{skill-name}/...`, extract `{skill-name}`. Otherwise ask:

```
Which /ari-hemingway--structure-* skill produced this doc?
(1) subsystem-explainer
(2) other — name it (I'll validate)
(3) none / generic gdoc review
```

On (2), validate `[[ -f $HOME/.claude/skills/ari-hemingway--structure-${name}/SKILL.md ]]`. If not found, list matching directories via `ls -d $HOME/.claude/skills/ari-hemingway--structure-*/`, ask "Did you mean {closest-match}?", retry until valid OR user picks (3).

Load sibling rules:
- If sibling identified AND `$HOME/.claude/skills/ari-hemingway--structure-{skill-name}/review-rules.md` exists → load it. Append path to scratchpad `Rules loaded`.
- Otherwise → skip the sibling reviewer.

Print: `Identify sibling complete — producing={skill-name or "generic"}, rules={loaded or "format-only"}. Next: Dispatch.`

### Dispatch reviewers

**MUST launch all reviewers in a SINGLE assistant turn — multiple Agent tool uses in the same response. NEVER dispatch sequentially.**

Two prompt templates apply, depending on whether the reviewer is gdoc-specific or axis-delegated.

#### Template A — gdoc-specific reviewer (paste check bullets verbatim)

```
You are reviewing a Google Doc draft as a {role} expert, READ-ONLY.

Rules the draft is judged against live in `/home/ubuntu/.claude/skills/ari-hemingway--format-gdoc/SKILL.md` (sections: {rule-sections from panel table}).
{If sibling reviewer: plus sibling rules at `/home/ubuntu/.claude/skills/ari-hemingway--structure-{skill-name}/review-rules.md`.}

Read the draft at {investigation_folder}/source.md. NEVER call Edit/Write/NotebookEdit on it — you are read-only. Report findings only.

Checklist — copy this block VERBATIM into the top of your output file. Mark each item PASS, FAIL (link to the finding number), or N/A:
{check bullets pasted verbatim from the gdoc-specific reviewer panel}

Output format MUST follow the schema in this skill's `## Per-reviewer output file` section. No free-form prose outside that schema.

Write to: {investigation_folder}/{output-filename}
```

#### Template B — axis-delegated reviewer (reference axis skill SKILL.md)

```
You are reviewing a Google Doc draft as a {axis} expert, READ-ONLY.

The rules and check bullets you must apply live at `$HOME/.claude/skills/ari-hemingway--review-{axis}/SKILL.md` `## Rules this axis checks` and `## Check bullets`. Read that file first, then apply.

For audience-fit only: declared destination is `gdoc`. Use the gdoc row from that skill's destination rules table.

Read the draft at {investigation_folder}/source.md. NEVER call Edit/Write/NotebookEdit on it — you are read-only. Report findings only.

Output format MUST follow the schema in `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`. Reviewer name: `{axis}`.

Write to: {investigation_folder}/{axis}.md
```

After dispatching, print: `Dispatched {n} reviewers in parallel ({n_gdoc} gdoc-specific + {n_axis} axis).`

**Reviewer-failure handling.** After agents return, verify each output file exists and matches the schema (has the Checklist block). For each missing or malformed file: present `{reviewer} failed. (1) Retry this reviewer, (2) Skip (partial review, mark findings.md incomplete), (3) Abort.` Wait for user pick.

### Challenge

For each reviewer finding, record a verdict in `challenge-log.md`:

```
[formatting.md#1] real=Y fix-safe=Y cost=low → keep
[brevity.md#3] real=N → drop (cited rule "headings should be sentence case" not in any loaded source)
[factual.md#2] real=Y fix-safe=N → drop (suggested fix hardcodes SHA, itself violates format rule)
```

Three gates per finding (ALL must pass for `keep`):
1. **Real** — rule cited actually exists in `/ari-hemingway--format-gdoc`, the loaded sibling `review-rules.md`, OR one of the loaded axis skills (`review-brevity`, `--clarity`, `--factual`, `--kr`, `--audience-fit`). If the reviewer invented a rule → drop.
2. **Fix-safe** — the suggested fix is itself rule-compliant (no hardcoded SHAs, no branch permalinks, no markdown gdoc links, no marketing language reintroduced, etc.). If not → drop.
3. **Cost-justified** — fix isn't more disruptive than the violation.

**Cross-reviewer merge.** If two or more reviewers flagged the same line or the same rule, merge into one finding. Record in `challenge-log.md`:
```
[formatting.md#4] + [links.md#1] → merged as findings.md#3 (same line, same rule, different lenses)
[brevity.md#2] + [kr.md#5] → merged as findings.md#7 (both flagged the same filler word)
```

**Scope violations → spec-questions.md.** Any fix that would change the doc's subject, scope, or intent (rename `#` sections to mean something different, delete entire sections' worth of content) goes to `spec-questions.md`, not `findings.md`.

Write `challenge-summary.md`:
```
Challenged {total} findings from {N} reviewers ({n_gdoc} gdoc + {n_axis} axis). Kept {X}. Dropped {Y} ({reasons}). Merged {Z} across reviewers. Spec-questions: {W}.
```

Print: `Challenge complete — kept {X}, dropped {Y}, merged {Z}. Next: Rank.`

### Rank

Score every kept finding in `findings.md`:

```
incorrect_behavior = 5  (draft will mislead readers — wrong SHA, fabricated claim, broken link)
silent_failure     = 4  (looks fine, behaves wrong — markdown gdoc link not rendering as smart chip)
missing_required   = 4  (required section absent)
multi_reviewer     = 3  (flagged by ≥2 reviewers)
flaky_compliance   = 2  (example pulls reader toward reproducing the violation)
ambiguity          = 1
polish             = 0

score = sum of applicable criteria
tiebreak = source-line-number ascending
```

Record `Score:` on each finding. Rank descending.

Print: `Rank complete — {n} findings, top score {max}. Next: Present.`

### Present

**Zero-findings short-circuit.** If `findings.md` has no entries AND `spec-questions.md` has none: print `Review complete — no findings. Draft is clean per the checked rules.` and skip the menu.

Otherwise:
1. Print the `findings.md` path.
2. Show the ordered list inline (one entry per finding, in the `findings.md` schema).
3. If `spec-questions.md` non-empty: `These touch the doc's purpose or scope — your call:` then list entries by SQN.
4. Optionally summarize: `Challenge: {X} kept, {Y} dropped, {Z} merged. Full log: {investigation_folder}/challenge-log.md.`
5. Print menu:
```
Which to apply?
- all                — apply every finding
- numbers            — e.g., "1, 3, 5"
- top N              — e.g., "top 5"
- clarify            — if ambiguous, I'll echo back my parse
```

**Ambiguous answer handling.** If the response doesn't match the above, echo the parsed interpretation and re-ask:
```
I read "{user input}" as "apply findings {X, Y}". Confirm? Or pick: all / numbers / top N.
```
Do NOT guess.

If invoked from another skill, return the approved list to the caller rather than writing anything else.

Print: `Present complete — {k} findings selected.` (or `... 0 selected — closing review.` if zero-findings path fired.)

## Reviewer panels

### gdoc-specific reviewers (defined here, prompts use Template A)

| Reviewer | Output file | Rules (sections in `/ari-hemingway--format-gdoc`) | Check bullets |
|---|---|---|---|
| Formatting | `formatting.md` | Document conventions → Title, sections, footer; Diagrams; Tables | Title plain text + starts with `[🤖 AI generated]`; final line exactly `🤖🌸 Generated with Claude Code`, optionally followed by ` with the ari-hemingway skill`; emoji literals preserved; sections start at `#`; subsections `##`; no skipped heading levels; diagrams are `[![alt](ink_url?width=620)](live_url)`: an image linked to its mermaid.live source, width capped at 620 px; each diagram plausibly fits one page (a nested flowchart past ~8 nodes or a long vertical chain is flagged); every table has a header row (styling is applied by `/ari-hemingway--share-gdoc` at publish, so flag any plan to paste the doc by hand) |
| Links | `links.md` | Link formatting; Link formatting → Link density; Useful links | First-mention code refs are `/blob/{sha}/` permalinks with full 40-char SHAs; later mentions bare backticks; new `#` sections reset the counter; aliases re-link; code without repo location uses bare backticks (not fabricated permalinks); every named external entity (source-by-title, product/tool, company, person, protocol/spec) is hyperlinked at its first mention in the body, not just listed in `# Useful links`; PR refs use full title + number + escaped brackets; `docs.google.com`/`drive.google.com` URLs are raw (not markdown), so the publish step can chip them; no mention of a Claude skill outside the footer, so no skill names in the body, no `github.com/AriSweedler/dotfiles/...` URL, and no `## Code and PRs` block listing the toolchain; request flows are numbered lists; `# Useful links` section is present and inventories every URL in the body + every resource named but not linked inline |
| Typography | `typography.md` | Typography → Jargon and literal tokens | Every technical jargon / literal token is backticked: protocol tokens (`|c`, `|ms`, `:1|c`), wire formats, daemon / port / path / env-var / command names, metric type names, and acronyms used as literals (`UDP`, `TCP`, `OTLP`, `HTTP`) when naming the literal protocol/token rather than reading as prose; an acronym reading as prose is left unbackticked |
| Scaffolding | `scaffolding.md` | Document conventions skeleton + sibling `review-rules.md` `Required sections`, `Reshape rules` | Required sections present and in order; no required section empty (or contains mandated fallback text like "None found during research"); section sizes proportional to doc's target word count; flow-diagram trigger respected per sibling rules; reshape rules not violated (optional sections renamed only to concrete titles, merges stay under size cap) |
| Sibling (conditional) | `sibling.md` | `$HOME/.claude/skills/ari-hemingway--structure-{skill-name}/review-rules.md` — all sections | Every constraint in the sibling's `review-rules.md`; fires only when `Identify sibling` step loaded one |

### axis reviewers (delegated, prompts use Template B)

| Reviewer | Output file | Source of rules |
|---|---|---|
| Brevity | `brevity.md` | `$HOME/.claude/skills/ari-hemingway--review-brevity/SKILL.md` |
| Clarity | `clarity.md` | `$HOME/.claude/skills/ari-hemingway--review-clarity/SKILL.md` |
| Factual | `factual.md` | `$HOME/.claude/skills/ari-hemingway--review-factual/SKILL.md` |
| K&R | `kr.md` | `$HOME/.claude/skills/ari-hemingway--review-kr/SKILL.md` |
| Audience-fit | `audience-fit.md` | `$HOME/.claude/skills/ari-hemingway--review-audience-fit/SKILL.md` (destination = `gdoc`) |

## Examples

### Slug derivation walkthrough

- Input: `/tmp/hemingway/subsystem-explainer/widget-cache-invalidation-ab3f9c/20260416-120000-7a3c/draft.md`
- Auto-detect: path matches `/tmp/hemingway/{skill-name}/` → `skill-name = subsystem-explainer`.
- Doc first line: `[🤖 AI generated] Widget Cache Invalidation` → title exists.
- Slug source: title → `widget-cache-invalidation-{sha1:0:6}`.
- Print: `Slug derived from: title.`

### Per-reviewer output (formatting reviewer, one finding)

```markdown
## Checklist
- [x] Title plain text + starts with `[🤖 AI generated]`: PASS
- [x] Final line `🤖🌸 Generated with Claude Code`: PASS
- [ ] Emoji literals preserved: FAIL (see Finding #1)
- [x] Sections start at `#`: PASS
- [x] Diagrams are images: N/A (no diagrams)

## Finding 1

- **Rule violated**: Document conventions → Title, sections, footer (`/ari-hemingway--format-gdoc`)
- **Location**: Line 1
- **Severity**: major
- **Problem**: Title uses `[AI generated]` (ASCII) instead of `[🤖 AI generated]` (emoji literal).
- **Fix**: Replace `[AI generated]` with `[🤖 AI generated]`.
```

### Per-reviewer output (kr axis reviewer, one finding)

```markdown
## Checklist
- [x] Rule 1 — no marketing adjectives untethered to a concrete fact: PASS
- [ ] Rule 2 — no unqualified hedges: FAIL (see Finding #1)
- [x] Rule 3 — imperative voice for instructions: PASS

## Finding 1

- **Rule violated**: K&R rule 2 (no hedging) (`/ari-hemingway--review-kr`)
- **Location**: Line 18
- **Severity**: polish
- **Problem**: "The cache typically holds 10K entries" — `typically` without a named exception.
- **Fix**: "The cache holds 10K entries; spikes to 12K under heavy load" — replace hedge with the specific exception.
```

### findings.md entry (after merge across gdoc-specific and axis)

```markdown
## 3. Hardcoded `Hyperbase/hyperbase/blob/a1b2c3d/` in permalink

**Flagged by:** links, factual
**Rule:** Link formatting → Permalinks for code references (`/ari-hemingway--format-gdoc`) + Factual rule on permalink format (`/ari-hemingway--review-factual`)
**Location:** Lines 42, 58
**Severity:** blocker
**Score:** 9 (silent_failure=4, missing_required=0, multi_reviewer=3, flaky_compliance=2)
**Problem:** Uses hardcoded repo name and 7-char SHA instead of `{owner_repo}` / full 40-char `{sha}` placeholders; other-repo readers will follow the example and produce broken permalinks.
**Fix:** Replace with `https://github.com/{owner_repo}/blob/{sha}/server/widget_cache.tsx#L42` on both lines.
```

### Dropped finding

```
[brevity.md#7] Reviewer flagged: "Sentence is over 30 words."
Challenge: real=Y, fix-safe=Y, cost=low. → keep, score=1 (ambiguity).

[scaffolding.md#2] Reviewer flagged: "Headings should be in title case."
Challenge: real=N → drop. No such rule in /ari-hemingway--format-gdoc or sibling review-rules.md; reviewer invented it.
```

### Cross-axis merge

```
Before:
  [brevity.md#3] "in order to" → "to" at line 14.
  [kr.md#6] Rule 9: "in order to" replaced with "to" at line 14.

After:
  [findings.md#5] merged from brevity.md#3 + kr.md#6
  Score: multi_reviewer=3, polish=0 → 3
```

### Scope violation (→ spec-questions.md)

```
[scaffolding.md#7] Reviewer suggests renaming `# How it works` → `# Architecture`.
Challenge: real=Y, fix-safe=Y, cost=low. But: changes the doc's contract per /ari-hemingway--structure-subsystem-explainer
  review-rules.md (How it works is REQUIRED with that exact title).
→ spec-questions.md as SQ1: "Sibling explicitly requires `# How it works`. Review wants `# Architecture`. Reviewer over-reached."
```
