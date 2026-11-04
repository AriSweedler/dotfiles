---
name: ari-skill-update
description: Edit a skill, review it, and end with one proposal that a single 'yes' commits to the dotfiles tier that owns it, adopting it first if it is not yet versioned. Runs on request, and unasked in the same session whenever Claude did what a skill forbade, skipped what it required, found its instruction or script wrong in use, or met a case it is silent on. The main thread settles only which skill and what change; the rest (edit, quality review, company-information review, adoption sweep) runs in one subagent, the driver, whose report is the proposal; a session that cannot spawn a driver hands the update to a /branch. A company-information reviewer blocks company-identifying content from any public skill. Owns the rule that a question authorizes a consequence, never the start of work.
---

# Skill Update

Edit a skill, review it, and end with one *proposal* that a single `yes` commits to the dotfiles tier that owns it, adopting it first if it is not yet versioned. It runs when Ari asks, and unasked on a mistake (**A mistake is a skill update**). The *main thread* (the session Ari talks to) settles only which skill and what change; the rest — the edit, the quality review, the company-information reviewer who reads the whole skill before any public commit, the adoption sweep — runs in one subagent, the *driver*, whose final report is the proposal (**Driver by default**). A session that cannot spawn a driver hands the update to a `/branch` (**No Agent tool: branch**). `/ari-skill-review` owns the quality review; `/ari-skill-shellscripts` and `/ari-skill-pythonscripts` own script conventions.

## Rules

- **A mistake is a skill update.** When Claude sees, or Ari points out, that Claude did what a skill forbade, skipped what it required, found its instruction or script wrong in use, or met a case it is silent on: name the skill in chat, state the mistake and its evidence in one line, undo the effect (or name it as not undoable in the same line), invoke `/ari-skill-update <skill>` with that line as the change, and go on with the work — same session, unasked. The edit starts unasked; the commit still waits for `yes`. Waiting to be asked is the failure this rule removes.
  - The fix is a rule where the behavior belongs and, when the skill has tests, a test that would have caught it.
  - A *background session* (a fork, a driver) does not invoke: the line rides its report under **Surfaced skills**, and the main thread routes it — to the skill's live driver by `SendMessage`, else to a new one. Never two drivers on one skill.
  - A mistake with no skill behind it goes to Claude's auto-memory, or to a bead when the project has a tracker.
  ```
  BAD:  "Sorry, I shouldn't have done that." … (work continues)
  BAD:  "Want me to update the skill so this doesn't recur?"
  BAD:  (the main thread runs init.zsh or edits SKILL.md itself — no driver, no review, no proposal)
  GOOD: "ari-driving-remote: I typed into a pane another session was driving; the read came back as its output.
         /ari-skill-update ari-driving-remote"  → the driver starts; the work resumes
  GOOD (its driver already lives): SendMessage({to: "<driver>", message: "second line, same skill: <line>; fold it in and re-propose"})
  ```
- **The main thread holds the proposal, never the work behind it.** The main thread NEVER runs `init.zsh`, reads the target skill's files, edits, or reviews (`inline` excepted): it settles the skill and the change, spawns one driver, relays one proposal, asks **Commit?**. Nothing of the driver's run reaches it but the proposal (**Report the proposal**), which is long, and is the one long thing it holds. Any answer but `yes` goes back to the same driver by `SendMessage` and returns as the proposal again.
- **Keep skill text short.** One sentence per instruction; no preamble. Cut any sentence that adds no information.
- **Integrate, don't append.** When editing a skill, rewrite the section where the new behavior belongs — never tack lines onto the end of a section or append bullets to a list.
  ```
  BAD (appending a bullet):
    ### Push to registry
    - Verify the branch is clean.
    - Run sync and push commands.
    - If the user said "draft", pass --draft.   ← appended

  GOOD (rewriting):
    ### Push to registry
    Verify the branch is clean. If the user said "draft" or "wip",
    include the --draft flag. Then sync and push:
  ```
