---
name: ari-hemingway--share-gdoc
description: "Publish a markdown draft as a Google Doc in one command — create, or update an existing doc in place — and finish it: table header rows styled (bold, centered, grey), every image checked to fit one page. Dry-runs first; the doc is created only on confirm."
---

# Publish to Google Doc

Turn a finished `output.md` (or any draft that follows `/ari-hemingway--format-gdoc`) into a Google Doc with one script call. The script uploads the markdown through Drive's Docs conversion, then applies what markdown cannot express: header rows on every table become bold, centered, and grey (`#D9D9D9`), and every inline image is checked against the page content box so a diagram never spills onto a second page. Styling is part of publishing, never a follow-up.

## Preconditions

- `gws` CLI installed and authenticated for the user's @airtable.com account (`/gws-docs` covers setup). `jq` installed.
- The draft's first line is the plain-text title (ending `[🤖 AI generated]` per `/ari-hemingway--format-gdoc`). The script strips that line from the body and uses it as the Doc title; pass `--title` to override and keep the whole file as body.
- Updating in place (`--doc`) replaces the entire body. Manual edits in the Doc are lost, including "Pin header row". Say so before updating a doc the user has touched.
- Docs in shared drives work: the script sets `supportsAllDrives`. A Drive 404 on a doc the user can open therefore means the id is wrong, not that the doc moved.

## File storage

- `bin/gdoc_publish.zsh` — the one-shot publish: create or update, then finish. Prints the doc URL on stdout.
- `bin/gdoc_finish.zsh` — the finishing half, runnable alone on any doc: styles table header rows and reports whether each image fits one page. `--check-only` reports without styling.

## Workflow

### Dry-run

Emit exactly this one Bash call (add `--doc <id|url>` to update an existing doc):

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md> --dry-run
```

It logs the title and body size and validates the Drive request without creating anything. Show the user the title and whether this is a create or an update, then wait for confirmation.

### Publish

Same call without `--dry-run`:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh --file <path/to/output.md>
```

The script creates (or updates) the doc, then runs `gdoc_finish.zsh` on it. A non-zero exit after "Doc created" means finishing failed — most often an image taller than one page. Fix the draft (split or flatten the diagram) and re-run with `--doc <url>`.

### Report

Relay the URL the script printed, as a raw `docs.google.com` URL. State the one manual step: the Docs API cannot pin a header row (`tableHeader` is read-only), so the user pins it via Format > Table > Pin header row if they want it repeating across pages. Then, if the draft has its own hemingway investigation folder, record the URL in its `scratchpad.md`.

### Re-check an existing doc

To verify a doc someone edited by hand, or to restyle after manual table edits:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh --doc <id|url> --check-only
```

Drop `--check-only` to apply the header styling. Both are idempotent.
