---
name: ari-hemingway--structure-bookmark
description: "Sub-structure for any hemingway draft bound for a Google Doc: a link that lands on a sentence, not a section. `[text](#bm-<slug>)` bookmarks the text, `[text](#goto-<slug>)` links to it, and every aside marker is bookmarked for its return links. One script checks the one-time Apps Script setup, records it, and applies the bookmarks after each publish."
---

# Bookmarks

A bookmark is a link target inside a paragraph. A heading link lands the reader at the top of a section; a bookmark lands them on the sentence. This is a sub-structure: any `/ari-hemingway--structure-*` draft may use it, and `/ari-hemingway--structure-aside` uses it for the `← Return to main article` links once the setup below is in place. Targets a Google Doc.

This skill owns the `#bm-`/`#goto-` dialect and the bookmark publish step; every other formatting rule is `/ari-hemingway--format-gdoc`'s. Workflow patterns: see `/ari-hemingway--lib`. Publishing is `/ari-hemingway--share-gdoc`.

## When to use

Use a bookmark when the reader must land on one sentence: a return link from an aside, a "see the gate above" reference, a definition a later section points back to. For a section, link its heading; this skill is for a sentence. To point at an aside, use a reference by title (`/ari-hemingway--structure-aside`), not a bookmark.

## Dialect

- `[text](#bm-<slug>)` puts a bookmark on `text`. **It lives in the main body only** (every line outside an `# Aside n:` section, `# Useful links` included). After publishing, the text renders plain.
- `[text](#goto-<slug>)` links `text` to that bookmark, from anywhere: the body, `# Useful links`, an aside. It renders as a link.
- **Each slug has exactly one `#bm-` and any number of `#goto-` links, with the same slug.** Slugs are kebab-case (`[a-z0-9-]`, starting with a letter or digit). `#goto-aside-n` is not a form; refer to an aside by title.
- **The bookmarked text MUST occur exactly once in the main body, as a substring of any paragraph, headings included.** An apply finds the target by its exact text once the `#bm-` link is gone, and fails on a second hit before it writes.
- **The text is one line with no `]`.** A code span or `**bold**` works: the apply matches the text without its backticks and asterisks.
- **Every `--apply --execute` removes all bookmarks in the first tab and recreates the draft's.** To add a bookmark to a Doc published this way, add the `#bm-` and its `#goto-` links to the draft and republish; NEVER create one in the Docs UI or through the API, since the next apply deletes it.
- Asides need nothing extra: each `([aside n ℹ️](#aside-n))` marker is an implicit target, and its tab's return links move from the heading above the marker onto the marker itself.

- GOOD: `Do not proceed until [the status reads done](#bm-status-done).` … later, in the body or an aside: `That is the [gate in Step 2](#goto-status-done).`
- BAD: `[the status reads done](#bm-status_done)` — underscore, not kebab-case; the publish fails naming the link before the Doc is touched.
- BAD: `[done](#bm-done)` in a body that also says "done" elsewhere — the apply fails `target text occurs more than once`; bookmark a longer phrase.
- BAD: `[the gate](#goto-step-2)` with no `#bm-step-2` anywhere — the publish fails naming `step-2`.
- BAD: a `#bm-` inside `# Aside 2: …` — the publish fails naming aside 2 and the slug; put the `#bm-` on the body sentence and the `#goto-` in the aside.
- BAD: `[Manual cleanup](#goto-aside-3)` — not a form; `[Manual cleanup](#aside-3)` is the reference.

## Rules

### Content scope

A bookmark adds no words. Its text is the sentence already there.

### What publishing does

`/ari-hemingway--share-gdoc` runs `gdoc_bookmarks.zsh --check-setup` after the asides rebuild. When every line is `OK`, it runs `--apply --execute`, covered by the user's `yes` to the publish, which creates a bookmark at every `#bm-` run and aside marker through Apps Script, then sends one batch that points every `#goto-` link and aside return link at `link.bookmark` and strips the `#bm-` link style. Otherwise it logs one `WARN` naming the first missing prerequisite: aside return links stay on headings, and every `#goto-` link points nowhere. Bookmarks die on republish like tabs, so this runs every time; the bookmark ids change each time, so a bookmark URL shared outside the Doc breaks.

### Destinations

Google Doc only. Slack, PR description, and markdown have no bookmark form.

## File storage

- `bin/gdoc_bookmarks.zsh` (+ `gdoc_bookmarks.py`, per `/ari-skill-pythonscripts`; Docs helpers shared with share-gdoc live in `ari-hemingway--lib/lib/gdoc_api.py`) — three modes:
  - `--check-setup` prints one line per prerequisite in dependency order (scopes, api, project, content, deployment, run: `OK`, `MISSING` with the exact next command or click path, or `SKIPPED` behind a missing one) and exits non-zero if anything is missing. It is read-only and refuses `--execute` and `--dry-run`.
  - `--configure --script-id ID [--deployment-id ID]` records the ids in `~/.local/share/ari-hemingway/gdoc_bookmarks.json` (`{"scriptId": …, "deploymentId": …}`) and logs the previous values; a new script id without `--deployment-id` drops the old project's deployment.
  - `--apply --doc ID_OR_URL --file DRAFT.md` creates the bookmarks and relinks. `--doc` takes an id or URL.
