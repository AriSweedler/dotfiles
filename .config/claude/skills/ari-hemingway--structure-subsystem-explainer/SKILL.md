---
name: ari-hemingway--structure-subsystem-explainer
description: "Write or update concise explainer documents for subsystems. Three modes: research (from scratch), distill (from session knowledge), update (improve existing doc)."
---

# Subsystem Explainer

Produce explainer documents for subsystems in three modes: **research** (from scratch), **distill** (from session knowledge), **update** (from an existing doc).

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns (investigation folder, restore context, drafting, permalink resolution, fact-check, present/output): see `/ari-hemingway--lib`. If any rule here appears to contradict `/ari-hemingway--format-gdoc`, the format skill wins.

## Modes

- **Research** — given a subsystem name and optional pointers, investigate the codebase and produce an explainer from scratch.
- **Distill** — during or after a session where the user has been learning about a subsystem (e.g., working on a PR), condense what was learned into an explainer.
- **Update** — given a pointer to an existing explainer (Google Doc URL or ID), read it, compare against current codebase state, and propose changes.

## Document structure

Required sections, in order:
- Title (plain text, starting with `[🤖 AI generated]` per `/ari-hemingway--format-gdoc`)
- `# Summary` — one sentence per distinct capability, never exceed 4 sentences
- `# How it works` — core mechanism; flows as numbered steps
- `# Gotchas` (see "Gotchas vs Operational notes" below)
- `# Useful links` — required final section before the footer, per `/ari-hemingway--format-gdoc`

Optional and reorderable (appear between `# Gotchas` and `# Useful links`): `# Key details`, `# <Comparison>`, `# Integration points`, `# Operational notes`.

### Gotchas vs Operational notes

- **Gotchas** = what surprises you: race conditions, failure modes from git history, non-obvious constraints. **Required.**
- **Operational notes** = what you do: debug, rotate, restart, intervene commands. **Optional.**

If research surfaced zero gotchas, the Gotchas section body MUST be exactly `None found during research.` NEVER omit the section, even when empty.

### Reshape latitude

Other sections MAY be altered only as follows:
- Rename a section only to a title that names the subject concretely (e.g., "Key details" → "Shard routing rules"). NEVER to a vaguer title.
- Merge two adjacent optional sections if combined content is under 300 words.
- Drop an optional section if it would contain fewer than 2 bullets/rows.

Any reshape beyond this list MUST be called out in the update-mode diff summary.

### Flow diagram trigger

Include a flow diagram in `How it works` if EITHER: ≥4 numbered steps, OR the flow spans ≥3 distinct services. Otherwise omit. Follow the `Diagrams` procedure in `/ari-hemingway--format-gdoc`.

### Update-mode diff summary

Each bullet: `**[section]** — verb: detail.` Allowed verbs: `added | removed | corrected | renamed`.
- Corrections include both values: `corrected: X → Y per commit abc123.`
- Prose rewrites include word-count delta: `rewritten — 78 → 62 words.`
- Renames include old AND new headings: `**[Overview → Summary]** — renamed and tightened.`

Group into: `## Fact corrections`, `## Additions`, `## Removals`, `## Prose/structure edits`. User may approve categories selectively.

### Skeleton

```
[🤖 AI generated] Title Goes Here

# Summary
One sentence per distinct capability. Never exceed 4 sentences.

# How it works
Core mechanism. Flows, numbered steps.

# Gotchas
Race conditions, failure modes, non-obvious constraints. "None found during research." if empty.

# Key details (optional)
Tables of config, paths, flags, naming conventions.

# <Comparison section> (optional)
Side-by-side table; title names both: "emptyDir vs hostPath".

# Integration points (optional)
How this subsystem connects to other systems.

# Operational notes (optional)
How to debug, rotate, restart, or intervene. Commands with real arguments.

# Useful links
Complete inventory per `/ari-hemingway--format-gdoc` — every URL inlined above, plus every resource mentioned by name but not linked inline.

🤖🌸 Generated with Claude Code
```

### Structural example

Structural skeleton only — NOT a target length. See word-count buckets in `## Rules` for real targets.

