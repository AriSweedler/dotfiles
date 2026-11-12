---
name: ari-skill-update
description: Edit a skill, review it, and end with one proposal that a single 'yes' commits to the dotfiles tier that owns it, adopting it first if it is not yet versioned. Runs on request, and unasked in the same session whenever Claude did what a skill forbade, skipped what it required, found its instruction or script wrong in use, or met a case it is silent on. The main thread settles only which skill and what change; the rest (edit, a quality review scaled to the change, a company-information review on every machine but the personal laptop, adoption sweep) runs in one subagent, the driver, which writes the proposal to a file and reports only its path and a short summary; a session that cannot spawn a driver hands the update to a /branch. Except on the personal laptop, a company-information reviewer blocks company-identifying content from any public skill. Owns the rule that a question authorizes a consequence, never the start of work.
---

# Skill Update

Edit a skill, review it, and end with one *proposal* that a single `yes` commits to the dotfiles tier that owns it, adopting it first if it is not yet versioned. It runs when Ari asks, and unasked on a mistake (**A mistake is a skill update**). The *main thread* (the session Ari talks to) settles which skill and what change; one subagent, the *driver*, does the rest and writes the proposal to a file Ari opens (**Driver by default**). The update is *side work* in the sense `/ari-bead-driven-development` defines (Terms: main work / side work): the main thread stays on main work, and by default the update is handed to the driver, which reports in a line or two. `/ari-skill-review` owns the quality review; `/ari-skill-shellscripts` and `/ari-skill-pythonscripts` own script conventions.

## Rules

