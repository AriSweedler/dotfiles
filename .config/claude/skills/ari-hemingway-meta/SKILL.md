---
name: ari-hemingway-meta
description: "Create a new ari-hemingway--<pipeline>-<specific> skill following the naming grammar and pipeline contract. Use when adding a sibling to the hemingway family (structure, format, review, share)."
---

# Hemingway Meta

Creator for new `ari-hemingway--*` skills. Locks in the naming grammar and generates a skeleton that cross-references lib and format correctly.

## Naming grammar (authoritative)

```
ari-hemingway--<pipeline>[-<specific>]
```

| Field | Values | Examples |
|---|---|---|
| `<pipeline>` | `acquire` \| `structure` \| `format` \| `review` \| `share` | `structure`, `format`, `review` |
| `<specific>` | free-text, kebab-case, describes the concrete thing | `subsystem-explainer`, `gdoc`, `brevity` |

Exceptions:
- `ari-hemingway--lib` — shared workflow (no `<specific>`). Single special case.
- `ari-hemingway` — the dispatcher. No `--`.
- `ari-hemingway-meta` — this skill. No `--`.

Do NOT create new exceptions without updating this grammar.

## Preconditions

- Skills are versioned in the dotfiles (`/ari-dotfiles-skill-registry`); a fresh skeleton is `unlinked` until adopted.
- `$HOME/.claude/skills/` writable.
- `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` exists (skeleton references it).

## Workflow

### 1. Pick pipeline stage

```
Which pipeline stage?
(1) structure  — document shape (what sections, required/optional)
(2) format     — destination syntax (gdoc, slack, md, pr)
(3) review     — quality gate (axis: brevity/clarity/factual/audience-fit; or destination bundle)
(4) share      — publish to destination
(5) acquire    — knowledge gathering (rarely needed; lib covers this)
```

Record choice in scratchpad.

### 2. Pick specific

```
What does this {pipeline} skill do? (kebab-case suffix)
Examples for {pipeline}:
  structure:  subsystem-explainer, slack-status, pr-description, post-mortem
  format:     gdoc, slack, md, pr
  review:     brevity, clarity, factual, audience-fit, <destination>
  share:      gdoc, slack, gist
```

Validate: lowercase, hyphens only, starts with a letter.

Compute full name: `ari-hemingway--{pipeline}-{specific}`.

### 3. Check for collision

```
[[ -d $HOME/.claude/skills/${full_name} ]] && STOP "Skill already exists at $path. (1) Edit with /ari-skill-update, (2) Pick different specific"
```

### 4. Generate skeleton

Write `$HOME/.claude/skills/{full_name}/SKILL.md` using the template for the chosen pipeline (below).

For `structure-*` skills, ask a few more questions:
```
- Required sections (comma-separated):
- Optional sections (comma-separated, or "none"):
- Word-count target (e.g. "200-500", "<300", "600-3000"):
- Default destination (gdoc | slack | pr-description | md | other):
```

For `format-*` skills, ask:
```
- Destination platform (gdoc | slack | pr | md | email):
- Primary rendering constraint (e.g., "slack mrkdwn: asterisks for bold, colons for emoji"):
```

For `review-*` skills, ask:
```
- Axis or destination? (axis = brevity/clarity/etc; destination = bundle for gdoc/slack)
- 3-5 check bullets the reviewer will enforce:
```

For `share-*` skills, ask:
```
- Destination: what tool/API handles publication? (gh, slack API, gdoc API, clipboard)
- Dry-run step: what does it print before side-effecting?
```

### 5. Present and confirm

Show the generated SKILL.md inline. Ask:
```
Skill skeleton written to {path}. Options:
(1) Good — I'll start editing it with /ari-skill-update
(2) Regenerate — I want different questions answered
(3) Delete — scratch this
```

### 6. Suggest sync

If user picked (1), print:
```
Next steps:
- Edit: $HOME/.claude/skills/{full_name}/SKILL.md
- Test locally (skill shows up in your skill index immediately).
- When ready, adopt into the dotfiles: `zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/adopt --skill {full_name} --tier df`, then commit per /ari-dotfiles.
```

## Skeleton templates

### structure-*

```markdown
---
name: ari-hemingway--structure-{specific}
description: "Produce {document-type} drafts. {modes or use-cases}."
---

# {Human Title}

Produce {document-type} for {audience}. Targets {destination}.

Formatting rules: see `/ari-hemingway--format-{destination}`. Workflow patterns (investigation folder, restore context, drafting, permalink resolution, fact-check, present/output): see `/ari-hemingway--lib`. If any rule here appears to contradict `/ari-hemingway--format-{destination}`, the format skill wins.

## Document structure

Required sections, in order:
{required sections}

Optional sections:
{optional sections}

## Rules

### Content scope — word count

{word-count target}

### {Domain-specific rules}

{rules here}

## Investigation folder

Root path: `/tmp/hemingway/{specific}/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`.

## Workflow

### Determine mode
{per-skill modes if any}

### Gather pointers
Follow `Gather pointers` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Restore context
Follow `Restore context` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Investigate
{per-skill investigation rules; reference lib cadence}

### Draft
Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` and all `/ari-hemingway--format-{destination}` rules.

### Fact-check
Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Present
Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Output
Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.
```

### format-*

```markdown
---
name: ari-hemingway--format-{destination}
description: "Shared formatting conventions for {destination}-bound skills. Not user-invocable — referenced by `/ari-hemingway--structure-*` and `/ari-hemingway--review-*` siblings."
user_invocable: false
---

# {Destination} Formatting

Reference formatting rules for any skill that produces {destination} output. Siblings follow these rules; they do not invoke this skill.

## Prose style
{rules}

## Syntax conventions
{destination-specific markup}

## Links
{link handling}

## {Other sections as needed}
```

### review-*

```markdown
---
name: ari-hemingway--review-{axis-or-destination}
description: "Review a draft for {thing}. {Standalone-invocable or destination bundle.}"
---

# {Title}

{One-sentence purpose.}

## Rules this axis checks
{list of rules}

## Check bullets
{checklist the reviewer enforces}

## Standalone workflow
{reuse brevity/clarity pattern}

## Invoked by a bundle
{reuse brevity/clarity pattern}

## Per-reviewer output file
Schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`. Reviewer name: `{axis}`.

## Rules the reviewer must obey
- READ-ONLY.
- Cite the rule section name on each finding.
- {axis-specific constraints on fix suggestions}
```

### share-*

```markdown
---
name: ari-hemingway--share-{destination}
description: "Publish a draft to {destination}. Dry-runs by default; destructive only on explicit confirm."
---

# Publish to {Destination}

{One-sentence purpose.}

## Preconditions
- {tool/API auth confirmed, token env var set, etc.}

## Workflow

### 1. Dry-run
Print what would be published (destination, visibility, title, first 10 lines). Ask to confirm.

### 2. Publish
{concrete command or API call}

### 3. Report
Print the resulting URL or handle.
```

## Rules this skill obeys

- NEVER create a skill that breaks the naming grammar. If the user's `{pipeline}` or `{specific}` doesn't fit, STOP and surface the conflict.
- Generated skeletons MUST cross-reference lib and format correctly — no dangling `/ari-gdoc-*` or `/ari-hemingway--format-{undefined}` references.
- After skeleton is written, REMIND the user it is `unlinked` until adopted (`/ari-dotfiles-skill-registry`); other machines see it only after adoption and a dotfiles push.
