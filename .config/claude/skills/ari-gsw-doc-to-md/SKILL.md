---
name: ari-gsw-doc-to-md
description: Convert a Google Doc — or one tab of it (?tab=<id>) — into readable markdown, preserving headings, lists, tables, links, smart chips (rich-link/person/date), and inline images, via a deterministic Python converter. Use when you need a Google Doc as markdown to read or diff. For a folder of docs, use /ari-gsw-read.
---

# Google Doc to Markdown

Turn a Google Doc (or one of its tabs) into a local markdown file you Read. The conversion lives in a checked-in Python script, so the same document always yields the same markdown; `--json-file` re-converts a saved fetch with no network call.

The converter (worker) of the `ari-gsw` family. For a Drive folder, or to fan a multi-tab doc out into one file per tab, use the `/ari-gsw-read` dispatcher — it expands a source into per-tab links and calls this converter per link.

## When to use

Use this for ANY "give me / read / diff this Google Doc (or this tab) as markdown" request. Do NOT hand-roll the conversion — no `gws docs … | jq`, no ad-hoc Docs-JSON parsing, no browser copy-paste. The checked-in converter is the only supported path; anything else drops smart chips, tables, and inline images.

## Input

`source` — a Google Doc URL or bare document ID. A `?tab=<id>` in the URL selects one tab (so the expander's output Just Works). Fetching needs the `gws` CLI authenticated (see `/gws-docs`); the script invokes it for you, so never reimplement Google auth or fetch the doc another way.

## Tabs

This worker renders exactly **one tab → one file**. The fetch always includes tab content:
- **`?tab=<id>` in the URL (or `--tab <id>`)** → render exactly that tab.
- **No tab, single-tab doc** → render it.
- **No tab, multi-tab doc** → error listing the tabs. Pick one with `--tab`, or use `/ari-gsw-read` to expand the doc into one file per tab.

Output names carry a common per-doc prefix: `<doc-slug>__<tab-slug>.md` (single-tab docs: `<doc-slug>.md`), so all tabs of one doc group together.

## Workflow

1. Run the converter:
   ```zsh
   zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh "<source>" [--tab ID] [--out PATH] [--stdout] [--force]
   ```
2. It prints the output file path to **stdout** (logs go to stderr).
3. **ALWAYS Read that stdout path before responding.** The script only writes the file — you have not seen the doc until you Read it. Do not summarize, quote, or answer from the path alone.

Worked run:
```
$ zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh "https://docs.google.com/document/d/1AbC.../edit"
[INFO] fetching | doc_id='1AbC...'              (stderr)
[INFO] wrote markdown | path='my-doc.md' ...    (stderr)
my-doc.md                                        (stdout — Read this)
```

### Flags

- **default** (no flag): fetch + write a `.md` to CWD (`<title-slug>.md`, or `<title-slug>__<tab-slug>.md` when one tab is selected), then Read it. Pass `--out` to a scratch path (e.g. `/tmp/...`) if you don't want a file in the repo tree.
- `--tab ID`: render one tab by id (overrides any `?tab=` in the source URL).
- `--out PATH`: pin the output file. If PATH is a directory (or ends with `/`), write the default `<doc-slug>__<tab-slug>.md` name inside it — how the dispatcher keeps a doc's tabs grouped by prefix.
- `--stdout`: print markdown, leave no file (prefer when you only need to read it once).
- `--force`: overwrite an existing output file. Without it the script refuses to clobber.
- `--json-file PATH`: re-convert a saved fetch offline — use when iterating on output or avoiding a re-fetch. Capture (with tabs) then replay:
  ```zsh
  gws docs documents get --params '{"documentId":"1AbC...","includeTabsContent":true}' --format json > doc.json
  zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh --json-file doc.json --tab t.0 --stdout
  ```
  Each fetch is also auto-saved to `/tmp/ari-gsw-doc-to-md/<doc_id>.json` for this.

## Output contract

| Docs construct | Markdown |
|---|---|
| TITLE / HEADING_1 … HEADING_6 | `#` … `######` |
| bold / italic / monospace font | `**` / `*` / `` ` `` |
| bulleted vs ordered list (by glyph) | `-` vs `1.`, indented 2 spaces per nesting level |
| link | `[text](url)` (adjacent same-URL runs coalesced into one link) |
| rich-link (doc/drive/url) chip | `[title](url)` |
| person chip | `name <email>` |
| date chip | display text (e.g. `Jul 8, 2026`) |
| table | GitHub pipe table, `\|` escaped in cells |
| inline image | `![alt](contentUri)` |

Dropped (not representable / not content): autoText, pageBreak, columnBreak, footnoteReference, equation, sectionBreak, tableOfContents, and nested tables inside cells (replaced with `[nested table omitted]`). Treat their absence as expected, not a bug.

Inline-image `contentUri` values are Google URLs that expire (minutes-to-hours). They render but will 404 later — re-run the converter for fresh URLs.

## Recovery

- Missing-prereq or gws-auth error → run `/gws-docs` setup, confirm `gws docs documents get` works, re-run. Do not fetch the doc another way.
- Timeout / transient fetch failure → retry once; on persistent auth failure, stop and tell the user to re-auth.
- Iterating on output → re-run with `--json-file` against the auto-saved `/tmp` JSON to skip the network.

## Files

- `bin/doc-to-md.zsh` — entrypoint: checks prerequisites, runs the converter under a wall-clock cap.
- `bin/doc_to_md.py` — the converter (fetch, parse, emit).
