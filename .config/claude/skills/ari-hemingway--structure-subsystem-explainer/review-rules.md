---
applies_to: ari-hemingway--structure-subsystem-explainer
loaded_by: /ari-hemingway--review-gdoc
---

# Review rules: subsystem-explainer

Sibling-specific rules that extend `/ari-hemingway--format-gdoc`. `/ari-hemingway--format-gdoc` is the floor — these rules ADD constraints; they MUST NOT override format rules.

## Required sections (order-sensitive)

Every explainer MUST include these sections, in this order:
1. Title — plain text, starting with `[🤖 AI generated]`.
2. `# Summary`
3. `# How it works`
4. `# Gotchas`
5. *(optional sections: Key details, Comparison, Integration points, Operational notes)*
6. `# Useful links`
7. Footer `🤖🌸 Generated with Claude Code`

## Mandatory section bodies

- **`# Gotchas`** — never omit, even when empty. If research found none, body MUST be exactly `None found during research.`
- **`# Useful links`** — MUST contain (a) every URL inlined in the body, (b) every resource named but not linked inline.

## Reshape rules

Optional sections MAY be altered only as:
- Rename only to a title that names the subject concretely (e.g., "Key details" → "Shard routing rules"). NEVER to a vaguer title.
- Merge two adjacent optional sections if combined content is under 300 words.
- Drop an optional section if it would contain fewer than 2 bullets/rows.

Any reshape beyond this list MUST be called out in the update-mode diff summary.

## Word count by scope

Walk top-to-bottom; first match wins:

| Scope | Words |
|---|---|
| Single file or single script, no cross-service calls | ≤600 |
| One service, 2-5 named collaborating services/packages | 600-1800 |
| Multiple services OR more than one team | >1800 |

Word count MUST land within the declared bucket (recorded in `scratchpad.md`).

## Flow diagram trigger

Include a flow diagram in `# How it works` if EITHER:
- `# How it works` contains ≥4 numbered steps, OR
- The flow spans ≥3 distinct services.

Otherwise omit.

## Mode-specific invariants

### Distill mode

Every included incident MUST have ALL of:
- Date OR PR/commit link.
- Named failure mode.
- Explicit user statement OR linked post-mortem.

Every included incident MUST carry inline attribution: `Discovered during [specific user statement or PR]`.

### Update mode

If a diff is shown:
- Grouped into `## Fact corrections` / `## Additions` / `## Removals` / `## Prose/structure edits`.
- Allowed verbs: `added | removed | corrected | renamed`.
- Corrections include both values: `corrected: X → Y per commit abc123`.
- Renames include old AND new heading: `**[Overview → Summary]** — renamed and tightened`.

Per-claim diff checklist MUST have been applied (each file path, config value, command, numbered flow step, and named component compared against current codebase).