- **Ask only to authorize a consequence.** Two questions are allowed: for what only the user knows (which skill, which of two histories to keep), and for a `yes` to a consequence (a commit, push, send, delete: anything outward-facing or hard to undo). Never for permission to start read-only or reversible work — editing an uncommitted file, running a reviewer, drafting a commit plan: do it, then show it.
  - A question arrives ready: evidence gathered, an answer recommended, every pending consequence folded into the one question that ends the message.
  - An optional tail step (a sweep, a cleanup, adopting stragglers) starts when its inputs exist, in parallel, in a subagent when slow or wide (in the same thread when none can spawn), and runs to a ready-to-land proposal; its `yes` covers only what the proposal explains, and what prep cannot explain is listed and left out.
  - A question whose `yes` only starts work is a defect: on every edit, rewrite each one the target skill holds.
  ```
  BAD:  "Want me to check for other pending changes?"  → yes → look → "Commit these?"
  GOOD: (a subagent already looked) "Also pending, ready to commit:
          ldf: share/bin/foo → "Add foo" — wrapper behind the new oneshot entry
        Commit it?"
  ```
- **MUST confirm before committing, and only after review.** The `yes` that commits answers a diff shown in that same message. Only the main thread writes **Commit?**, never a driver, a fork or any subagent, and only once the company-information reviewer's latest pass on the files as they stand returned `none` (or the skill is private) and `/ari-skill-review` has run (or the user said `skip review`, which skips the quality review only); a proposal before that is a defect. Unqualified agreement ("yes", "do it", "lgtm") commits; conditional agreement ("yes, but change X") is an edit request: make it and re-propose. Never commit what the user has not seen.
- **Audit every documented invocation for the `$HOME` form.** On every edit — including prose-only edits — scan the skill for any line that runs a skill script. Each MUST use `$HOME` (never `~`), have no leading `cd`, and not be piped (redirect to a file if you need the output). Fix every non-conforming invocation you find, even ones unrelated to the requested change.
  ```
  BAD:  zsh ~/.claude/skills/foo/bin/x.zsh --id 123                  # ~ instead of $HOME
  BAD:  cd ~/.claude/skills/foo && zsh bin/x.zsh --id 123            # leading cd + relative path
  BAD:  zsh $HOME/.claude/skills/foo/bin/x.zsh --id 123 | head       # piped — truncates output
  BAD:  cd /repo; zsh ~/.claude/skills/foo/bin/x.zsh --id 123 2>&1 | tail -40   # all of the above
  GOOD: zsh $HOME/.claude/skills/foo/bin/x.zsh --id 123
  ```
- **NEVER scaffold around a self-contained script.** Skill scripts do their own setup. When a step says to run one, emit exactly that one Bash call — no `mkdir`, `ls`, `echo`, `cd`, or timestamp before or after it. Need its output? Read what it prints; don't re-derive it.
- **Anything that identifies the employer belongs only in a private skill.** A skill in the shared tier (`tier=df`) or in a submodule with a public upstream (`source=submodule:…`; every submodule today) is public; the local tier (`tier=ldf`) is private — `/ari-dotfiles` Placement rules own that split. Identifying content includes the company's name, brand or email domain; internal repo, service, tool, CLI, pipeline, table, team or channel names; hostnames, IPs, cloud account or project IDs, ARNs and secret paths; internal file paths and PR titles; ticket systems and ticket IDs; coworkers' names; office details; and names of private skills. Not identifying is what Ari owns himself: his first name, the names of his personal machines, his personal GitHub, his homelab. Never write the employer's name into a public skill, not even to forbid it. Fix each instance one of two ways: make it neutral (a placeholder such as `acme/shop`, `example.com`, `ip-10-0-12-34`, or a generic tool kind), or move it to the local tier — the whole skill (an `unlinked` one by `adopt --tier ldf`; a linked one per `/ari-dotfiles` § Moving a file between tiers, then the registry's `link`), or just the company part, in a local file the public skill reads when it exists (a cutpoint, per `/ari-dotfiles` § Cutpoints).
- **Scripts MUST follow the conventions skill for their language.** zsh → `/ari-skill-shellscripts`, Python → `/ari-skill-pythonscripts`. Read it first, then bring the whole script — not just the lines you changed — into compliance, and run its Validation gate. For another language, use that language's conventions skill; if none exists, build one (mirroring these) first.

