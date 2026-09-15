---
name: ari-hemingway--structure-post-mortem
description: "Write or update incident post-mortems as quick explainers. Three sections: summary, timeline, detailed explanation. Every claim must link to an external factual source. Three modes: research (from scratch), distill (from session/investigation knowledge), update (improve existing draft). Distinct from /ari-hemingway--structure-design-doc, which proposes a future change; a post-mortem describes a past incident."
---

# Incident Post-mortem (Quick Explainer)

A short, link-dense explainer of a past incident: what happened, when, and why. Optimized for a reader who wasn't there and has 5 minutes. Targets a Google Doc.

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns (investigation folder, restore context, drafting, permalink resolution, fact-check, present/output): see `/ari-hemingway--lib`. If any rule here contradicts `/ari-hemingway--format-gdoc`, the format skill wins.

## Document structure

Final section order, top to bottom:

1. **Summary** — 2–4 sentences. Broad strokes only: what broke, when, root cause in one phrase, how it cleared. No timestamps deeper than the hour. No code references. A reader who stops here knows the shape of the incident.
2. **Timeline** — one bullet per load-bearing event. Each bullet ends with a parenthetical citation linking to the source: a Datadog event URL, OpenSearch log permalink, Slack message permalink, GitHub commit, or AWS console reference. No claim without a link. Times in Pacific Time per `/ari-hemingway--format-gdoc` `## Timestamps`. **First line under the `# Timeline` header MUST be the disclaimer `All times are in Pacific Time.` on its own line.**
3. **Detailed explanation of what went wrong** — the technical narrative. Trigger, contributing factors, root cause. Each claim must cite a source (inline link or end-of-sentence parenthetical). Cite verbatim error messages, monitor IDs, instance IDs, ASG names. If a claim can't be sourced, mark it explicitly: *"Suspected: ... ; not confirmed because ..."*.

That's the whole document. No "what went well", no "lucky vs unlucky", no follow-ups — those belong in a deeper RCA. This is the explainer.

## Rules

### Data sources and tooling

When investigating or fact-checking, use these tools for these data sources. Don't substitute.

| Source | Tool | Notes |
|---|---|---|
| Datadog (events, metrics, monitors, logs, traces, dashboards) | `mcp__datadog__*` MCP server | Use directly. Includes `search_datadog_events`, `aggregate_events`, `search_datadog_logs`, etc. |
| OpenSearch (application logs) | `/opensearch-query` skill | OpenSearch MCP exists but is not yet available in this environment. Use the skill (CLI path) for now. When OpenSearch MCP shows up in the tool registry, switch to it. |
| Slack threads | `mcp__escalation_mcp_server__slack_*` | Use for resolving thread permalinks and reading messages cited as sources. |
| Google Docs (playbooks, design docs) | `mcp__escalation_mcp_server__google_docs_read_document` | When a citation points to a gdoc. |

If a post-mortem claim depends on data that lives in one of these sources, query it directly — don't paraphrase from someone else's summary. The earlier you query, the cheaper the iteration.

**AWS-side data (CloudTrail, EC2 console, ASG history, etc.):** prefer the four sources above when they're sufficient. The AWS MCP isn't reliable yet, and shelling out to `aws` CLI is something the user can do but generally doesn't want to — most post-mortem questions resolve through Datadog events (resource changes, alerts), OpenSearch logs, or Slack thread context. Only ask the user to run AWS CLI when none of those can answer the question — and say specifically which CLI command would help, so they can decide whether it's worth it.

### The load-bearing rule: every claim has a link

This is the single non-negotiable rule of this skill.

- Every timestamp links to its source event (Datadog event URL, OpenSearch query URL with time bounds, Slack message permalink).
- Every named identifier (monitor ID, ASG name, instance ID, pod name, PR number, IAM role) appears verbatim and links to its canonical reference.
- Every causal claim ("X caused Y") links to evidence — a log line, a metric chart, an AWS docs page describing the mechanism.
- If you can't link it, you can't claim it. State the gap instead: *"The actual IPAMD error message is not recoverable — aws-node logs aren't shipped to OpenSearch and the host was terminated at 21:08."*

A post-mortem without links is a story. A post-mortem with links is evidence.

### Don't inline-qualify what the link already proves

The citation is the proof. Don't pad a claim with "*(per Halo's timeline; not directly verified against monitor history)*" or "*(constructed from query + time range; verify before sharing)*" parentheticals. They're noise; the reader can click the link and see for themselves.

The flow is:
1. Made the claim → link it. Done. No qualifier.
2. Couldn't verify the claim from a primary source but it appears in a secondary source (Halo, another investigator) → either upgrade the verification (query the primary source directly) or DON'T MAKE THE CLAIM. Don't ship a half-asserted, half-hedged sentence.
3. Claim is your interpretation and not sourced anywhere → mark it `**Suspected:**` / `**Inference:**` and explain why it isn't verified. This is the ONLY acceptable case for hedging in prose.