- **A mistake is a skill update.** When Claude sees, or Ari points out, that Claude did what a skill forbade, skipped what it required, found its instruction or script wrong in use, or met a case it is silent on: diagnose the cause first (**Diagnose the cause first**), then name the skill in chat, state the mistake, its evidence and its `Cause:` line in one line, undo the effect when the undo is local and reversible (else name it as not undoable in the same line), invoke `/ari-skill-update <skill>` with that line as the change, and go on with the work — same session, unasked. The edit starts unasked; the commit still waits for `yes`. Waiting to be asked is the failure this rule removes.
  - The fix is a rule where the behavior belongs and, when the skill has tests, a test that would have caught it.
  - A *background session* (a fork, a driver) does not invoke: the line rides its report (a driver's as a `Surfaced:` line, **Report the proposal**), and the main thread routes it — to the skill's live driver by `SendMessage`, else to a new one. Never two drivers on one skill.
  - A mistake with no skill that could carry the rule goes to Claude's auto-memory, or to a bead when the project has a tracker.
  ```
  BAD:  "Sorry, I shouldn't have done that." … (work continues)
  BAD:  "Want me to update the skill so this doesn't recur?"
  BAD:  (the main thread runs init.zsh or edits SKILL.md itself — no driver, no review, no proposal)
  GOOD: "ari-driving-remote: I typed into a pane another session was driving; the read came back as its output; not undoable: the keys were already sent.
         Cause: pending — skill text not read here; the driver classifies.
         /ari-skill-update ari-driving-remote"  → the driver starts; the work resumes
  GOOD (its driver already lives): SendMessage({to: "<driver>", message: "second line, same skill: <line>; fold it in and re-propose"})
  ```
- **Diagnose the cause first.** Before you answer Ari's "why did you…?" or "where did that come from?", and before any skill edit, write the `Cause:` line; an answer or edit written before it is a fault in its own right. Treat your recollection of why you acted as a hypothesis to test, never as evidence. A why-question runs the diagnosis and answers; it starts an update only when the finding is a mistake or a gap.
  ```
  Cause: <class> — quoted: "<text>" (<source>); inferred: <claim | none>; unknown: <what | none>
  ```
  - **Class**, the first that holds: `skill ignored` (the skill's text says the opposite of what you did), `other source` (CLAUDE.md, memory, user message, tool or hook output quotes it), `harness` (visible system-prompt text quotes it), `skill silent` (the skill covers the topic, not this case), `model default` (no source quotes it; list the sources you read, and only a source read this turn counts as `none`).
  - **Who.** The main thread diagnoses from text already in its context. It writes `other source` or `harness` only with a quote, and otherwise `Cause: pending — skill text not read here`; it never writes `skill ignored`, `skill silent` or `model default`. The driver reads the skill, checks the brief's `Cause:` against it, and its class wins: it writes `Cause (checked):` in the scratchpad and the proposal head, and names a changed class in the report. An undo may precede the `Cause:` line when delay worsens the effect. A request with no mistake writes `Cause: n/a — request`.
  - **Edit.** The class sets what the edit says, not whether to edit. When the skill is not the cause, write a counter-rule: `Counter-rule (cause: <class>): do not <default>; do <required>.`, so it is not read as the skill's design. When the source is CLAUDE.md or memory, add the Open question `fix at <source> instead? recommended: <answer>`. A public skill names the class and behavior only; the quote stays in the scratchpad and proposal.
  - **Harness.** Tell Ari in the answer, quoting the text. The driver writes `feedback.md` in the investigation folder from the brief's quote, and its path rides the report under Open questions; never send it. With no text visible, write `Cause: harness — unknown: no instruction visible`; never guess the harness.
  ```
  BAD:  "I handed it over so you could decide."          ← reconstruction, answered before looking
  BAD:  "Cause: model default."                           ← no sources listed
  GOOD: Cause: skill ignored — quoted: "NEVER Read, cat or paste proposal.md" (ari-skill-update Rules); inferred: I read it to summarize the diff; unknown: none
  GOOD: Cause: model default — quoted: none (read: the skill, CLAUDE.md, memory); inferred: none; unknown: system prompt (no instruction visible)
  ```
- **The main thread holds the report, never the proposal or the work behind it.** The main thread NEVER runs `init.zsh`, reads the target skill's files, edits, or reviews: it settles the skill and the change, spawns one driver, relays one report, asks **Commit?**. **NEVER Read, cat or paste `proposal.md`:** its only accesses are the `awk` prints of its Commit command at **Commit to dotfiles**, after `yes`, and of its Revert command, after `no`; Ari opens the file to see the diff. Nothing of the driver's run reaches the main thread but the report (**Report the proposal**). An edit request (`drop N`, a spec answer, a change) goes back to the same driver by `SendMessage` and returns as a new report.
- **Every agent runs on Opus.** No agent this skill starts — the driver, `/ari-skill-review`'s reviewers, the company-information reviewer — runs on any model but Opus: each Agent call passes `model: "opus"`, never omits it, never forks; a thread that cannot guarantee it does the step inline instead.
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
- **MUST confirm before committing, and only after review.** The `yes` that commits answers a diff Ari can open at the proposal path named in that same message. Only the main thread writes **Commit?**, never a driver, a fork or any subagent, and only once **Review** has settled both gates on the files as they stand: the company-information reviewer's latest pass returned `none`, or it was skipped on the personal laptop, or the skill is private (a drafted move to ldf included); and `/ari-skill-review` has run, or was skipped for a small change or for `skip review` (which skips the quality review only). The driver checks both gates and its summary names any unmet; a **Commit?** before they are met is a defect. Unqualified agreement ("yes", "do it", "lgtm"), or a scope the **Commit?** line offered ("yes, no adoptions"), commits; conditional agreement ("yes, but change X") is an edit request: make it and re-propose. Never commit what the named proposal file does not show: the commit lands the blobs the proposal recorded and nothing else, never through `git add <skill dir>` or `commit -- <path>`, which take the working tree as it stands at commit time (**Commit to dotfiles**).
- **One driver per skill: the claim.** init.zsh takes the skill's claim for your investigation folder; record_blobs.zsh renews it and, with commit_blobs.zsh, refuses while another live driver holds it. Only commit_blobs.zsh releases it. A claim is stale when its owner's folder is gone, or nothing in it (nor the claim itself) changed for two hours (7200 s, `SKILL_UPDATE_CLAIM_STALE_SECONDS`); init.zsh takes a stale claim itself. The claim also ends, with no commit, when Ari answers `no` or a driver reports `no change` or `stopped`: the main thread then puts `takeover` in the next brief's Flags for that skill, and the driver passes `--takeover`.
  - init.zsh refusing with `Another driver holds this skill` is not an error to retry or route around: the report's `Proposal:` line is `Proposal: none — skill claimed by <owner folder>` (the `owner=` value of the log line). The main thread then looks for a driver it spawned for that skill in this conversation that has not reported `committed`: found → `SendMessage` it the change (`second line, same skill: <change>; fold it in and re-propose`); not found → one line, `<skill> is claimed by <owner folder>, not a driver of this session; held`, and nothing spawned. `takeover` otherwise only on Ari's word that the holder is dead.
  - After `claim=taken-stale` or `taken-over` the old owner counts as stopped: if its folder shows in `concurrent=`, the Open question is `assumed: it stopped; its edits stay unless the Change reverts them`, not a hold. Otherwise `claim=` says no other live driver exists, so `concurrent=` and `foreign=` mean an older driver's leftovers or a by-hand edit (**Another session may be editing the skill**): the claim does not cover a session that edits or commits the skill's files by hand, and the commit guard keeps those edits out of a proposal.
- **Another session may be editing the skill.** Re-read each file right before you edit it, and never revert a change you did not make. Its signs: `concurrent=` not empty (init.zsh, record_blobs.zsh), a file changed since your last Read (the Edit tool refuses it, or a re-read differs), or record_blobs.zsh's `foreign=` naming a changed file you did not edit. Each becomes an Open question: `Concurrent edit: <files> (<folder> | unknown session)? assumed: hold Commit? until that session lands or stops, then re-propose.`
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
/tmp/skill-update/{skill-name}/.claim            # symlink to the owning driver's folder below
/tmp/skill-update/{skill-name}/{timestamp}/     # one per invocation
├── scratchpad.md
├── feedback.md          # harness cause only: product-feedback draft, never sent
├── <skill>.diff.patch   # the diff of the recorded blobs (record_blobs.zsh), one per skill proposed
├── <skill>.commit.md    # its Commit command, naming each blob (record_blobs.zsh)
└── proposal.md          # the proposal Ari opens; the only copy of the diff he sees
```

### scratchpad.md

The setup script pre-fills **Skill**; fill **Purpose** at "Read the skill", **Goal** at "Classify the change", **Changes made**, **Files edited**, **Own read** and **Open questions** at "Edit the skill"; review changes continue the numbering of **Changes made**, and every later edit (a review fix, `drop N`) adds its file to **Files edited**. A skill not yet in a tier adds `- **Tier picked**: <df|ldf> — <rule>` at "Set up the session". Drop a section if it's empty.

```markdown
- **Skill**: ari-diagram-mermaid — $HOME/.claude/skills/ari-diagram-mermaid/SKILL.md — Create, validate, and share Mermaid.js diagrams
- **Purpose**: Create, validate and share Mermaid diagrams in a fixed palette that stays legible on any canvas.
- **Goal**: Add a dark-canvas preview when the user says "dark" or "night" — implementation (the purpose already says "any canvas"; the flag is how)
- **Changes made**:
  - [1] FILE STORAGE — added a --dark flag to bake for the preview image
  - [2] SHARE — the Share step mentions dark previews
  - [3] EXAMPLES — a filled dark-canvas example (review: examples)
- **Files edited**: $HOME/.claude/skills/ari-diagram-mermaid/SKILL.md, bin/bake.zsh
- **Own read**: clean
- **Open questions**:
  - Should bake refuse a theme block that fails contrast only on the dark canvas? assumed: yes, the same gate on both canvases.
```

## File storage

- `bin/init.zsh` — run once at **Set up the session**, which holds its output contract.
- `bin/record_blobs.zsh` — run with `--execute` at **Report the proposal**: records each changed file's blob (skill files, and `--shared` tier lib files), writes their diff and the Commit command.
- `bin/commit_blobs.zsh` — the Commit command **Commit to dotfiles** runs, with `--execute` as record_blobs.zsh wrote it: commits exactly the recorded blobs, or refuses. Without `--execute` it checks and stages privately, and commits nothing.
- `lib/blobs.zsh` — shared by the three: the skill's repo, its entries against HEAD (skill files, and tier lib files as `@shared:<path>`), live sibling drivers.
- `lib/claim.zsh` — shared by the three: the per-skill claim, a symlink `<investigation root>/<skill>/.claim` to the owner's folder.
- `tests/claim.test.zsh` — the claim, shared lib files and a not-yet-linked dev-repo skill (`state=missing`), in throwaway HOMEs; run it after any edit to these scripts: `zsh $HOME/.claude/skills/ari-skill-update/tests/claim.test.zsh`.

## Workflow

### Driver by default

Decide once which thread you are, in this order, and name it in your first line of output (a driver's final message still begins `Skill:`):

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

Main thread. ONE fresh general-purpose subagent (Agent tool, `subagent_type: general-purpose`, `model: "opus"`, `description: skill-update <skill>`) with this prompt; it has no conversation, so the brief carries everything:

````
You are the driver for /ari-skill-update on `<skill>`. Read $HOME/.claude/skills/ari-skill-update/SKILL.md, then run it from **Set up the session** through **Report the proposal**: write the complete proposal, full diff included, to the `proposal=` path init.zsh prints. Your final message is the report only: the `Skill:`, `Proposal:` and `Proposal summary:` lines of **Report the proposal**, plus one `Surfaced:` line per surfaced skill, and no diff, hunk or file contents. Hard limits: ask nothing; the Agent tool is for /ari-skill-review's reviewers and the company-information reviewer only, NEVER another driver; NEVER edit, invoke /ari-skill-update on, or spawn anything for a second skill — list it under Surfaced skills; NEVER run adopt or commit.
Model rule: every Agent call you make, reviewers included, MUST pass `model: "opus"`; never omit it, never fork.
Skill: <skill>. Change: <the settled change in one sentence>.
Origin: <mistake | request>.
Evidence: "<Ari's words, or the mistake line, quoted>" — <the gap: what was done instead, or what the skill should have done>.
Cause: <the line from **Diagnose the cause first**; the driver checks it against the skill>.
Flags: <skip review | new | takeover | none, comma-separated>.
Settled: <what the conversation decided the text must say, or none>.
````

Then one line, no question — `driver <name> spawned for <skill>: <change>; back to <work>`, where `<name>` is the name or agent ID the Agent tool returned (what `SendMessage` takes) — and back to the main work. Never ask whether to wait; the report arrives as a notification. The Evidence, Cause and Settled lines for the **A mistake is a skill update** GOOD case:

```
Evidence: "ari-driving-remote: I typed into a pane another session was driving; the read came back as its output." — the send gate checks idle-at-prompt and the mark, not which session set the mark.
Cause: pending — quoted: none (read: this session's context only); inferred: the gate checks idle and the mark, not who set it; unknown: skill text not read here
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
state=linked        # linked / missing / unlinked / ignored go on; any other state stops (below)
tier=df             # - when no tier holds it
source=             # submodule:<path> when a submodule's skills/ holds it (commit there)
skill_dir=$HOME/.claude/skills/<name>   # state=missing: the skill's own real directory
link_after=         # state=missing only: the step that links it after the commit, Ari's to run
investigation_dir=/tmp/skill-update/<name>/<timestamp>
scratchpad=/tmp/skill-update/<name>/<timestamp>/scratchpad.md
proposal=/tmp/skill-update/<name>/<timestamp>/proposal.md
claim=taken         # taken / renewed / taken-stale / taken-over: this folder owns the skill
concurrent=         # this skill's other live investigation folders, comma-separated (**Another session may be editing the skill**)
=== start FILES ===
<one absolute path per line>
=== end FILES ===
```

Add `--new` only when Flags says `new` (`inline`: the user said the skill is brand-new), and `--takeover` only when Flags says `takeover`. Then act on `state`:

- `linked` → go on.
- `missing` (held by a tier or dev repo, not linked yet) → go on, **working only under `skill_dir=`**: read, Edit and Write there, never under `$HOME/.claude/skills/<skill>`, where a Write would make a real directory that shadows the held one. **NEVER link it** (`link`, `dotfiles switch`): `link_after=` is Ari's step after the commit, and the proposal names it (**Report the proposal**). Its last commit predates this session (`git log -1` on `skill_dir=`) → Open question `<skill> is held but not linked here — intended? assumed: yes, edit in place`.
- `unlinked`, `ignored` or `is_new=true` → pick its tier now (`/ari-dotfiles` Placement rules), record `**Tier picked**` in the scratchpad (an Open question when the rule does not decide); **Commit to dotfiles** adopts it. A brand-new skill meant for a dev repo is created under `<dev repo>/skills/<name>/` first (`/ari-dotfile--submodule`) and run without `--new`: it reads as `missing`.
- `dangling`, `shadowed`, `conflict`, `foreign` → stop: the registry's fix comes first (`/ari-dotfiles-skill-registry` § See where things stand), as the first Open question.

On a non-zero exit, do not edit; no folder exists, so the report's `Proposal:` line is `Proposal: none — init.zsh failed: <stderr's last line>` (a claim refusal is the exception below), and:

- no such skill → stop; the name is wrong, or the skill is brand-new and the user has not said so.
- `--new` but the skill exists → re-run without it.
- `Another driver holds this skill` → stop; the report is `Proposal: none — skill claimed by <owner folder>` (**One driver per skill: the claim**).
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
2. **Update implementation** — **before the first edit of each file, check no other session changed it**: `git df status --short -- <file>` (`tier=df`, no source), `git ldf status --short -- <file>` (`tier=ldf`), or `git -C $HOME/<path> status --short -- <file>` (`source=submodule:<path>`); any output → leave the file, Open question `Concurrent edit: <file>…` (**Another session may be editing the skill**). Place each change per **Skill anatomy**. Before adding a step, `ls $HOME/.claude/skills/` and delegate to a skill that already does it (**Reuse**).
3. **Audit and syntax-check** — apply the `$HOME` rule to every invocation, pre-existing ones included; for every edited script, `zsh -n <script>.zsh` then `zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/conventions.test.zsh` (Python: `/ari-skill-pythonscripts` § Validation).
4. **Own read for company information** — when the skill is public (see Rules), read every file in the directory, and every tier lib file you will pass as `--shared`, against the identifying-content list and fix what you find per the Rules. Record `own read: clean`, `own read: <n> fixed`, or `own read: n/a (private)`, never `none`: that word is the reviewer's verdict. **Review › Company information** dispatches even when the own read is clean, except on the personal laptop, where the own read is the only check.
5. **Update scratchpad** — `[n] SECTION — change` per change, each file you edited under **Files edited** (the path you gave Edit or Write; each becomes one `--edited` at **Report the proposal**, or one `--shared` when it is a tier lib file), the own-read line, each open question as `assumed: <answer>`.

### Review

Driver, or the `inline` thread, right after **Edit the skill**, on the files as they stand. The main thread never runs this step.

1. **Quality** — scaled to the change. A substantial change (a script edited, a new step or section, an intent change, or 40 or more changed lines, counted over your edits' added and removed lines) gets `/ari-skill-review` via the Skill tool with the skill name as the argument. A short prose-only edit skips it: pre-check `skipped (small change)`. `skip review` skips it whatever the size: `skipped (skip review)`. A driver is a subagent, so the ranked findings come back in the review's own output (`findings: inline`) and `findings.md` stays empty; only the `inline` thread gets the file. Its `spec-questions.md` is in the review folder either way. Apply every finding, continuing the scratchpad's numbering (`[3] EXAMPLES — a filled dark-canvas example (review: examples)`); one that conflicts with a Rule, or that you challenged away, is not applied and goes under the proposal's Not carried as `<recommendation> — <rule name | reason>`. Spec questions are not applied; they ride the proposal as `<question>? recommended: <answer>`. An empty `findings.md` is not a failed review; the review failed only when its output holds no ranked list either, and then the pre-check says `failed: <why>`.
2. **Company information** — when the skill is public (see Rules), dispatch a fresh reviewer with the Agent tool, `model: "opus"`, and this brief, unless `dotfiles machine-name` prints `ozone` (the machine check `/ari-dotfiles` § Review before push uses): then dispatch nothing, pre-check `skipped (not the employer laptop)`. Three holes: `<skill_dir>`, `<shared_files>` (the absolute `--shared` paths, or `none`), and the quote, pasted byte-for-byte from your Read of this file's Rules (never retyped):

   ````
   Read EVERY file under <skill_dir> (SKILL.md, bin/, lib/, templates, fixtures, tests), not just a diff, and also <shared_files> (tier lib files committed with the skill; none when empty). Flag anything that identifies Ari's employer; this is the test, quoted from the skill's Rules, including its last sentence of what is not identifying:
   "<the two Rules sentences, from 'Identifying content includes' through 'his homelab.', verbatim>"
   Report each finding as `<file>:<line> — <what identifies the employer> — <neutral rewrite | move to ldf>`. Return exactly `none` when clean. Edit nothing.
   ````

   Apply each fix per the Rules, then dispatch a new reviewer; repeat until it returns exactly `none`. A reply that is neither `none` nor findings is a failed dispatch. A whole-skill move to the local tier is drafted, never run before `yes`, and ends the loop with the pre-check `private (pending: <move command>)`, the move command first under Commit command in its own fenced `zsh` block (**Commit to dotfiles** runs fenced blocks only); a cutpoint move is applied before the next dispatch. Stop after two failed dispatches (`failed: <why>`) or three passes with findings (`failed: N findings remain`, each under Open questions with its recommended fix).

### Find unadopted skills

Driver, or the `inline` thread; a re-proposal runs it again.

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status
```

For each `unlinked` row other than the target skill, pick its tier (`/ari-dotfiles` Placement rules) and record its blobs with `--adopt` (**Report the proposal**). An adoption into df enters the proposal only after its own **Review › Company information** pass returned `none` or was skipped on the personal laptop; otherwise it is listed as `<skill> — not proposed: <n> findings`, no command. An `ignored` skill is third-party: list it; commit it only when the user names it. `status` fails → Adoptions is `failed: <stderr's last line>`; go on.

### Report the proposal

Driver, or the `inline` thread. Write the proposal to the `proposal=` path, then send the report as your final message. Every driver exit has both, a stop included: the proposal's title is then `## Proposal: <skill> — stopped at <step>` or `— no change`, Diff `none — <why>`, Commit command `none`, and the stop reason is the first Open question with a recommended answer (a stop inside `init.zsh` has no file: **Set up the session**). Neither asks Ari anything — questions carry `assumed:` or `recommended:` answers — or holds anything of the run but what **Commit?** needs: no reviewer reports, no scratchpad contents, no intermediate diffs. A re-proposal overwrites the file, whose first line, above `## Proposal:`, is `Since last: <what changed>`; the summary then reads `Proposal summary: Since last: <what changed>. <its 1–2 sentences>`.

**Record the blobs; NEVER print or Read the diff.** Once per skill the proposal commits (the target, then each adoption), after the last edit. Without `--execute` the script is a dry run that writes nothing, so every call carries it; this one runs unattended, with no `yes`:

```zsh
zsh $HOME/.claude/skills/ari-skill-update/bin/record_blobs.zsh --skill <skill-name> --tier <tier> --investigation-dir <investigation_dir> --message "<skill-name>: <what changed and why>" --edited <file> --edited <file> [--shared <lib file>] --execute
```

- **Flags.** `--tier` and `--source <source>` as init.zsh printed them. A skill no tier holds yet takes `--adopt`, the tier picked, and the message `claude: adopt the <skill-name> skill into the <shared | local> tier`. A public tier's message says what changed, never what leaked.
  - **`--edited`**: one per **Files edited** entry, relative to the skill directory (`SKILL.md`, `bin/init.zsh`; right in every state), or absolute under `skill_dir=` or `$HOME/.claude/skills/<skill-name>/`; an adoption passes none.
  - **`--shared <tier lib file>`**: one per edited file under `$HOME/.config/claude/lib` (the *tier lib*, df only; not this skill's own `lib/`), absolute or relative to `$HOME`. NEVER a directory, a sweep of the tier lib, a file elsewhere outside the skill directory, a local-tier skill or a submodule skill: those exit 1. The file is recorded and committed in the same Commit command as the skill, and refused like a skill file when the working tree stops yielding its blob or HEAD moved it since recording. Any other outside file stays uncommitted: Open question `<path> is outside the committed set; Ari commits it. assumed: left uncommitted`.
- **What it writes.** With `--execute`, each changed file's blob to the tier's object store, then `<skill>.diff.patch` (the diff of exactly those blobs, untracked files included) and `<skill>.commit.md` (the Commit command that lands them, blob by blob; `none — empty diff` when nothing changed). The Commit command ends in `--execute`: it runs only after `yes`.
- **What it prints.** Those paths; `files=`, `insertions=` and `deletions=` (the proposal's Diff counts); `unmatched_edited=`, an `--edited` or `--shared` file with no change against HEAD (a reverted edit: drop it from **Files edited**; else fix the path and re-run); `foreign=` and `concurrent=` (**Another session may be editing the skill**); `dry_run=1|0` (a `1` means nothing was written: add `--execute`; if it was already there, an inherited `DRY_RUN` forced it, so unset that and re-run).
- **Exit 1.** A log naming `moved_files=` means a file changed while it recorded: re-run once; a second failure stops the run with that as the first Open question. A log naming `Another driver holds this skill` stops the run with `Proposal: none — skill claimed by <owner folder>`, never `--takeover`. A log naming `The repo has no commits yet` stops the run with its hint as the first Open question. Any other exit 1 names the flag at fault (an `--edited` that is not a file in the skill directory, a `--tier`/`--source` that does not hold the skill): fix it and re-run; it is never an Open question. When `--tier`/`--source` already match init.zsh's output, re-run the registry's `status`: a state other than `linked` or `missing` stops the run with that state as the first Open question.
- **Assemble.** Only after the print shows `dry_run=0`; a dry run leaves the previous run's diff and command files in place. Write each prose part to its own file in the investigation folder and join them in document order with one `cat`, e.g. `cat head.md <skill>.diff.patch mid.md <skill>.commit.md adopt-<other>.md <other>.commit.md tail.md > <proposal>`. **The file's diff MUST be complete: every hunk, every file, no `…`, no `(N lines omitted)`;** an elided diff is not a proposal.

The proposal, in the file:

`````markdown
## Proposal: <skill-name>
Tier: <df (public) | ldf (private) | submodule:<path> (public) | unlinked → <df|ldf>><; not linked: `<link_after>` after the commit, Ari's — state=missing only>
Pre-check: own read <clean | n fixed | n/a (private)>; company-information reviewer: <none | skipped (not the employer laptop) | private | private (pending: <move command>) | failed: <why>>; quality review: <run: N findings, N applied, N not carried | skipped (small change) | skipped (skip review) | failed: <why>>.
Investigation: <scratchpad path>; review folder: <path, findings: <inline | findings.md path> | skipped>.
Diff: <complete — <n> files, +<a> −<b> | none — <why>>
### Diff
~~~~diff
<<skill>.diff.patch>
~~~~
### Changes (numbered; `drop N` reverts one)
1. SECTION — change
Not carried: <recommendation> — <rule name | reason>; …
### Spec questions
<each as `<question>? recommended: <answer>`; or none>
### Open questions
<each as `<question> assumed: <answer>`; or none>
### Commit command
<<skill>.commit.md as written, its fenced zsh block; or none — <why>>
### Adoptions
<skill> → <tier> — reviewer: <none | skipped (not the employer laptop) | private> — files: <list> — <reason>
<its <skill>.commit.md as written>
### Surfaced skills
<one mistake line each, as in **A mistake is a skill update**; or none>
### Revert command
<one fenced zsh block, shown on `no`, never run: `checkout --` the tracked files through the repo that holds them (df `git df checkout -- <path>`, ldf `git ldf checkout -- <path>`, dev repo `git -C $HOME/<path> checkout -- skills/<skill-name>`), then `rm` each untracked file the diff adds>
`````

The report, the final message — three lines, then one `Surfaced:` line per **Surfaced skills** entry (none when there are none), and nothing else:

````markdown
Skill: <skill-name>
Proposal: <proposal path | none — <why>>
Proposal summary: <1–2 plain sentences: what the change does for Ari (or stopped at <step>: <why> | no change: <why>), then whatever blocks Commit? or needs his answer>
Surfaced: <skill> — <its mistake line>
````

The driver checks the commit gate: before the summary, hold the proposal to **MUST confirm before committing** (Pre-check met; Diff `complete`, written so only when `grep -c '^diff --git ' <proposal>` equals the target's record_blobs.zsh `files=` (the `### Diff` section holds the target's patch only); no `Concurrent edit:` Open question assuming a hold). The summary's second sentence names each unmet gate (`Blocked: the company-information reviewer failed twice.`, `Held: concurrent edit on bin/x.zsh.`), any question whose answer would change the edit, each ready adoption by name and tier (`Adoptions ready: ari-foo → df, ari-bar → ldf.`), and, for `state=missing`, the link step (`Not linked until: dotfiles switch.`); with none of these it is one sentence.

```
BAD:  ## Proposal: ari-driving-remote / ### Diff / diff --git …   ← the proposal belongs in the file, not the report
BAD:  Tier: df (public) / Pre-check: … / Diff: complete — 2 files, +14 −3 / …   ← implementation details; they live in the file
BAD:  … / Ready to commit?                                          ← Commit? is the main thread's word
GOOD: Skill: ari-driving-remote
      Proposal: /tmp/skill-update/ari-driving-remote/20261104T231402Z/proposal.md
      Proposal summary: Claude no longer types into a pane another session is driving: the send gate refuses a pane whose mark that session set.
GOOD (a gate unmet): Skill: ari-driving-remote
      Proposal: /tmp/skill-update/ari-driving-remote/20261104T231402Z/proposal.md
      Proposal summary: Claude no longer types into a pane another session is driving. Blocked: the company-information reviewer failed twice; the proposal lists the fix per finding.
```

### Relay and commit

Main thread; the `inline` thread on its own report (the report is the relay: show it once); origin on a sent one. In the next message you send:

1. **Gate the report.** Its lines are `Skill: <skill>`, `Proposal: ` and then a path ending `/proposal.md` or `none —`, `Proposal summary: …`, then only `Surfaced: …` lines; no `diff --git`, `@@` or `###`. **Not a report → NEVER relay any of it:** one status line, and send the driver `report only, per Report the proposal`.
2. **Relay it.** `driver <name> reported:`, then the three lines as sent — never the file's contents, no read of the file, no added findings. Route each `Surfaced:` line per **A mistake is a skill update**.
3. **End with Commit?** when the summary names no `Blocked:` or `Held:` (the driver checked the gate). State its scope: `Commit? (yes = <skill> + <each adoption → tier>; yes, no adoptions = <skill> only)` when the summary names adoptions ready, else `Commit? (yes = <skill>)`. A `Held:` summary ends with `Held: <its reason>; re-propose once that session lands or stops` instead. A no-change or stopped report is relayed with no retry, and asks `Commit? (yes = <each adoption → tier>)` only when adoptions are ready. If the message already ends in a question, the one question names both consequences. `yes` still commits only what the file's Commit command holds (**Commit to dotfiles**).
4. **Otherwise** (`Blocked:`) relay without the question and send the driver one line to retry (`full diff`, `retry reviewer`); if that retry also fails, ask Ari to pick, with a recommendation (`skip review` covers a quality gap only; a reviewer gap: the fix per finding, or the move to ldf).

```
BAD:  "Driver done: added the owner check to ari-driving-remote, both reviews clean. Commit?"   ← no path; `yes` answers a diff Ari cannot open
BAD:  driver skill-update-ari-driving-remote reported: ## Proposal: … ### Diff … (844 lines)   ← the file pasted into the conversation
GOOD: driver skill-update-ari-driving-remote reported:
      Skill: ari-driving-remote
      Proposal: /tmp/skill-update/ari-driving-remote/20261104T231402Z/proposal.md
      Proposal summary: Claude no longer types into a pane another session is driving.
      Commit? (yes = ari-driving-remote)
GOOD (adoptions, a re-proposal, a surfaced skill): driver skill-update-ari-driving-remote reported:
      Skill: ari-driving-remote
      Proposal: /tmp/skill-update/ari-driving-remote/20261104T231402Z/proposal.md
      Proposal summary: Since last: dropped change 2. Claude no longer types into a pane another session is driving. Adoptions ready: ari-foo → df.
      driver skill-update-ari-driving-tmux spawned for ari-driving-tmux: <its Surfaced: line>; back to <work>
      Commit? (yes = ari-driving-remote + ari-foo → df; yes, no adoptions = ari-driving-remote only)
GOOD (held): driver skill-update-ari-driving-remote reported:
      <the three lines as sent, the summary ending "Held: concurrent edit on bin/send.zsh.">
      Held: concurrent edit on bin/send.zsh; re-propose once that session lands or stops
GOOD (a gate unmet): driver skill-update-ari-driving-remote reported:
      <the three lines as sent, the summary ending "Blocked: the company-information reviewer failed twice.">
      Sent the driver: retry reviewer.
```

- `yes` → **Commit to dotfiles**.
- "show me the diff" → the path again and `$EDITOR <path>`; quote only a hunk Ari names, never the file.
- `no` → one line, the edits sit uncommitted; then the revert, shown, not run, printed with `awk '/^### Revert command$/{p=1} p' <proposal path>` (the driver wrote it for the skill's repo, a dev repo's real directory included).
- `drop N`, a spec answer, an edit, or `re-propose` after a refusal → `SendMessage({to: "<driver>", message: "drop 2"})`; the driver edits (for `re-propose`, nothing: its `Since last` names what changed under it), re-runs **Review › Company information** on the files as they stand, then **Find unadopted skills** and **Report the proposal** in full (record_blobs.zsh for every skill, a fresh assembly), and returns a new report; relay and ask again. NEVER a fresh driver for this. Only when `SendMessage` fails, or the result fails the gate twice: relay its last line and respawn ONE driver with the original brief plus `Resume: the files are already edited; investigation = <the directory of the last reported Proposal: path>; apply "<Ari's answer>"; start at Review`.
- A message that does not address the proposal → handle it, keep **Commit?** pending, re-ask it in full at the end of the next message.

A git failure's diagnosis is the main thread's; a fix that touches skill files goes to the driver as an edit request.

### Commit to dotfiles

Main thread, on `yes`. Print the commands with `awk '/^### Commit command$/{p=1} /^### Surfaced skills$/{p=0} p' <proposal path>` (for `yes, no adoptions`: `awk '/^### Commit command$/{p=1} /^### Adoptions$/{p=0} p' <proposal path>`), and run each fenced block it prints, in order, and nothing else. It prints nothing, or the file is missing → no commit; send the driver `re-propose`. Commit command `none — …` → nothing to commit; skip.

Each block is the `commit_blobs.zsh --execute` call record_blobs.zsh wrote, naming every file's blob (never drop `--execute`: without it the call is a dry run and prints `result=dry-run`, a commit that did not happen); a `--source` one commits in that dev repo, which must be on its `main` (`/ari-dotfile--submodule`), and an `--adopt` one runs the registry's `adopt` once its check passes. The gate is *staged content == proposed content*:

- HEAD changed the skill (or a `--shared` file) since the proposal, or the working tree no longer yields the proposed blobs (another session or Ari edited a skill file or a shared one) → it commits nothing and prints `result=refused` and `mismatched=<files>` (a tier lib file shows as `@shared:<path>`, repo-root-relative, when the tree changed, or `HEAD:<path>` when HEAD's blob at that path moved). Stop there: name the files, send the driver `re-propose`, and NEVER commit another way (`git add`, `commit -- <path>`, a hand-edited command). A refusal is never a warning to commit past.
- Otherwise it stages exactly those blobs in a private index (the shared index, and whatever another session staged in it, stay out of the commit), commits it with the tier's hooks, points the shared index at the committed blobs, and prints `result=committed` (`already-committed` on a re-run) and `sha=`.
- `result=refused` with `claim_holder=<folder>` → another live driver took the skill after the proposal: it commits nothing. Relay the line, send the driver `re-propose` (**Relay and commit**), and never rerun with `env -u DRY_RUN`.
- `result=refused` with `branch=<name | detached | unborn>` → the dev repo is off `main`, or the repo has no commit: it commits nothing. Name it; Ari puts the repo on `main` (`/ari-dotfile--submodule`), then send the driver `re-propose`.
- `result=committed-differs` with `sha=` → **a commit landed that the proposal did not show.** Stop running blocks; say so with its `sha=` and the logged `mismatched=`, and end with one question: undo (`git <df | ldf | -C $HOME/<path>> reset --soft <sha>~1`, shown, not run; recommended) or keep it. Then send the driver `re-propose`.
- Any other `result=`, `dry-run` included (an inherited `DRY_RUN` beats `--execute`), means nothing was committed: say so in one line, never report a commit without `sha=`, and offer the rerun with `env -u DRY_RUN` for the same block.

Then the SHA per commit, and for a public tier "push is yours (`/ari-dotfiles`)"; for a dev repo (`source=submodule:…`), Ari's `dotfiles push` pushes the dev repo, then commits the flake.lock bump (`/ari-dotfiles` § Dev repos). When the summary said `Not linked until: <step>.`, repeat it: the skill loads only after that step, which is Ari's. Pushing follows `/ari-dotfiles`'s Pushing rules; this skill never pushes. On any other failure, stop at that commit and say which landed (their SHAs); show the error, diagnose it, and propose the fix with the command that retries; never retry before a `yes`. The edits stay local whatever the answer.

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
