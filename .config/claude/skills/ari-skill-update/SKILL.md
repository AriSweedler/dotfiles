---
name: ari-skill-update
description: Edit a skill, review it, and propose one ready-to-land commit to the dotfiles tier that owns it (adopting it, and any other unadopted skill, first if needed); one 'yes' commits. A fresh-eyes reviewer blocks any commit that would put company-identifying content in a public skill. Owns the skill-building rule that a question authorizes a consequence, never the start of work. Runs as a background fork by default.
---

# Skill Update

Edit a skill, review it, and end with one proposal that a single `yes` commits to the dotfiles tier that owns it, adopting it first if it is not yet versioned. Before any commit to a public tier, a separate reviewer reads the whole skill for anything that identifies Ari's employer; such content belongs only in a private skill. Runs in a fork by default so the main thread stays on the real work (see the first workflow step). Quality review is delegated to `/ari-skill-review`; script conventions to `/ari-skill-shellscripts` and `/ari-skill-pythonscripts`.

## Rules

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
- **Ask only to authorize a consequence.** A skill asks the user two kinds of question: for something only the user knows (which skill, which of two histories to keep), or for a `yes` to a consequence (a commit, push, send, delete, anything outward-facing or hard to undo). Never for permission to start the agent's own read-only or reversible work: editing an uncommitted file, running a reviewer, diagnosing a failure and drafting a commit plan are done, then shown. Every question arrives ready: its evidence gathered, an answer recommended, and every pending consequence folded into the one question that ends the message. A delineated optional tail step (a sweep, a cleanup, adopting stragglers) starts as soon as its inputs exist, in parallel with the main work, through a subagent when it is slow or wide (inline when already a fork), and runs to a ready-to-land proposal, so one `yes` lands it; that `yes` covers only what the proposal explains, and anything prep cannot explain is listed and left out. A question whose `yes` only starts work is a defect: on every edit, rewrite each one the target skill holds.
  ```
  BAD:  "Want me to check for other pending changes?"  → yes → look → "Commit these?"
  GOOD: (a subagent already looked) "Also pending, ready to commit:
          ldf: share/bin/foo → "Add foo" — wrapper behind the new oneshot entry
        Commit it?"
  ```
- **MUST confirm before committing.** The `yes` that commits answers a diff shown in that same message. Unqualified agreement ("yes", "do it", "lgtm") commits; conditional agreement ("yes, but change X") is an edit request: make it and re-propose. Never commit what the user has not seen.
- **Audit every documented invocation for the `$HOME` form.** On every edit — including prose-only edits — scan the skill for any line that runs a skill script. Each MUST use `$HOME` (never `~`), have no leading `cd`, and not be piped (redirect to a file if you need the output). Fix every non-conforming invocation you find, even ones unrelated to the requested change.
  ```
  BAD:  zsh ~/.claude/skills/foo/bin/x.zsh --id 123                  # ~ instead of $HOME
  BAD:  cd ~/.claude/skills/foo && zsh bin/x.zsh --id 123            # leading cd + relative path
  BAD:  zsh $HOME/.claude/skills/foo/bin/x.zsh --id 123 | head       # piped — truncates output
  BAD:  cd /repo; zsh ~/.claude/skills/foo/bin/x.zsh --id 123 2>&1 | tail -40   # all of the above
  GOOD: zsh $HOME/.claude/skills/foo/bin/x.zsh --id 123
  ```
- **NEVER scaffold around a self-contained script.** Skill scripts do their own setup. When a step says to run one, emit exactly that one Bash call — no `mkdir`, `ls`, `echo`, `cd`, or timestamp before or after it. Need its output? Read what it prints; don't re-derive it.
- **Anything that identifies the employer belongs only in a private skill.** A skill in the shared tier (`tier=df`) or in a submodule with a public upstream (`source=submodule:…`; every submodule today) is public; the local tier (`tier=ldf`) is private — `/ari-dotfiles` Placement rules own that split. Identifying content includes the company's name, brand or email domain; internal repo, service, tool, CLI, pipeline, table, team or channel names; hostnames, IPs, cloud account or project IDs, ARNs and secret paths; internal file paths and PR titles; ticket systems and ticket IDs; coworkers' names; office details; and names of private skills. Never write the employer's name into a public skill, not even to forbid it. Fix each instance one of two ways: make it neutral (a placeholder such as `acme/shop`, `example.com`, `ip-10-0-12-34`, or a generic tool kind), or move it to the local tier — the whole skill (`adopt --tier ldf`), or just the company part, in a local file the public skill reads when it exists (a cutpoint, per `/ari-dotfiles` § Cutpoints).
- **Scripts MUST follow the conventions skill for their language.** zsh → `/ari-skill-shellscripts`, Python → `/ari-skill-pythonscripts`. Read it first, then bring the whole script — not just the lines you changed — into compliance. For another language, use that language's conventions skill; if none exists, build one (mirroring these) first.

## Investigation folder

```
/tmp/skill-update/{skill-name}/{timestamp}/
├── scratchpad.md
```

