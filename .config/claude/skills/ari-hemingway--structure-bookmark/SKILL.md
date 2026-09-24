---
name: ari-hemingway--structure-bookmark
description: "Sub-structure for any hemingway draft bound for a Google Doc: a link that lands on a sentence, not a section. `[text](#bm-<slug>)` bookmarks the text, `[text](#goto-<slug>)` links to it, and every aside marker is bookmarked for its return links. One script checks the one-time Apps Script setup, records it, and applies the bookmarks after each publish."
---

# Bookmarks

A bookmark is a link target inside a paragraph. A heading link lands the reader at the top of a section; a bookmark lands them on the sentence. This is a sub-structure: any `/ari-hemingway--structure-*` draft may use it, and `/ari-hemingway--structure-aside` uses it for the `← Return to main article` links once the setup below is in place. Targets a Google Doc.

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns: see `/ari-hemingway--lib`. If any rule here appears to contradict `/ari-hemingway--format-gdoc`, the format skill wins. Publishing is `/ari-hemingway--share-gdoc`, which runs this skill's script after every publish.

## When to use

Use a bookmark when the reader must land on one sentence: a return link from an aside, a "see the gate above" reference, a definition a later section points back to. For a section, link its heading; this skill is for a sentence. To point at an aside, use a reference by title (`/ari-hemingway--structure-aside`), not a bookmark.

## Dialect

- `[text](#bm-<slug>)` puts a bookmark on `text`. **It lives in the main body only**; a `#bm-` inside an `# Aside n:` section fails the publish naming the aside and the slug. After publishing, the link style is removed, so the text renders plain; the bookmark is invisible.
- `[text](#goto-<slug>)` links `text` to that bookmark, from anywhere: the body, `# Useful links`, an aside. It renders as a link.
- **The `#bm-` and `#goto-` slugs MUST match.** Slugs are kebab-case (`[a-z0-9-]`, starting with a letter or digit) and unique per doc. A `#goto-` with no `#bm-` fails the publish naming the slug; a `#bm-` used twice fails naming it. `#goto-aside-n` is not a form; refer to an aside by title.
- **The bookmarked text MUST be unique in the main body.** A republish restores the `#bm-` anchor, but a re-apply without one finds the target by its exact text and fails if the text occurs twice.
- **Every `--apply` removes all bookmarks in the first tab and recreates the draft's.** Do not add bookmarks by hand to a doc published this way.
- Asides need nothing extra: each `([aside n ℹ️](#aside-n))` marker is an implicit target, and its tab's return links move from the heading above the marker onto the marker itself.
- The text may be anything, including a code span.

- GOOD: `Do not proceed until [every row reads deleted](#bm-rows-deleted).` … later, in the body or an aside: `That is the [gate in Step 2](#goto-rows-deleted).`
- BAD: `[every row reads deleted](#bm-rows_deleted)` — underscore, not kebab-case.
- BAD: `[the gate](#goto-step-2)` with no `#bm-step-2` anywhere — the publish fails naming `step-2`.
- BAD: a `#bm-` inside `# Aside 2: …` — the publish fails naming aside 2 and the slug; put the `#bm-` on the body sentence and the `#goto-` in the aside.
- BAD: `[Manual cleanup](#goto-aside-3)` — not a form; `[Manual cleanup](#aside-3)` is the reference.

## Rules

### Content scope

A bookmark adds no words. Its text is the sentence already there.

### What publishing does

`/ari-hemingway--share-gdoc` runs `gdoc_bookmarks.zsh --check-setup` after the asides rebuild. When every line is `OK`, it runs `--apply`, which creates a bookmark at every `#bm-` run and aside marker through Apps Script, then sends one batch that points every `#goto-` link and aside return link at `link.bookmark` and strips the `#bm-` link style. Otherwise it logs one `WARN` naming the first missing prerequisite and the doc keeps heading links. Bookmarks die on republish like tabs, so this runs every time.

### Destinations

Google Doc only. Slack, PR description, and markdown have no bookmark form.

## File storage