```markdown
[🤖 AI generated] Widget Cache Invalidation

# Summary

Widget cache invalidation ensures stale widget configs are evicted within 60 seconds of a schema change. Without it, users see outdated widget layouts after field deletions.

# How it works

1. A schema change commits to the live shard.
2. The Worker Child publishes a `WIDGET_INVALIDATE` message to Redis Pub/Sub.
3. All Worker Parents subscribed to the channel evict matching entries from their LRU cache.
4. The next widget render fetches fresh config from the shard.

# Gotchas

TTL and LRU eviction can both evict — dual eviction means metrics undercount invalidations by ~5%. Discovered during [[fix] Race condition in widget cache eviction (#198432)](https://github.com/{owner_repo}/pull/198432).

# Key details

| Setting | Value | Source |
|---|---|---|
| Redis channel | `widget:invalidate:{appId}` | [`widget_cache.tsx` L42](https://github.com/{owner_repo}/blob/{sha}/server/widget_cache.tsx#L42) |
| LRU max entries | 500 | [`widget_cache.tsx` L18](https://github.com/{owner_repo}/blob/{sha}/server/widget_cache.tsx#L18) |
| TTL | 60s | [`widget_cache.tsx` L19](https://github.com/{owner_repo}/blob/{sha}/server/widget_cache.tsx#L19) |

# Useful links

## Code and PRs
- [`widget_cache.tsx`](https://github.com/{owner_repo}/blob/{sha}/server/widget_cache.tsx#L1)
- [[fix] Race condition in widget cache eviction (#198432)](https://github.com/{owner_repo}/pull/198432)

## Docs
- see https://docs.google.com/document/d/1abc123_widget_cache_design

🤖🌸 Generated with Claude Code
```

## Rules

### Content scope — word count by scope

Walk buckets top-to-bottom; first match wins. Record the chosen bucket in `scratchpad.md` under `Bucket:` before drafting. Re-check word count at Draft step.

| Scope | Words |
|---|---|
| Single file or single script, no cross-service calls | ≤600 |
| One service, 2-5 named collaborating services/packages | 600-1800 |
| Multiple services OR more than one team | >1800 |

"Collaborators" = distinct service or package that calls or is called by this subsystem.

### Distill mode — incident attribution

- **An incident MUST have ALL of:** (a) date OR PR/commit link, (b) named failure mode, (c) explicit user statement OR linked post-mortem. If any is missing, MUST omit the incident entirely — do NOT infer or reconstruct.
- **Every included incident MUST carry inline attribution:** `Discovered during [specific user statement or PR]`.

GOOD: `An incident related to widget cache eviction was discussed — details not captured. [TODO: verify with user]`
BAD: `On 2025-11-14, a race condition caused stale widgets for 40 minutes until operators flushed Redis.` — date, duration, remediation fabricated.

## Investigation folder

Root path: `/tmp/hemingway/subsystem-explainer/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`.

**Mode-specific scratchpad fields.** Append to the `/ari-hemingway--lib` baseline:
```
- **Bucket**: ≤600 | 600-1800 | >1800
- **Distill supplements**: N (distill mode only)
```

## Workflow

### Determine mode

Evaluate in order, first match wins:
1. User's message contains a Google Doc URL OR the phrase "update this explainer" → **update**.
2. Current conversation contains 3+ Read/Grep/Bash(git) tool calls AND the user references a named subsystem AND those calls target files/paths under that subsystem's directory → **distill**.
3. Otherwise → **research**.

If both `update` AND `distill` conditions fire: infer **update-with-distill-context** (fetch doc + use conversation reads as evidence for the diff).

Print one line and continue straight into Gather pointers; do not ask for confirmation:
```
Inferred **{mode}**: {evidence}.
```
`{evidence}` cites the trigger: "you pasted a Google Doc URL", "this session contains 12 file reads under services/autoscaler/", etc. The user overrides by naming a mode at any point; on override, set `Mode` in the scratchpad and restart Investigate.

### Gather pointers

Collect user-provided pointers: code paths, doc URLs, PR links, subsystem names, config files. In distill mode, also harvest file reads and findings from the current conversation. Derive `{topic-slug}` per `/ari-hemingway--lib`. Create the investigation folder. Write the initial scratchpad (Subject, Mode, Bucket, Pointers).

### Restore context

Follow the `Restore context` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Resolve permalink SHA

Follow the `Resolve permalink SHA` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Investigate

Append to `sources.md` and update `scratchpad.md` key findings per the cadence in `/ari-hemingway--lib` (every batch of ≤3 Read/Grep/Bash calls).

