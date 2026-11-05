---
name: ari-hemingway--share-gdoc
description: "Publish a markdown draft as a Google Doc in one command — create inside a given Drive folder (else the ARI_HEMINGWAY_SCRATCH_DIR folder), or update an existing doc in place — and finish it: every Drive link a smart chip, table header rows styled (bold, centered, grey), every table's columns sized so it is shortest with no mid-word breaks, every image checked to fit one page and to link to its mermaid.live source, every aside section rebuilt as its own tab. Every script is a dry run unless --execute is on its command line, and --execute runs only after the user replies yes to the dry run: a create, or an update, which replaces the live Doc's whole body."
---

# Publish to Google Doc

Turn a finished `output.md` (or any draft that follows `/ari-hemingway--format-gdoc`) into a Google Doc with one script call: import the markdown through Drive's Docs conversion, into the caller's Drive folder (`--folder`, else `ARI_HEMINGWAY_SCRATCH_DIR`), apply one fix-up batch for what markdown cannot express, then verify from one re-read. The fix-up is part of publishing, never a follow-up. Nothing is written until the call carries `--execute`.

## Rules

- **NEVER put `--execute` on a command until the user has replied yes to that command's dry run.** Without it, `gdoc_publish.zsh`, `gdoc_finish.zsh` and `gdoc_asides.zsh --rebuild` read, plan and validate, log `Dry run: the default`, write nothing and exit 0. Run the dry run, end your turn with its confirm message (**Dry-run**), and add `--execute` in a later turn, after the user's reply. The request that started the publish, a caller skill's "publish", or a yes given before the dry run's output is never that reply. **A `next=` or `rerun=` field in any log is the command for after the user's yes, never your next call.**
  ```
  BAD:  gdoc_publish.zsh --file draft.md --doc <id> --execute                    ← no dry run: replaces the live body
  BAD:  gdoc_publish.zsh --file draft.md --doc <id> && gdoc_publish.zsh … --execute   ← the user never saw the dry run
  GOOD: gdoc_publish.zsh --file draft.md --doc <id>  → confirm message, end turn → user: "yes" → the same call + --execute
  ```
  Mechanics: `/ari-skill-shellscripts` § Mutations (`lib/dry_run.zsh`; `gdoc_asides.py` mirrors it). An executing `gdoc_publish.zsh` passes `--execute` to `gdoc_finish.zsh`, `gdoc_asides.zsh --rebuild` and, when its setup passes, `gdoc_bookmarks.zsh --apply`; the user's yes to the publish's dry run covers those three. It never covers a command you type: a by-hand rebuild or bookmark apply gets its own dry run and its own yes.

- **Every Drive link becomes a smart chip.** Drive's markdown import lands a raw `docs.google.com` or `drive.google.com` URL as a plain hyperlink, not a chip. The fix-up batch converts each one with the Docs API `insertRichLink` request (present since April 2026): `deleteContentRange` over the link text, then `insertRichLink` at the same index with `richLinkProperties.uri` only, since the server resolves the title and rejects `title` or `mimeType`. Requests run in descending index order so earlier indexes stay valid, and every target is pre-checked with `drive files get`, because one unreadable target fails the whole atomic batch. The verify read fails the publish if any Drive URL is still a plain link. A markdown-linked Drive URL is converted too, and its label is deleted with the link text, which is why `/ari-hemingway--format-gdoc` keeps them raw.
- **Table header rows** become bold, centered, and grey (`#D9D9D9`) in the same batch. The row is already pinned: Drive's markdown import sets `tableRowStyle.tableHeader` on every table's first row, and the PDF export repeats it on each page the table spans. The verify read checks that flag on every table and fails when it is missing.
- **Every table takes the column widths that make it shortest, and no column is narrower than its widest token.** `bin/gdoc_table_widths.zsh` predicts each cell's wrapped line count from Arial and Roboto Mono metrics (bold for the header row), sets each column's floor at its widest unbreakable token plus padding so nothing breaks mid-word, then searches whole-point transfers between every pair of columns for the fewest lines; ties move width toward the earlier column so terms stay on one line where that is free. Every column is set `FIXED_WIDTH` in the same batch. `--table-widths START:w1,w2,...` on `gdoc_finish.zsh` replaces the model for one table and is logged.
- **A table that cannot fit fails the finish step; nothing is guessed.** When the column floors sum past the text width, the Doc is still created, the log names the table, the deficit in points and the widest token per column, and the exit is non-zero. Fold a column or shorten the token in the draft, then follow **Recover after a failure**.
- **Code needs no fix-up in the main tab; aside tabs copy its look.** Drive's markdown import lands a fence as a native Docs code block (grey box with a language label in the PDF export; in the document JSON, Roboto Mono paragraphs behind a U+E907 placeholder) and a code span as Roboto Mono in green `#188038`. `gdoc_asides.zsh` fills aside tabs through the API, which cannot insert the code block and sets no colour, so it matches the main tab by hand:
  - a fenced block: one Roboto Mono paragraph, uncoloured, shaded Docs' code-block grey `#F1F3F4`;
  - a code span: Roboto Mono `#188038`;
  - a code span inside link text: Roboto Mono in the link's colour, as the import leaves it.
