---
name: ari-hemingway--review-factual
description: "Review a draft (markdown file, gdoc URL, or inline paste) for factual rigor: unverified claims, speculative language, broken permalinks, misused TODO markers. Standalone-invocable or used by review bundles."
---

# Factual Review

One axis of the Hemingway review family. Flags claims that aren't anchored to evidence.

Lib reference: fact-check gate in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` `## Fact-check gate`.

## Rules this axis checks

- **Every path / command / table-name / config-value / numeric-constant is cited or marked `[TODO: verify — reason]`.** Citation = permalink, PR, commit, user statement, or linked doc.
- **No speculative language.** Flag `probably`, `likely`, `I think`, `seems to`, `should work` in factual claims. Permitted in explicit "hypothesis" framing only.
- **`[TODO: verify]` markers anchor to a specific phrase, not a whole sentence or paragraph.** `[TODO: verify — did this SHA land?]` on the phrase is fine; `[TODO: verify this section]` FAILS.
- **`[TODO: verify]` count ≤20% of counted claims** (table rows + flow steps + bullets). Above this → draft isn't ready.
- **Permalinks use full 40-char SHAs**, not `/blob/main/` or short SHAs. Reviewer spot-checks with `git cat-file -p "${sha}:${path}"` if it can.
- **PR references include full title + number** (`[fix pagination (#12345)](...)`), not bare numbers.
- **Fabricated details flagged.** A duration, error count, user name, or date with no provenance is fabricated until proven otherwise.

## Check bullets

- [ ] Every path / command / config-value / numeric-constant cited or TODO-marked.
- [ ] No unmarked speculative language in factual claims.
- [ ] All `[TODO: verify]` markers anchored to specific phrases, not whole sections.
- [ ] `[TODO: verify]` count ≤20% of counted claims (report actual %).
- [ ] Permalinks use full 40-char SHAs; no `/blob/main/`, no short SHAs, no fabricated paths.
- [ ] PR refs use full title + number + escaped brackets.
- [ ] Dates, durations, counts, and names have provenance (user statement, PR, commit, or linked doc) OR are TODO-marked.

## Standalone workflow

Same pattern as `$HOME/.claude/skills/ari-hemingway--review-brevity/SKILL.md` but:
- Investigation folder: `/tmp/hemingway/review-factual/{topic-slug}/{timestamp}/`
- Output file: `{investigation_folder}/factual.md`
- MAY use `git cat-file` to spot-check permalinks cited in the draft if running in a git worktree that might plausibly host them.

## Invoked by a bundle

Bundle passes `{investigation_folder}`; output to `{investigation_folder}/factual.md`.

## Per-reviewer output file

Schema from `$HOME/.claude/skills/ari-hemingway--review-gdoc/SKILL.md` `## Per-reviewer output file`. Reviewer name: `factual`.

## Rules the reviewer must obey

- READ-ONLY.
- NEVER invent a citation. If unsure whether a claim has a source, add `[TODO: verify]` rather than fabricate one.
- Fix suggestions that cite a SHA MUST use the `{sha}` placeholder unless the reviewer has verified the exact SHA.