- **`--configure` and `--apply` write only with `--execute`** (`/ari-skill-shellscripts` § Mutations, gated in the entrypoint by its `lib/dry_run.zsh`). Without it, with `--dry-run` (which wins over `--execute`), or under an inherited `DRY_RUN=1`, they run every read and check, log what they would change, and write nothing. Their last stdout line is JSON carrying `"dry_run": 1` or `0`.
- `tests/gdoc_bookmarks_dry_run.test.zsh` — the dry-run gate against a fake `gws` and a throwaway `HOME`; never a real Doc or project. Run it after any change to `bin/`: `zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/tests/gdoc_bookmarks_dry_run.test.zsh`.
- `bin/gas/Bookmarks.gs` (+ `appsscript.json`) — the Apps Script project: `addBookmarks(docId, targets)` finds each target in the first tab by its link URL or its exact text and returns `{key: bookmarkId}`; `ping()` is the setup probe.

## Setup

Once per Google account (api, project, deployment, run), plus once per machine (scopes, the recorded ids). Run `--check-setup`, act on the first `MISSING` line only, and run it again, until six lines read `OK`:

- **Ari's steps, never Claude's:** the `gws auth login --scopes …` line (a browser; hand him that exact line through `/ari-driving-tmux`, NEVER a bare `gws auth login` or `-s script`) and the click paths for **api** and **run**. Wait for him to say it is done.
- **Claude's steps:** the push, `versions create`, `deployments create`, and the printed `--configure … --execute` commands. Run `gws script projects create` once: after a failure or timeout, `gws script projects list` before any retry, so no second project is made.

What each step establishes:

1. **scopes** — the `gws` token carries `script.projects` and `script.deployments` on top of the publishing scopes (`documents`, `drive`). **`gws auth login` replaces the token's whole scope set on every run**, and its `-s script` picker grants `cloud-platform`, not the Apps Script scopes, so the check prints a `gws auth login --scopes <every current scope plus the missing ones>` command; run that one (browser), then `gws auth status`.
2. **api** — the per-user "Google Apps Script API" toggle is on. Click path: https://script.google.com/home/usersettings. Off, every `gws script` call answers 403 `User has not enabled the Apps Script API`.
3. **project** — an Apps Script project exists and its id is recorded with `--configure --execute`.
4. **content** — the project's files equal `bin/gas`. `gws` rejects an absolute `--dir`, so the push runs from inside the folder: `(cd $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gas && gws script +push --script <scriptId> --dir .)`.
5. **deployment** — a deployment of a numbered version with an API-executable entry point exists and its id is recorded with `--configure --execute`. Apps Script makes a HEAD deployment by itself; the check ignores it and says so.
6. **run** — `scripts.run` reaches the project, which needs the script's GCP project switched to the one `gws` signs in with (`project_id` in `~/.config/gws/client_secret.json`) in the Apps Script editor's project settings (click path; no API sets this).

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

### Check setup

Run the check when a draft gets its first `#bm-` or `#goto-` link on this machine, before publishing it; the publish runs it too, but only warns:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --check-setup
```

Exit 1 → tell the user the first `MISSING` line and finish **Setup**, or drop the draft's `#bm-`/`#goto-` links: without setup a `#goto-` publishes as a link to nowhere.

### Draft

While drafting the host document per `Drafting` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, write `#bm-` on the body sentence to land on and `#goto-` where the reader jumps from, with the same kebab-case slug, per **Dialect**.

### Apply

**After every publish, read its log: bookmarks were applied only if it shows `bookmarks applied | targets=…`.** A `Bookmarks skipped` line → quote it to the user. Neither line, on a draft with `#bm-` links or aside markers → apply by hand. Also apply by hand after a by-hand `gdoc_asides.zsh --rebuild --execute`, or any body replace outside `gdoc_publish.zsh`. `--file` is the full draft the Doc was published from, `# Aside n:` sections included. Dry run first:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc <id|url> --file <path/to/draft.md>
```

It reads the Doc, checks every target against it, prints the plan and the relink batch on stdout, and logs on stderr:

```
[INFO] Dry run: the default; nothing will change | rerun='--execute'
[INFO] would apply bookmarks | doc='1AbC…' title='Runbook' targets='2' goto_links='1'
[INFO] would run scripts.run addBookmarks | doc='1AbC…' deployment='AKfy…' targets='2'
[INFO] would bookmark target | key='aside-1' text='aside 1 ℹ️' bookmark='BOOKMARK_aside-1'
[INFO] would bookmark target | key='bm-status-done' text='the status reads done' bookmark='BOOKMARK_bm-status-done'
[INFO] dry-run: would send batch | what='relink batch' requests='4'
[INFO] Dry run; nothing changed | changes='2' rerun='zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc 1AbC… --file draft.md --execute'
```

`changes` counts writes: the Apps Script call and the batch.

**NEVER add `--execute` in the same turn as the dry run.** End the turn with those stderr lines and: "`--execute` deletes every bookmark in the first tab, including any made by hand, and recreates the draft's." Run the `rerun` command, unchanged, only after the user replies yes to that message; the request that started the work is not that yes:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh --apply --doc <id|url> --file <path/to/draft.md> --execute
```

Its log, on success:

```
[INFO] Executing: --execute given
[INFO] applying bookmarks | doc='1AbC…' title='Runbook' targets='2' goto_links='1'
[INFO] running scripts.run addBookmarks | doc='1AbC…' targets='2'
[INFO] bookmarks added | count='2'
[INFO] bookmark target | key='aside-1' text='aside 1 ℹ️' bookmark='id.abc123'
[INFO] bookmark target | key='bm-status-done' text='the status reads done' bookmark='id.def456'
[INFO] bookmarks applied | targets='2' relinked_runs='4' bookmark_links='4'
[INFO] Executed | changes='2'
```

A failure names what broke, and every draft or target failure stops before the first write: `malformed #bm-/#goto- link`, `#goto- links with no #bm- target`, `bookmark slug used twice`, `#bm- inside an aside body`, `target not found in the first tab`, `target text occurs more than once`, `bookmark setup incomplete`. Each carries its `fix=`.
