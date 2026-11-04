---
name: ari-skill-update
description: Edit a skill, review it, and end with one proposal that a single 'yes' commits to the dotfiles tier that owns it, adopting it first if it is not yet versioned. Runs on request, and unasked in the same session whenever Claude did what a skill forbade, skipped what it required, found its instruction or script wrong in use, or met a case it is silent on. The main thread settles only which skill and what change; the rest (edit, quality review, company-information review, adoption sweep) runs in one subagent, the driver, which writes the proposal to a file and reports only its path and a short summary; a session that cannot spawn a driver hands the update to a /branch. A company-information reviewer blocks company-identifying content from any public skill. Owns the rule that a question authorizes a consequence, never the start of work.
---

# Skill Update

Edit a skill, review it, and end with one *proposal* that a single `yes` commits to the dotfiles tier that owns it, adopting it first if it is not yet versioned. It runs when Ari asks, and unasked on a mistake (**A mistake is a skill update**). The *main thread* (the session Ari talks to) settles which skill and what change; one subagent, the *driver*, does the rest and writes the proposal to a file Ari opens (**Driver by default**). `/ari-skill-review` owns the quality review; `/ari-skill-shellscripts` and `/ari-skill-pythonscripts` own script conventions.

## Rules

- **A mistake is a skill update.** When Claude sees, or Ari points out, that Claude did what a skill forbade, skipped what it required, found its instruction or script wrong in use, or met a case it is silent on: name the skill in chat, state the mistake and its evidence in one line, undo the effect when the undo is local and reversible (else name it as not undoable in the same line), invoke `/ari-skill-update <skill>` with that line as the change, and go on with the work — same session, unasked. The edit starts unasked; the commit still waits for `yes`. Waiting to be asked is the failure this rule removes.
  - The fix is a rule where the behavior belongs and, when the skill has tests, a test that would have caught it.
  - A *background session* (a fork, a driver) does not invoke: the line rides its report under **Surfaced skills**, and the main thread routes it — to the skill's live driver by `SendMessage`, else to a new one. Never two drivers on one skill.
  - A mistake with no skill behind it goes to Claude's auto-memory, or to a bead when the project has a tracker.
  ```
  BAD:  "Sorry, I shouldn't have done that." … (work continues)
  BAD:  "Want me to update the skill so this doesn't recur?"
  BAD:  (the main thread runs init.zsh or edits SKILL.md itself — no driver, no review, no proposal)
  GOOD: "ari-driving-remote: I typed into a pane another session was driving; the read came back as its output; not undoable: the keys were already sent.
         /ari-skill-update ari-driving-remote"  → the driver starts; the work resumes
  GOOD (its driver already lives): SendMessage({to: "<driver>", message: "second line, same skill: <line>; fold it in and re-propose"})
  ```
- **The main thread holds the report, never the proposal or the work behind it.** The main thread NEVER runs `init.zsh`, reads the target skill's files, edits, or reviews: it settles the skill and the change, spawns one driver, relays one report, asks **Commit?**. **NEVER Read, cat or paste `proposal.md`:** its one access is the `awk` print at **Commit to dotfiles**, after `yes`; Ari opens the file to see the diff. Nothing of the driver's run reaches the main thread but the report (**Report the proposal**). An edit request (`drop N`, a spec answer, a change) goes back to the same driver by `SendMessage` and returns as a new report.
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
  - An optional tail step (a sweep, a cleanup, adopting stragglers) starts when its inputs exist, in parallel, in a subagent when slow or wide (a driver runs it itself; so does a thread that cannot spawn), and runs to a ready-to-land proposal; its `yes` covers only what the proposal explains, and what prep cannot explain is listed and left out.
  - A question whose `yes` only starts work is a defect: on every edit, rewrite each one the target skill holds.
  ```
  BAD:  "Want me to check for other pending changes?"  → yes → look → "Commit these?"
  GOOD: (a subagent already looked) "Also pending, ready to commit:
          ldf: share/bin/foo → "Add foo" — wrapper behind the new oneshot entry
        Commit it?"
  ```
