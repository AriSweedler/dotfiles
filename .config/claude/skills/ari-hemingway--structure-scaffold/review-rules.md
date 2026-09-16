---
applies_to: ari-hemingway--structure-scaffold
loaded_by: /ari-hemingway--review-gdoc
---

# Review rules: scaffold

Sibling-specific rules that extend `/ari-hemingway--format-gdoc`. `/ari-hemingway--format-gdoc` is the floor — these rules ADD constraints; they MUST NOT override format rules.

A scaffold is one Doc (single layout) or a folder of Docs (a Glossary Doc plus one Doc per subsystem). Identify the kind from the title before applying the section rules.

## Required sections (order-sensitive)

Single Doc, title `[ari-hemingway scaffold] <Topic> [🤖 AI generated]`:
1. `# Summary` — names the topic and what this revision contains.
2. `# Definitions` — exactly one table, then at most one diagram image.
3. `# Subsystems` — one `##` per subsystem.
4. `# Useful links` — `## Docs` with every doc URL from the table and the body; no `## Code and PRs` unless the topic is code.
5. Footer `🤖🌸 Generated with Claude Code with the ari-hemingway skill`.

Glossary Doc, title `[ari-hemingway scaffold] <Topic> — Glossary [🤖 AI generated]`:
1. `# Summary` — names the topic and the sub-explainers.
2. `# Definitions` — exactly one table (the universal rows), then at most one diagram image (the cluster-level graph).
3. `# Sub-explainers` — one raw `docs.google.com` URL per subsystem Doc, nothing else; a missing subsystem Doc or a markdown-linked URL is a finding.
4. `# Useful links` — `## Docs` with every doc URL from the table.
5. Footer.

Subsystem Doc, title `[ari-hemingway scaffold] <Topic> — <Subsystem> [🤖 AI generated]`:
1. `# Summary` — names the subsystem; its second sentence carries the Glossary Doc's raw URL.
2. `# Definitions` — exactly one table: the rows hoisted into this subsystem.
3. One or more `#` sections — the article's headings.
4. `# Useful links` — `## Docs` with every doc URL from the table and the body.
5. Footer.

Any mention of a skill outside the footer is a finding in every kind.

## Definitions table

- Two columns, `Word | Definition`. Word cells are links to canonical documentation when a page exists, plain text otherwise; no fabricated URLs.
- Rows in dependency order: a definition mentions a table term only if that term is an earlier row (whole-word, including plurals and -ed/-ing forms). No self-mention.
- At most 2 sentences of at most 25 words each; what the thing IS comes first; no "etc", "...", "various", "and so on".
- Across a scaffold, 25 to 35 rows expected; more than 50 is a violation. In the folder layout the count is the Glossary rows plus every subsystem's rows, and no row appears in two Docs.
- Literal tokens backticked per `/ari-hemingway--format-gdoc`.
- The reviewer reproduces the mechanical check rather than eyeballing it: dump the rows to JSON and run `zsh $HOME/.claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh --file <rows.json>`; every printed violation is a finding. A subsystem table is dumped as the Glossary rows followed by its own rows, so a hoisted row may lean on a Glossary row and a Glossary row that leans on a hoisted row is a finding.

## Subsystem articles

- Each article (a `##` in the single Doc, a subsystem Doc in the folder layout) is readable alone given its tables: no jargon outside the Glossary rows and its own rows, no reliance on another article's text.
- An article may name another subsystem but MUST NOT describe its internals.
- An article that introduces a term the tables lack is a finding against the tables, not the article.
- A term hoisted into one subsystem Doc but used in another subsystem Doc's prose is a finding against the split: the row belongs in the Glossary.

## Summary

- Written from the accepted tables and articles: every claim in it appears in the body.
- Says nothing about how the scaffold was made; the footer carries the credit.

## Diagram

- At most one image per Doc, directly after its table, per the Diagrams rule in `/ari-hemingway--format-gdoc`: `[![alt](ink_url?width=620)](live_url)`, so the image links to its mermaid.live source. In a single Doc it ties together terms that are all in the table; in the Glossary it is the cluster-level graph whose nodes are the subsystem Docs listed under `# Sub-explainers`.
