---
name: ari-hemingway--structure-design-doc
description: "Write or update design docs: proposals that present a problem, a proposed change, sequencing constraints, tradeoffs, and out-of-scope work. Three modes: propose (from scratch), distill (from session/Slack thread), update (improve existing doc). Distinct from subsystem-explainer, which describes an existing system rather than proposing a change."
---

# Design Doc

Produce design docs for Airtable engineering proposals in three modes: **propose** (from scratch), **distill** (from session knowledge or a Slack thread), **update** (from an existing doc).

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns (investigation folder, restore context, drafting, permalink resolution, fact-check, present/output): see `/ari-hemingway--lib`. If any rule here appears to contradict `/ari-hemingway--format-gdoc`, the format skill wins.

## Modes

- **Propose** — given a problem statement and a rough proposal, structure into a design doc.
- **Distill** — during or after a session where the user has been triaging a problem (Slack thread, incident, brainstorm), condense what was decided into a design doc.
- **Update** — given a pointer to an existing design doc (Google Doc URL or ID), read it, compare against current codebase state and the user's latest direction, propose changes.

## Document structure

Required sections, in order:
- Title (plain text, starting with `[🤖 AI generated]` per `/ari-hemingway--format-gdoc`)
- `# TL;DR` — 2–4 sentences. Problem, proposal, the sequencing constraint or risk that matters most. A reader who only reads this should know whether to engage.
- `# Problem` — what's wrong today, with concrete evidence (permalinks, incidents, Slack threads). No marketing language; describe the failure mode.
- `# Proposal` — numbered steps describing the change. Each step is a concrete artifact (file path, TF resource, config key, command). Cite the precedent the step follows when applicable.
- `# Sources` — required final section before the footer, per `/ari-hemingway--format-gdoc`. Permalinks to code, rules, prior discussions, Slack threads, related PRs.

Optional and reorderable (appear between `# Proposal` and `# Sources`): `# Sequencing / cutover`, `# Tradeoffs considered`, `# Out of scope / future work`, `# Open questions`.

### When each optional section is required

- **Sequencing / cutover** — required if any two steps in the Proposal have a hard ordering constraint, or if cutover involves coordinated changes across systems (DNS + secret + IAM, e.g.). Omit only when steps are genuinely independent.
- **Tradeoffs considered** — required if a meaningful alternative was rejected. "Do nothing" counts as an alternative when the doc proposes net-new work.
- **Out of scope / future work** — required if the user mentioned a follow-up direction in the brief. Each item gets a one-line "why later."
- **Open questions** — required if any question in the brief is unresolved at draft time. Each question gets a name (so reviewers can address by reference) and either an owner or a decide-by date.

### Reshape latitude

Sections MAY be altered only as follows:
- Rename a section only to a title that names the subject concretely (e.g., "Proposal" → "Move MCP publisher key to hyperbase-production"). NEVER to a vaguer title.
- Merge two adjacent optional sections if combined content is under 300 words.
- Drop an optional section per the rules above ("when each optional section is required").

Any reshape beyond this list MUST be called out in the update-mode diff summary.

### Skeleton

```
[🤖 AI generated] Design Doc Title

# TL;DR
2–4 sentences. Problem, proposal, sequencing/risk that matters most.

# Problem
What's wrong today. Concrete evidence with permalinks. Failure mode, not marketing.

# Proposal
1. Step — concrete artifact (file/TF resource/config). Precedent: `path/to/precedent.tsx`.
2. Step — ...

# Sequencing / cutover (optional)
Why steps can't run in parallel. What blocks what. Cutover order if multiple systems coordinate.

# Tradeoffs considered (optional)
Alternative A — rejected because <reason>.
Alternative B — rejected because <reason>.

# Out of scope / future work (optional)
- Item — why later: <one line>.

# Open questions (optional)
- **[Q-name]** — question. Owner: <name> OR Decide by: <date>.

# Sources
- [Title or short description](https://permalink) — what it shows.

🤖🌸 Generated with Claude Code
```

### Structural example

Structural skeleton only — NOT a target length. See word-count buckets in `## Rules` for real targets.