- **MUST confirm before committing, and only after review.** The `yes` that commits answers a diff Ari can open at the proposal path named in that same message. Only the main thread writes **Commit?**, never a driver, a fork or any subagent, and only once the company-information reviewer's latest pass on the files as they stand returned `none` (or the skill is private, a drafted move to ldf included) and `/ari-skill-review` has run (or the user said `skip review`, which skips the quality review only); a **Commit?** before that is a defect. Unqualified agreement ("yes", "do it", "lgtm"), or a scope the **Commit?** line offered ("yes, no adoptions"), commits; conditional agreement ("yes, but change X") is an edit request: make it and re-propose. Never commit what the named proposal file does not show.
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
├── diff.patch        # the tier's diff, written by redirect at Report the proposal
└── proposal.md       # the proposal Ari opens; the only copy of the diff he sees
```

### scratchpad.md

The setup script pre-fills **Skill**; fill **Purpose** at "Read the skill", **Goal** at "Classify the change", **Changes made**, **Own read** and **Open questions** at "Edit the skill"; review changes continue the numbering of **Changes made**. A skill not yet in a tier adds `- **Tier picked**: <df|ldf> — <rule>` at "Set up the session". Drop a section if it's empty.

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

Decide once which thread you are, in this order, and name it in your first line of output (a driver's final message still begins `Proposal:`):

1. Your prompt opens "You are the driver for /ari-skill-update" → *driver*: run **Set up the session** through **Report the proposal**; the Agent tool is for reviewers only, NEVER for another driver; a second skill found wanting goes under **Surfaced skills**, unedited.
2. You are a fork or a subagent on another task → *background session*: this skill is not yours to run; the one line rides your report under **Surfaced skills**.
3. Ari typed the literal word `inline` ("just do it here" is not it) → *inline thread*: the main thread's NEVER list does not bind you; run every step yourself, then **Relay and commit** on your own report. `inline` needs the Agent tool for the reviewers.
4. The Agent tool is in your function list → *main thread*: **Identify the skill**, **Settle the change**, **Spawn the driver**, then nothing until **Relay and commit**.
5. Otherwise → **No Agent tool: branch**.

Each step below opens with its actor. The driver never asks: it takes the recommended answer to any question it would have put to Ari, finishes the edit on it, and lists the question under Open questions as `assumed: <answer>`.

### Identify the skill

Main thread.

- An exact skill directory name under `$HOME/.claude/skills/` → use it.
- A partial name or description → the one match this conversation used, and say which; ask, with `name — purpose` rows likeliest first and the top row recommended, only when two or more matches were used here, or none was.
- No name → the skill the conversation was just using; ask with a recommended pick only when there is none.
- Nothing matches → "no skill matches `<x>`; nearest: `<a>`, `<b>`; brand-new → `/ari-skill-update <x> --new`?", one recommended, and stop.

### Settle the change

Main thread. A self-caught mistake needs no search: the stated line is the change. Otherwise, if Ari ran the target skill earlier in this conversation and then corrected, overrode or worked around its output, tell him — "Earlier you used `/X` and had to do Y by hand. The skill should have done Y itself." — and that is the change. With no prior invocation, ask him to describe it (this and **Identify the skill** hold the only questions before the proposal). Note `skip review` if he said it, and `new` if he said the skill is brand-new.

### Spawn the driver

Main thread. ONE fresh general-purpose subagent (Agent tool, `subagent_type: general-purpose`, `description: skill-update <skill>`) with this prompt; it has no conversation, so the brief carries everything:

````
You are the driver for /ari-skill-update on `<skill>`. Read $HOME/.claude/skills/ari-skill-update/SKILL.md, then run it from **Set up the session** through **Report the proposal**: write the complete proposal, full diff included, to the `proposal=` path init.zsh prints. Your final message is the report only: it begins `Proposal: `, is at most 12 lines, and holds no diff, hunk or file contents. Hard limits: ask nothing; the Agent tool is for /ari-skill-review's reviewers and the company-information reviewer only, NEVER another driver; NEVER edit, invoke /ari-skill-update on, or spawn anything for a second skill — list it under Surfaced skills; NEVER run adopt or commit.
Skill: <skill>. Change: <the settled change in one sentence>.
Origin: <mistake | request>.
Evidence: "<Ari's words, or the mistake line, quoted>" — <the gap: what was done instead, or what the skill should have done>.
Flags: <skip review | new | none>.
Settled: <what the conversation decided the text must say, or none>.
````

Then one line, no question — `driver <name> spawned for <skill>: <change>; back to <work>`, where `<name>` is the name or agent ID the Agent tool returned (what `SendMessage` takes) — and back to the main work. Never ask whether to wait; the report arrives as a notification. The Evidence and Settled lines for the Rule's GOOD case:

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
This session is `<origin>` (`/rename <origin>` first if it has none). In the branch, say `send the report to <origin>` to answer Commit? here; otherwise answer it in the branch.
````

Either session reaches the other with `SendMessage({to: "<name>", message: "from <sender>: <one self-contained line>…"})`. The branch sends nothing unasked; a reply to origin's message goes back unasked.

- `send the report to <origin>` → the driver's report as sent, never the proposal file's contents (both sessions share the machine, so the path opens from either). Origin runs **Relay and commit** on it, sends `drop N` or an edit back to `skill-update/<skill>` (whose driver re-proposes, to origin), and sends `committed <sha>` at the end; the branch says "Commit? is answered in `<origin>`" and asks nothing further.
- `status?` → one line: `driver running` or `report ready`.

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
proposal=/tmp/skill-update/<name>/<timestamp>/proposal.md
=== start FILES ===
<one absolute path per line>
=== end FILES ===
```

