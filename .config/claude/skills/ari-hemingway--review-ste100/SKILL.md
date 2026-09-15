---
name: ari-hemingway--review-ste100
description: "Review a draft (markdown file, gdoc URL, or inline paste) against ASD-STE100 Simplified Technical English: sentence-length caps, one idea per sentence, active voice, present tense, one word one meaning, short noun clusters. Standalone-invocable or used by review bundles."
---

# Simplified Technical English Review

One axis of the Hemingway review family. Enforces ASD-STE100 Simplified Technical English — the controlled language the AeroSpace and Defence Industries Association of Europe specifies for maintenance documentation. The spec has two parts: writing rules, and a dictionary of ~900 approved words where each word has one meaning and one part of speech. This axis applies the writing rules; it treats the dictionary as a principle (prefer the common, simple word) rather than a lookup table.

Overlaps with `ari-hemingway--review-brevity` (sentence length), `ari-hemingway--review-clarity` (active voice, run-ons), and `ari-hemingway--review-kr` (one idea per sentence, imperative) but adds STE-specific rules: tense restrictions, controlled vocabulary, noun-cluster limits, paragraph caps. Run this axis when the draft must survive stressed or non-native readers — runbooks, playbooks, alerts, operational instructions.

## Rules this axis checks

### 1. Sentence length

Instructions: 20 words or fewer. Descriptive sentences: 25 words or fewer. Flag any sentence over its cap and split it.

### 2. One instruction or idea per sentence

One sentence does one thing. Flag sentences that chain an instruction with a second instruction, a condition, and a caveat. `Run the script. If it fails, read the log.` (good); `Run the script and if it fails you should probably check the log for errors.` (fails).

### 3. Active voice

Flag passives: `The flag is read by the worker` → `The worker reads the flag`. Passives hide the actor; procedures need the actor.

### 4. Present tense

Describe behavior in the present tense. Flag `will return`, `was designed to`, `is going to` when `returns` / `does` serves. Future tense is permitted only for a genuinely future event.

### 5. One word, one meaning

Use the same word for the same thing everywhere in the draft. Flag elegant variation (`the job` / `the task` / `the run` for one thing) and words used in two senses (`check` as verb and noun). Pick one term; repeat it.

### 6. No gerund-led clauses

Flag `-ing` clauses that open a sentence or hide an actor: `Before starting the rotation` → `Before you start the rotation`; `Restarting the pod fixes it` → `Restart the pod to fix it`.

### 7. Noun clusters of three words or fewer

Flag noun strings longer than three words; break them with prepositions. `node rotation state table schema` → `the schema of the rotation-state table`.

### 8. Keep the articles

No telegraphic style. `Remove bolt and check seal` → `Remove the bolt and check the seal`. Dropped articles read fast and parse wrong.

### 9. Paragraphs of six sentences or fewer, one topic each

Flag paragraphs over six sentences or covering two topics. Split at the topic change.

### 10. Warnings and cautions first, as commands

A safety or irreversibility note comes before the instruction it protects, phrased as a command. `Warning: this deletes the table. Run the drop script.` (good); `Run the drop script (note: this deletes the table).` (fails).

## Check bullets

Reviewer MUST report on each:

- [ ] No sentence over 20 words (instruction) / 25 words (descriptive) (rule 1).
- [ ] No sentence carries two instructions or ideas (rule 2).
- [ ] No passive voice where the actor matters (rule 3).
- [ ] Present tense for behavior; future only for future events (rule 4).
- [ ] One term per concept; no elegant variation or double senses (rule 5).
- [ ] No gerund-led clauses (rule 6).
- [ ] No noun cluster over three words (rule 7).
- [ ] Articles present; no telegraphic style (rule 8).
- [ ] Paragraphs ≤ 6 sentences, one topic each (rule 9).
- [ ] Warnings/cautions precede their instruction, as commands (rule 10).

## Standalone workflow

When invoked with a draft path / URL / inline, follow the `Accept input` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Then:

1. Create investigation folder at `/tmp/hemingway/review-ste100/{topic-slug}/{timestamp}/`.
2. Copy source to `source.md`.
3. Dispatch a single reviewer Agent with the 10 check bullets and the output-file schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`.
4. Reviewer writes to `{investigation_folder}/ste100.md`.
5. Present findings inline (no challenge/rank step — that's the bundle's job).

## Invoked by a bundle

When a review bundle invokes this skill, it passes the existing `{investigation_folder}` and expects output at `{investigation_folder}/ste100.md`. Skip folder creation and presentation.

## Per-reviewer output file

Schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`. Reviewer name: `ste100`.

## Relationship to other axes

| Axis | Overlaps with STE100 on | STE100 adds |
|---|---|---|
| brevity | long sentences, filler | hard word-count caps, paragraph cap |
| clarity | active voice, run-ons | present tense, articles, gerund ban |
| kr | one idea per sentence, imperative instructions | controlled vocabulary, noun-cluster limit, warnings-first |

`ari-hemingway--review-common` includes STE100 as an always-on axis. Run this skill standalone only when you want just the STE lens — everything else covers broader ground.

## Rules the reviewer must obey

- READ-ONLY. Never call Edit/Write/NotebookEdit on the source.
- Cite the rule NUMBER (1-10) on each finding.
- Fixes MUST themselves be STE100-compliant. A fix that splits a sentence but goes passive is a broken fix.
- If a rule genuinely does not apply (e.g., a narrative post-mortem has no procedures for rule 10), mark the check bullet `N/A` with a one-sentence justification, don't silently skip.