```markdown
[🤖 AI generated] Move MCP Registry Publisher Key Out of Hyperbase Dev

# TL;DR

The `com.airtable/mcp` publisher private key lives in the dev AWS account where ~half the company can read it. Proposal: introduce an `MCP_PUBLISHERS` LogicalGroup, move the secret to `hyperbase-production`, scope IAM to a single ARN, then rotate the key as cutover. The new home must exist before there's anywhere to land the rotated key — rotation is blocked until steps 1–5 ship.

# Problem

`/hyperbase/mcp-registry-publisher` is stored in the dev account. `HyperbaseDevAccess` (~50% of engineering) can read it via `grunt credential:show` — see [`agent_skills/authoring/mcp-registry/README.md` L43-59](https://github.com/Hyperbase/hyperbase/blob/{sha}/agent_skills/authoring/mcp-registry/README.md#L43-L59). Anyone with that role can publish under our registry namespace.

# Proposal

1. New `LogicalGroup MCP_PUBLISHERS` at `admin/engineering_access/config/logical_groups/mcp_publishers.tsx`. Members: Ari, Andrew, Clement. Precedent: any existing file in [`config/logical_groups/`](https://github.com/Hyperbase/hyperbase/tree/{sha}/admin/engineering_access/config/logical_groups).
2. New `CustomerManagedPolicy mcp_registry_publish` granting `secretsmanager:GetSecretValue` on one ARN. Precedent: [`hyperbase_production_deny_secrets.tsx` L12-14](https://github.com/Hyperbase/hyperbase/blob/{sha}/admin/engineering_access/config/aws/customer_managed_policies/hyperbase_production_deny_secrets.tsx#L12-L14).
3. ...

# Sequencing / cutover

Steps 1–5 land first (access plumbing). Rotation is the cutover: it cannot run earlier because there is no prod SM path to write the rotated key into.

# Tradeoffs considered

- Keep the secret in dev with a DenyList SCP — rejected: every new IAM principal would need to be added to the deny list, fragile.
- Jump straight to OIDC-federated CI publish (Layer 3) — deferred: more work, and publishing is rare today.

# Out of scope / future work

- OIDC-federated GitHub Actions publish flow — why later: removes humans from the loop entirely, but requires workflow + OIDC role + version-bump trigger semantics. Worth a follow-up doc.

# Sources

- [`agent_skills/authoring/mcp-registry/README.md`](https://github.com/Hyperbase/hyperbase/blob/{sha}/agent_skills/authoring/mcp-registry/README.md) — current publish + rotation flow.
- [`engineering_access.mdc` L227-232](https://github.com/Hyperbase/hyperbase/blob/{sha}/.cursor/rules/engineering_access.mdc#L227-L232) — LogicalGroup add flow.

🤖🌸 Generated with Claude Code
```

## Rules

### Content scope — word count by scope

Walk buckets top-to-bottom; first match wins. Record the chosen bucket in `scratchpad.md` under `Bucket:` before drafting. Re-check word count at Draft step.

| Scope | Words |
|---|---|
| Single-system change, no cross-team coordination | ≤500 |
| Multi-step change in one team's domain, or single-system with sequencing constraints | 500-1500 |
| Cross-team or cross-system change, or coordinated cutover across multiple systems | 1500-3500 |

A 1-page design doc is fine. Skip sections that don't apply rather than padding them.

### Distill mode — claim attribution

- **A claim about prior discussion (Slack thread, incident, decision)** MUST cite the source: thread URL, message timestamp, or named participant + date. If the source is paraphrased without a link, mark with `[TODO: verify with user]`.
- **An open question that came up in conversation but wasn't resolved** MUST appear in the Open questions section with the conversation as its source, NOT be silently answered by the skill.

GOOD: `Doug Forster surfaced this in #infra-security on 2026-05-12 — see thread <slack-url>.`
BAD: `The team has been concerned about this for some time.` — no source, speculative.

## Investigation folder

Root path: `/tmp/hemingway/design-doc/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`.

**Mode-specific scratchpad fields.** Append to the `/ari-hemingway--lib` baseline:
```
- **Bucket**: ≤500 | 500-1500 | 1500-3500
- **Distill supplements**: N (distill mode only)
- **Open questions resolved during investigation**: list (so they don't silently disappear from the draft)
```

## Workflow

### Determine mode

Evaluate in order, first match wins:
1. User's message contains a Google Doc URL OR the phrase "update this design doc" → **update**.
2. Current conversation contains an explicit problem statement + a proposal + ≥3 referenced files/threads/PRs in the user's prior turns → **distill**.
3. Otherwise → **propose**.

If both `update` AND `distill` conditions fire: infer **update-with-distill-context** (fetch doc + use conversation reads as evidence for the diff).

Print the inferred mode with evidence:
```
I inferred **{mode}** because {evidence}. Confirm, or pick: (1) Propose, (2) Distill, (3) Update.
```
`{evidence}` cites the trigger: "you pasted a Google Doc URL", "the conversation contains a problem statement from a Slack thread and a 6-step proposal", etc.

**MUST stop after printing. Do NOT call any tool except to wait for the user reply.**

### Gather pointers

Collect user-provided pointers: code paths, doc URLs, PR links, Slack threads, prior decisions. In distill mode, also harvest the dispatcher's brief and prior conversation turns as the primary source. Derive `{topic-slug}` per `/ari-hemingway--lib`. Create the investigation folder. Write the initial scratchpad (Subject, Mode, Bucket, Pointers, Open questions resolved).

### Restore context

Follow the `Restore context` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Resolve permalink SHA

Follow the `Resolve permalink SHA` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Investigate

Append to `sources.md` and update `scratchpad.md` key findings per the cadence in `/ari-hemingway--lib` (every batch of ≤3 Read/Grep/Bash calls).