## Investigation folder

```
/tmp/skill-update/{skill-name}/{timestamp}/     # one per invocation
├── scratchpad.md
```

### scratchpad.md

The setup script pre-fills **Skill**; fill **Purpose** at "Read the skill", **Goal** at "Classify the change", **Changes made**, **Own read** and **Open questions** at "Edit the skill"; review changes continue the numbering of **Changes made**. Drop a section if it's empty.

```markdown
- **Skill**: ari-diagram-mermaid — $HOME/.claude/skills/ari-diagram-mermaid/SKILL.md — Create, validate, and share Mermaid.js diagrams
- **Purpose**: Create, validate and share Mermaid diagrams in a fixed palette that stays legible on any canvas.
- **Goal**: Add a dark-canvas preview when the user says "dark" or "night" — implementation (the purpose already says "any canvas"; the flag is how)
- **Changes made**:
  - [1] FILE STORAGE — added a --dark flag to bake for the preview image
  - [2] SHARE — the Share step mentions dark previews
  - [3] EXAMPLES — a filled dark-canvas example (review: examples)
- **Own read**: clean
- **Open questions**:
  - Should bake refuse a theme block that fails contrast only on the dark canvas? assumed: yes, the same gate on both canvases.
```

## File storage

- `bin/init.zsh` — run once at **Set up the session**, which holds its output contract.

## Workflow

### Driver by default

Decide once which thread you are, in this order, and name it in your first line:

1. Your prompt opens "You are the driver for /ari-skill-update" → *driver*: run **Set up the session** through **Report the proposal**; the Agent tool is for reviewers only, NEVER for another driver; a second skill found wanting goes under **Surfaced skills**, unedited.
2. You are a fork or a subagent on another task → *background session*: this skill is not yours to run; the one line rides your report under **Surfaced skills**.
3. Ari typed the literal word `inline` ("just do it here" is not it) → *inline thread*: run every step yourself, then **Relay and commit** on your own proposal. `inline` needs the Agent tool for the reviewers.
4. The Agent tool is in your function list → *main thread*: **Identify the skill**, **Settle the change**, **Spawn the driver**, then nothing until **Relay and commit**.
5. Otherwise → **No Agent tool: branch**.

Each step below opens with its actor. The driver never asks: a question it would have put to Ari is answered with its recommended answer, the edit finished on it, and the question listed under Open questions as `assumed: <answer>`.

### Identify the skill

Main thread.

- An exact skill directory name under `$HOME/.claude/skills/` → use it.
- A partial name or description → the one match this conversation used, and say which; ask, with `name — purpose` rows likeliest first and the top row recommended, only when two or more matches were used here, or none was.
- No name → the skill the conversation was just using; ask with a recommended pick only when there is none.
- Nothing matches → "no skill matches `<x>`; brand-new → `/ari-skill-update <x> --new`?" and stop.

### Settle the change

Main thread. A self-caught mistake needs no search: the stated line is the change. Otherwise, if Ari ran the target skill earlier in this conversation and then corrected, overrode or worked around its output, tell him — "Earlier you used `/X` and had to do Y by hand. The skill should have done Y itself." — and that is the change. With no prior invocation, ask him to describe it (this and **Identify the skill** hold the only questions before the proposal). Note `skip review` if he said it.

### Spawn the driver

Main thread. ONE fresh general-purpose subagent (Agent tool, `subagent_type: general-purpose`, `description: skill-update <skill>`) with this prompt; it has no conversation, so the brief carries everything:

````
You are the driver for /ari-skill-update on `<skill>`. Read $HOME/.claude/skills/ari-skill-update/SKILL.md, then run it from **Set up the session** through **Report the proposal** and return that proposal, complete and verbatim, as your final message. Hard limits: ask nothing; the Agent tool is for /ari-skill-review's reviewers and the company-information reviewer only, NEVER another driver; NEVER edit, invoke /ari-skill-update on, or spawn anything for a second skill — list it under Surfaced skills; NEVER run adopt or commit.
Skill: <skill>. Change: <the settled change in one sentence>.
Evidence: "<Ari's words, or the mistake line, quoted>" — <the gap: what was done instead, or what the skill should have done>.
Flags: <skip review | none>.
Settled: <what the conversation decided the text must say, or none>.
````

Then one line, no question — `driver <name> spawned for <skill>: <change>; back to <work>` — and back to the main work. Never ask whether to wait; the proposal arrives as a notification. The Evidence and Settled lines for the Rule's GOOD case:

```
Evidence: "ari-driving-remote: I typed into a pane another session was driving; the read came back as its output." — the send gate checks idle-at-prompt and the mark, not which session set the mark.
Settled: the gate refuses a pane whose mark another session set; nothing new to ask Ari.
```

### No Agent tool: branch

Main thread without the Agent tool. Do not edit, run `init.zsh` or review here, however small the change: the review fan-out would land in this conversation, which is what the driver exists to prevent. Hand the update to a `/branch`: it inherits the conversation, so the settled skill and change travel with it, and there `/ari-skill-update <skill>` is the main thread and spawns the driver. Both sessions take names: `SendMessage` addresses by name (`ListAgents` lists them). Put this in chat, filled in; Ari types the lines:

````
This session has no Agent tool, so the update runs in a branch:
  /branch
  /rename skill-update/<skill>
  /ari-skill-update <skill>
This session is `<origin>` (`/rename <origin>` first if it has none). In the branch, say `send the proposal to <origin>` to answer Commit? here; otherwise answer it in the branch.
````

Either session reaches the other with `SendMessage({to: "<name>", message: "from <sender>: <one self-contained line>…"})`. The branch sends nothing unasked; a reply to origin's message goes back unasked.

- `send the proposal to <origin>` → the whole proposal. Origin runs **Relay and commit** on it, sends `drop N` or an edit back to `skill-update/<skill>` (whose driver re-proposes, to origin), and sends `committed <sha>` at the end; the branch says "Commit? is answered in `<origin>`" and asks nothing further.
- `status?` → one line: `driver running` or `proposal ready`.

A branch that also has no Agent tool stops and says so; never a second branch.

### Set up the session

Driver, or the `inline` thread. Run the setup script — **exactly this one Bash call, nothing around it**:

```zsh
zsh $HOME/.claude/skills/ari-skill-update/bin/init.zsh --skill <skill-name>
```

It prints (`state`/`tier` per `/ari-dotfiles-skill-registry`):

```
skill=<name>
is_new=false
state=linked        # unlinked / ignored: not yet adopted into a tier; any other state: see below
tier=df             # - when no tier holds it
source=             # submodule:<path> when a submodule's skills/ holds it (commit there)
skill_dir=$HOME/.claude/skills/<name>
investigation_dir=/tmp/skill-update/<name>/<timestamp>
scratchpad=/tmp/skill-update/<name>/<timestamp>/scratchpad.md
=== start FILES ===
<one absolute path per line>
=== end FILES ===
```

Run it without `--new`; add `--new` only when the user said the skill is brand-new. `state` `unlinked` or `ignored`: pick its tier now (`/ari-dotfiles` Placement rules), record `tier picked: <df|ldf> — <rule>` in the scratchpad (an Open question when the rule does not decide); **Commit to dotfiles** adopts it. Any other non-linked state (`missing`, `dangling`, `shadowed`, `conflict`, `foreign`) → stop: the registry's fix comes first (`/ari-dotfiles-skill-registry` § See where things stand), as the first Open question. On a non-zero exit, do not edit:

- no such skill → stop; the name is wrong, or the skill is brand-new and the user has not said so.
- `--new` but the skill exists → re-run without it.
- anything else → the script's stderr verbatim, and stop.

