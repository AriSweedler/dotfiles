---
name: ari-skill-update
description: Edit a skill interactively, then commit it to the dotfiles tier that owns it (adopting it first if needed). Runs as a background fork by default.
---

# Skill Update

Edit a skill interactively, then commit it to the dotfiles tier that owns it, adopting it first if it is not yet versioned. Runs in a fork by default so the main thread stays on the real work (see the first workflow step). Quality review is delegated to `/ari-skill-review`; script conventions to `/ari-skill-shellscripts` and `/ari-skill-pythonscripts`.

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
- **Gate edits on user approval.** After presenting the planned change, wait for the user's next message. Proceed to editing ONLY on unqualified agreement ("yes", "go ahead", "do it", "lgtm"). Conditional agreement ("yes, but change X") is a modification request — address it and re-present. A question or topic change — address it first. Do NOT open or write skill files until this gate passes.
- **MUST confirm before committing.** Show a fresh diff of all changes immediately before committing. Never commit without the user seeing what changed.
- **Audit every documented invocation for the `$HOME` form.** On every edit — including prose-only edits — scan the skill for any line that runs a skill script. Each MUST use `$HOME` (never `~`), have no leading `cd`, and not be piped (redirect to a file if you need the output). Fix every non-conforming invocation you find, even ones unrelated to the requested change.
  ```
  BAD:  zsh ~/.claude/skills/foo/bin/x.zsh --id 123                  # ~ instead of $HOME
  BAD:  cd ~/.claude/skills/foo && zsh bin/x.zsh --id 123            # leading cd + relative path
  BAD:  zsh $HOME/.claude/skills/foo/bin/x.zsh --id 123 | head       # piped — truncates output
  BAD:  cd /repo; zsh ~/.claude/skills/foo/bin/x.zsh --id 123 2>&1 | tail -40   # all of the above
  GOOD: zsh $HOME/.claude/skills/foo/bin/x.zsh --id 123
  ```
- **NEVER scaffold around a self-contained script.** Skill scripts do their own setup. When a step says to run one, emit exactly that one Bash call — no `mkdir`, `ls`, `echo`, `cd`, or timestamp before or after it. Need its output? Read what it prints; don't re-derive it.
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
- **Skill**: ari-pr — $HOME/.claude/skills/ari-pr/SKILL.md — Create or update a PR
- **Goal**: Add draft PR support when user says "draft" or "wip"
- **Changes made**:
  - Added --draft flag to gh pr create in the push step
  - Updated heading to mention draft PRs
- **Open questions**:
  - Should existing PRs be convertible to draft? Check gh pr ready support.
```

## File storage

- `bin/init.zsh` — session-setup script run once at "Set up the session": confirms the skill exists, reports its dotfiles tier state, creates the investigation folder + pre-filled scratchpad, and prints the skill's files to read. See that step for its output contract.

## Workflow

### Fork by default

If this skill was invoked in a main working thread (you are not already a fork), spawn a fork carrying the full skill-update directive and return to the main work — do NOT run the rest of this workflow inline. Skip the fork ONLY when the user explicitly asked not to fork. Forks nest: when an update surfaces a meta-skill that also needs updating, fork again from the fork. Everything below executes inside the fork.

### Identify the skill

- If the user gave an exact skill directory name under `$HOME/.claude/skills/`, use it.
- If the user gave a partial name or description, list matches as `name — purpose` rows and ask the user to pick one by exact name.
- If no name was given, list all skills and ask.
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

**Step 3: Confirm.** Repeat the planned change in one sentence. If the behavior already exists in the skill, say so and stop — don't make an empty edit. Otherwise wait for the user to approve before touching any files.

### Edit the skill

Do not start until the approval gate (see Rules) has passed.

1. **If intent changed** — rewrite the `#` heading and opening paragraph from scratch, as if written fresh for the new purpose.
2. **Update implementation** — read the full skill first, then place each change per **Skill anatomy** below. Before adding a new step, run `ls $HOME/.claude/skills/` and delegate to any skill that already does it — never reimplement.
3. **Audit and syntax-check** — before showing the diff, scan the edited skill for script invocations and confirm each matches the `$HOME` form (see Rules), fixing any that don't (including pre-existing ones). Syntax-check any edited script (`zsh -n <script>.zsh`; `python3 -m py_compile <script>.py`).
4. **Update scratchpad** — record what changed and why.

After edits, show the diff of all modified files. Then ask:

> What next?
> 1. Commit to dotfiles
> 2. Review first, then decide
> 3. Review and commit
> 4. Keep editing

Map responses: commit/push/ship/deploy → 1; bare "review" (no mention of committing) → 2; "review and commit" / "review then ship" → 3; edit/change → 4. If a review response is ambiguous about whether to commit afterward, choose 2. Anything else → re-ask. When in doubt, do NOT commit.

### Review

Invoke `/ari-skill-review` via the Skill tool with the skill name as the argument. When it returns:
1. Present each recommended change to the user, one per line:
   ```
   [1/3] EXAMPLES — scratchpad has no filled example
     Fix: add a concrete entry with real values
   ```
2. Apply only the changes the user approves.
3. Re-show the diff and re-present the four-option menu. Always re-show the diff after applying review changes — never auto-commit, even if "review and commit" was pre-selected (pre-selection is intent, not authorization to commit unseen changes). If the review fails or returns nothing, say so and re-present the menu.

### Commit to dotfiles

Re-show the current diff (or state "no changes since the last diff") immediately before committing. If the diff is empty, there is nothing to commit; skip.

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

It moves, links, and stages; commit as above. An `ignored` skill is third-party: warn that naming it adopts it into your dotfiles, and confirm first.

On a failure, show the error, then stop and offer: **Retry** the failed command, **Skip** and keep local edits, or **Debug**. Do NOT retry automatically.

### Check for other unadopted skills

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status
```

List the `unlinked` rows and ask which to adopt; adopt only the ones the user names, one commit each. If nothing is actionable, say so.

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