- **Images are checked, never resized.** Every inline image, in the main tab or an aside tab, must fit the page content box and link to `https://mermaid.live/view#...` (the fullscreen form, not `/edit#`); the Diagrams rule in `/ari-hemingway--format-gdoc` says how to author that, and the verify read fails otherwise.
- **Layout is measured from the PDF export.** The Docs API reports no geometry, so after every publish the finish step exports the doc to PDF, logs the page count and every table's rendered height in points beside the model's prediction for the widths the doc now has, and warns when they differ by more than one and a half lines (a single extra wrapped line is model rounding, not a layout problem). When the log has a `Rendered table drifts from the model` warning, `gdoc_finish.zsh --check-only --render-pages DIR` also writes one PNG per page (PDFKit through `swift`, nothing to install), since heights alone do not show a mid-word break.
- **One read, one batch, one read.** The batch is pinned to the revision it was built from (`writeControl.requiredRevisionId`), so a concurrent edit fails the batch instead of corrupting the doc.
- **Asides become tabs, rebuilt on every publish**, because the markdown re-import deletes every tab but the first and drops tab links. `bin/gdoc_asides.zsh`:
  - strips every `# Aside n:` section (`/ari-hemingway--structure-aside`) out of the body before the upload, and fails the publish there, naming the aside, on anything the rebuild would reject (**Rebuild asides** lists each refusal);
  - after the fix-up batch, finds every marker and reference in the first tab, and only then deletes any tab titled `Aside n:` and adds one tab per section;
  - fills each tab: return link with a bottom border, `Aside n: <title>` as H1, the body with an empty paragraph between blocks as the import lays out the main tab, one empty paragraph, return link with a top border. The return link targets the heading above the marker; the bookmark step moves it onto the marker.
  - chips the tab's Drive links with `insertRichLink` after the same `files.get` pre-check as the main pass, and inserts each diagram with `insertInlineImage`, linked to its mermaid.live view;
  - points the marker, and each reference whose text is the aside's title, at the tab;
  - pins both batches to the revision they were built from, then verifies: no plain Drive link, and every planned image present, inside the page, with its own view link.

  A diagram is a line holding only the `/ari-hemingway--format-gdoc` form `[![alt](https://mermaid.ink/img/base64:…?width=620)](https://mermaid.live/view#…)`. Its alt text is dropped (the Docs API has no request for it). `insertInlineImage` takes at most a 2 kB URI, so a longer `base64:` URL is re-encoded in mermaid.ink's `pako:` form of the same diagram; the draft keeps the URL bake printed.
  ```
  GOOD: [![Request flow](https://mermaid.ink/img/base64:eyJj…?width=620)](https://mermaid.live/view#pako:eNp…)
  BAD:  ![Request flow](https://mermaid.ink/img/base64:eyJj…)           ← no view link
  BAD:  See [![Request flow](…)](…) for the flow.                       ← not alone on its line
  BAD:  ```mermaid                                                       ← publishes as source text; bake it
  ```
- **Bookmarks come last, when their setup passes.** After a clean finish and asides rebuild, and only when the draft has an aside or a `#bm-`/`#goto-` link, `gdoc_publish.zsh` runs `/ari-hemingway--structure-bookmark`'s read-only `gdoc_bookmarks.zsh --check-setup`. When every prerequisite is `OK`, it runs `--apply --execute`, which bookmarks every `[text](#bm-<slug>)` run and aside marker through Apps Script and points every `[text](#goto-<slug>)` link and aside return link at the bookmark. The publish's yes covers it because the body replace has already dropped every bookmark. The dry run runs the same setup check and reports `bookmarks='would-apply'`, `'skipped'`, `'check-failed'` or `'none'`. Bookmarks die on republish like tabs.

