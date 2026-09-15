---
name: ari-hemingway--review-brevity
description: "Review a draft (markdown file, gdoc URL, or inline paste) for brevity: sentences that can be deleted without losing a concrete fact, abstract where concrete would work, filler. Standalone-invocable or used by review bundles."
---

# Brevity Review

One axis of the Hemingway review family. Flags prose that can be cut without losing meaning.

Formatting rules reference: `/ari-hemingway--format-gdoc` `## Prose style`. Other destinations share the same brevity principles.

## Rules this axis checks

- **Write like Kernighan & Ritchie.** Terse, precise, one idea per sentence.
- **Delete any sentence with no concrete fact.** Names no path, identifier, number, decision, or failure mode → delete it.
- **Concrete over abstract.** Paths, ports, table names, golinks, config values, commands. `<file>` and `<path>` placeholders FAIL.
- **Tables for structured data.** 3+ rows × 2+ attribute columns → table. Fewer → bullets.
- **Filler words.** `basically`, `essentially`, `simply`, `just`, `really`, `very`, `actually`, `in order to` → cut or rewrite.
- **Adverb-heavy phrasing.** Replace with a stronger verb where possible.

## Check bullets

Reviewer MUST report on each:

- [ ] Every sentence names at least one concrete fact (path, identifier, number, decision, failure mode). Flag sentences that don't.
- [ ] No placeholder tokens like `<file>`, `<path>`, `<your-value-here>` in operational text. Flag each occurrence.
- [ ] Filler words absent. Flag uses of `basically`, `essentially`, `simply`, `just`, `really`, `very`, `actually`, `in order to`.
- [ ] Structured data ≥3 rows × 2 attributes lives in a table, not prose or bullets.
- [ ] No sentence exceeds 30 words without a good reason (compound fact, unavoidable enumeration).
- [ ] Adverbs justified; flag `very`, `really`, `just`, `simply` used as intensifiers.

## Standalone workflow

When invoked with a draft path / URL / inline, follow the `Accept input` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Then:

1. Create investigation folder at `/tmp/hemingway/review-brevity/{topic-slug}/{timestamp}/`.
2. Copy source to `source.md`.
3. Dispatch a single reviewer Agent with the check bullets above and the output-file schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`.
4. Reviewer writes to `{investigation_folder}/brevity.md`.
5. Present findings inline (no challenge/rank step — that's the bundle's job).

## Invoked by a bundle

When a review bundle (`ari-hemingway--review-gdoc`, `ari-hemingway--review-common`) invokes this skill, it passes the existing `{investigation_folder}` and expects output at `{investigation_folder}/brevity.md`. Skip the folder-creation and presentation steps.

## Per-reviewer output file

Use the schema defined in `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file` verbatim. Reviewer name: `brevity`.

## Rules the reviewer must obey

- READ-ONLY. Never call Edit/Write/NotebookEdit on the source.
- Cite the rule section name (from this file's `## Rules this axis checks`) on each finding.
- Fixes MUST themselves be brief — rewrites that add words violate the axis.
