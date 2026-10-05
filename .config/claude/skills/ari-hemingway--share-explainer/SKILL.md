---
name: ari-hemingway--share-explainer
description: "Publish one explainer article to explainers.sweedler.com in one command: add or update its front-page card (title and description from the article head, figure count, reading time, three palette swatches), render its link-preview card, run the CLI gates and the tests, commit in the house shape, push main as the account that owns the remote (never the ambient GITHUB_TOKEN), watch the Pages run for that SHA, and open the short URL. Dry-runs first; nothing is written or pushed without --apply."
---

# Publish to the explainers site

Turn a finished `articles/<slug>/index.html` (validated per `/ari-hemingway--format-explainer`, produced by `/ari-hemingway--structure-ciechanowski`) into a live page at `https://explainers.sweedler.com/<slug>/` with one script call: the front-page card, the `og.png` link preview, the gates, the commit, the push, the deploy watch and the open are one step, never follow-ups.

## Arguments

- `--article <repo>/articles/<slug>` — the article directory; a relative path resolves against the current directory, so the documented calls pass the repo path.
- `--apply` — do it; without it the run is a dry-run that writes and pushes nothing.
- `--no-open` — leave opening the URL to the caller.
- `--message "<subject>"` — the commit subject, in the house shape `articles/<slug>: <what changed>`.
- `--autonomous` (per `## Autonomous mode` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`) changes nothing here: the dry-run runs, the run ends with `Publish gate — rerun with --apply`, and `--apply` is never added without the user's confirmation, because it pushes `main` to the public site.

## Rules

- **The card is derived from the article head, never typed.** Title from `<title>`, description from `<meta name="description">` with a trailing `N interactive figures.` sentence dropped (the card's meta row prints the count), the figure count from `<figure class="x-fig">`, the reading time from the words outside `<script>`, `<style>`, `<svg>`, `<math>` and the collapsed glossary `<details>` at 230 wpm, rounded to the minute. The markup is the one `index.html` already uses (`<li><a class="x-card" href="articles/<slug>/">`, `<h2>`, `<p>`, `<p class="x-meta">` with `.x-swatches`, the count and `N min`). A new card goes to the top of `<ul class="x-index">`; an existing card for the slug is replaced in place, so re-running after an edit refreshes the count and the time.
- **Swatches are the article's first three `--c-` tokens, and the front page gets the tokens it lacks.** `index.html` declares every article's swatch tokens in its own `:root` so the dots resolve; a token missing there is appended before the block's closing brace with the article's `light-dark()` value. A token the front page already has under a different value is kept and logged as a `WARN`: the palette is shared across the site, so change it in both places on purpose.
- **The link preview is re-rendered every time.** `node tools/og-image.mjs articles/<slug>/index.html` draws `assets/og.png` from the title, description, palette and hero poster; `build` cannot (it needs a browser), and `validate` only warns while it is missing or stale. The renderer needs Playwright's `chrome-headless-shell` or `EXPLAINERS_HEADLESS_SHELL`; a missing binary fails the apply before anything is committed.
- **Gates before commit.** `build` (in place, idempotent), `validate --budget 170k`, `states`, `budget --budget 170k`, then `npm test`. A failing gate stops the run with the CLI's `file:line: CODE figure-id: message` lines; fix the article, not the CLI, and re-run. The dry run already runs the three read-only gates.
- **Every include URL is versioned, or the deploy breaks the page.** The CDN caches `dist/` longer than the HTML, so an unversioned include pairs new HTML with an old runtime and Subresource Integrity blocks it (unstyled page, no figures). `explainers build` appends `?v=<first ten hash characters>` to the article's includes and `validate` refuses a stale one as `INTEGRITY_STALE`; the script gives the front page's stylesheet link the same `?v=` from `dist/integrity.json` on every run.
- **One commit in the house shape.** Subject `articles/<slug>: <title>, <n> figures` for a new card, `articles/<slug>: front-page card and link preview refreshed` for an update, or `--message` for the author's own subject; body naming the card's facts and the short URL; the `Co-Authored-By` trailer. Everything under `articles/<slug>` and `index.html` is staged (`git add -A`), so read the `git status --short` lines the dry run prints: an untracked folder under the article ships too.
- **The push uses the remote owner's token, never the ambient `GITHUB_TOKEN`.** The owner is parsed from `git remote get-url origin`; the token is `gh auth token -u <owner>`, which reads the keyring entry for that account even when `GITHUB_TOKEN` (a work account) is exported in the session. The push goes through a one-shot credential helper (`git -c credential.helper= -c 'credential.helper=!f() { echo username=<owner>; echo password=$TOKEN; }; f' push origin main`), so no stored helper and no env token can answer the prompt. A `gh` login for the owner is a precondition (`gh auth login -u <owner>`); the remote must be https. The same token drives the run watch (`GH_TOKEN`).
- **Main only, never diverged.** The script refuses any branch but `main` (the Pages workflow deploys only `main`) and fetches first: a local `main` that is not ahead of `origin/main` by a fast-forward is an error to rebase, not to force.
- **Deploy is watched for the pushed SHA, not for "the latest run".** `gh run list --workflow pages.yml --json databaseId,headSha` is polled (up to 180 s) until a row carries the SHA just pushed, then `gh run watch <id> --exit-status` follows it (capped at 15 min). A failed run is a failed share: the run URL is in the log.
- **The short URL needs no table row.** `infra/explainers-proxy/worker.js` maps any `/<slug>/` to `articles/<slug>/` generically, so a new article is live at `https://explainers.sweedler.com/<slug>/` as soon as Pages deploys; the Worker is redeployed by hand only when `worker.js` itself changes.
- **Idempotent.** A second run finds the card already current (the diff is empty), nothing to commit, nothing to push, and only opens the URL.

## Preconditions

- The article lives at `<repo>/articles/<slug>/index.html` inside the explainers repo (default `$HOME/Desktop/workspace/explainers`) on a checked-out `main`, and passes `validate`, `states` and `budget` (`/ari-hemingway--format-explainer`).
- `git`, `gh`, `node` (22+), `npm`, `awk`, `jq`. `gh auth status` lists the account that owns the remote (`AriSweedler` for `github.com/AriSweedler/explainers`). Playwright's `chrome-headless-shell` under `~/Library/Caches/ms-playwright/`, or `EXPLAINERS_HEADLESS_SHELL`, for the link preview.
- `EXPLAINERS_SITE_URL` overrides the short-URL origin (default `https://explainers.sweedler.com`).

## File storage

- `bin/share.zsh` — the one-shot share: card, link preview, gates, commit, push, watch, open. Dry-run by default; `--apply` does it; `--no-open` leaves the opening to the caller; `--message` sets the commit subject. Prints `slug`, `action` (`insert` or `update`), `figures`, `minutes`, `sha`, `run_id` and `url` as `key=value` lines on stdout; logs go to stderr.

## Workflow

### Dry-run

Emit exactly this one Bash call:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-explainer/bin/share.zsh --article <repo>/articles/<slug> --no-open
```

It logs the article's facts (`title`, `figures`, `words`, `minutes`), the swatch tokens and any token the front page would gain, whether the card is an `insert` or an `update`, the card as a unified diff against `index.html`, the full commit message, the `validate`, `states` and `budget` results, the paths git would stage (`git status --short`), and the push target (`remote`, `owner`, `account`, `token_source`, `commits_ahead`). Nothing is written. Show the user the action, the diff and the commit subject, then wait for confirmation. A `WARN` about a differing palette token means the front page's value wins; say so.

### Publish

Same call with `--apply`. Keep `--no-open` when the Chrome MCP tools are connected (`mcp__claude-in-chrome__tabs_context_mcp` answers), so the page opens in the user's Chrome rather than the default browser; drop it otherwise and the script runs `open`:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--share-explainer/bin/share.zsh --article <repo>/articles/<slug> --apply --no-open
```

Read the log in order: `Front page written`, the gate lines, `Tests pass`, `Committed | sha=`, `Pushed`, `Pages run found | run_id= url=`, the `gh run watch` steps, `Pages run succeeded`. A non-zero exit before `Committed` leaves the working tree with the card and `og.png` changed and nothing committed (`git status` shows them; fix and re-run). A non-zero exit after `Pushed` means the Pages run failed; open the run URL from the log, fix, and re-run (the next push gets its own run).

### Open

With `--no-open` and Chrome connected: load the Chrome tools once (`ToolSearch` with `select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__navigate`), create a tab and navigate it to the `url=` line the script printed. Without Chrome, the script's own `open` has already done it.

### Report

Relay the short URL (`https://explainers.sweedler.com/<slug>/`), the commit SHA and the run URL. If the article has a hemingway investigation folder (`/tmp/hemingway/ciechanowski/<topic-slug>/<timestamp>/`), add `- **Published**: <url> @ <sha>, run <run url>` after `Last phase` in its `scratchpad.md`.

### Refresh a card

After editing an article's title, description, figures or prose, the same two calls refresh the card, the reading time and the link preview; the action is `update` and the subject is the refresh form unless `--message` names the edit.
