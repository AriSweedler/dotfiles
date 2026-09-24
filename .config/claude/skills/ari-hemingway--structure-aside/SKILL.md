---
name: ari-hemingway--structure-aside
description: "Sub-structure for any hemingway draft: move optional content (a manual fallback, a rationale, an edge case, an example list) into an aside the reader opens on purpose. Defines the marker, the `# Aside n:` section, references by title, and what publishing does with them. Google Doc destination only, via /ari-hemingway--share-gdoc."
---

# Asides

An aside is optional content the reader opens on purpose. It lives in its own tab. This is a sub-structure: any `/ari-hemingway--structure-*` draft may use it, and it is never a document shape of its own. Targets a Google Doc.

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns (investigation folder, restore context, drafting, fact-check, present/output): see `/ari-hemingway--lib`. If any rule here appears to contradict `/ari-hemingway--format-gdoc`, the format skill wins.

## When to use

Use an aside for content a first-time reader skips and a second-time reader wants: a manual fallback path, the rationale behind a rule, an edge case, a list of example PRs. Gates (`Do not proceed until…`), expected output, commands on the main path, and anything every reader must read stay in the body. One aside carries one idea; one body sentence carries its marker; one marker per sentence.

## Document structure

Required, per aside:

1. A marker at the end of one body sentence.
2. A `# Aside n: <title>` section after `# Useful links` and before the footer.

Optional: references to the aside from anywhere else in the draft.

## Rules

### Content scope — word count

**An aside body is 15 to 80 words**, counting every word of the section body as written, code lines included, the heading excluded (today's six in the MCR deletion playbook: 14 to 78, median 53). Over 80 words, the content is a section of the main document or a document of its own.

### Marker

Write ` ([aside n ℹ️](#aside-n))` after the sentence's period: parentheses plain, inner text a link whose URL is the anchor `#aside-n`. `n` counts up from 1 in body order. When an aside moves or goes away, renumber all of them in body order; the tabs are rebuilt on publish, so renumbering costs nothing. The anchor is how publishing finds the marker; the inner text is what the reader clicks, so it stays `aside n ℹ️` (blue, underlined, big enough to hit). **The marker is the only place the word `aside` and the emoji appear**: never in a title, never in a reference.

### Section and title

One `# Aside n: <title>` section per marker, after `# Useful links`. The title is plain words (markup is stripped), and **`Aside n: <title>` MUST be at most 50 characters**, the Docs tab-title limit; the publish fails otherwise.

### Body content

Paragraphs, `code` spans, `[text](url)` links (a code span inside the link text stays monospace and linked; bold is dropped), and fenced code blocks (each becomes one shaded Roboto Mono paragraph, like the main tab's native code blocks). A Drive URL is written as a markdown link and becomes a smart chip in the tab. Lists, tables, images, and headings fail the publish by aside number.

### References

Refer to an aside from anywhere else (a body sentence, `# Useful links`, another aside) as `[<title>](#aside-n)`, the text being the title's words; code and bold markup are ignored on both sides. It renders as a plain link to the tab, named like the tab, so it stays searchable; a chip cannot point at a tab. Any other text fails the publish naming the aside and the text.

### What publishing does

`/ari-hemingway--share-gdoc` moves each section into a tab titled `Aside n: <title>`, points the marker and every reference at the tab, and opens and closes the tab with an italic `← Return to main article` link set off by a rule. The return link lands on the heading above the marker, or on the marker itself when `/ari-hemingway--structure-bookmark` is set up. The publish fails, naming the aside, on: a marker without a section or a section without a marker, an empty section, a reference whose text is not the title, a title over the limit, or unsupported body content. Tabs are rebuilt on every publish, because the markdown re-import deletes every tab but the first; the mechanics are share-gdoc's.

### Caveats

**The saved draft is the source of truth.** `/ari-gsw-doc-to-md --tab t.0` returns the main tab only: the aside tabs never come back as sections and the markers come back as plain text, so a draft rebuilt from the Doc republishes with no asides and nothing fails. Edit `output.md` and republish; never rebuild a draft from a Doc that has asides. Asides hide in the editor and viewer only: a PDF export prints every tab.

### Destinations

Google Doc only. Slack, PR description, and markdown have no aside form; write the content inline or leave it out.

### Examples

A complete aside, after `# Useful links`:

```markdown
# Aside 3: Manual cleanup

Run this grunt task once per region, with the `STAGE`, `REGION` and `SERVICE_NAME` you exported in Step 2.

```
grunt eks:deleteServiceClusterConfigTombstones --stage=$STAGE --region=$REGION --serviceName=$SERVICE_NAME
```

Expected output: the task exits 0 and `hyperbase_app.serviceDeploymentConfig` returns no items for `$SERVICE_NAME`.
```

- GOOD: `Once that merges, wait one week for the report card to clear your deleted rows. ([aside 3 ℹ️](#aside-3))` with the section above.
- GOOD: `The grunt path is in [Manual cleanup](#aside-3).` — a reference, named like the tab, from the body or from another aside.
- BAD: `rows.[aside 3 ℹ️](#aside-3)` — no space, no parentheses, so the link glues to the sentence.
- BAD: `(see [manual cleanup](#aside-3))` — neither the marker form nor the title's words.
- BAD: `see [Aside 3: Manual cleanup](#aside-3)` — a reference carries the title only, never the `Aside n:` prefix.
- BAD: a `# Aside 3:` section with no `#aside-3` marker in the body — the publish fails.
- BAD: `Do not proceed to Step 3 until every row reads deleted. ([aside 2 ℹ️](#aside-2))` with the gate's details in the aside — a gate stays in the body.

## Investigation folder

None of its own. An aside is drafted inside a host `/ari-hemingway--structure-*` skill, whose folder under `/ari-hemingway--lib` holds everything.

## Workflow

This skill runs inside the host skill's `Draft` step; there is no standalone mode. Fact-check, Present, and Output are the host's per `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`: an aside's claims meet the same standard as the body's, the Present line names the asides and their word counts, and the sections travel inside `output.md` for `/ari-hemingway--share-gdoc` to turn into tabs.

### Draft

While drafting the host document per `Drafting` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, decide per paragraph whether it is main path or aside (see When to use), place the marker, and write the section after `# Useful links`. **An aside body is 15 to 80 words. Count them before moving on.** Start from the saved draft, never from the Doc.
