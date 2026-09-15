---
name: ari-hemingway--review-clarity
description: "Review a draft (markdown file, gdoc URL, or inline paste) for clarity: passive voice, undefined jargon, unclear pronouns, run-ons. Standalone-invocable or used by review bundles."
---

# Clarity Review

One axis of the Hemingway review family. Flags prose that's hard to parse even if brief.

## Rules this axis checks

- **Active voice preferred.** Passive voice acceptable only when the agent is unknown or unimportant.
- **Define acronyms on first use.** `MCR` → `MCR (multi-cluster rollout)` on first mention per section.
- **Jargon requires a one-sentence definition** if the audience isn't guaranteed to know it. "PDB" is fine for a k8s-internal doc; "disruption budget" for a general doc.
- **Pronoun antecedent unambiguous.** `it`, `this`, `they` must refer to something identified in the previous sentence.
- **One clause per sentence in operational text.** Split compound sentences that chain actions.
- **Ordered steps are numbered lists, not prose.** Sentences like "first do X, then Y, finally Z" FAIL.
- **No "we" / "you" shifts within a section.** Pick one and stay.

## Check bullets

- [ ] Active voice predominates. Flag passive constructions whose agent is known and material.
- [ ] All acronyms defined on first mention per section.
- [ ] Jargon defined or obviously in-scope for the audience.
- [ ] Every `it`, `this`, `these` has an unambiguous antecedent in the previous ~15 words.
- [ ] No sentence chains 3+ actions with commas or `and`. Flag for splitting or bulleting.
- [ ] Sequential steps formatted as numbered lists when ≥3.
- [ ] Consistent subject (we | you | imperative) within each section.

## Standalone workflow

Same pattern as `$HOME/.claude/skills/ari-hemingway--review-brevity/SKILL.md` `## Standalone workflow` but:
- Investigation folder: `/tmp/hemingway/review-clarity/{topic-slug}/{timestamp}/`
- Output file: `{investigation_folder}/clarity.md`

## Invoked by a bundle

Bundle passes `{investigation_folder}`; output to `{investigation_folder}/clarity.md`.

## Per-reviewer output file

Schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`. Reviewer name: `clarity`.

## Rules the reviewer must obey

- READ-ONLY.
- Cite the rule section name on each finding.
- Fix suggestions MUST be at least as clear as what they replace — don't trade clarity for brevity here.
