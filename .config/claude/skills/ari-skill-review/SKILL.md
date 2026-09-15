---
name: ari-skill-review
description: Dispatch expert reviewers to evaluate a Claude Code skill and produce a prioritized, ordered list of improvements.
---

# Skill Review

Dispatch expert reviewers against a skill. Challenge their findings, deduplicate, rank by importance, present a single ordered list.

## Rules

- **Reviewers MUST NOT change the skill's purpose.** They improve execution, not intent. If a reviewer flags a problem with the purpose itself, the manager escalates it to the user as a "spec question" — never instructs a reviewer to act on it.
- **Write like Kernighan & Ritchie.** Terse, precise, full information, no filler.

## Investigation folder

```
/tmp/skill-review/{skill-name}/{timestamp}/
├── structure.md
├── clarity.md
├── edge-case.md
├── reuse.md
├── interaction.md
├── examples.md
├── kernighan-ritchie.md
├── deflake.md
├── findings.md             # Deduplicated, challenged, ordered list
└── spec-questions.md       # Items that touch the skill's purpose
```

`bin/setup.zsh` creates this folder (timestamped, so sessions never clash) and scaffolds every file. Reviewers write directly to it. `findings.md` is the final deliverable.

## Workflow

### Identify the target

If the user specified a skill name, use it. Otherwise ask.

Read all files in `$HOME/.claude/skills/<skill-name>/`. Extract the skill's stated purpose: the `#` heading + first paragraph.

Scaffold the investigation folder — it prints the folder path to stdout:

```zsh
zsh $HOME/.claude/skills/ari-skill-review/bin/setup.zsh --skill <skill-name>
```

Capture that path as the investigation folder for the rest of the run.

### Dispatch reviewers

Launch all 8 reviewers **in parallel** using the Agent tool. Pass the folder path from setup to each reviewer so they write their own output:

> You are reviewing a Claude Code skill as a {role} expert. The skill's purpose is: "{purpose}". Do NOT suggest changes to this purpose — only improve how it's achieved. Read the skill below and return a list of specific, actionable recommendations for your area of expertise. Be terse — state the problem, state the fix.
>
> Write your findings to: {investigation_folder}/{reviewer-name}.md — `setup.zsh` already created this folder and an empty file there. Write to it directly; do NOT run `mkdir`, `touch`, or any other setup command (it would trigger a needless permission prompt).
>
> {full skill text}

### Challenge and deduplicate

For each reviewer's findings:

1. **Challenge every item.** Push back on the recommendation. Is it actually a problem? Would the suggested fix introduce new issues? Is the cost of the fix worth the improvement? Drop items that don't survive scrutiny.
2. **Cross-reference across reviewers.** If multiple reviewers flagged the same issue (even in different terms), that's a strong signal — merge them into one item and note which reviewers flagged it.
3. **Filter for scope violations.** Re-read the skill's purpose. Any recommendation that changes *what* the skill does goes to `spec-questions.md`, not the main list.

### Rank and write findings

Produce a single **ordered list** in `findings.md` — item 1 is the most important, last item is the least. Not buckets, not categories. One list, strictly ranked.

Ranking criteria (in order of weight):
- **Flagged by multiple reviewers** — cross-reviewer agreement is the strongest signal
- **Incorrect behavior or silent failure** — the skill does the wrong thing
- **Flaky compliance** — an LLM will skip the instruction regularly
- **Ambiguity** — two LLMs would interpret the instruction differently
- **Missing error path** — failure case unhandled
- **Clarity / examples** — works but could be clearer
- **Style / polish** — cosmetic

Each item in `findings.md`:

```markdown
## 1. {Short title}

**Flagged by:** {reviewer names, comma-separated}
**Problem:** {one sentence}
**Fix:** {concrete action}
```

### Present to user

Share the `findings.md` path first so the user can read the full file. Then show the ordered list inline.

If `spec-questions.md` has items, present those separately: "These touch the skill's purpose — your call:"

Ask which items to implement. Valid answers:
- "all" — implement everything
- Item numbers — "1, 3, 5"
- "top N" — "top 5"
- Anything else — ask for clarification, do NOT guess

If invoked from `/ari-skill-update`, return the approved list to the calling workflow rather than applying changes directly.

## Reviewer panel

### Structure reviewer

Does the skill follow standard layout? Check:
- Short explanation up top (1-2 sentences)
- `##` sections with `### Descriptive Name` sub-headers (no numbered prefixes)
- Base skills referenced where appropriate, not duplicated
- Reference material (principles, tables, schemas) separated from workflow steps
- Sections in logical order: intent → reference data → workflow → appendices

### Clarity reviewer

Can an LLM follow every instruction without ambiguity? Check:
- Vague phrases ("when appropriate", "if needed", "briefly") without concrete criteria
- Missing format specs for structured output (scratchpad entries, summaries, prompts)
- Judgment calls without guiding examples
- Mixed-case handling (e.g., "intent change" vs "implementation change" but no guidance for "both")
- Overlapping terms (e.g., "description" vs "summary" vs "purpose" used interchangeably)

### Edge case reviewer

What happens when things go wrong? Check:
- Commands that can fail (network, auth, missing files) without error handling
- Missing precondition checks (env vars, directories, file existence)
- No fallback for tool/command unavailability
- Idempotency — what happens if the skill runs twice on the same input?
- The "nothing to do" case — all items already addressed, no changes needed

### Reuse reviewer

Is this skill reimplementing existing functionality? Check:
- Run `ls $HOME/.claude/skills/` and compare capabilities
- Delegation opportunities (e.g., `/ari-diagram-mermaid` for diagrams, `/pr` for push workflows)
- `/tmp` used for runtime state, skill directory for persistent files
- Shared patterns that should live in a base skill instead of being duplicated

### Interaction reviewer

Does the skill respect the user's agency? Check:
- Confirmation gates before destructive or visible actions (push, delete, overwrite)
- Ambiguity handled by asking, not guessing
- Progress updates at phase transitions
- Clear options on failure (retry / skip / debug), not just "show error"
- Diff or summary shown before any irreversible action

### Examples reviewer

Does the skill show what it means? Check:
- Formats that need a concrete example (scratchpad entries, output structures, CLI output)
- Anti-examples for instructions that contradict LLM defaults ("do NOT append" needs a before/after)
- Worked examples for judgment calls (intent vs. implementation classification)
- Example of the expected combined output format (reviewer results, status messages)

### Kernighan & Ritchie reviewer

Is the writing tight? Check:
- Filler words and phrases ("In order to", "It should be noted that", "basically")
- Passive voice where active is clearer
- Redundant explanations — if the instruction is clear, the rationale is noise
- Paragraphs that could be bullet points
- Bullet points that could be one line
- Sections that repeat what another section already said
- Every sentence should earn its place. If removing it changes nothing, remove it.

### Deflake reviewer

Which instructions will an LLM skip? Check:
- Instructions buried mid-paragraph — move to own line, bold them
- Negative instructions ("don't X") without positive alternative ("do Y instead")
- Instructions contradicting LLM defaults without strong framing (needs MUST/NEVER, not "prefer")
- Conditions hard to evaluate ("if appropriate") — replace with concrete triggers
- Instructions far from point of action — repeat the constraint where it matters
- Soft language ("try to", "consider") for actual requirements — upgrade to MUST/always/never

For each flaky instruction: state the original, explain why it's flaky, provide a specific rewrite.

## Files

- `bin/setup.zsh` — scaffolds the timestamped investigation folder and its per-reviewer files; prints the folder path to stdout.
