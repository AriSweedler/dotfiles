---
name: ari-hemingway--review-common
description: "Common review bundle — runs all applicable axis reviewers (brevity, clarity, factual, kr, ste100, and audience-fit if destination declared). Orthogonal to destination-specific bundles (review-gdoc, etc); composes only the universal axes."
---

# Common Review

Bundle that runs every axis reviewer applicable to any draft. For destination-specific checks (gdoc formatting, slack mrkdwn), use `/ari-hemingway--review-gdoc` or similar bundle instead of — or in addition to — this one.

## Preconditions

Verify per `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` `## Preconditions`:
- CWD is a git worktree.
- `/ari-hemingway--lib` installed.
- Each axis skill installed: `review-brevity`, `review-clarity`, `review-factual`, `review-kr`, `review-ste100`, `review-audience-fit`.
- Investigation folder root is writable (`/tmp/hemingway/` or fallback).

## Axes composed

| Axis | Skill | Conditional |
|---|---|---|
| Brevity | `ari-hemingway--review-brevity` | always |
| Clarity | `ari-hemingway--review-clarity` | always |
| Factual | `ari-hemingway--review-factual` | always |
| K&R | `ari-hemingway--review-kr` | always |
| STE100 | `ari-hemingway--review-ste100` | always |
| Audience-fit | `ari-hemingway--review-audience-fit` | only if destination declared |

## Investigation folder

```
/tmp/hemingway/review-common/{topic-slug}/{timestamp}/
├── scratchpad.md
├── source.md
├── target.md
├── brevity.md
├── clarity.md
├── factual.md
├── kr.md
├── ste100.md
├── audience-fit.md         # only if destination declared
├── challenge-log.md
├── findings.md
└── spec-questions.md
```

## Workflow

### Accept input

Follow the `Accept input` step from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `### Accept input` verbatim.

### Ask for destination (optional)

```
Declare destination for audience-fit? (optional — skip to run the always-on axes only)
(1) gdoc  (2) slack  (3) pr-description  (4) email  (5) readme  (6) skip audience-fit
```

If user picks (1)-(5), add audience-fit to the dispatch list and record `Destination: {value}` in scratchpad.

### Dispatch reviewers in parallel

**MUST launch all enabled axis reviewers in a SINGLE assistant turn — multiple Agent tool uses in the same response. NEVER dispatch sequentially.**

For each enabled axis:
- Read that axis skill's `## Check bullets` from its SKILL.md.
- Dispatch an Agent with a prompt that:
  - States the role: "You are a {axis} reviewer, READ-ONLY."
  - Lists the check bullets verbatim.
  - Points at `{investigation_folder}/source.md`.
  - Requires output in the schema from `/ari-hemingway--review-gdoc` `## Per-reviewer output file`.
  - Requires write path: `{investigation_folder}/{axis}.md`.

After dispatching, print: `Dispatched {n} axes in parallel.`

### Challenge, rank, present

Follow `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `### Challenge`, `### Rank`, and `### Present` procedures verbatim. Substitute source-of-truth: rules cited must exist in one of the composed axis skills' `## Rules this axis checks` sections.

## Per-reviewer output file

Every axis writes the schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file` to its dedicated file.

## Rules the bundle must obey

- READ-ONLY at the bundle level.
- If an axis skill is missing from `$HOME/.claude/skills/`, report it and skip rather than failing the whole bundle.
- Challenge gates still apply: each finding must cite a real rule from one of the composed axis skills; fixes must themselves be rule-compliant.
