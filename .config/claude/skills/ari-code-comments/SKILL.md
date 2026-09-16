---
name: ari-code-comments
description: Conventions for adding code comments — when a comment is justified, where it goes, and how to word it. Use when adding comments to code, or when the user deliberately asks to rewrite a specific existing comment. Has a non-interactive mode that converges on an inline comment through adversarial review.
---

# Code Comments

Conventions for adding code comments. A comment states only what the code cannot: constraints, invariants, contracts, the why. The default for any line of code is no comment.

## Rules

### When to comment

- **Comment only insights that are not obvious when grepping the code.** Constraints, races, invariants, the why.
- **Never restate the code.** No narrating the next line, no synopsis of a function's body.
- **Never talk to the reviewer.** Where code came from and why the change is correct belong in the PR description — that commentary is noise the moment the PR merges.
- **Never touch comments elsewhere.** Update an existing comment only when updating the code it is attached to, or when the user deliberately invokes this skill on that comment to rewrite it. A deliberate rewrite follows all the same rules — an inline rewrite goes through the 5-candidate flow.

```tsx
// BAD — restates the code
// Update the import run status from FAILED to RUNNING.
await updateStatus(FAILED, RUNNING);

// GOOD — states what the code cannot
// The user could be missing if their account was deactivated.
skipIfUserMissing(userId);
```

### Placement

Put knowledge at the highest level that owns it. Each lower level assumes the levels above as prior knowledge.

- **Never repeat information across levels.** If a comment leans on definitions or imports, you MUST read those files so you do not restate what they already say.
- **Type level.** A type's comment is assumed prior knowledge everywhere the type is used.
- **Function level.** A function's comment is assumed prior knowledge only inside that function.
- **Inline (inside a function body).** Never write one from a single draft — every inline comment goes through **Workflow › Choose an inline comment**.

```tsx
// GOOD — the type owns the invariant, the function leans on it
// A ShardMap is immutable after bootstrap. Rebalancing produces a new map.
type ShardMap = ReadonlyMap<ShardId, NodeId>;

// The old map stays live for in-flight reads until they drain.
function rebalance(map: ShardMap): ShardMap {
```

### Wording

Before adding a comment, you MUST read every existing comment in the file and let their style influence yours — no need to conform exactly. Write like K&R (The C Programming Language): terse, explanatory, to the point. Follow ASD-STE100 Simplified Technical English: short sentences, one idea per sentence, active voice, simple vocabulary.

- **Full sentences.** No padding, no bullet-list essays.
- **No semicolons.**
- **Reference files rarely; file name only.** Never a full path, never a line number.
- **No dates, no one-off test references.** Never "(2026-07-23)" or "verified manually on staging".

### Syntax

- **Always the language's line-comment token (`//`, `#`, `--`), never block comments (`/* */`).**
- **Never JSDoc.** Document a declaration with `//` lines, and only when it adds information not derivable from the name or body — lead with the why or the contract.

## Workflow

### Choose an inline comment

Draft 5 candidates per inline comment, then take one path.

- **Interactive (default).** Present every candidate set to the user, one decision per comment. Iterate until they pick one or shape a final draft.
- **Non-interactive.** Only when the user says so ("non-interactive", "don't ask", "just pick"). Converge without asking:
  1. Spawn one Agent per axis in parallel, ~5 total: `/ari-hemingway--review-kr`, `/ari-hemingway--review-ste100`, `/ari-hemingway--review-brevity`, a restates-the-code finder (reads the code and the levels above it, rejects any candidate they already say), and one batch skeptic that checks every candidate's factual claims against the source.
  2. Each reviewer ranks the 5 and names the Rule behind each rejection. Drop every rejected candidate. No survivors: redraft 5 from the rejection reasons and rerun once.
  3. Merge the survivors' strongest phrasings into one draft and run the skeptic on it once more. Two rounds max, then take the best-ranked survivor.
  4. Write it. Put the 5 candidates, each rejection with its Rule, and the winner in the recap so the user can override afterwards.

Several inline comments run as independent pipelines: each review starts as soon as its candidates exist.
