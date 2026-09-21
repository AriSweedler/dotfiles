---
name: ari-hemingway--share-gdoc
description: "Publish a markdown draft as a Google Doc in one command — create, optionally inside a given Drive folder, or update an existing doc in place — and finish it: every Drive link a smart chip, table header rows styled (bold, centered, grey), every table's columns sized so it is shortest with no mid-word breaks, every image checked to fit one page and to link to its mermaid.live source. Dry-runs first; the doc is created only on confirm."
---

# Publish to Google Doc

Turn a finished `output.md` (or any draft that follows `/ari-hemingway--format-gdoc`) into a Google Doc with one script call: import the markdown through Drive's Docs conversion, into the caller's Drive folder when `--folder` is given, apply one fix-up batch for what markdown cannot express, then verify from one re-read. The fix-up is part of publishing, never a follow-up.

## Rules

- **Every Drive link becomes a smart chip.** Drive's markdown import lands a raw `docs.google.com` or `drive.google.com` URL as a plain hyperlink, not a chip. The fix-up batch converts each one with the Docs API `insertRichLink` request (present since April 2026): `deleteContentRange` over the link text, then `insertRichLink` at the same index with `richLinkProperties.uri` only, since the server resolves the title and rejects `title` or `mimeType`. Requests run in descending index order so earlier indexes stay valid, and every target is pre-checked with `drive files get`, because one unreadable target fails the whole atomic batch. The verify read fails the publish if any Drive URL is still a plain link. A markdown-linked Drive URL is not converted, which is why `/ari-hemingway--format-gdoc` keeps them raw.
- **Table header rows** become bold, centered, and grey (`#D9D9D9`) in the same batch. The row is already pinned: Drive's markdown import sets `tableRowStyle.tableHeader` on every table's first row, and the PDF export repeats it on each page the table spans. The verify read checks that flag on every table and fails when it is missing.
- **Every table takes the column widths that make it shortest, and no column is narrower than its widest token.** `bin/gdoc_table_widths.zsh` predicts each cell's wrapped line count from Arial and Roboto Mono metrics (bold for the header row), sets each column's floor at its widest unbreakable token plus padding so nothing breaks mid-word, then searches whole-point transfers between every pair of columns for the fewest lines; ties move width toward the earlier column so terms stay on one line where that is free. Every column is set `FIXED_WIDTH` in the same batch. `--table-widths START:w1,w2,...` on `gdoc_finish.zsh` replaces the model for one table and is logged.
- **A table that cannot fit fails the finish step; nothing is guessed.** When the column floors sum past the text width, the Doc is still created, the log names the table, the deficit in points and the widest token per column, and the exit is non-zero. Fold a column or shorten the token in the draft and re-run with `--doc`.
- **Images are checked, not fixed.** Every inline image must fit the page content box and link to `https://mermaid.live/view#...` (the fullscreen form, not `/edit#`); the Diagrams rule in `/ari-hemingway--format-gdoc` says how to author that, and the verify read fails otherwise.
- **Layout is measured from the PDF export.** The Docs API reports no geometry, so after every publish the finish step exports the doc to PDF, logs the page count and every table's rendered height in points beside the model's prediction for the widths the doc now has, and warns when they differ by more than one and a half lines (a single extra wrapped line is model rounding, not a layout problem). Pass `--render-pages DIR` to also get one PNG per page (PDFKit through `swift`, nothing to install) when wrapping needs a look, since heights alone do not show a mid-word break.
- **One read, one batch, one read.** The batch is pinned to the revision it was built from (`writeControl.requiredRevisionId`), so a concurrent edit fails the batch instead of corrupting the doc.

## Preconditions