Wrong:
> 20:59:28 — Monitor X fired. *(Per Halo; not cross-checked against monitor history.)*

Right (either):
> 20:59:28 — Monitor X fired. *(link to the Datadog monitor event)*
> *or*: omit the bullet entirely until you've verified it.

### Timestamps

All timestamp formatting, timezone conversion, and rendering rules live in `/ari-hemingway--format-gdoc` `## Timestamps`. Post-mortems inherit those rules verbatim — format (`Month DD, YYYY HH:MM:SS`), Pacific Time conversion with correct DST offset, no TZ suffix, no bolding, full-form on first mention per section, tables use full form in every cell.

Post-mortem-specific overlay (not in format-gdoc because it's about section placement, not format):
- The `# Timeline` section MUST start with the disclaimer `All times are in Pacific Time.` on its own line, immediately under the header.
- Same disclaimer is recommended for any other section with ≥3 timestamps (e.g., a dense "How it cleared" passage). Use judgment.

### Link text for Datadog event explorer

When linking to a Datadog Event Explorer query, the link text MUST start with `Datadog event explorer:` followed by a short description of what the query covers.

- GOOD: `[Datadog event explorer: k8s events on node ip-172-30-98-110, 18:29-22:29 UTC](https://app.datadoghq.com/event/explorer?...)`
- GOOD: `[Datadog event explorer: fleetwide `failed to assign an IP` events, 20:14-20:35 UTC](https://app.datadoghq.com/event/explorer?...)`
- BAD: `[Datadog events on the node](https://...)` — doesn't name the destination tool
- BAD: `[k8s events on node ip-172-30-98-110](https://...)` — same

Rationale: reader scanning the doc should know what's behind the link before clicking, both the platform (Datadog Event Explorer) and the specific query scope. The same convention applies to OpenSearch shareable links (`OpenSearch dashboards:`) and Datadog dashboards (`Datadog dashboard:`).

### Datadog Event Explorer URL template

A minimal-looking URL (just `?query=...&from_ts=...&to_ts=...`) **does not load the absolute time range correctly** when clicked — Datadog's UI silently falls back to a relative window of size `to_ts − from_ts` ending at "now". For historical post-mortem citations, you need the explorer in **paused/absolute mode**.

### The single most important param: `live=false`

**Every Datadog Event Explorer URL in a post-mortem MUST include `&live=false`.** Without it (or with `live=true`), Datadog interprets `from_ts` / `to_ts` as a rolling-window duration ending at "now" and the link silently shows the wrong data — usually "Past N minutes" where N is `(to_ts − from_ts)/60000`. This is the #1 failure mode for shared Datadog links.

There is no scenario in a historical post-mortem where `live=true` is correct. If you find yourself omitting `live=false` "because the URL looks cleaner without it," stop and add it back. The reader's clock is not the incident's clock.

### Full template

```
https://app.datadoghq.com/event/explorer?query={URL-encoded query}&fromUser=true&messageDisplay=expanded-lg&options=&refresh_mode=paused&sort=timestamp%2Casc&view=all&from_ts={start_ms}&to_ts={end_ms}&live=false
```

Required params (don't drop any, don't change the values):
- `query` — URL-encoded Datadog event query.
- `fromUser=true` — marks the URL as user-shared (vs. auto-generated).
- `messageDisplay=expanded-lg` — readable event rendering.
- `options=` — empty but required.
- **`refresh_mode=paused`** — anchors the time range to the absolute `from_ts` / `to_ts` below. Using `refresh_mode=sliding` instead causes Datadog to treat the range as a rolling window of duration `(to_ts − from_ts)` ending at "now".
- `sort=timestamp%2Casc` — ascending chronological order. Use `-timestamp` (descending) only if you specifically want most-recent-first.
- `view=all` — shows all events, not just the latest.
- `from_ts` / `to_ts` — Unix epoch in **milliseconds**, not seconds.
- **`live=false`** — see the callout above. Non-negotiable. Always present.

### Verification before shipping

Click every Datadog URL in the doc before finalizing. The correct behavior: explorer opens with the time picker showing your explicit `MM/DD HH:MM` range, NOT "Past N minutes". If you see "Past N minutes," `live=false` is missing or `refresh_mode` is set to `sliding`. Fix and re-verify.

### Content scope — quick explainer

300–800 words total. If the draft trends past 800, the *Detailed explanation* is doing the work of a deeper RCA — split it out and link from this doc.

Summary specifically: 2–4 sentences, < 80 words. Reading it aloud should take under 30 seconds.

### Tone — blameless and past tense

- Past tense throughout. The incident is over; describe what happened, not what is happening.
- Blameless. Name systems and decisions, not people. "The on-call paged at 20:35" not "Alice paged at 20:35".
- No softening. "The monitor didn't fire" not "the monitor could have fired sooner". State facts directly.

### Root cause depth

- Distinguish *trigger* (what kicked it off) from *contributing factors* (what made it worse) from *root cause* (the underlying weakness).
- If you can't get to a clean root cause from the evidence, say so. Write "Suspected: ... ; not confirmed because ..." rather than asserting.
- Don't conflate symptoms with causes. "Pods couldn't get IPs" is a symptom. "Subnet IP exhaustion in us-east-1a" is a candidate root cause.

### What this skill is NOT

- Not a design doc. If you're proposing a *future* change, use `/ari-hemingway--structure-design-doc`.
- Not a deep RCA. If the analysis genuinely needs *what went well*, *lucky vs unlucky*, or *follow-ups with owners*, that's a fuller post-mortem template — out of scope here.
- Not a status update. If the incident is ongoing, write a Slack update first; come back to this skill after resolution.

## Investigation folder

Root path: `/tmp/hemingway/post-mortem/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`.

## Workflow

### Determine mode

Ask once:

```
Which mode?
(1) research  — start from scratch; you give me the incident anchor (alert URL, Slack thread, ticket) and I investigate
(2) distill   — turn an existing investigation in this session's context (findings.md, transcript, scratch files) into a post-mortem
(3) update    — improve an existing post-mortem draft (give me the path or gdoc URL)
```

Auto-detect:
- If there's an `output.md`, `findings.md`, or similar in the session's investigation folder, suggest *distill*.
- If the user provided a markdown path or gdoc URL upfront, suggest *update*.
- Otherwise, *research*.

### Gather pointers

Follow `Gather pointers` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

Post-mortem-specific anchors to ask for:
- Incident detection time (when did the alert fire / customer report come in?)
- Incident resolution time (when did the symptom clear?)
- Alert URL or monitor ID
- Slack thread where triage happened
- Ticket if one was filed

### Restore context

Follow `Restore context` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

In *distill* mode, the prior investigation is the primary source — read it first (`findings.md`, scratch notes, transcript permalinks) before any fresh queries. In *research* mode, expect to query Datadog/OpenSearch/Slack fresh.

### Investigate

Per-mode:

- **research**: full investigation per `/ari-hemingway--lib` cadence. Build a timeline from raw events, not from human memory.
- **distill**: cross-reference the existing investigation against the three required sections. Confirm every timeline entry has a source link; flag any that don't.
- **update**: read the existing draft, identify which claims lack links, ask the user which to keep vs. rework.

### Draft — two-pass procedure

The draft happens in two passes. Don't skip the order; the final shape depends on it.

**Pass 1 — write in causal order, not reading order:**

1. **Timeline first.** Build it directly from raw event sources (Datadog events, OpenSearch hits, Slack permalinks). One bullet per load-bearing moment, each with its citation. This is the spine — everything else hangs off it.
2. **"What went wrong" summary second.** Once the timeline exists, write 1–2 paragraphs explaining what the timeline *means* — what the failure mode was, what cleared it. This is a *working* summary; it will get rewritten in pass 2.
3. **Detailed explanation third.** Expand on the failure mode: trigger, contributing factors, root cause, with citations on every claim. This is where verbatim error messages, monitor IDs, and mechanism explanations live.

At the end of pass 1, sections are in order: Timeline → Summary → Detailed. Every claim is linked.

**Pass 2 — reshape for reading:**

1. **Move the summary to the top.** Final order becomes: Summary → Timeline → Detailed.
2. **Rewrite the summary in broad strokes.** Strip out anything that requires the timeline or detail to make sense. Target 2–4 sentences, < 80 words, < 30 seconds aloud. The summary should answer "what was this incident" — not "what's the technical mechanism". A reader who reads only the summary should know enough to decide whether to keep reading.
3. **Re-verify links.** The reorder is a good moment to confirm no claim in any section lost its citation in the shuffle.

Follow all `/ari-hemingway--format-gdoc` rules throughout.

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

Post-mortem-specific fact-check additions:
- Every timestamp in the timeline must trace to a real event (Datadog event ID, log line, Slack permalink). Click each link; confirm it resolves to the cited event.
- Every monitor ID, ASG name, instance ID, pod name, and error string must be verbatim — copy-paste from the source, don't retype.
- Every causal claim must have at least one citation. If a claim is your interpretation rather than a sourced fact, mark it ("Inference:" / "Suspected:") rather than asserting it flat.

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Output

Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.
