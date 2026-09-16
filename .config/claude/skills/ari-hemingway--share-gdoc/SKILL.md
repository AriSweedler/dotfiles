---
name: ari-hemingway--share-gdoc
description: "Publish a markdown draft as a Google Doc in one command — create, optionally inside a given Drive folder, or update an existing doc in place — and finish it: every Drive link a smart chip, table header rows styled (bold, centered, grey), two-column tables at their shortest split, every image checked to fit one page and to link to its mermaid.live source. Dry-runs first; the doc is created only on confirm."
---

# Publish to Google Doc

Turn a finished `output.md` (or any draft that follows `/ari-hemingway--format-gdoc`) into a Google Doc with one script call: import the markdown through Drive's Docs conversion, into the caller's Drive folder when `--folder` is given, apply one fix-up batch for what markdown cannot express, then verify from one re-read. The fix-up is part of publishing, never a follow-up.

## Rules

- **Every Drive link becomes a smart chip.** Drive's markdown import lands a raw `docs.google.com` or `drive.google.com` URL as a plain hyperlink, not a chip. The fix-up batch converts each one with the Docs API `insertRichLink` request (present since April 2026): `deleteContentRange` over the link text, then `insertRichLink` at the same index with `richLinkProperties.uri` only, since the server resolves the title and rejects `title` or `mimeType`. Requests run in descending index order so earlier indexes stay valid, and every target is pre-checked with `drive files get`, because one unreadable target fails the whole atomic batch. The verify read fails the publish if any Drive URL is still a plain link. A markdown-linked Drive URL is not converted, which is why `/ari-hemingway--format-gdoc` keeps them raw.
- **Table header rows** become bold, centered, and grey (`#D9D9D9`) in the same batch. Pinning the header row stays manual: `tableHeader` is read-only in the API.
- **Two-column tables take the split that makes them shortest.** `lib/table_widths.jq` predicts each cell's wrapped line count from Arial metrics and tries every whole-point split of the text width; ties go to the widest first column so terms stay on one line where that is free. Both columns are set `FIXED_WIDTH` in the same batch.
- **Images are checked, not fixed.** Every inline image must fit the page content box and link to `https://mermaid.live/edit#...`; the Diagrams rule in `/ari-hemingway--format-gdoc` says how to author that, and the verify read fails otherwise.
- **Layout is measured from the PDF export.** The Docs API reports no geometry, so after every publish the finish step exports the doc to PDF and logs the page count and every table's rendered height in points. Judge a width change by that, not by the model.
- **One read, one batch, one read.** The batch is pinned to the revision it was built from (`writeControl.requiredRevisionId`), so a concurrent edit fails the batch instead of corrupting the doc.

## Preconditions

- `gws` CLI installed and authenticated for the user's @airtable.com account (`/gws-docs` covers setup). `jq` and `python3` installed.
- The draft's first line is the plain-text title (ending `[🤖 AI generated]` per `/ari-hemingway--format-gdoc`). The script strips that line from the body and uses it as the Doc title; pass `--title` to override and keep the whole file as body.
- Updating in place (`--doc`) replaces the entire body. Manual edits in the Doc are lost, including "Pin header row". Say so before updating a doc the user has touched.
- Docs and folders in shared drives work: the script sets `supportsAllDrives`. A Drive 404 on a doc or folder the user can open therefore means the id is wrong, not that it moved.
- `--folder <id|url>` creates the Doc inside that folder (a bare id or a `drive.google.com/drive/folders/…` URL). The script first checks that the target exists, is a folder, and accepts new files. The Doc is placed at creation and never moved, so `--folder` together with `--doc` is an error.

## File storage

- `bin/gdoc_publish.zsh` — the one-shot publish: create or update, then finish. Prints the doc URL on stdout.
- `bin/gdoc_finish.zsh` — the finishing half, runnable alone on any doc: the fix-up batch (chips, header styles, column widths) and the verify read (image fit, image link, no plain Drive link, page count, table heights). `--check-only` runs the verify read and changes nothing. Exit is non-zero on any failed check.
- `bin/gdoc_table_heights.zsh` — measures every table in a PDF exported from Docs from the cell clip rectangles the export draws: rendered height in points per table, summed across pages, with and without the header row Docs repeats on each page. `gdoc_finish.zsh` calls it; run it by hand on a before and after export to judge a change.
- `lib/table_widths.jq` — the column-width model.

## Workflow

### Dry-run

Emit exactly this one Bash call (add `--doc <id|url>` to update an existing doc, or `--folder <id|url>` to create inside a Drive folder):

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md> --dry-run
```

It logs the title, the body size, and the target folder's name and id when `--folder` is given, then validates the Drive request without creating anything. Show the user the title, whether this is a create or an update, and the folder, then wait for confirmation.

### Publish

Same call without `--dry-run`, keeping `--doc` or `--folder`:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md>
```

The script creates (or updates) the doc, then runs `gdoc_finish.zsh` on it.

### Chip, style, and resize

`gdoc_finish.zsh` runs inside Publish; nothing to emit. Read its log: one `Converted Drive links to chips` or `Applied fix-up batch` line, one `Table columns resized` or `Table columns kept` line per two-column table, then the verify lines. A non-zero exit after "Doc created" means a check failed: an image wider or taller than one page, an image with no mermaid.live link, or a Drive link the chip pass could not convert (a target the caller cannot open, or a non-Drive URL styled as one). The doc exists at that point; record its URL, fix the draft per `/ari-hemingway--format-gdoc`, and re-run with `--doc <url>`.

### Report

Relay the URL the script printed, as a raw `docs.google.com` URL. State the one manual step: the Docs API cannot pin a header row (`tableHeader` is read-only), so the user pins it via Format > Table > Pin header row if they want it repeating across pages. Then, if the draft has its own hemingway investigation folder, record the URL in its `scratchpad.md`.

### Re-check an existing doc

To verify a doc someone edited by hand, or to redo the fix-up after manual table edits:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh --doc <id|url> --check-only
```

Drop `--check-only` to apply the fix-up batch. Both are idempotent: a chip is not a plain link, so a second run finds nothing to convert.

### Measure a change

Export before and after, then compare table heights in points:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_heights.zsh --pdf <path/to/export.pdf>
```

One JSON line per table: `pages`, `rows`, `cols`, `height_pt` as printed, and `content_height_pt` without the repeated header rows. A row Docs splits across a page break counts once per page, so `rows` can exceed the true count; the heights are exact.
