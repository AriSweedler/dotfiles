---
name: ari-gsw-read
description: Read any Google Workspace source as markdown — a Drive folder or a Google Doc (all tabs). Expands the source into per-tab doc links, then dispatches each to the right converter. Use when you need a folder of docs, or a multi-tab doc, as markdown.
---

# Google Workspace Read

Read a Drive folder or a Google Doc (all tabs) as markdown. Entrypoint of the `ari-gsw` family: it **expands** a source into per-tab links, then dispatches each to the `/ari-gsw-doc-to-md` converter, which owns all rendering.

## When to use

Use for a folder of docs or a multi-tab doc. A plain `/ari-gsw-doc-to-md` call sees only the first tab, so route whole docs through here. Call the converter directly only when the user wants one specific tab and the URL already carries `?tab=<id>`.

| Source | Action |
| --- | --- |
| `.../folders/<id>` | folder of docs → this skill |
| `.../document/d/<id>/edit` | whole doc, all tabs → this skill |
| `.../document/d/<id>/edit?tab=<id>` | one known tab → call `/ari-gsw-doc-to-md` directly |

Passing a `?tab=` URL to the expander re-expands every tab — it classifies by doc, not tab.

## Input

`source` — a Drive folder URL, a Google Doc URL, or a bare id. A bare or `?id=` id is resolved by Drive mimeType; a `/folders/` or `/document/` URL is unambiguous. Requires an authenticated `gws` CLI (see `/gws-docs`); the scripts invoke it.

## Workflow

### Expand the source into per-tab links

The script is self-contained — it creates the working directories and records the links itself, so emit exactly this one call with no setup commands around it:

```zsh
zsh $HOME/.claude/skills/ari-gsw-read/bin/expand.zsh "<source>"
```

- Writes one tab URL per line (`.../document/d/<id>/edit?tab=<tabId>`) to `/tmp/ari-gsw-read/links.txt`, echoing them on stdout; creates `/tmp/ari-gsw-read/out/` for the converter step. stderr: per-doc/tab discovery.
- Folder → every Google Doc inside (non-recursive, Docs only) × every tab. Doc → every tab.
- A doc with no tabs emits a plain `/edit` line (no `?tab=`). That line is its renderable unit — convert it like any other; do not skip it, and do not invent extra URLs of your own.

Report scope before converting: `wc -l < /tmp/ari-gsw-read/links.txt`. Above ~15 links, tell the user the count (N docs → M files) and confirm before continuing.

### Convert every tab link

Convert EVERY line — not a sample, not one per doc. Pass the SAME `--out` directory to every call, so a doc's tabs group together (the converter names files `<doc-slug>__<tab-slug>.md`):

```zsh
while IFS= read -r url; do
  zsh $HOME/.claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh "$url" --out /tmp/ari-gsw-read/out/ --force
done < /tmp/ari-gsw-read/links.txt
```

`--force` lets a re-run overwrite stale output. You may run calls in parallel to go faster; parallelism is optional, converting every link is not. See `/ari-gsw-doc-to-md` for the markdown output contract.

Verify completeness — the file count must equal the link count:

```zsh
[ "$(ls /tmp/ari-gsw-read/out/*.md | wc -l)" = "$(wc -l < /tmp/ari-gsw-read/links.txt)" ] && echo OK || echo SHORTFALL
```

A shortfall means skipped links, or two docs whose titles collided onto one filename — re-convert the missing ones with an explicit `--out <file>`.

### Read every produced file, then report

Running the converter writes a file; it does not show you the content. List the directory and Read every `.md` before you answer — never summarize from the converter's stderr or a filename alone:

```zsh
ls /tmp/ari-gsw-read/out/*.md
```

Then tell the user the output directory and file count, noting `/tmp` is ephemeral (cleared on reboot).

## Example

```
$ zsh $HOME/.claude/skills/ari-gsw-read/bin/expand.zsh "https://drive.google.com/drive/folders/1AbC...Xyz"
# stderr:
[INFO] expanded folder | folder_id='1AbC...Xyz' docs='2' skipped_non_docs='1'
[INFO] expanded doc | doc_id='1Doc...AAA' name='Q3 Planning' tabs='2'
[INFO]   tab | tab_id='t.0' title='Overview'
[INFO]   tab | tab_id='t.aBcD' title='Risks'
[INFO] expanded doc | doc_id='1Doc...BBB' name='Launch Checklist' tabs='1'
[INFO] links recorded | links_file='/tmp/ari-gsw-read/links.txt' count='3'
# /tmp/ari-gsw-read/links.txt (also echoed on stdout):
https://docs.google.com/document/d/1Doc...AAA/edit?tab=t.0
https://docs.google.com/document/d/1Doc...AAA/edit?tab=t.aBcD
https://docs.google.com/document/d/1Doc...BBB/edit?tab=t.0
# after converting, /tmp/ari-gsw-read/out/:
q3-planning__overview.md
q3-planning__risks.md
launch-checklist.md
```

## Recovery

- `gws ... failed` → auth likely expired, or the doc/folder isn't shared with your account; re-run `/gws-docs`, then retry.
- `no Google Docs in folder | ... other_items=...` → the folder holds only the listed non-Doc items (Sheets/Slides/subfolders aren't expanded), or is empty/inaccessible.
- `folder expansion incomplete | failed=N` → some docs couldn't be read; the links file is partial (the named docs were skipped). Convert the rest, then retry the failures individually.
- `expander timed out` → the folder fanned out too far under the 600s cap. Expand individual doc URLs instead of the whole folder.

## Files

- `bin/expand.zsh` — entrypoint: checks prerequisites, creates `/tmp/ari-gsw-read/out/`, runs the expander under a timeout, records `links.txt`.
- `bin/expand_links.py` — classifies the source (by mimeType when ambiguous), lists folder docs, fetches tabs, emits tab URLs.