Add `--new` only when Flags says `new` (`inline`: the user said the skill is brand-new). `state` `unlinked` or `ignored`, or `is_new=true`: pick its tier now (`/ari-dotfiles` Placement rules), record `**Tier picked**` in the scratchpad (an Open question when the rule does not decide); **Commit to dotfiles** adopts it. Any other non-linked state (`missing`, `dangling`, `shadowed`, `conflict`, `foreign`) → stop: the registry's fix comes first (`/ari-dotfiles-skill-registry` § See where things stand), as the first Open question. On a non-zero exit, do not edit; no folder exists, so the report's first line is `Proposal: none — init.zsh failed: <stderr's last line>`, and:

- no such skill → stop; the name is wrong, or the skill is brand-new and the user has not said so.
- `--new` but the skill exists → re-run without it.
- anything else → the script's stderr verbatim, and stop.

### Read the skill

Driver, or the `inline` thread. Read every file between `=== start FILES ===` and `=== end FILES ===` (Read tool). Empty on a non-`--new` run → stop: the directory holds no files (the script exits 0; the stop is yours). No `SKILL.md` → on `--new`, create it from **Skill anatomy** and go on; otherwise stop with an Open question (create one, recommended, or abort). Write the Purpose, one synthesized sentence from the `#` heading + opening paragraph, to the scratchpad's **Purpose** line; the `inline` thread also says it in chat.

### Classify the change

Driver, or the `inline` thread. Every skill has two layers — **Intent** (the Purpose: `#` heading + opening paragraph; what and why) and **Implementation** (workflow steps, rules, scripts, schemas; how):

- **Intent change:** the skill will do something new or stop doing something. Rewrite the heading + opening paragraph, and update the `description:` frontmatter field.
- **Implementation change:** purpose unchanged; a step, rule, or script changes.
- **Both:** new behavior that also needs new or changed steps. Intent first, then implementation.
- **Ambiguous:** intent — a needlessly updated description is cheaper than a stale one.

Write the scratchpad's **Goal** line: `<the change> — <intent | implementation | both> (<why, one clause>)`. If the behavior already exists in the skill, make no edit: the proposal is the no-change shape (**Report the proposal**), skipping **Review** but not **Find unadopted skills** — except when the brief's Origin is `mistake`, which never stops empty: the skill had the rule and it still broke, so sharpen the rule or add the test. Otherwise edit; the user approves the commit, not the edit.

### Edit the skill