### Read the skill

Driver, or the `inline` thread. Read every file between `=== start FILES ===` and `=== end FILES ===` (Read tool). Empty on a non-`--new` run → stop: the directory holds no files (the script exits 0; the stop is yours). No `SKILL.md` → stop with an Open question (create one from **Skill anatomy**, recommended, or abort). Write the Purpose, one synthesized sentence from the `#` heading + opening paragraph, to the scratchpad's **Purpose** line; the `inline` thread also says it in chat.

### Classify the change

Driver, or the `inline` thread. Every skill has two layers — **Intent** (the Purpose: `#` heading + opening paragraph; what and why) and **Implementation** (workflow steps, rules, scripts, schemas; how):

- **Intent change:** the skill will do something new or stop doing something. Rewrite the heading + opening paragraph, and update the `description:` frontmatter field.
- **Implementation change:** purpose unchanged; a step, rule, or script changes.
- **Both:** new behavior that also needs new or changed steps. Intent first, then implementation.
- **Ambiguous:** intent — a needlessly updated description is cheaper than a stale one.

Write the scratchpad's **Goal** line: `<the change> — <intent | implementation | both> (<why, one clause>)`. If the behavior already exists in the skill, make no edit: the proposal is the no-change shape (**Report the proposal**), skipping **Review** but not **Find unadopted skills** — except on a mistake path, which never stops empty: the skill had the rule and it still broke, so sharpen the rule or add the test. Otherwise edit; the user approves the commit, not the edit.

### Edit the skill

Driver, or the `inline` thread.

1. **If intent changed** — rewrite the `#` heading and opening paragraph for the new purpose; do not patch them.
2. **Update implementation** — place each change per **Skill anatomy**. Before adding a step, `ls $HOME/.claude/skills/` and delegate to a skill that already does it (**Reuse**).
3. **Audit and syntax-check** — apply the `$HOME` rule to every invocation, pre-existing ones included; for every edited script, `zsh -n <script>.zsh` then `zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/conventions.test.zsh` (Python: `/ari-skill-pythonscripts` § Validation).
4. **Own read for company information** — when the skill is public (see Rules), read every file in the directory against the identifying-content list and fix what you find per the Rules. Record `own read: clean` or `own read: <n> fixed`, never `none`: that word is the reviewer's verdict, and **Review › Company information** dispatches even when the own read is clean.
5. **Update scratchpad** — `[n] SECTION — change` per change, the own-read line, each open question as `assumed: <answer>`.

### Review

Driver, or the `inline` thread, right after **Edit the skill**, on the files as they stand. The main thread never runs this step.

1. **Quality** — invoke `/ari-skill-review` via the Skill tool with the skill name as the argument, unless `skip review`. It leaves `findings.md` and `spec-questions.md` in its review folder. Apply every finding, continuing the scratchpad's numbering (`[3] EXAMPLES — a filled dark-canvas example (review: examples)`); one that conflicts with a Rule, or that you challenged away, is not applied and goes under the proposal's Not carried as `<recommendation> — <rule name | reason>`. Spec questions are not applied; they ride the proposal. If the review fails or returns nothing, say so in the pre-check.
2. **Company information** — when the skill is public (see Rules), dispatch a fresh reviewer with the Agent tool and this brief. Two holes: `<skill_dir>`, and the quote, pasted byte-for-byte from your Read of this file's Rules (never retyped):

   ````
   Read EVERY file under <skill_dir> (SKILL.md, bin/, lib/, templates, fixtures, tests), not just a diff. Flag anything that identifies Ari's employer; this is the test, quoted from the skill's Rules, including its last sentence of what is not identifying:
   "<the two Rules sentences, from 'Identifying content includes' through 'his homelab.', verbatim>"
   Report each finding as `<file>:<line> — <what identifies the employer> — <neutral rewrite | move to ldf>`. Return exactly `none` when clean. Edit nothing.
   ````

   Apply each fix per the Rules, then dispatch a new reviewer; repeat until it returns exactly `none`. A reply that is neither `none` nor findings is a failed dispatch. A whole-skill move to the local tier is drafted, never run before `yes`, and ends the loop with the pre-check `private (pending: <move command>)`; a cutpoint move is applied before the next dispatch. Stop after two failed dispatches (`failed: <why>`) or three passes with findings (`failed: N findings remain`, each under Open questions with its recommended fix).

