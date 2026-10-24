---
name: ari-hemingway--review-kr
description: "Review a draft (markdown file, gdoc URL, or inline paste) against Kernighan & Ritchie style: no marketing language, no hedging, imperative instructions, show-don't-tell, no self-referential prose. Standalone-invocable or used by review bundles."
---

# Kernighan & Ritchie Review

One axis of the Hemingway review family. Enforces the distinctive K&R authorial style from *The C Programming Language*: terse, imperative, concrete, no ornamentation.

Overlaps with `ari-hemingway--review-brevity` (shortness) and `ari-hemingway--review-clarity` (active voice, active subject) but adds K&R-specific rules. Run this axis when the draft needs to read like technical reference prose — not a product brochure, not a blog post, not a teacher explaining.

## Rules this axis checks

### 1. No marketing language

Flag adjectives used as selling language: `powerful`, `robust`, `seamless`, `easy`, `simple`, `elegant`, `efficient`, `scalable`, `flexible`, `comprehensive`, `cutting-edge`. Permitted only when tied to a concrete fact in the same clause: `efficient: caches 10K entries in 2MB` is fine; `our efficient cache` FAILS.

### 2. No hedging

Flag unqualified hedges: `probably`, `typically`, `generally`, `usually`, `tends to`, `in most cases`, `somewhat`, `fairly`, `quite`. Permitted only if followed by the specific exception or cited evidence: `typically 50ms; spikes to 500ms during GC` is fine.

### 3. Imperative voice for instructions

Instructions MUST use the imperative. `Run X` (good); `You should run X` (bad); `It is recommended to run X` (bad); `Running X will...` (bad). Flag any instruction that starts with `You`, `We`, or `It`.

### 4. Show, don't tell

If a paragraph can be replaced by a code block, table, or concrete example, it should be. Flag abstract prose that describes a mechanism without showing it. K&R would write `foo(a, b)` with output, not "the function combines its arguments."

### 5. No self-referential meta-prose

Flag phrases that describe the document describing something: `In this section we will...`, `Below we show...`, `This document covers...`, `Next, we'll discuss...`. Delete them; just say the thing.

### 6. One idea per sentence

Flag sentences that chain two or more distinct facts with `and` / `;` / comma splices when the facts warrant separate sentences. K&R sentences read: "The function returns zero. A non-zero return indicates error." NOT "The function returns zero and a non-zero return indicates error."

### 7. Specific over general

Flag generic nouns where a specific one is available from context: `the configuration file` → `server.conf`; `the handler` → `handle_request`; `the error` → `ENOENT`; `the user` → the named user or role.

### 8. No throat-clearing

Flag opening phrases that add no information before the actual sentence: `It should be noted that`, `It is worth mentioning`, `Note that`, `Importantly,`, `Of course,`, `Obviously`. Delete; the next clause is the sentence.

### 9. Word choice over word count

K&R is not just about being short — it's about picking the right word. Flag verbose constructions with a stronger one-word alternative:
- `make use of` → `use`
- `in order to` → `to`
- `due to the fact that` → `because`
- `at this point in time` → `now`
- `in the event that` → `if`
- `is able to` → `can`

### 10. No empty intensifiers

Flag `very`, `really`, `quite`, `rather`, `pretty` as modifiers of adjectives (`very fast`, `really simple`). Either drop them or replace with a number (`very fast` → `50ms`).

## Check bullets

Reviewer MUST report on each:

- [ ] No marketing adjectives untethered to a concrete fact (rule 1).
- [ ] No unqualified hedges (rule 2).
- [ ] All instructions in imperative voice (rule 3).
- [ ] Abstract-prose paragraphs that should be code/tables flagged (rule 4).
- [ ] No self-referential meta-prose (rule 5).
- [ ] No sentence chains two distinct facts where a period would serve (rule 6).
- [ ] Generic nouns replaced with specific ones where context supports it (rule 7).
- [ ] No throat-clearing openers (rule 8).
- [ ] Verbose constructions replaced with single words where possible (rule 9).
- [ ] No empty intensifiers (rule 10).

## Standalone workflow

When invoked with a draft path / URL / inline, follow the `Accept input` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Then:

1. Create investigation folder at `/tmp/hemingway/review-kr/{topic-slug}/{timestamp}/`.
2. Copy source to `source.md`.
3. Dispatch a single reviewer Agent with the 10 check bullets and the output-file schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`.
4. Reviewer writes to `{investigation_folder}/kr.md`.
5. Present findings inline (no challenge/rank step — that's the bundle's job).

## Invoked by a bundle

When a review bundle invokes this skill, it passes the existing `{investigation_folder}` and expects output at `{investigation_folder}/kr.md`. Skip folder creation and presentation.

## Per-reviewer output file

Schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`. Reviewer name: `kr`.

## Relationship to other axes

| Axis | Overlaps with K&R on | K&R adds |
|---|---|---|
| brevity | filler words, adverb-heavy phrasing | marketing language, hedging, throat-clearing, verbose→single-word |
| clarity | active voice | imperative (narrower than active), self-referential prose, specific nouns |
| factual | speculation | hedging without named exception |

`ari-hemingway--review-common` includes K&R as an always-on axis. Run this skill standalone only when you want just the K&R lens — everything else covers broader ground.

## Rules the reviewer must obey

- READ-ONLY. Never call Edit/Write/NotebookEdit on the source.
- Cite the rule NUMBER (1-10) on each finding.
- Fixes MUST themselves be K&R-compliant. A fix that adds a marketing adjective to replace a hedge is a broken fix.
- If a rule genuinely does not apply (e.g., this is a narrative post-mortem, not a reference doc), mark the check bullet `N/A` with a one-sentence justification, don't silently skip.
