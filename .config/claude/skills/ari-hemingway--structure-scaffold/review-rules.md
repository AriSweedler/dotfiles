---
applies_to: ari-hemingway--structure-scaffold
loaded_by: /ari-hemingway--review-gdoc
---

# Review rules: scaffold

Sibling-specific rules that extend `/ari-hemingway--format-gdoc`. `/ari-hemingway--format-gdoc` is the floor — these rules ADD constraints; they MUST NOT override format rules.

## Required sections (order-sensitive)

1. Title — plain text, `[ari-hemingway scaffold] <Topic> [🤖 AI generated]`.
2. `# Summary` — names the topic and what this revision contains. Any mention of a skill outside the footer is a finding.
3. `# Definitions` — exactly one table, then at most one diagram image.
4. `# Subsystems` — one `##` per subsystem.
5. `# Useful links` — `## Docs` with every doc URL from the table and the body; no `## Code and PRs` unless the topic is code.
6. Footer `🤖🌸 Generated with Claude Code with the ari-hemingway skill`.

## Definitions table

- Two columns, `Word | Definition`. Word cells are links to canonical documentation when a page exists, plain text otherwise; no fabricated URLs.
- Rows in dependency order: a definition mentions a table term only if that term is an earlier row (whole-word, including plurals and -ed/-ing forms). No self-mention.
- At most 2 sentences of at most 25 words each; what the thing IS comes first; no "etc", "...", "various", "and so on".
- 25 to 35 rows expected; more than 50 is a violation.
- Literal tokens backticked per `/ari-hemingway--format-gdoc`.
- The reviewer reproduces the mechanical check rather than eyeballing it: dump the rows to JSON and run `zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh --file <rows.json>`; every printed violation is a finding.

## Subsystem sections

- Each `##` section is readable alone given the table: no jargon outside the table's words, no reliance on another section's text.
- A section may name another subsystem but MUST NOT describe its internals.
- A section that introduces a term the table lacks is a finding against the table, not the section.

## Summary

- Written from the accepted table and sections: every claim in it appears in the body.
- Says nothing about how the article was made; the footer carries the credit.

## Diagram

- At most one image directly after the table, per the Diagrams rule in `/ari-hemingway--format-gdoc`: `[![alt](ink_url?width=620)](live_url)`, so the image links to its mermaid.live source; it ties together terms that are all in the table.