## Preconditions

- `gws` CLI installed and authenticated for the user's Google Workspace account (`/gws-docs` covers setup) with the `documents` and `drive` scopes. `gws auth login` replaces the token's whole scope set on every run, so a login for another service drops them; `gdoc_publish.zsh` and `gdoc_finish.zsh` check first and fail with the `gws auth login --scopes …` command that restores every scope. `jq`, `python3` and `strings` installed.
- The draft's first line is the plain-text title (starting with `[🤖 AI generated]` per `/ari-hemingway--format-gdoc`). The script strips that line from the body and uses it as the Doc title; pass `--title` to override and keep the whole file as body.
- Updating in place (`--doc`) replaces the entire body and drops every tab but the first; manual edits in the Doc are lost. `gdoc_publish.zsh` reads the target first, dry run or not, and fails before any upload when it is not a Google Doc the caller can edit.
- Docs and folders in shared drives work: the script sets `supportsAllDrives`. A Drive 404 on a doc or folder the user can open therefore means the id is wrong, not that it moved.
- A new Doc always lands in a folder: `--folder <id|url>` (a bare id or a `drive.google.com/drive/folders/…` URL), else `ARI_HEMINGWAY_SCRATCH_DIR` in the same forms, logged as `folder from ARI_HEMINGWAY_SCRATCH_DIR`. With neither set the script exits non-zero naming both; ask the user for a folder then. The script first checks that the target exists, is a folder, and accepts new files. The Doc is placed at creation and never moved, so `--folder` together with `--doc` is an error.

## File storage

- `bin/gdoc_publish.zsh` — the one-shot publish: with `--execute`, create or update, then finish, and print the doc URL on stdout; without it, the dry run.
- `bin/gdoc_finish.zsh` — the finishing half, runnable alone on any doc: the fix-up batch (chips, header styles, column widths), sent only with `--execute`, and the verify read (image fit, image link, no plain Drive link, header rows pinned, every table fits, page count, table heights against the model). Without `--execute` the batch is validated locally and the checks read the unchanged doc, a failure logged as a `WARN`; `--check-only` builds no batch; `--table-widths` overrides one table's widths; `--render-pages DIR` renders the export. Exit is non-zero on any failed check, except on a dry run.
- `bin/gdoc_table_widths.zsh` (+ `gdoc_table_widths.py`, per `/ari-skill-pythonscripts`) — the column-width planner for tables of any column count: one JSON line per table with the current and best widths, modeled line counts, predicted heights, the widest token per column, and whether the table can fit at all. Read-only; `gdoc_finish.zsh` calls it before the batch and again for the verify read.
- `bin/gdoc_table_heights.zsh` — measures every table in a PDF exported from Docs from the cell clip rectangles the export draws: rendered height in points per table, summed across pages, with and without the header row Docs repeats on each page. `gdoc_finish.zsh` calls it; run it by hand on a before and after export to judge a change.
- `bin/gdoc_render_pages.zsh` (+ `gdoc_render_pages.swift`) — renders a PDF export to one PNG per page with PDFKit; needs `swift` from the Xcode command line tools and nothing from brew.
- `bin/gdoc_asides.zsh` (+ `gdoc_asides.py`, per `/ari-skill-pythonscripts`; the Docs helpers it shares with `/ari-hemingway--structure-bookmark` live in `ari-hemingway--lib/lib/gdoc_api.py`) — `--split` writes the draft without its aside sections after checking markers, sections, references, and tab-title length; `--rebuild` deletes stale `Aside n:` tabs, adds and fills one per section, chips their Drive links, and links every marker and reference. `--doc` takes an id or URL. `gdoc_publish.zsh` runs both; after any other body replace, rebuild per **Re-check an existing doc**. `--rebuild` without `--execute` prints the batches and sends nothing; `--first-tab-title` renames the first tab, which the import resets to `Tab 1`. The bookmark step lives in `/ari-hemingway--structure-bookmark`.
- `tests/gdoc_asides.test.zsh` — runs `gdoc_asides.zsh` against a fake `gws` on `PATH` (no network, no Doc; needs `jq`, `base64` and `node`): the split's refusals, the fill batch's images, chips, pako re-encoding and code styles, the lookups before any batch, and the verify read's image checks. Its `draft.md` heredoc is a worked diagram aside.
- `tests/gdoc_dry_run.test.zsh` — runs the three writing scripts against a fake `gws` that records every call, in a throwaway `HOME` (needs `jq` and `python3`): no flag, `--dry-run`, both flags in either order, and an inherited `DRY_RUN` send no write, for an update and a create; `--execute` creates one Doc in the folder or updates the named one, and its children write; a target that is not a Doc, or a title-only draft, fails before any upload; a header-cell Drive link is chipped after every style. A fake bookmark skill shows that an executing publish checks the setup and then applies with `--execute`, that a dry run only checks, and that a missing setup is a skip. A crashed check, a failed apply, an apply that dry-ran, or a failed finish fails the publish; a skill without `--execute` and a draft with nothing to bookmark are never called.

