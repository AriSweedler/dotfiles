---
name: ari-hemingway--format-gdoc
description: "Shared formatting conventions for Google Doc-bound skills. Not user-invocable — referenced by `/ari-hemingway--*` skills."
user_invocable: false
---

# Google Doc Formatting

Reference formatting rules for any skill that produces a Google Doc. Siblings follow these rules; they do not invoke this skill. Workflow patterns (investigation folder, drafting, permalink resolution, fact-check, present/output) live in `/ari-hemingway--lib`.

## Timestamps

Google Docs renders `@`-typed date strings as smart chips — but smart chips do not carry timezone metadata. A timestamp pasted with a TZ suffix (`UTC`, `PT`, `PDT`) either fails to chip, or chips and silently drops the TZ. Either way, the reader sees a timezone-less value. Mixing TZs in a single doc therefore creates ambiguity that the reader can't resolve.

### Hard rules

1. **All displayed timestamps MUST be in Pacific Time** (Airtable's primary TZ). Convert every UTC, ET, GMT, ISO-with-Z, or local-other-zone source to PT before rendering.
2. **Apply the correct DST offset for the event date.** Pacific Time switches between PDT (UTC−7, in effect roughly second Sunday of March → first Sunday of November) and PST (UTC−8, the rest of the year). Use the offset that was in effect *at the moment of the source event*, not "today's" offset. A May event uses UTC−7; a January event uses UTC−8.
3. **No TZ suffix on the timestamp itself.** Not `UTC`, not `PT`, not `PDT`, not `PST`. Bare. Smart-chip constraint.
4. **Format: `Month DD, YYYY HH:MM`** — 24-hour clock, full date, **minute precision only**. Example: `May 21, 2026 13:36`. No leading zero on the day (`May 1, 2026` not `May 01, 2026`). Leading zeros on hours and minutes. **Strip seconds from every source timestamp** — log lines, Datadog events, and monitor fires all carry second precision; truncate (don't round) when converting for the doc. Two events in the same minute become indistinguishable in the doc; that's fine for a quick-explainer. If sub-minute ordering actually matters for the narrative, that's a different document (a deep RCA), not this skill.
5. **Top of every timestamp-heavy section MUST include a one-line TZ disclaimer.** Exact text: `All times are in Pacific Time.` Place it immediately under the section header, on its own line, as plain prose (not a bullet, not a heading). One disclaimer per section that contains ≥3 timestamps. The disclaimer is for the human reader; the individual timestamps still stay bare so smart-chip rendering is uniform.
6. **Keep the source UTC values in `scratchpad.md` or `sources.md`**, never in the final doc. The post-mortem/explainer is the rendered artifact; the investigation folder holds the raw.
7. **Do NOT bold timestamps.** The em-dash after a timestamp already separates it from the event description; bolding adds visual weight without meaning. Bold is reserved for substantive emphasis, never time markers.
8. **First timestamp in any section MUST be full form** (`Month DD, YYYY HH:MM`). Within the same section, subsequent references MAY drop to `HH:MM` once the date is unambiguous from context. Every cell in a table MUST be full form regardless of column.
9. **Use `: ` (colon + space) to separate a timestamp from the event description, NOT ` — ` (em-dash).** The em-dash is reserved for parenthetical separation in prose; the colon reads as a label-value pair, which is exactly what a timestamped event is. Applies to timeline bullets and any prose construction `<timestamp> <separator> <event>`. Tables and citation parentheticals don't have this separator and are unaffected.

### Conversion algorithm

For every source timestamp:

1. Parse the source. If it's UTC (`...Z`, `... UTC`, `... GMT`), keep as UTC. If it's another zone, convert to UTC first.
2. Determine whether the event date falls in PDT or PST.
   - PDT (UTC−7): from ~March second Sunday 02:00 local to ~November first Sunday 02:00 local. (Exact dates vary year-to-year.)
   - PST (UTC−8): the rest.
   - When in doubt, look up the year's transitions. Don't guess.
3. Subtract 7 hours (PDT) or 8 hours (PST) from the UTC value.
4. Handle date rollover: if subtraction lands you before 00:00:00, decrement the date. (Example: `May 21, 2026 06:00:00 UTC` → `May 20, 2026 23:00:00` in PDT.)
5. Render in the format above. Strip any TZ suffix the source carried.

### Worked examples

| Source | Convert via | Output (seconds stripped) |
|---|---|---|
| `2026-05-21T20:36:57Z` | UTC−7 (PDT, May is in DST) | `May 21, 2026 13:36` |
| `2026-01-15T08:00:00 UTC` | UTC−8 (PST, January is standard) | `January 15, 2026 00:00` |
| `2026-05-21T06:00:30 UTC` | UTC−7 (PDT) | `May 20, 2026 23:00` (date decremented — rolled back across midnight; seconds stripped) |
| `2026-11-01T09:30:45Z` (DST transition day) | Look up: 2026-11-01 02:00 PT is the fallback to PST. 09:30 UTC = 01:30 PDT = 01:30 PT, on the date before transition; safe to use UTC−7. | `November 1, 2026 02:30` (using PDT; note the choice in `sources.md`) |

For the transition-day edge case: don't try to be clever about which side of the fall-back the timestamp lands on — just pick PDT for events before the local 02:00 transition and PST after, and note the choice in `sources.md`.

### Don'ts

- Don't write `UTC` after a converted timestamp ("backup labelling"). The whole point is uniform smart-chip rendering.
- Don't mix TZs across sections. The disclaimer covers the whole doc; convert everything.
- Don't apply DST-as-of-today. May 21, 2026 is PDT regardless of whether you're drafting in January or July.
- Don't leave raw UTC values in the body because they were "the original log timestamp". They were; the doc isn't.
- Don't render in 12-hour format with AM/PM. 24-hour only.
- Don't bold timestamps. (Hard rule 7.)
- Don't drop to abbreviated form (`HH:MM:SS`) in the first timestamp of a section. (Hard rule 8.)
- Don't separate timestamp from event with ` — `. Use `: `. (Hard rule 9.)

### Examples

Single-bullet timestamps (in a timeline):

- GOOD: `- May 21, 2026 13:36: ASG desired count changed 3→4.`
- BAD: `- May 21, 2026 13:36:57: ASG desired count changed 3→4.` *(rule 4: strip seconds)*
- BAD: `- May 21, 2026 13:36 — ASG desired count changed 3→4.` *(rule 9: use `: `, not em-dash)*
- BAD: `- May 21, 2026 20:36 UTC: ASG desired count changed 3→4.` *(rule 3: no TZ suffix; also rule 2: should be 13:36 PT)*
- BAD: `- **May 21, 2026 13:36**: ASG desired count changed 3→4.` *(rule 7: don't bold)*
- BAD: `- **20:36** — ASG desired count changed 3→4.` *(rules 7, 8, 9 — bold, abbreviated, em-dash)*
- BAD: `- May 21, 2026 12:36: ASG desired count changed 3→4.` *(rule 2: May is in PDT, UTC−7, so 20:36 UTC → 13:36, not 12:36. Using PST literally (UTC−8) on a DST date is a 1-hour error.)*

Section header + disclaimer:

- GOOD:
  ```
  # Timeline

  All times are in Pacific Time.

  - May 21, 2026 13:36: ASG desired count changed 3→4.
  ```
- BAD:
  ```
  # Timeline

  All times UTC, 2026-05-21.

  - **20:36:57** — ASG desired count changed 3→4.
  ```
  *(disclaimer cites wrong TZ; bullet violates rules 3, 4, 7, 8, 9 simultaneously)*

Prose with first + subsequent reference in same section:

- GOOD: `The node was Ready at May 21, 2026 13:38. Pod scheduling started at 13:38 as well; by 13:39 the first sandbox failure landed.`
  *(First mention full form; subsequent mentions abbreviated per rule 8. Note the loss of sub-minute ordering — accept it.)*
- BAD: `The node was Ready at 13:38. Pod scheduling started at 13:38.`
  *(First reference in section drops the date — rule 8 violation. A reader pulling this sentence into Slack loses the date.)*

Table cells:

- GOOD:

  | Pod | First fail | Last fail |
  |---|---|---|
  | `secrets-store-csi-driver-9qnl6` | May 21, 2026 13:38 | May 21, 2026 14:03 |

- BAD:

  | Pod | First fail | Last fail (UTC) |
  |---|---|---|
  | `secrets-store-csi-driver-9qnl6` | 13:38:39 | 21:03:13 |

  *(column header carries TZ, first cell abbreviated, last cell still in UTC with seconds — four violations)*

### Why this many rules?

Timestamps are the single most-referenced fact type in a post-mortem or explainer. One ambiguous time = a reader silently doubting every other claim. Stricter rules here pay back across the rest of the doc.

### When the source is already in PT

Some Slack threads / human-written summaries cite times in PT. Verify the offset before reusing — well-meaning humans sometimes mix UTC and PT inside one paragraph. Cross-check against a primary source (Datadog event, log timestamp) before trusting.

## Prose style

- **Write like Kernighan & Ritchie.** Terse, precise, one idea per sentence.
- **Delete any sentence with no concrete fact.** A sentence that names no path, identifier, number, decision, or failure mode MUST be deleted.
- **Concrete over abstract.** Paths, ports, table names, golinks, config values, commands.
- **Tables for structured data.** 3+ rows × 2+ attribute columns → table. Fewer → bullets.
- **For component sections, answer "what breaks without this?" in one sentence.** Skip for Summary, How-to-run, References.
- **Operational commands use real values.** No `<file>` / `<path>` placeholders.
  - GOOD: `curl -sfL 'https://dr6dw6x4v1iqo.cloudfront.net/ami_dependencies/maxmind/maxmind.tar.gz?cb=1' -o maxmind.tar.gz`
  - BAD: `curl -sfL 'https://dr6dw6x4v1iqo.cloudfront.net/<path>?cb=1' -o <file>`

## Link formatting

### Permalinks for code references

- **Permalink the FIRST mention per section; bare backticks for later mentions.**
  - First mention in a section: MUST be a `/blob/{sha}/` GitHub permalink. Resolve the SHA BEFORE writing any permalinks — see `Resolve permalink SHA` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.
  - Later mentions in the same section: bare backtick code span.
  - New `#` section resets the counter. `##` subsections inherit from the parent `#`. Aliases count as new mentions (re-link `router` if the first mention was `WWW_ROUTES`).
  - NEVER use `/blob/main/`, a branch name, a tag, or a short SHA. ALWAYS `/blob/{sha}/` with the full 40-char SHA from the script.
- **Link labels describe the thing, NOT its address.** Line numbers (`L42`, `L104-L134`) belong in the URL fragment only — never in the visible label text. The label names the function, behavior, file, or concept; the URL carries the coordinates.
- **Code without a stable repo location uses bare backticks with no link.** Examples: shell builtins, external library symbols, env vars set only at runtime, generated code, dynamically-constructed names. Do NOT fabricate a repo path.

URL template: `https://github.com/{owner_repo}/blob/{sha}/{path}#L{line}`. Substitute `{owner_repo}` and `{sha}` from the script output — do not hardcode repo names in any example.

- GOOD: `[WWW_ROUTES](https://github.com/{owner_repo}/blob/{sha}/packages/www/www_server_utilities.tsx#L28)`
- GOOD: `[the cancel() override in PipelineStage.java](https://github.com/{owner_repo}/blob/{sha}/path/PipelineStage.java#L104-L134)`
- BAD: `[PipelineStage.java L104-L134](https://github.com/{owner_repo}/blob/{sha}/path/PipelineStage.java#L104-L134)` — line numbers in label
- BAD: `[widget_cache.tsx — pruneFn (L47)](https://...)` — line number in parenthetical
- BAD: `[WWW_ROUTES](https://github.com/Hyperbase/hyperbase/blob/main/packages/www/www_server_utilities.tsx#L28)` — branch name, hardcoded repo
- BAD (first mention): `` `WWW_ROUTES` ``

### Link density

Every named external entity MUST be hyperlinked at its FIRST mention in the body — not merely listed in `# Useful links`. Named external entities: a blog post or doc cited by title, a product or tool (Datadog, Prometheus, Graphite, Node.js), a company, a person, a protocol or spec (StatsD, OTLP, the OpenTelemetry spec). The inline link and the `# Useful links` entry are BOTH required — same as URLs already inlined in the body. Listing an entity in `# Useful links` does NOT discharge the inline-link requirement.

- The opening summary is the most-skimmed paragraph; an unlinked source named there is the most-felt miss. Link it.
- Code symbols follow `Permalinks for code references`, not this rule. This rule covers prose entities — sources, products, people, companies, protocols.
- If no canonical URL exists for an entity, leave it unlinked and do not fabricate one.

- GOOD: `We mirror the [StatsD](https://github.com/statsd/statsd) line protocol, as described in [Etsy's "Measure Anything, Measure Everything"](https://www.etsy.com/codeascraft/measure-anything-measure-everything/).`
- BAD: `We mirror the StatsD line protocol, as described in Etsy's "Measure Anything, Measure Everything".` — two named sources, neither linked at first mention
- BAD: `We mirror the StatsD line protocol.` (with the StatsD URL only in `# Useful links`) — inventory entry without an inline link

### No skill mentions

Never mention a Claude skill in a Doc, let alone link one: no skill name in the Summary or body, no `github.com/AriSweedler/dotfiles/...` URL anywhere, no `## Code and PRs` block that lists the toolchain. A doc is for readers of its topic. The one exception is the footer, which may read `🤖🌸 Generated with Claude Code with the ari-hemingway skill`.

- GOOD: body says nothing about how it was made; last line `🤖🌸 Generated with Claude Code with the ari-hemingway skill`
- BAD: `This article was generated as an example output of the ari-hemingway writing pipeline.`
- BAD: `[ari-hemingway](https://github.com/AriSweedler/dotfiles/tree/main/.config/claude/skills/ari-hemingway) shaped it`

### PR references

Full title + number as link text. Escape `[]` in titles; keep `()` as-is.

- GOOD: `[[deploy] Mirror k8s tools (eksctl, kubectl) to Cloudfront CDN in production (#207238)](https://github.com/Hyperbase/hyperbase/pull/207238)`
- BAD: `PR #207238: mirroring eksctl/kubectl to this CDN`

### Google Workspace URLs

Raw, not markdown links, and every one of them a smart chip in the published Doc. Applies to any `docs.google.com/*` or `drive.google.com/*` URL (Docs, Sheets, Slides, Drive, Forms). Drive's markdown import lands a raw URL as a plain hyperlink; `/ari-hemingway--share-gdoc` converts every such link into a chip with the Docs API `insertRichLink` request (Drive URLs only) and fails the publish if any Drive URL is left as a plain link. A markdown-linked URL is not converted, which is why the URL stays raw. Chips show the target's title, so never append one.

- GOOD: `see https://docs.google.com/document/d/1abc...`
- BAD: `see [My Doc](https://docs.google.com/document/d/1abc...)`

If a Drive/Docs URL is itself the value being documented (a config key pointing to a spec), still render it raw. The permalink rule applies to the config key, not the value.

### Request flows

Numbered list, one hop per step. Each item = one network hop or service boundary crossing. For in-process transforms, use a sub-bullet under the owning step. NEVER a fenced code block with arrows.

GOOD:
1. Client sends POST to /api/v1/run.
2. Server validates the token.
3. Server enqueues the task.

BAD:

    ```
    Client → Server → Queue → Worker
    ```

## Typography

### Jargon and literal tokens

Every piece of technical jargon or literal token MUST be wrapped in backticks. Literal tokens: protocol tokens (`|c`, `|ms`, `:1|c`), wire formats, daemon / port / path / env-var / command names, metric type names, and acronyms used as literals (`UDP`, `TCP`, `OTLP`, `HTTP`) when naming the literal protocol or token rather than reading as prose. Backticks tell the reader "this is a token to type or match exactly," not a word to parse.

- Backtick the acronym only when it IS the token. "sent over `UDP`" — token. "the protocol is connectionless" — prose, no backticks.
- A token embedded in prose still gets backticks: the daemon name, the port number when it's a literal, the env var.

- GOOD: `The agent appends `:1|c` to increment a counter, then ships the packet over `UDP` to `localhost:8125`.`
- BAD: `The agent appends :1|c to increment a counter, then ships the packet over UDP to localhost:8125.` — protocol token, literal acronym, and host:port all unbackticked
- GOOD: `Set `STATSD_HOST` before starting `statsd`.`
- BAD: `Set STATSD_HOST before starting statsd.` — env var and daemon name unbackticked

## Document conventions

### Title, sections, footer

- **Title is plain text, no `#` prefix.** First line of the draft becomes the Google Docs document title.
- **Title MUST start with `[🤖 AI generated]`.** The marker is a prefix; the title never ends with it and never names a skill.
- **Sections start at `#` (h1); subsections at `##` (h2).**
- **Final line MUST be `🤖🌸 Generated with Claude Code`**, optionally followed by ` with the ari-hemingway skill` — on its own, no heading. That suffix is the only place a skill may be named (see `No skill mentions`).
- **The 🤖 and 🌸 are required literals.** Do not substitute ASCII (`[AI generated]`), unify bracketing, or strip emoji.

Full skeleton:

```
[🤖 AI generated] Template Gallery Traffic Routing

# Summary
One-paragraph overview.

# Architecture
## Request flow
1. Client sends POST to /api/v1/run.
2. ...

# Useful links
- [WWW_ROUTES](https://github.com/{owner_repo}/blob/{sha}/...)
- see https://docs.google.com/document/d/1abc...
- [[deploy] ... (#207238)](https://github.com/.../pull/207238)

🤖🌸 Generated with Claude Code
```

### No hallucinated details

Every path, command, table name, config value, and numeric constant MUST come from a file you opened this session OR a linked document. If you cannot cite the source, mark the claim `[TODO: verify — reason]` anchored to the specific unverifiable phrase. Do not omit silently, do not guess.

- GOOD: `The job runs every 5 minutes [TODO: verify — not found in crontab].`
- BAD: `The job runs every 5 minutes.` — unverified, unmarked
- BAD: `[TODO: verify] The job runs every 5 minutes.` — tag covers whole sentence

All TODO markers follow the anchored form: `[TODO: verb — reason]`. Examples: `[TODO: verify]`, `[TODO: add permalink]`.

### Diagrams

Every diagram is an inline image that links to its mermaid.live source in fullscreen view (`https://mermaid.live/view#pako:…`, never `/edit#`: a reader gets the diagram, not the editor) and fits on one page. Drive's markdown import turns a linked image into an inline image whose link is the mermaid.live URL, so the link costs nothing.

1. Invoke `/ari-diagram-mermaid` twice on the same `.mmd`: `MERMAID_FORMAT=ink_url` and `MERMAID_FORMAT=live_url`. Read the two sidecars (`<name>.ink_url.url`, `<name>.live_url.url`); never retype the base64.
2. Embed the image wrapped in the link, with the ink URL capped at 620 px: `[![Request flow from CDN to worker](https://mermaid.ink/img/base64:eNp...?width=620)](https://mermaid.live/view#pako:eNp...)`.
3. `?width=620` renders at 465 pt, inside the 468 pt text width (Letter, 1in margins: 468 × 648 pt). Without it the native PNG imports at 900 to 1400 pt wide and fails the one-page check. Height is still the author's job: a 6-to-8-node nested flowchart fits; flatten with `direction LR` or split before adding more.
4. `/ari-hemingway--share-gdoc` checks both invariants at publish time and fails on an image that spills or lacks a `mermaid.live/view#` link.

See `/ari-hemingway--lib` for the failure contract when `/ari-diagram-mermaid` fails.

### Tables

Every table's header row is bold, centered, and grey (`#D9D9D9`); data rows are plain. Markdown import only bolds the header, so publishing through `/ari-hemingway--share-gdoc` applies the rest mechanically. A table that reaches a Doc any other way must be restyled by hand (or with `gdoc_finish.zsh` from that skill). The import also pins the header row (`tableHeader` is true on the first row), so it repeats at the top of every page the table spans; `/ari-hemingway--share-gdoc` verifies that flag at publish.

### Useful links (required final section)

Every gdoc MUST end with a `# Useful links` section immediately before the `🤖🌸 Generated with Claude Code` footer. It is a complete inventory of external resources the doc depends on:

1. **Every URL already inlined in the body** — permalinks, PR references, Drive/Docs smart chips. Repeat them here as a scannable list. A section that is itself a list of links (a scaffold's `# Sub-explainers`) is the exception: its URLs are not repeated.
2. **Every resource mentioned by name but NOT linked inline** — e.g., "the design doc", "the ops runbook", "that Slack thread". Surface the URL here so readers don't have to hunt.

Group into subsections when the list grows:
- `## Code and PRs` — GitHub permalinks, PR links.
- `## Docs` — Google Docs/Drive URLs (raw, for smart chips).
- `## Dashboards and playbooks` — Datadog boards, runbooks, Grafana, golinks.
- `## Related explainers` — the gdocs the body directly relies on, not every sibling in a folder.

The inline link inside the body and its entry in Useful links are BOTH required — do not substitute one for the other. A reader skimming Useful links gets the full surface area without reading the body.