Driver, or the `inline` thread.

1. **If intent changed** — rewrite the `#` heading and opening paragraph for the new purpose; do not patch them.
2. **Update implementation** — place each change per **Skill anatomy**. Before adding a step, `ls $HOME/.claude/skills/` and delegate to a skill that already does it (**Reuse**).
3. **Audit and syntax-check** — apply the `$HOME` rule to every invocation, pre-existing ones included; for every edited script, `zsh -n <script>.zsh` then `zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/conventions.test.zsh` (Python: `/ari-skill-pythonscripts` § Validation).
4. **Own read for company information** — when the skill is public (see Rules), read every file in the directory against the identifying-content list and fix what you find per the Rules. Record `own read: clean`, `own read: <n> fixed`, or `own read: n/a (private)`, never `none`: that word is the reviewer's verdict, and **Review › Company information** dispatches even when the own read is clean.
5. **Update scratchpad** — `[n] SECTION — change` per change, the own-read line, each open question as `assumed: <answer>`.

### Review

Driver, or the `inline` thread, right after **Edit the skill**, on the files as they stand. The main thread never runs this step.

1. **Quality** — invoke `/ari-skill-review` via the Skill tool with the skill name as the argument, unless `skip review`. It leaves `findings.md` and `spec-questions.md` in its review folder. Apply every finding, continuing the scratchpad's numbering (`[3] EXAMPLES — a filled dark-canvas example (review: examples)`); one that conflicts with a Rule, or that you challenged away, is not applied and goes under the proposal's Not carried as `<recommendation> — <rule name | reason>`. Spec questions are not applied; they ride the proposal as `<question>? recommended: <answer>`. If the review fails or returns nothing, say so in the pre-check.
2. **Company information** — when the skill is public (see Rules), dispatch a fresh reviewer with the Agent tool and this brief. Two holes: `<skill_dir>`, and the quote, pasted byte-for-byte from your Read of this file's Rules (never retyped):

   ````
   Read EVERY file under <skill_dir> (SKILL.md, bin/, lib/, templates, fixtures, tests), not just a diff. Flag anything that identifies Ari's employer; this is the test, quoted from the skill's Rules, including its last sentence of what is not identifying:
   "<the two Rules sentences, from 'Identifying content includes' through 'his homelab.', verbatim>"
   Report each finding as `<file>:<line> — <what identifies the employer> — <neutral rewrite | move to ldf>`. Return exactly `none` when clean. Edit nothing.
   ````

   Apply each fix per the Rules, then dispatch a new reviewer; repeat until it returns exactly `none`. A reply that is neither `none` nor findings is a failed dispatch. A whole-skill move to the local tier is drafted, never run before `yes`, and ends the loop with the pre-check `private (pending: <move command>)`, the move command first under Commit command; a cutpoint move is applied before the next dispatch. Stop after two failed dispatches (`failed: <why>`) or three passes with findings (`failed: N findings remain`, each under Open questions with its recommended fix).

### Find unadopted skills

Driver, or the `inline` thread; a re-proposal runs it again.

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status
```

For each `unlinked` row other than the target skill, pick its tier (`/ari-dotfiles` Placement rules) and draft its adopt and commit (see **Commit to dotfiles**). An adoption into df enters the proposal only after its own **Review › Company information** pass returned `none`; otherwise it is listed as `<skill> — not proposed: <n> findings`, no command. An `ignored` skill is third-party: list it; commit it only when the user names it. `status` fails → Adoptions is `failed: <stderr's last line>`; go on.

### Report the proposal

Driver, or the `inline` thread. Write the proposal to the `proposal=` path, then send the report as your final message. Every driver exit has both, a stop included: the proposal's title is then `## Proposal: <skill> — stopped at <step>` or `— no change`, Diff `none — <why>`, Commit command `none`, and the stop reason is the first Open question with a recommended answer (a stop inside `init.zsh` has no file: **Set up the session**). Neither asks Ari anything — questions carry `assumed:` or `recommended:` answers — or holds anything of the run but what **Commit?** needs: no reviewer reports, no scratchpad contents, no intermediate diffs. A re-proposal overwrites the file, which opens with `Since last: <what changed>`, and the report carries the same line.