### Find unadopted skills

Driver, or the `inline` thread.

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status
```

For each `unlinked` row, pick its tier (`/ari-dotfiles` Placement rules) and draft its adopt and commit (see **Commit to dotfiles**). An adoption into df enters the proposal only after its own **Review › Company information** pass returned `none`; otherwise it is listed as `<skill> — not proposed: <n> findings`, no command. An `ignored` skill is third-party: list it; commit it only when the user names it.

### Report the proposal

The driver's final message; the `inline` thread writes it into the scratchpad and shows it. Every driver exit uses this shape, including a stop: then the title is `## Proposal: <skill> — stopped at <step>` or `— no change`, Diff is `none — <why>`, Commit command `none`, and the stop reason is the first Open question with a recommended answer. It contains no question and nothing of the run but what **Commit?** needs: no reviewer reports, no scratchpad contents, no intermediate diffs. **The diff MUST be complete: every hunk, every file, no `…`, no `(N lines omitted)`;** an elided diff is not a proposal. A re-proposal opens with `Since last: <what changed>`.

````markdown
## Proposal: <skill-name>
Tier: <df (public) | ldf (private) | submodule:<path> (public) | unlinked → <df|ldf>>
Pre-check: own read <clean | n fixed>; company-information reviewer: <none | private | private (pending: <move command>) | failed: <why>>; quality review: <run: N findings, N applied, N not carried | skipped | failed: <why>>.
Investigation: <scratchpad path>; review folder: <findings.md path | skipped>.
### Diff
<the full output of the tier's diff command>
### Changes (numbered; `drop N` reverts one)
1. SECTION — change
Not carried: <recommendation> — <rule name | reason>; …
### Spec questions
<from the review folder's spec-questions.md, each with a recommended answer; or none>
### Open questions
<each as `<question> assumed: <answer>`; or none>
### Commit command
<the tier's add + commit, per **Commit to dotfiles**>
### Adoptions
<skill> → <tier> — reviewer: <none | private> — files: <list> — <reason>
  <its adopt + commit>
### Surfaced skills
<one mistake line each, as in **A mistake is a skill update**; or none>
````

Diff command by tier: df `git df diff HEAD -- $HOME/.config/claude/skills/<skill-name>`; ldf `git ldf diff HEAD -- $HOME/.local/share/claude-skills/<skill-name>`; submodule `git -C $HOME/<path> diff HEAD -- skills/<skill-name>`; unlinked `git diff --no-index /dev/null <file>` per file.

```
BAD:  …### Surfaced skills / none / Ready to commit?            ← Commit? is the main thread's word
GOOD: ### Open questions / Should bake refuse … on the dark canvas? assumed: yes, the same gate on both canvases.
```

### Relay and commit

Main thread; the `inline` thread on its own proposal; origin on a sent one. Paste the proposal verbatim in the next message you send — no summary, no re-read of the diff for problems, no added findings; if that message already ends in a question, the one question names both consequences. Keep the driver's name in the line before it. End with **Commit?** when the pre-check meets **MUST confirm before committing** (reviewer `none` or `private`; quality `run` or `skipped`) and the Diff is complete; the question states its scope: `Commit? (yes = <skill> + N adoptions; yes, no adoptions = <skill> only)`. Otherwise relay without the question, say what is missing, send the driver one line to retry (`full diff`, `retry reviewer`), and after a second failure ask Ari to pick, with a recommendation (`skip review` covers a quality gap only; a reviewer gap: the fix per finding, or the move to ldf).