**After ANY change to a `bin/` script or `ari-hemingway--lib/lib/gdoc_api.py`, both tests MUST pass: exit 0 and a last line of `pass=N fail=0`.**

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/tests/gdoc_asides.test.zsh
```

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/tests/gdoc_dry_run.test.zsh
```

## Workflow

### Dry-run

A `Published: <url>` line in a `scratchpad.md` beside the draft makes this an update: pass `--doc <that url>`. Otherwise it is a create. Emit exactly one Bash call, with no `--execute`. A create (drop `--folder` to use `ARI_HEMINGWAY_SCRATCH_DIR`):

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md> --folder <id|url>
```

An update in place:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md> --doc <id|url>
```

An update's log:

```
[INFO] Dry run: the default; nothing will change
[INFO] Using first line as title; stripped from body | title='[🤖 AI generated] Request flow'
[INFO] Staged body | title='[🤖 AI generated] Request flow' body='/tmp/gdoc_publish.Ab12cd/body.md' bytes='8421' asides='1'
[INFO] Doc to replace; its whole body and every tab but the first go | doc='1AbC' name='Request flow' modified='2026-11-05T09:00:00Z' modified_by='Ari'
[INFO] Bookmarks would be applied after the asides rebuild | setup='OK'
[OK] Dry run valid; nothing written | would='update' title='[🤖 AI generated] Request flow' doc='1AbC' folder='' folder_name='' asides='1' bookmarks='would-apply' next='…'
```

A create logs `Target folder | folder= name=` in place of `Doc to replace`, and `would='create'`. A create with neither folder source exits non-zero before any Drive call; ask the user for a folder and re-run. **Then end your turn with one confirm message, filled from the log:**

```
GOOD (create): Dry run: would create "<title>" in <folder_name> (from <--folder | ARI_HEMINGWAY_SCRATCH_DIR>). Publish it?
GOOD (update): Dry run: would replace the whole body of "<name>" (<url>), last edited <modified> by <modified_by>; manual edits and every tab but the first are lost. Publish over it?
GOOD (bookmarks='skipped', added to either): Bookmarks would be skipped (<missing>): #goto- links and aside return links stay on headings.
BAD:           Doc created (dry run).        ← nothing was created; would= is the plan
```

### Publish

**Only after the user replied yes to the confirm message.** Re-send the dry run's exact command plus `--execute`, changing nothing else, with the Bash tool's `timeout` at `600000` (a publish with asides and bookmarks can outrun the two-minute default):

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md> --folder <id|url> --execute
```

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md> --doc <id|url> --execute
```