- `gws` CLI installed and authenticated for the user's @airtable.com account (`/gws-docs` covers setup). `jq` and `python3` installed.
- The draft's first line is the plain-text title (starting with `[🤖 AI generated]` per `/ari-hemingway--format-gdoc`). The script strips that line from the body and uses it as the Doc title; pass `--title` to override and keep the whole file as body.
- Updating in place (`--doc`) replaces the entire body. Manual edits in the Doc are lost. Say so before updating a doc the user has touched.
- Docs and folders in shared drives work: the script sets `supportsAllDrives`. A Drive 404 on a doc or folder the user can open therefore means the id is wrong, not that it moved.
- `--folder <id|url>` creates the Doc inside that folder (a bare id or a `drive.google.com/drive/folders/…` URL). The script first checks that the target exists, is a folder, and accepts new files. The Doc is placed at creation and never moved, so `--folder` together with `--doc` is an error.

## File storage

- `bin/gdoc_publish.zsh` — the one-shot publish: create or update, then finish. Prints the doc URL on stdout.
- `bin/gdoc_finish.zsh` — the finishing half, runnable alone on any doc: the fix-up batch (chips, header styles, column widths) and the verify read (image fit, image link, no plain Drive link, header rows pinned, every table fits, page count, table heights against the model). `--check-only` runs the verify read and changes nothing; `--table-widths` overrides one table's widths; `--render-pages DIR` renders the export. Exit is non-zero on any failed check.
- `bin/gdoc_table_widths.zsh` (+ `gdoc_table_widths.py`, per `/ari-skill-pythonscripts`) — the column-width planner for tables of any column count: one JSON line per table with the current and best widths, modeled line counts, predicted heights, the widest token per column, and whether the table can fit at all. Read-only; `gdoc_finish.zsh` calls it before the batch and again for the verify read.
- `bin/gdoc_table_heights.zsh` — measures every table in a PDF exported from Docs from the cell clip rectangles the export draws: rendered height in points per table, summed across pages, with and without the header row Docs repeats on each page. `gdoc_finish.zsh` calls it; run it by hand on a before and after export to judge a change.
- `bin/gdoc_render_pages.zsh` (+ `gdoc_render_pages.swift`) — renders a PDF export to one PNG per page with PDFKit; needs `swift` from the Xcode command line tools and nothing from brew.

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

`gdoc_finish.zsh` runs inside Publish; nothing to emit. Read its log: one `Applied fix-up batch` line, one `Table columns resized`, `Table columns kept`, or `Table columns overridden` line per table, then the verify lines, ending with one `Rendered table` line per table that carries `predicted_pt` and `drift_pt`. A non-zero exit after "Doc created" means a check failed: an image wider or taller than one page, an image whose link is not the `mermaid.live/view#` form, a Drive link the chip pass could not convert (a target the caller cannot open, or a non-Drive URL styled as one), or a `Table cannot fit the text width` line naming the deficit and the widest token per column. The doc exists at that point; record its URL, fix the draft per `/ari-hemingway--format-gdoc` (for an unfit table: fold a column, or shorten or split the named token), and re-run with `--doc <url>`. A `Rendered table drifts from the model` warning means the layout differs from the prediction by more than one and a half lines; re-run with `--check-only --render-pages <dir>` and look at the page before touching widths by hand.

### Report

Relay the URL the script printed, as a raw `docs.google.com` URL. There is no manual step: header rows are pinned by the import and verified by the script. If the draft has its own hemingway investigation folder, record the URL in its `scratchpad.md`.

### Re-check an existing doc

To verify a doc someone edited by hand, or to redo the fix-up after manual table edits:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh --doc <id|url> --check-only
```

Drop `--check-only` to apply the fix-up batch. Both are idempotent: a chip is not a plain link, so a second run finds nothing to convert, and a table already at its planned widths is kept. Add `--render-pages <dir>` to either form to inspect the rendered pages.

### Measure a change

Export before and after, then compare table heights in points:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_heights.zsh --pdf <path/to/export.pdf>
```

One JSON line per table: `pages`, `rows`, `cols`, `height_pt` as printed, and `content_height_pt` without the repeated header rows. A row Docs splits across a page break counts once per page, so `rows` can exceed the true count; the heights are exact.
