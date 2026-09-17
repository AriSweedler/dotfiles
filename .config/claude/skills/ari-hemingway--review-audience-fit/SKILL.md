---
name: ari-hemingway--review-audience-fit
description: "Review a draft for fit with its audience and destination: length, tone, depth, assumed knowledge. Requires a declared destination (gdoc, slack, pr, email, readme). Standalone-invocable or used by review bundles."
---

# Audience-Fit Review

One axis of the Hemingway review family. Flags mismatches between the draft and where it's going.

Orthogonal to format: format checks syntax and convention (emoji literals, heading levels, permalinks); audience-fit checks *whether the draft works for the reader at all*.

## Preconditions

- **Declared destination required.** If the caller didn't specify, ask:
  ```
  Which destination? (1) gdoc (2) slack (3) pr-description (4) email (5) readme (6) other — name it
  ```
  Do NOT proceed without a destination.

## Destination rules

| Destination | Typical length | Tone | Depth | Reader assumption |
|---|---|---|---|---|
| gdoc | 600–3000 words | precise, neutral | deep (required sections, tables) | colleagues with shared context |
| slack (status) | <300 words | conversational, emoji ok | shallow (tl;dr + bullets) | partial context, skimming |
| slack (thread reply) | <100 words | direct | shallow | just read the parent |
| pr-description | 100–500 words | factual | medium (summary + test plan) | reviewer has PR diff in front of them |
| email | 200–800 words | structured, greeting | medium | reader hasn't asked for it |
| readme | 200–2000 words | instructive | deep (install, usage, contributing) | new to the project |

## Check bullets

- [ ] Length within the destination's typical range (report actual word count vs range).
- [ ] Tone matches destination (slack can use emoji and contractions; gdoc cannot).
- [ ] Depth matches destination (slack = skimmable; gdoc = substantive; pr = factual).
- [ ] Assumed knowledge matches destination's reader profile — no in-group jargon dropped on outsiders; no over-explanation for insiders.
- [ ] Destination-specific conventions honored:
  - gdoc: plain-text title starting with `[🤖 AI generated]`; `# Useful links` section
  - slack: opening `:wave:` or context line; no formal headings (`#`); `*bold*` mrkdwn
  - pr-description: `# Summary` and `# Test Plan` sections
  - email: greeting + closing
  - readme: install/usage sections, code fences with language tags

## Standalone workflow

Same pattern as `$HOME/.claude/skills/ari-hemingway--review-brevity/SKILL.md` but:
- First confirm destination (see Preconditions).
- Investigation folder: `/tmp/hemingway/review-audience-fit/{topic-slug}/{timestamp}/`
- Output file: `{investigation_folder}/audience-fit.md`

## Invoked by a bundle

Bundle passes `{investigation_folder}` and the declared destination. Output to `{investigation_folder}/audience-fit.md`.

## Per-reviewer output file

Schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`. Reviewer name: `audience-fit`.

## Rules the reviewer must obey

- READ-ONLY.
- Fixes MUST move the draft toward the declared destination, not away.
- If the draft clearly isn't meant for the declared destination, flag as a meta-finding (`severity: blocker`, problem: "draft's shape doesn't fit destination X — reconsider destination or rewrite").