- `bin/gdoc_bookmarks.zsh` (+ `gdoc_bookmarks.py`, per `/ari-skill-pythonscripts`; Docs helpers shared with share-gdoc live in `ari-hemingway--lib/lib/gdoc_api.py`) — `--check-setup` prints one line per prerequisite in dependency order (scopes, api, project, content, deployment, run: `OK`, `MISSING` with the exact next command or click path, or `SKIPPED` behind a missing one) and exits non-zero if anything is missing; `--configure --script-id ID [--deployment-id ID]` records the ids in `~/.local/share/ari-hemingway/gdoc_bookmarks.json` and logs the previous values; `--apply --doc ID_OR_URL --file DRAFT.md [--dry-run]` creates the bookmarks and relinks. `--doc` takes an id or URL.
- `bin/gas/Bookmarks.gs` (+ `appsscript.json`) — the Apps Script project: `addBookmarks(docId, targets)` finds each target in the first tab by its link URL or its exact text and returns `{key: bookmarkId}`; `ping()` is the setup probe.

## Setup (one time, per account)

`--check-setup` prints the exact command or click path for whichever step is next; run it and follow the first `MISSING` line until six lines read `OK`. What each step establishes:

1. **scopes** — the `gws` token carries `script.projects` and `script.deployments` on top of the publishing scopes (`documents`, `drive`). **`gws auth login` replaces the token's whole scope set on every run**, and its `-s script` picker grants `cloud-platform`, not the Apps Script scopes, so the check prints a `gws auth login --scopes <every current scope plus the missing ones>` command; run that one (browser), then `gws auth status`.
2. **api** — the per-user "Google Apps Script API" toggle is on. Click path: https://script.google.com/home/usersettings. Off, every `gws script` call answers 403 `User has not enabled the Apps Script API`.
3. **project** — an Apps Script project exists and its id is recorded with `--configure`.
4. **content** — the project's files equal `bin/gas`. `gws` rejects an absolute `--dir`, so the push runs from inside the folder: `(cd $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gas && gws script +push --script <scriptId> --dir .)`.
5. **deployment** — a deployment of a numbered version with an API-executable entry point exists and its id is recorded with `--configure`. Apps Script makes a HEAD deployment by itself; the check ignores it and says so.
6. **run** — `scripts.run` reaches the project, which needs the script's GCP project switched to `airtable-gws-cli` in the Apps Script editor's project settings (click path; no API sets this).

A passing check:

```
OK       scopes: token carries script.projects and script.deployments (and documents, drive)
OK       api: Apps Script API enabled for this user
OK       project: scriptId=1AbC… in /Users/you/.local/share/ari-hemingway/gdoc_bookmarks.json
OK       content: project files match bin/gas (Bookmarks, appsscript)
OK       deployment: API-executable deployment AKfy… (ignoring the automatic HEAD deployment AKfy…)
OK       run: scripts.run reaches the project (ping returned ok)
```

A blocked one stops at the first gap and skips the rest:

```
MISSING  scopes: token lacks script.projects, script.deployments; a login replaces the whole scope set, so run: gws auth login --scopes email,profile,…,https://www.googleapis.com/auth/script.projects,https://www.googleapis.com/auth/script.deployments
SKIPPED  api: blocked by scopes
SKIPPED  project: blocked by scopes
SKIPPED  content: blocked by scopes
SKIPPED  deployment: blocked by scopes
SKIPPED  run: blocked by scopes
```

## Investigation folder

None of its own. A bookmark is drafted inside a host `/ari-hemingway--structure-*` skill, whose folder under `/ari-hemingway--lib` holds everything.

## Workflow

This skill runs inside the host skill's `Draft` step and inside `/ari-hemingway--share-gdoc`'s publish; there is no standalone drafting mode. Fact-check, Present, and Output are the host's per `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Draft

While drafting the host document per `Drafting` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, write `#bm-` on the body sentence to land on and `#goto-` where the reader jumps from, with the same slug.

### Check setup

Run the check once per machine before relying on bookmarks; the publish runs it too, but only warns:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --check-setup
```

### Apply

Nothing to emit: `/ari-hemingway--share-gdoc` runs `--apply` after every publish. To run it by hand after another body replace:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc <id|url> --file <path/to/output.md> --dry-run
```

Drop `--dry-run` to apply. Its log, on success:

```
[INFO] bookmark target | key='aside-1' text='aside 1 ℹ️' bookmark='id.abc123'
[INFO] bookmark target | key='bm-rows-deleted' text='every row reads deleted' bookmark='id.def456'
[INFO] bookmarks applied | targets='2' relinked_runs='4' bookmark_links='4'
```

A failure names the slug (`#goto- links with no #bm- target`, `bookmark slug used twice`, `#bm- inside an aside body`) or the target the Apps Script could not find.