**Write the diff by redirect; NEVER print or Read it.** Run the tier's diff command with `> <investigation_dir>/diff.patch`, append `git diff --no-index /dev/null <file> >> …/diff.patch` for each file `<tier git> ls-files --others --exclude-standard -- <path>` lists (`diff HEAD` omits untracked files, which `add` then commits), and take the report's counts from the same commands with `--shortstat`. Assemble the file with one `cat` of the part above Diff, `diff.patch` and the part below. **The file's diff MUST be complete: every hunk, every file, no `…`, no `(N lines omitted)`;** an elided diff is not a proposal. An empty diff makes the Commit command `none — empty diff`.

Diff command by tier: df `git df diff HEAD -- $HOME/.config/claude/skills/<skill-name>`; ldf `git ldf diff HEAD -- $HOME/.local/share/claude-skills/<skill-name>`; submodule `git -C $HOME/<path> diff HEAD -- skills/<skill-name>`; unlinked `git diff --no-index /dev/null <file>` per file (exit 1 means it differs, not a failure).

The proposal, in the file:

`````markdown
## Proposal: <skill-name>
Tier: <df (public) | ldf (private) | submodule:<path> (public) | unlinked → <df|ldf>>
Pre-check: own read <clean | n fixed | n/a (private)>; company-information reviewer: <none | private | private (pending: <move command>) | failed: <why>>; quality review: <run: N findings, N applied, N not carried | skipped | failed: <why>>.
Investigation: <scratchpad path>; review folder: <findings.md path | skipped>.
### Diff
~~~~diff
<diff.patch: the tier's diff, untracked files appended>
~~~~
### Changes (numbered; `drop N` reverts one)
1. SECTION — change
Not carried: <recommendation> — <rule name | reason>; …
### Spec questions
<each as `<question>? recommended: <answer>`; or none>
### Open questions
<each as `<question> assumed: <answer>`; or none>
### Commit command
```zsh
<the tier's add + commit, per **Commit to dotfiles**; or none — <why>>
```
### Adoptions
<skill> → <tier> — reviewer: <none | private> — files: <list> — <reason>
```zsh
<its adopt + commit>
```
### Surfaced skills
<one mistake line each, as in **A mistake is a skill update**; or none>
`````

The report, the final message — at most 12 lines, each field one line; a list field holds up to 3 items, `; `-separated, and more become `<n> — see proposal`:

````markdown
Proposal: <proposal path | none — init.zsh failed: <why>>
<skill-name> — <what changes, one line | stopped at <step>: <why> | no change: <why>>
Since last: <what changed; re-proposals only>
Tier: <as in the proposal>
Pre-check: <as in the proposal>
Diff: <complete — <n> files, +<a> −<b> | none — <why>>
Changes: <n> (`drop N` reverts one); not carried: <n>
Spec questions: <`<question>? recommended: <answer>` each | none>
Open questions: <`<question> assumed: <answer>` each | none>
Adoptions: <skill → tier each | none>
Surfaced skills: <one mistake line each | none>
````

```
BAD:  ## Proposal: ari-driving-remote / ### Diff / diff --git …   ← the proposal belongs in the file, not the report
BAD:  …Surfaced skills: none / Ready to commit?                    ← Commit? is the main thread's word
GOOD: Proposal: /tmp/skill-update/ari-driving-remote/20261104T231402Z/proposal.md
      ari-driving-remote — the send gate refuses a pane whose mark another session set
      Tier: df (public)
      Pre-check: own read clean; company-information reviewer: none; quality review: run: 9 findings, 7 applied, 2 not carried.
      Diff: complete — 2 files, +14 −3
      Changes: 4 (`drop N` reverts one); not carried: 2
      Spec questions: none
      Open questions: Refuse a stale mark from a dead session too? assumed: yes, the owner check covers it.
      Adoptions: none
      Surfaced skills: none
```

### Relay and commit