Each invocation creates a fresh timestamped folder, so sessions never clash.

### scratchpad.md

The setup script pre-fills the **Skill** line; fill **Goal** during "Read the skill", and **Changes made** / **Open questions** during "Edit the skill". Drop a section if it's empty.

```markdown
- **Skill**: ari-diagram-mermaid — $HOME/.claude/skills/ari-diagram-mermaid/SKILL.md — Create, validate, and share Mermaid.js diagrams
- **Goal**: Add a dark-canvas preview when the user says "dark" or "night"
- **Changes made**:
  - Added a --dark flag to bake for the preview image
  - Updated the Share step to mention dark previews
- **Open questions**:
  - Should bake refuse a theme block that fails contrast only on the dark canvas?
```

## File storage

- `bin/init.zsh` — session-setup script run once at "Set up the session": confirms the skill exists, reports its dotfiles tier state, creates the investigation folder + pre-filled scratchpad, and prints the skill's files to read. See that step for its output contract.

## Workflow

### Fork by default

If this skill was invoked in a main working thread (you are not already a fork), spawn a fork carrying the full skill-update directive and return to the main work — do NOT run the rest of this workflow inline. Skip the fork ONLY when the user explicitly asked not to fork. Forks nest: when an update surfaces a meta-skill that also needs updating, fork again from the fork. Everything below executes inside the fork.

### Identify the skill

- If the user gave an exact skill directory name under `$HOME/.claude/skills/`, use it.
- If the user gave a partial name or description, take the one match the conversation points at and say which; list matches as `name — purpose` rows, likeliest first, and ask only when none stands out.
- If no name was given, take the skill the conversation was just using (Step 1 of **Understand the change**); ask with a recommended pick only when there is none.
- If nothing matches, say so and stop.

### Set up the session

Once the skill is identified, run the setup script. This is the whole setup — **emit exactly this one Bash call, nothing around it**:

```zsh
zsh $HOME/.claude/skills/ari-skill-update/bin/init.zsh --skill <skill-name>
```

It confirms the skill exists, reports where it stands in the dotfiles tiers (`state`/`tier` per `/ari-dotfiles-skill-registry`), creates the investigation folder with a pre-filled scratchpad, and prints what to read:

```
skill=<name>
is_new=false
state=linked        # or unlinked / ignored: not yet adopted into a tier
tier=df             # - when no tier holds it
source=             # submodule:<path> when a submodule's skills/ holds it (commit there)
skill_dir=$HOME/.claude/skills/<name>
investigation_dir=/tmp/skill-update/<name>/<timestamp>
scratchpad=/tmp/skill-update/<name>/<timestamp>/scratchpad.md
=== start FILES ===
<one absolute path per line>
=== end FILES ===
```

Run it WITHOUT `--new` first. Add `--new` only when the user says the skill is brand-new, or re-run with it if the script reports no such skill. If `state` is not `linked`, tell the user the skill is not yet versioned in the dotfiles; the **Commit to dotfiles** step adopts it.

Handle a non-zero exit by its cause, then do NOT continue to editing:

- no such skill → confirm the name with the user; `--new` only if it is brand-new.
- `--new` but the skill exists → drop `--new` and re-run.
- any other non-zero exit → show the script's stderr verbatim and stop.

### Read the skill

Read every file listed between the setup script's `=== start FILES ===` / `=== end FILES ===` markers (use the Read tool). If `FILES` is empty on a non-`--new` run, stop — the pull found nothing. If no `SKILL.md` exists, warn the user and ask whether to create one (use **Skill anatomy** as the template) or abort.

Show the skill's intent:

```
**Purpose:** <one synthesized sentence from the # heading + opening paragraph>
```

### Understand the change

**Step 1: Check conversation history.** Before asking anything, search the current conversation for prior invocations of the target skill. If the user ran it and then corrected, overrode, or worked around its output:
1. Identify what the skill did wrong or failed to do.
2. Identify what the user did instead.
3. Tell the user: "Earlier you used `/X` and had to manually do Y. The skill should have done Y itself."
4. Proceed to step 2 with this inferred change.

If no prior invocation exists, ask the user to describe the change.

**Step 2: Classify the change.** Every skill has two layers — **Intent** (the `#` heading + opening paragraph, i.e. the Purpose; what and why) and **Implementation** (workflow steps, rules, scripts, schemas; how). Determine which the change affects:
- **Intent change:** the skill will do something new or stop doing something. Rewrite the heading + opening paragraph, and update the `description:` frontmatter field.
- **Implementation change:** purpose unchanged; a step, rule, or script changes.
- **Both:** the skill gains new behavior that also needs new or changed steps. Rewrite intent first, then implementation.
- **When ambiguous:** default to intent change — updating the description unnecessarily is cheaper than leaving it stale.

State it, e.g.:
> "Currently the skill does X. You're asking it to also do Y — an intent change. I'll update the heading + description, then the implementation."

**Step 3: State it.** Repeat the planned change in one sentence. If the behavior already exists in the skill, say so and stop — don't make an empty edit. Otherwise go straight to editing: the user approves the commit, not the edit (see Rules).