```
BAD:  "Driver done: added the owner check to ari-driving-remote, both reviews clean. Commit?"   ← no diff shown; `yes` answers nothing
GOOD: driver skill-update-ari-driving-remote reported:
      <the proposal, verbatim, diff included>
      Commit? (yes = ari-driving-remote; no adoptions pending)
```

- `yes` → **Commit to dotfiles**.
- `no` → one line: the edits sit uncommitted at `<skill_dir>`; the revert command, shown, not run (`git df checkout -- $HOME/.config/claude/skills/<skill-name>`; unlinked: the files to delete).
- `drop N`, a spec answer, an edit → `SendMessage({to: "<driver>", message: "drop 2"})`; the driver edits, re-runs **Review › Company information** on the files as they stand, and returns the proposal; relay and ask again. NEVER a fresh driver for this. Only when `SendMessage` fails, or the result is not a proposal (does not begin `## Proposal:`): relay its last line and respawn ONE driver with the original brief plus `Resume: the files are already edited; investigation = the newest under /tmp/skill-update/<skill>/; apply "<Ari's answer>"; start at Review`.
- A message that does not address the proposal → handle it, keep **Commit?** pending, re-ask it in full at the end of the next message.

A git failure's diagnosis is the main thread's; a fix that touches skill files goes to the driver as an edit request.

### Commit to dotfiles

Main thread, on `yes`, with the command the proposal shows and nothing else; then the SHA per commit, and for a public tier "push is yours (`/ari-dotfiles`)". An empty `diff HEAD` has nothing to commit; skip. Commit messages in a public tier say what changed, never what leaked.

`state=linked`: stage and commit through `tier` per `/ari-dotfiles`, the path after `--` as well:

```zsh
git df add $HOME/.config/claude/skills/<skill-name> && git df commit -m "<skill-name>: <what changed and why>" -- $HOME/.config/claude/skills/<skill-name>
```

(`git ldf add $HOME/.local/share/claude-skills/<skill-name>` and `git ldf commit … -- <that path>` for `tier=ldf`.) Pushing follows `/ari-dotfiles`'s Pushing rules; this skill never pushes.

`source=submodule:<path>`: the skill is versioned in that submodule's own repo, not the tier. Commit there per `/ari-dotfile--submodule` (on its `main`, its commit conventions); Ari's `dotfiles push` pushes it and commits the pointer bump (`/ari-dotfiles` § Submodules):

```zsh
git -C $HOME/<path> add skills/<skill-name> && git -C $HOME/<path> commit -m "<skill-name>: <what changed and why>" -- skills/<skill-name>
```

`state=unlinked` or `ignored` (a `--new` skill is `unlinked` once its SKILL.md exists): adopt into the tier picked at setup, then commit in the registry's form; the adoptions drafted under **Find unadopted skills** land the same way, one commit each:

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/adopt --skill <skill-name> --tier df && git df commit -m "claude: adopt the <skill-name> skill into the shared tier" -- $HOME/.config/claude/skills/<skill-name>
```

On a failure, show the error, diagnose it, and propose the fix with the command that retries; never retry before a `yes`. The edits stay local whatever the answer.

## Skill-writing principles

### Skill anatomy

Sections are `##`, steps `###`, never numbered: steps get reordered.

- **Workflow** — sequential steps, start to finish
- **Rules** — invariants, always in effect regardless of step
- **Investigation folder** — `/tmp` structure for runtime state
- **File storage** — persistent files in the skill directory (`bin/`, `templates/`)
- **Input** — what the user provides to start

**Where to place an instruction:**
- Applies to one `###` step? Put it inside that step.
- Applies to two or more steps, or always? Put it in `## Rules`.
- Unsure? `## Rules`: an over-broad rule is harmless; one buried in a step that applies to many is a bug.

### Reuse

Never reimplement what another skill provides — delegate with a `/skill-name` reference. If multiple skills share a pattern, extract it to a base skill and reference it.

### Scripts

Prefer scripts over LLM tool calls: no permission prompts, standalone, deterministic. Conventions: see `## Rules`.