The script creates or updates the doc and logs `Doc created` or `Doc updated` with its `url=`, then runs `gdoc_finish.zsh --execute`, `gdoc_asides.zsh --rebuild --execute` and the bookmark step on it, and prints the URL on stdout.

### Chip, style, and resize

`gdoc_finish.zsh` runs inside Publish; nothing to emit. Read its log: one `Applied fix-up batch` line (`Nothing to fix up` for a doc with no tables and no Drive links), one `Table columns resized`, `Table columns kept`, or `Table columns overridden` line per table, then the verify lines, ending with one `Rendered table` line per table that carries `predicted_pt` and `drift_pt`. A non-zero exit from `gdoc_finish.zsh` after `Doc created` or `Doc updated` means a check failed: an image wider or taller than one page, an image whose link is not the `mermaid.live/view#` form, a Drive link the chip pass could not convert (a target the caller cannot open, or a non-Drive URL styled as one), or a `Table cannot fit the text width` line naming the deficit and the widest token per column. The doc exists at that point; fix the draft per `/ari-hemingway--format-gdoc` (for an unfit table: fold a column, or shorten or split the named token) and follow **Recover after a failure**. A `Rendered table drifts from the model` warning means the layout differs from the prediction by more than one and a half lines; run `gdoc_finish.zsh --doc <url> --check-only --render-pages <dir>` and look at the page before touching widths by hand.

### Rebuild asides

`gdoc_asides.zsh --rebuild` runs inside Publish after the fix-up; nothing to emit. A clean run logs, per section:

```
[INFO] aside section split out | n='1' title='Architecture' marker='aside 1 ℹ️' blocks='3' body_references='0' drive_links='1' images='1'
[INFO] aside image URL re-encoded as pako | n='1' bytes='3554' pako_bytes='1310' max='2048'
[INFO] stale aside tab deleted | tab='t.4f1q' title='Aside 1: Architecture'
[INFO] aside tab rebuilt | n='1' title='Architecture' tab='t.x9k2' return='heading' chips='1' images='1' body_references='0' marker_range='211-221'
```

The pako line is INFO, not a problem; a stale-tab line appears only on a republish. A dry run logs `would delete stale aside tab` and `would rebuild aside tab` instead. `No asides to rebuild` means the draft has none. A failure names the aside; what to do depends on when it failed:

- **Before upload** (the split, also run by the dry-run): nothing was created; fix the draft and re-run the same command.
  - `markers and aside sections do not pair up`, `reference text must be the aside title`, `aside tab title too long` (50 characters)
  - `unsupported content in aside`: a list, a table, a `##` heading, or `kind='image'`, an image that is not the diagram line
  - `aside image does not link to its mermaid.live view`, `aside image is not a mermaid.ink render`, `aside image type is not one Docs inserts`, `aside image needs a width inside the page`: re-bake with `/ari-diagram-mermaid` and paste its `[![alt](<ink_url>?width=620)](<live_url>)`
  - `aside image URL is not a mermaid.ink base64 diagram`, `aside image URL too long for the Docs API`: the URL was not bake's; re-bake it
  - `mermaid fence in aside would publish as source text`, `empty code fence in aside`
- **After `Doc created` or `Doc updated`**: fix, then follow **Recover after a failure**.
  - `Drive link target in aside is unreadable`: the user shares the target, or the draft drops the link
  - `marker not found in first tab`: the body changed under the rebuild; nothing was sent. Re-publishing re-imports the body.
  - the verify read: `aside tab Drive links are not all chips`; `aside tab images missing`; `aside tab image exceeds one page` (too wide: lower `?width=`; too tall: split the diagram); `aside tab image does not link to its mermaid.live view`
  - a `fill batch` failure from Docs (an image mermaid.ink would not render): the tabs exist but are empty; fix the diagram and re-publish, which deletes them as stale.

### Bookmarks