### Edit the skill

1. **If intent changed** — rewrite the `#` heading and opening paragraph from scratch, as if written fresh for the new purpose.
2. **Update implementation** — read the full skill first, then place each change per **Skill anatomy** below. Before adding a new step, run `ls $HOME/.claude/skills/` and delegate to any skill that already does it — never reimplement.
3. **Audit and syntax-check** — before showing the diff, scan the edited skill for script invocations and confirm each matches the `$HOME` form (see Rules), fixing any that don't (including pre-existing ones). Syntax-check any edited script (`zsh -n <script>.zsh`; `python3 -m py_compile <script>.py`).
4. **Review for company information** — when the skill is public (see Rules), dispatch a fresh reviewer with the Agent tool: you wrote the text and will read past your own examples. Give it the skill directory, the identifying-content list from Rules, and these instructions: read EVERY file in the directory (SKILL.md, `bin/`, `lib/`, templates, fixtures, tests), not just the diff; report each finding as `<file>:<line> — <what identifies the employer> — <neutral rewrite | move to ldf>`; return `none` when clean; edit nothing. Apply each fix per the Rules, then dispatch a new reviewer and repeat until it returns `none`. Report the findings and fixes with the diff. Skip this step for `tier=ldf`.
5. **Update scratchpad** — record what changed and why, including the reviewer's findings.

### Review

Invoke `/ari-skill-review` via the Skill tool with the skill name as the argument, unless the user said to skip it. Apply every change it recommends, number each in the scratchpad (`[1] EXAMPLES — added a filled scratchpad entry`), then re-run step 4 on the result. If the review fails or returns nothing, say so in the proposal.

### Find unadopted skills

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status
```

For each `unlinked` row, pick its tier with `/ari-dotfiles` Placement rules and draft its `adopt` command (see **Commit to dotfiles**), one commit each. An `ignored` skill is third-party: list it, but leave it out of the commits unless the user names it.

### Propose the commit

End with one message: the full diff, the numbered review changes, the company-information reviewer's verdict, the commit command, the drafted adoptions with a one-line reason each, and one question: **Commit?** `yes` commits everything shown; `drop 2` reverts that review change and re-proposes; anything else is an edit request.

### Commit to dotfiles

Commit only on a `yes` to the proposal; if anything changed since it, re-propose instead. If the diff is empty, there is nothing to commit; skip. NEVER commit a public skill (`tier=df`, `source=submodule:…`, or an adoption into df) until the company-information reviewer's latest pass on the files as they stand now returned `none`; changes made since that pass, including review fixes, need a new pass. Commit messages in a public tier follow the same rule: say what changed, never what leaked.

Skills are versioned in the dotfiles (`/ari-dotfiles-skill-registry`). If the setup output said `state=linked`, the tier is `tier`; stage and commit through it per `/ari-dotfiles`:

```zsh
git df add $HOME/.config/claude/skills/<skill-name> && git df commit -m "<skill-name>: <what changed and why>"
```

(`git ldf add $HOME/.local/share/claude-skills/<skill-name>` for `tier=ldf`.) Pushing follows `/ari-dotfiles`'s Pushing rules; this skill never pushes.

If the setup output carried `source=submodule:<path>`, the skill is versioned in that submodule's own repo, not the tier: stage and commit there, then finish the dotfiles change per `/ari-dotfiles` § Submodules (the user's push, then the pointer bump, committed as part of the same change):

```zsh
git -C $HOME/<path> add skills/<skill-name> && git -C $HOME/<path> commit -m "<skill-name>: <what changed and why>"
```

If `state` was `unlinked` or `ignored`, adopt first. Pick the tier with `/ari-dotfiles` Placement rules, then:

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/adopt --skill <skill-name> --tier df
```

It moves, links, and stages; commit as above. The adoptions drafted under **Find unadopted skills** land the same way, one commit each.

On a failure, show the error, diagnose it, and propose the fix with the command that retries; never retry before a `yes`. The edits stay local whatever the answer.

## Skill-writing principles

### Skill anatomy

A skill has distinct sections, each `##` headed with `###` sub-headers. Do not number step headers — they get reordered.

- **Workflow** — sequential steps, start to finish
- **Rules** — invariants, always in effect regardless of step
- **Investigation folder** — `/tmp` structure for runtime state
- **File storage** — persistent files in the skill directory (`bin/`, `templates/`)
- **Input** — what the user provides to start

**Where to place an instruction:**
- Applies to one `###` step? Put it inside that step.
- Applies to two or more steps, or always? Put it in `## Rules`.
- Unsure? Add it to `## Rules`. A rule that applies to fewer steps than expected is harmless; a rule buried inside one step when it applies to many is a bug.

### Reuse

Never reimplement what another skill provides — delegate with a `/skill-name` reference. If multiple skills share a pattern, extract it to a base skill and reference it.

### Scripts

Prefer scripts over LLM tool calls — they run without permission prompts, work standalone, and are deterministic. Scripts and the invocations that call them MUST follow the conventions skill for the language (see `## Rules`).