**Propose mode** — read every file the brief references. Verify line numbers. For each precedent cited in the proposal, READ the precedent file and confirm it actually demonstrates the pattern claimed; if it doesn't, mark the step `[TODO: precedent verification failed — pick a different example or remove the citation]`. Trace the proposal end-to-end: for each step, identify the concrete artifact (file path, TF resource, config key, IAM ARN); if a step doesn't name one, mark `[TODO: this step lacks a concrete artifact — sharpen with user]`.

**Distill mode** — the conversation and the dispatcher's brief are the primary source. Supplement with targeted reads for claims not yet attributable to a file read, grep result, Slack thread, or user statement. Count supplemental reads in `scratchpad.md` under `Distill supplements`. **On reaching 6, MUST stop** and print:
```
Distill supplement budget exceeded (6 reads). Switch to propose mode? (y/N)
```
On yes: update scratchpad `Mode: propose (switched from distill at {timestamp})`, then restart Investigate without re-running mode confirmation.

**Distill open-question check (before drafting).** Enumerate every unresolved question from the conversation. For each: (a) was it explicitly answered upstream (then incorporate into the relevant section)? (b) is it still open (then add to Open questions)? (c) was it implicitly answered by a later turn (then incorporate and record under `Open questions resolved` in scratchpad)? Do NOT silently drop unresolved questions.

**Update mode** — fetch the existing doc via `mcp__escalation_mcp_server__google_docs_read_document`. After fetching, print `Target doc: {title} — last edited {date}. Produce update? (y/N)` before proceeding.

On fetch failure, follow the `MCP reliability` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Option 3 is "switch to propose mode".

**Update-mode diff collection.** Compare EACH of the following against the current codebase AND the user's latest direction, recording deltas in `scratchpad.md`. Do NOT skip a claim because it "probably hasn't changed."
- Every file path, line number, and permalink SHA in the doc.
- Every config value, flag, environment variable, IAM ARN, IAM action.
- Every command (verify flags still exist).
- Every numbered proposal step (re-read the code; note adds/removes/reorders).
- Every named precedent (confirm the precedent still demonstrates the pattern).
- Every open question (still open? newly answered? newly raised?).

If the existing doc's heading doesn't map to the new structure, tag with the OLD heading in the diff: `- **[Overview → Problem]** — renamed and tightened.`

#### Research quality gate

A concrete proposal step references a specific artifact (file path, TF resource, config key, IAM ARN, command). A vague step ("improve permissions", "lock it down") fails the gate.

Gate by scope:
- **Single-system change (≤500 word bucket):** minimum 2 concrete artifacts in Proposal, minimum 1 cited precedent.
- **Multi-step or cross-system (>500 word bucket):** minimum 4 concrete artifacts, minimum 2 cited precedents.

GOOD step: `New \`CustomerManagedPolicy mcp_registry_publish\` granting \`secretsmanager:GetSecretValue\` on \`arn:aws:secretsmanager:*:*:secret:/hyperbase/mcp-registry-publisher-*\`. Precedent: \`hyperbase_production_deny_secrets.tsx\`.`
NOT a step: `Tighten secrets manager IAM.` — no artifact, no ARN, no precedent.
NOT a step: `We should probably also do something about the Okta groups.` — speculative, no artifact.

If the minimum is not met, MUST stop:
- **0 concrete artifacts in Proposal:** print `Proposal is too vague to produce a design doc. Sharpen at least N steps to name concrete artifacts (files, TF resources, IAM ARNs, commands).`
- **Below minimum but non-zero:** print what was found and offer: (1) Provide more concrete artifacts, (2) Narrow scope to fit a smaller bucket, (3) Abort.

Print: `Investigate complete — {n} files read, {m} grep queries, {p} precedents verified. Next: Draft.`

### Draft

Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` and all `/ari-hemingway--format-gdoc` rules.

Confirm the draft's word count lands within the bucket recorded in `scratchpad.md`. If over, cut before printing.

Print: `Draft complete — {sections} sections, {words} words, {dropped-sections} optional sections deliberately omitted. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

Additional design-doc-specific checks:
- Every numbered proposal step has a verifiable artifact reference.
- Every cited precedent has been read end-to-end during Investigate.
- Every open question has a name AND (owner OR decide-by date).
- The Sequencing section, if present, names the specific cross-step blocker — not just "these need to be in order."

Print: `Fact-check complete — {n} claims verified, {k} marked [TODO: verify]. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

**Per-mode option 1 label:**
- propose/distill: `Finalize — write output.md`
- update: `Finalize — write updated output.md, then update the Doc in place via /ari-hemingway--share-gdoc (replaces the whole body; manual edits in the Doc are lost)`

**Option 4 visible in update mode only.** When the update-mode diff is empty (doc already accurate), option 4 leads the list and is the default.

For update mode, show the diff summary BEFORE the menu, grouped into: `## Fact corrections`, `## Additions`, `## Removals`, `## Prose/structure edits`. User may approve categories selectively.

Print: `Draft ready — awaiting your choice.`

### Output

Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.
