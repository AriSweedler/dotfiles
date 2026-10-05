---
name: ari-hemingway
description: "Entrypoint for the writing pipeline. Routes a writing task through acquire → structure → format → review → share by picking the right ari-hemingway--* sibling skills. Use when you're about to write a doc, slack post, PR description, subsystem explainer, post-mortem, or any output where you want Hemingway-style rigor applied."
---

# Hemingway Pipeline

Dispatcher for the `ari-hemingway--*` family. Turns "I need to write X" into a sequence of sibling-skill invocations.

## Naming grammar

Every skill in the family follows: `ari-hemingway--<pipeline>[-<specific>]`

Pipeline stages:
- `acquire` — knowledge gathering (covered by `--lib` Investigate; for an unfamiliar topic, `structure-scaffold`'s definitions pass is the acquire strategy; an existing Google Doc is acquired with `/ari-gsw-doc-to-md --publish`)
- `structure` — document shape (what sections, what order, what required)
- `format` — destination syntax (gdoc, slack, md, pr-description, email)
- `review` — quality gates (axis-based: brevity, clarity, factual, audience-fit; or destination-bundle: review-gdoc)
- `share` — publish (`share-gdoc`, `share-explainer`; other destinations are manual copy-paste)

Exceptions:
- `ari-hemingway--lib` — shared workflow (not a stage; escape hatch)
- `ari-hemingway-meta` — creator for new hemingway skills

## Preconditions

- At least one `ari-hemingway--structure-*` skill is installed.
- `/ari-hemingway--lib` installed.

## Arguments

`--autonomous` — run the pipeline to the end without stopping at any "present and wait" point. Also on when the user's words say so ("proceed without asking", "finish without me", "don't stop to confirm"); a one-step "go ahead" or "yes" answers the current prompt only. **Print `Autonomous mode: on (from: <flag or the quoted words>)` once, before step 1.** Forward the flag verbatim to every sibling invoked via the Skill tool (structure, review, share); what a sibling does with it is `## Autonomous mode` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

The dispatcher's own wait points and their defaults: shape confirm → the inferred shape; review prompt → the default of step 3; findings → `all`, with spec questions and blocker meta-findings deferred and listed; share → the destination's share action up to its publish gate, never past it. The dispatcher records its defaults under `Defaults taken` in the structure sibling's scratchpad, prefixed `dispatcher:`, and prints the consolidated list at the end of the run.

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
(7) interactive explainer   → ari-hemingway--structure-ciechanowski  (one linear toy-to-real article with a figure per concept, for the explainers site)
(8) working doc             → ari-hemingway--structure-working-doc  (a session with many orthogonal asks: one file per ask, a dependency-ordered table, dispatch to agents)
(9) other — tell me what destination and the doc's purpose
```

Auto-detect if possible: if the user pasted a Google Doc URL → `subsystem-explainer` update mode is likely. If the session is a PR branch with uncommitted changes → `pr-description`. If the user wants to "break down", "come up to speed on", or "define the parts of" a topic they lack vocabulary for → `scaffold`. If the user wants an "interactive explainer", a "Ciechanowski-style" article, or something for `explainers.sweedler.com` → `ciechanowski` (it runs `scaffold` in Skeleton mode itself). If the session has piled up several unrelated asks, or the user wants a working doc, a task table with dependencies, or to fan asks out to agents → `working-doc`. Print the inferred shape with evidence and ask to confirm.

If no matching sibling is installed, STOP and print:
```
No structure sibling installed for {shape}. Options:
(1) /ari-hemingway-meta — create the skill
(2) Pick a different shape
(3) Abort
```

### 2. Invoke the structure skill

Invoke the sibling via the Skill tool — do not Read its SKILL.md first. The Skill tool loads the full file. The sibling handles acquire (investigation) and format internally, per its own SKILL.md. Two sub-structures apply to any shape bound for a Google Doc, inside the sibling's Draft step: `/ari-hemingway--structure-aside` (optional content in its own tab, one marker per aside) and `/ari-hemingway--structure-bookmark` (a link that lands on a sentence, not a section); `/ari-hemingway--share-gdoc` publishes both.

The sibling runs through Draft, Fact-check, its `Draft ready` line, and `output.md` on its own; there is no menu to answer. Step in only if the user asks for changes.

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

Destination `explainer` has no bundle: the default is (2) with `destination=explainer`, which turns on audience-fit and tells every reviewer where the article form's rules live. The reviewers read the prose body, never the assembled page (`article/index.html` carries every figure spec as inline JSON and every poster as inline SVG). Which file that is depends on how the article was made:

- **Toolchain article** (`<folder>/article/meta.json` exists; `<folder>` is the ciechanowski investigation folder from its `Output complete` line): the author's `article/body.html` already is the prose with figure placeholders and captions. Pass it as the draft. Apply findings to `body.html` (and `meta.json`), then re-run `assemble.py` and the four gates. **NEVER edit `article/index.html` by hand; `assemble.py` regenerates it.**
- **Any other article**: extract the body once into `<folder>/review/body.html`, a new file (`[[ -e ]]` → stop):

```zsh
perl -0777 -ne 'print $1 if m{(<main.*</main>)}s' <article>/index.html \
  | perl -0777 -pe 's{<figure(.*?)>.*?(<figcaption>.*?</figcaption>)?.*?</figure>}{<figure$1>$2</figure>}gs' \
  > <folder>/review/body.html
```

`[[ -s <folder>/review/body.html ]]` or stop: no `<main>` means the wrong file. Apply findings to `index.html`, then re-run the four gates (`validate`, `states`, `build`, `budget`). Findings are anchored by quoted sentence and section id, never by line number: the file the reviewer read is not the file edited.

### 4. Invoke the reviewer

Invoke the chosen review skill via the Skill tool — do not Read its SKILL.md first. Pass the draft path (for `explainer`, the body file step 3 chose) and the destination. Wait for its `Present` step.

Apply selected findings to the draft (the reviewer is READ-ONLY, so the dispatcher drives edits). Confirm each edit with the user or apply `all` if they picked it upfront.

### 5. Share

As soon as the findings are applied, print the final draft path and take the destination's share action:

| Destination | Share action |
|---|---|
| gdoc | Invoke `/ari-hemingway--share-gdoc` — creates (or updates in place) the Doc from the markdown and styles its tables. Pass `--folder` when the user named a Drive folder; otherwise the script uses `ARI_HEMINGWAY_SCRATCH_DIR`, and only when that is unset too do you ask for a folder. |
| explainer | Invoke `/ari-hemingway--share-explainer`: its dry-run shows the card diff and the commit; `--apply` publishes on the user's confirmation. Under `--autonomous` the run ends at that confirmation. |
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
6. Share: `/ari-hemingway--share-gdoc` into the folder the user named, else `ARI_HEMINGWAY_SCRATCH_DIR`.

### Writing an interactive explainer, unattended

User invocation: `/ari-hemingway --autonomous interactive explainer on the College Football Playoff`

1. Print `Autonomous mode: on`. Infer shape: `ciechanowski`; print the evidence and take it without waiting.
2. Run `/ari-hemingway--structure-ciechanowski --autonomous` — skeleton, insights and figures each print their prompt, take the default, and land in `Defaults taken`.
3. Review prompt → printed, default taken: `common`, destination=explainer. The draft is the author's `article/body.html` (toolchain article).
4. Run `/ari-hemingway--review-common --autonomous` with destination=explainer and the body path.
5. Apply `all` findings to `article/body.html`; re-run `assemble.py` and the four gates.
6. Share: `/ari-hemingway--share-explainer` dry-run; the run pauses at its publish gate and prints the `--apply` command.

## Rules

- Invoke siblings via the Skill tool. Do NOT Read sibling SKILL.md files — the Skill tool loads them, and their descriptions are already in your available-skills index. Reading is wasteful and treats invocable skills as documentation.
- Use Agent only for parallel reviewer dispatch inside bundles.
- NEVER short-circuit the review prompt — always print it, even under `--autonomous` and even if (4) Skip is the obvious pick.
- Do NOT edit the draft until the user selects review findings to apply, or `--autonomous` has taken `all`.
- If the user provides an existing draft and skips structure, go straight to the review prompt. A path is the draft as-is. A Google Doc URL is fetched with `zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh "<url>" --publish --out <scratch>/draft.md`, whose output is already the `/ari-hemingway--share-gdoc` dialect — never the read dialect, which drops the Doc title, renders chips as markdown links, and loses an image's mermaid.live link.