`gdoc_publish.zsh` then runs `/ari-hemingway--structure-bookmark`'s check and apply; nothing to emit. Read the log:
- `bookmark target | key= text= bookmark=` per target, then `bookmarks applied | targets= relinked_runs= bookmark_links=`: done.
- `Bookmarks: none in the draft`: no aside and no `#bm-`/`#goto-` link; nothing ran.
- `Bookmarks skipped; return links stay on headings | missing='…'` (WARN, exit 0): quote it to the user and offer the one-time setup in that skill. **NEVER run a command from `missing=` without their reply**; some carry `--execute`.
- `Bookmarks skipped; the bookmark skill is not installed` or `… predates --execute` (WARN): the doc keeps heading links; say so.
- `Bookmarks skipped; the finish step failed` or `… the aside rebuild failed`: fix that failure; the re-publish bookmarks.
- `Bookmark setup check failed`, `Bookmark apply failed` or `Bookmark step did not execute` (ERROR, non-zero exit): follow **Recover after a failure**.

### Recover after a failure

A non-zero exit after `Doc created` or `Doc updated` leaves the doc in place. **NEVER re-run without `--doc` then: a second create makes a second Doc.** Take the URL from that line's `url='…'` (stdout has it too), fix the draft, and re-publish with `gdoc_publish.zsh`, never `gdoc_finish.zsh`, which re-checks the unchanged body:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md> --doc <url> --execute
```

Keep `--title` and `--first-tab-title` as they were and drop `--folder`. A Bash timeout counts as a failure: take `url=` from a `Doc created` or `Doc updated` line, and with none, ask the user to check the folder before any re-run. The yes to the failed run's dry run covers this re-run only when `<url>` is the one its `Doc created` or `Doc updated` line named, and either the draft is unchanged (a transient failure: a timeout, a `fill batch` render error, a bookmark apply that failed on Apps Script) or the fix only re-bakes a diagram or follows a share of the target. A fix that changes what the draft says (drops a link, folds a column, lengthens a `#bm-` phrase that occurs twice) is shown to the user as a draft diff and waits for their reply; that yes covers one re-publish. Any other doc starts again at **Dry-run**. A batch refused on `requiredRevisionId` means someone edited the doc during the publish: stop, name it to the user, and re-run only on their reply, since a re-publish replaces their edit.

### Report

Relay the URL the script printed as a raw `docs.google.com` URL, never as `[text](url)`. On a failure, relay it with the first `[ERROR]` line and the fix. Quote every `[WARN]` line under the URL; for a bookmark skip, add that `#goto-` links and aside return links stay on headings. If the draft's directory holds a `scratchpad.md`, write or update one line there, `Published: <url>`, which the next **Dry-run** reads for `--doc`.

### Re-check an existing doc

To verify a doc someone edited by hand, or to redo the fix-up after manual table edits:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh --doc <id|url> --check-only
```

Without `--check-only` it is the fix-up's dry run: show the user its `Table columns resized` lines, which would reset widths a person set by hand (keep them with `--table-widths START:w1,w2,…`, `START` the `start=` of that table's line in this log), and add `--execute` only after their reply. Both are idempotent: a chip is not a plain link, so a second run finds nothing to convert, and a table already at its planned widths is kept. Add `--render-pages <dir>` to either form to inspect the rendered pages. Neither touches aside tabs; for those, the dry run:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_asides.zsh --rebuild --file <path/to/output.md> --doc <id|url>
```

Show the user its `would delete` and `would rebuild` lines; add `--execute` only after their reply. It reads the sections from the draft, so the draft must be the one the doc was published from. A rebuild by hand gives return links the heading target again, so re-apply the bookmarks after it, in a later turn than the rebuild's `--execute`. Run the dry run:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc <id|url> --file <path/to/output.md>
```

Show the user its plan with the confirm message from `/ari-hemingway--structure-bookmark` (`--execute` deletes every bookmark in the first tab, hand-made ones too), and add `--execute` only after their reply. **NEVER chain the rebuild's `--execute` and the bookmark apply's `--execute` in one turn.**

### Measure a change

Run `gdoc_finish.zsh --doc <url> --check-only` before and after the change and copy the `pdf=` path its `Rendered length` line names each time; then compare table heights in points:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_heights.zsh --pdf <path/to/export.pdf>
```

One JSON line per table: `pages`, `rows`, `cols`, `height_pt` as printed, and `content_height_pt` without the repeated header rows. A row Docs splits across a page break counts once per page, so `rows` can exceed the true count; the heights are exact.