**Research mode** — grep for the subsystem name, read key files, trace entry points, check git log for recent changes, read related docs. If tracing requires following function calls across ≥3 files to explain a single flow, follow the procedure in `$HOME/.claude/skills/ari-code-trace/SKILL.md` and record its artifact path in `sources.md` under "Call graphs". See `/ari-hemingway--lib` for failure contracts.

**Scaffold first when the vocabulary is missing.** If the subsystem has more than ~8 terms of its own jargon that neither you nor the reader can define, or the user asks to "break it down" or "explain the parts", STOP and run `/ari-hemingway--structure-scaffold` instead: its definitions pass builds the strictly ordered shared-jargon table, and each explainer section is then written in that vocabulary. Reuse the accepted table as this doc's `# Key details` glossary rather than re-deriving terms inline. Record the scaffold's investigation folder under `Pointers`.

**Distill mode** — the conversation is the primary source. Supplement with targeted reads for claims not yet attributable to a file read, grep result, or user statement. Count supplemental reads in `scratchpad.md` under `Distill supplements`. **On reaching 6, MUST stop** and print:
```
Distill supplement budget exceeded (6 reads). Switch to research? (y/N)
```
On yes: update scratchpad `Mode: research (switched from distill at {timestamp})`, then restart Investigate without re-running mode confirmation.

**Distill evidence check (before drafting).** Enumerate the candidate subsystem(s) the session's reads touched. If reads don't cluster around a single subsystem, ask: `The session touched {list}. Which should I distill?` If the user has no answer, STOP.

**Update mode** — fetch the existing doc via `mcp__escalation_mcp_server__google_docs_read_document`. After fetching, print `Target doc: {title} — last edited {date}.` and proceed.

On fetch failure, follow the `MCP reliability` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Option 3 is "switch to research mode".

**Update-mode diff collection.** Compare EACH of the following against the current codebase and record deltas in `scratchpad.md`. Do NOT skip a claim because it "probably hasn't changed."
- Every file path, line number, and permalink SHA in the doc.
- Every config value, flag, environment variable.
- Every command (verify flags still exist).
- Every numbered flow step (re-read the code; note adds/removes/reorders).
- Every named component (confirm it still exists at that name).

If the existing doc's heading doesn't map to the new structure, tag with the OLD heading in the diff: `- **[Overview → Summary]** — renamed and tightened.`

#### Research quality gate

A concrete fact, as defined in `/ari-hemingway--format-gdoc` prose style, is anchored to a specific code location. Two facts sourced from the same file/line count as one.

Gate by subsystem size:
- **Utilities (<200 LOC or single file):** minimum 1 concrete fact + verified code location.
- **All others:** minimum 3 concrete facts.

GOOD fact: `` `widget_pruner.tsx` runs every 30 minutes via `setInterval` at L47. ``
NOT a fact: `The widget pruner handles cleanup.` — no path, no value.
NOT a fact: `It probably uses Redis.` — speculative.

If the minimum is not met, MUST stop:
- **0 concrete facts:** print `Subsystem name may not map to anything in the codebase. Double-check spelling, or provide a file path pointer.`
- **Below minimum but non-zero:** print what was found and offer: (1) Provide more pointers, (2) Broaden the topic, (3) Abort.

Good broaden: `widget pruner` (too narrow, 2 facts) → `widget lifecycle: pruner + cache invalidation + LRU eviction`. Bad broaden: `widgets` — unbounded.

Print: `Investigate complete — {n} files read, {m} grep queries. Next: Draft.`

### Draft

Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` and all `/ari-hemingway--format-gdoc` rules.

Confirm the draft's word count lands within the bucket recorded in `scratchpad.md`. If over, cut before printing.

Print: `Draft complete — {sections} sections, {words} words. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

Print: `Fact-check complete — {n} claims verified, {k} marked [TODO: verify]. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`: print the draft path and the `Draft ready` line, then continue into Output without a menu.

In update mode, print the diff summary (grouped per "Update-mode diff summary" above) before the `Draft ready` line. An empty diff means the doc is already accurate: print `No changes needed — the doc is already accurate.` and stop instead of publishing.

### Output

Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. In update mode the publish passes `--doc` to `/ari-hemingway--share-gdoc`, which replaces the whole body; say that manual edits in the Doc are lost before it runs.