Main thread; the `inline` thread on its own report (the report is the relay: show it once); origin on a sent one. In the next message you send:

1. **Gate the report.** A report's first line is `Proposal: ` and then a path ending `/proposal.md` or `none —`; it has at most 12 lines and no `diff --git`, `@@` or `###`. **Not a report → NEVER relay any of it:** one status line, and send the driver `report only, per Report the proposal`.
2. **Relay it.** `driver <name> reported:`, then the report as sent — never the file's contents, no read of the file, no added findings.
3. **End with Commit?** when the Pre-check meets **MUST confirm before committing** (reviewer `none`, `private` or `private (pending: …)`; quality `run` or `skipped`) and Diff reads `complete`. State its scope: `Commit? (yes = <skill> + N adoptions; yes, no adoptions = <skill> only)`, or `Commit? (yes = <skill>; no adoptions pending)`. A no-change or stopped report is relayed with no retry, and asks `Commit? (yes = N adoptions)` only when adoptions are ready. If the message already ends in a question, the one question names both consequences.
4. **Otherwise** relay without the question, say what is missing, and send the driver one line to retry (`full diff`, `retry reviewer`); if that retry also fails, ask Ari to pick, with a recommendation (`skip review` covers a quality gap only; a reviewer gap: the fix per finding, or the move to ldf).

```
BAD:  "Driver done: added the owner check to ari-driving-remote, both reviews clean. Commit?"   ← no path; `yes` answers a diff Ari cannot open
BAD:  driver skill-update-ari-driving-remote reported: ## Proposal: … ### Diff … (844 lines)   ← the file pasted into the conversation
GOOD: driver skill-update-ari-driving-remote reported:
      <the report as sent: Proposal: <path>, then its summary lines>
      Commit? (yes = ari-driving-remote; no adoptions pending)
GOOD (a gate unmet): driver skill-update-ari-driving-remote reported:
      <the report as sent>
      Missing: the company-information reviewer failed. Sent the driver: retry reviewer.
```

- `yes` → **Commit to dotfiles**.
- "show me the diff" → the path again and `$EDITOR <path>`; quote only a hunk Ari names, never the file.
- `no` → one line: the edits sit uncommitted at `<skill_dir>`; the revert command, shown, not run (df `git df checkout -- $HOME/.config/claude/skills/<skill-name>`; ldf `git ldf checkout -- $HOME/.local/share/claude-skills/<skill-name>`; submodule `git -C $HOME/<path> checkout -- skills/<skill-name>`; new or unlinked files: the files to delete).
- `drop N`, a spec answer, an edit → `SendMessage({to: "<driver>", message: "drop 2"})`; the driver edits, re-runs **Review › Company information** on the files as they stand, rewrites the proposal file, and returns a new report; relay and ask again. NEVER a fresh driver for this. Only when `SendMessage` fails, or the result fails the gate twice: relay its last line and respawn ONE driver with the original brief plus `Resume: the files are already edited; investigation = <the directory of the last reported Proposal: path>; apply "<Ari's answer>"; start at Review`.
- A message that does not address the proposal → handle it, keep **Commit?** pending, re-ask it in full at the end of the next message.

A git failure's diagnosis is the main thread's; a fix that touches skill files goes to the driver as an edit request.

### Commit to dotfiles

Main thread, on `yes`. Print the commands with `awk '/^### Commit command$/{p=1} /^### Surfaced skills$/{p=0} p' <proposal path>` (for `yes, no adoptions`, end at `/^### Adoptions$/`), and run the fenced commands it prints and nothing else. It prints nothing, or the file is missing → no commit; send the driver `re-propose`. Commit command `none — …` → nothing to commit; skip. Then the SHA per commit, and for a public tier "push is yours (`/ari-dotfiles`)". Commit messages in a public tier say what changed, never what leaked.

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

On a failure, stop at that commit and say which landed (their SHAs); show the error, diagnose it, and propose the fix with the command that retries; never retry before a `yes`. The edits stay local whatever the answer.

## Skill-writing principles

### Skill anatomy

Sections are `##`, steps `###`; headings are never numbered: steps get reordered.

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
