---
name: ari-hemingway
description: "Entrypoint for the writing pipeline. Routes a writing task through acquire → structure → format → review → share by picking the right ari-hemingway--* sibling skills. Use when you're about to write a doc, slack post, PR description, subsystem explainer, post-mortem, or any output where you want Hemingway-style rigor applied."
---

# Hemingway Pipeline

Dispatcher for the `ari-hemingway--*` family. Turns "I need to write X" into a sequence of sibling-skill invocations.

## Naming grammar

Every skill in the family follows: `ari-hemingway--<pipeline>[-<specific>]`

Pipeline stages:
- `acquire` — knowledge gathering (covered by `--lib` Investigate; for an unfamiliar topic, `structure-scaffold`'s definitions pass is the acquire strategy)
- `structure` — document shape (what sections, what order, what required)
- `format` — destination syntax (gdoc, slack, md, pr-description, email)
- `review` — quality gates (axis-based: brevity, clarity, factual, audience-fit; or destination-bundle: review-gdoc)
- `share` — publish (`share-gdoc`; other destinations are manual copy-paste)

Exceptions:
- `ari-hemingway--lib` — shared workflow (not a stage; escape hatch)
- `ari-hemingway-meta` — creator for new hemingway skills

## Preconditions

- At least one `ari-hemingway--structure-*` skill is installed.
- `/ari-hemingway--lib` installed.

## Workflow

### 1. Identify the shape

Ask:
```
What are you writing?
(1) subsystem explainer     → ari-hemingway--structure-subsystem-explainer
(2) slack status update     → ari-hemingway--structure-slack-status         [planned]
(3) pr description          → ari-hemingway--structure-pr-description       [planned]
(4) post-mortem             → ari-hemingway--structure-post-mortem          [planned]
(5) design doc              → ari-hemingway--structure-design-doc           [planned]
(6) scaffold article        → ari-hemingway--structure-scaffold  (break a topic into definitions + subsystems)
(7) other — tell me what destination and the doc's purpose
```

Auto-detect if possible: if the user pasted a Google Doc URL → `subsystem-explainer` update mode is likely. If the session is a PR branch with uncommitted changes → `pr-description`. If the user wants to "break down", "come up to speed on", or "define the parts of" a topic they lack vocabulary for → `scaffold`. Print the inferred shape with evidence and ask to confirm.

If no matching sibling is installed, STOP and print:
```
No structure sibling installed for {shape}. Options:
(1) /ari-hemingway-meta — create the skill
(2) Pick a different shape
(3) Abort
```

### 2. Invoke the structure skill

Invoke the sibling via the Skill tool — do not Read its SKILL.md first. The Skill tool loads the full file. The sibling handles acquire (investigation) and format internally, per its own SKILL.md.

Wait for the sibling to reach its `Present` step (draft ready).

### 3. Review prompt

Once the draft is in `output.md` or similar, print:

```
Draft complete ({word-count} words). Review before sharing?
(1) Bundle for destination — runs /ari-hemingway--review-{destination} (all axes + destination-specific)
(2) Common — runs /ari-hemingway--review-common (all axes, no destination-specific)
(3) Pick axes individually: brevity / clarity / factual / audience-fit
(4) Skip review
```

Default to (1) if the destination has a bundle installed; otherwise (2).

### 4. Invoke the reviewer

Invoke the chosen review skill via the Skill tool — do not Read its SKILL.md first. Pass the draft path. Wait for its `Present` step.

Apply selected findings to the draft (the reviewer is READ-ONLY, so the dispatcher drives edits). Confirm each edit with the user or apply `all` if they picked it upfront.

### 5. Share

Print the final draft path and suggest a destination-appropriate share action:

| Destination | Share action |
|---|---|
| gdoc | Invoke `/ari-hemingway--share-gdoc` — creates (or updates in place) the Doc from the markdown and styles its tables. |
| slack | "Paste into the target channel / thread. Preserve the formatting — it's already mrkdwn." |
| pr-description | "Run `gh pr edit {PR} --body-file {path}`." |
| gist | "Run `gh gist create {path} --desc '{topic}'`." |
| readme | "Commit to `README.md` or the target path in the repo." |

If a `/ari-hemingway--share-*` sibling is installed and matches the destination, offer to invoke it instead.

## Examples

### Writing today's Slack update

User invocation: `/ari-hemingway slack update about the k8smon PR shipments`

1. Infer shape: `slack-status`. Not installed → offer meta or fallback.
2. Fallback: pick `subsystem-explainer` (closest match) + explicitly override destination to `slack`, accept reshape latitude.
3. Run `/ari-hemingway--structure-subsystem-explainer` with bias toward short/slack shape.
4. Review prompt → user picks `common`.
5. Run `/ari-hemingway--review-common` with destination=slack.
6. Apply findings.
7. Share: paste into the channel.

### Writing a subsystem explainer

User invocation: `/ari-hemingway explain the multi-cluster rollout subsystem`

1. Infer shape: `subsystem-explainer`. Installed.
2. Run `/ari-hemingway--structure-subsystem-explainer` — its own workflow covers investigate + draft.
3. Review prompt → user picks `bundle for destination` (gdoc).
4. Run `/ari-hemingway--review-gdoc`.
5. Apply findings.
6. Share: paste into a Google Doc.

## Rules

- Invoke siblings via the Skill tool. Do NOT Read sibling SKILL.md files — the Skill tool loads them, and their descriptions are already in your available-skills index. Reading is wasteful and treats invocable skills as documentation.
- Use Agent only for parallel reviewer dispatch inside bundles.
- NEVER short-circuit the review prompt — always ask, even if (4) Skip is the obvious pick.
- Do NOT edit the draft until the user selects review findings to apply.
- If the user provides an existing draft (path or URL) and skips structure, go straight to the review prompt.
