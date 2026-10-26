---
name: ari-hemingway--structure-repo-quickstart
description: "Write a repository's top-level README as a quick start: what it is in two sentences, a screenshot strip, one command block that runs it, then one link line per deeper topic in docs/. Modes: research (from a repo), update (review an existing README, move what is not needed to start into docs/, rewritten as the current design). Checked mechanically: every command copy-pasteable, every link and image resolving, no history, under the word cap."
---

# Repo quickstart

Produce a repository README that gets a newcomer running in two minutes, and a `docs/` folder that holds everything else. The README is the quick start; `docs/` is the manual. Destination is GitHub-flavored Markdown in the repository itself.

Formatting: GitHub-flavored Markdown as GitHub renders it; no `/ari-hemingway--format-*` sibling exists for it, so the Rules below are the formatting rules. Workflow patterns (investigation folder, restore context, drafting, fact-check, present/output): see `/ari-hemingway--lib`. Review axes come from `/ari-hemingway--review-common` with `destination=readme`; every reviewer brief says "read-only, run no commands", and one reviewer is briefed "you have never seen this machine" to find the step an owner forgets.

## Modes

- **Research** — given a repository, read it and write the README and the `docs/` pages from scratch.
- **Update** — given a repository with a README, review it against the Rules, move every section a newcomer does not need into `docs/`, and rewrite what stays. Moved sections are rewritten as the current design of that topic, never pasted as leftovers.

## Document structure

Required, in this order:

1. `# <name>` — the repository's name, nothing else.
2. **Pitch** — two sentences: what it does for whom, and the one design rule that makes it worth a look. Expand an acronym here, once. No heading.
3. **Screenshot strip** — for anything with a UI: three to five images in one `<p>` row at `width="180"`, each with an `alt` that names the view. A CLI shows nothing here; a table that is the product's key (a swatch table, a command table) may stand in its place.
4. `## Getting started` (or `## Run it`) — one sentence naming every prerequisite with a link, then one fenced block a newcomer pastes: clone, the one install step, a health check, the one command that proves it works and writes nothing. Then one sentence on what they see. The required path comes first; a step that is optional says so in its section's first line.
5. **One short section per credential or dependency** the quick start needs, numbered steps, ending with a `[Details](docs/credentials.md#anchor)` line. The README gives the value; the rationale lives behind the link.
6. **Integration snippet**, verbatim, when the thing is used from another system (the compose service, the MCP registration, the import line).
7. `## Configuration` — one line: where the values live and the link to `docs/configuration.md`.
8. `## Docs` — one line per page in `docs/`: `- [Title](docs/file.md) — what the reader gets there`.
9. `## License` — one word or one line.

Optional, before `## Docs`, each at most 120 words: `## What it does` (bullets, one per capability, when the pitch cannot carry them); `## How it is saved` (the one table or tree a user needs to trust it with their data); `## Layout` (only when the tree is not self-evident; a fenced tree, one comment per line); `## API` (a table or a fenced block of routes, never prose).

Everything else goes to `docs/`, split by the reader's question, not by code module: `architecture.md` (how it works, the diagram), `credentials.md`, `configuration.md`, `cli.md`, `deployment.md` or `<host>-integration.md`, `migration.md`; `CONTRIBUTING.md` at the root holds tests, CI and release. Each page is written as the current state (per the no-scars rule) and gets one line in `## Docs`.

### Skeleton

The skeleton is `templates/readme.md`; copy it, do not retype it.

## Rules

### The README is the quick start

- **300 to 500 words outside code blocks.** Past the cap, move a section to `docs/`; never tighten by deleting the run block or a screenshot. Refine until a brevity pass returns nothing: three rounds is normal.
- **The first fenced block appears within the first 40 lines.** A reader who scrolls to find how to run it has already lost.
- **Every command is copy-pasteable**: real flags, no `<placeholder>` in the run block (put the choice in the sentence above it), no `$` prompt prefix, one block per step sequence. A warning stands before the command it protects, never after.
- **Every screenshot shows the thing the nearest text describes**, taken by a script that is in the repo (a smoke test, a `make shots`), so it can be remade. Images live under `docs/screenshots/`, under 100 KB each.
- **Prerequisites are counted.** Name every tool a newcomer must install before the block, with a link; include the ones an owner forgets (an external CLI's own OAuth client, a parse time zone). "Docker is the only requirement" is the goal.
- **No history, no scars.** No "previously", "used to", "no longer", "legacy", "renamed from", no changelog, no dates of past work. The README describes what is, in present tense (see `[[design-doc-no-scars]]`). Rationale sentences belong in `docs/`.
- **One place per fact.** A fact in `docs/` is linked from the README, not repeated; a count stated twice is a count stated wrong once.
- **No personal data in a public README or `docs/`**: no emails, ids, tokens, hostnames or employer content; defaults are named as defaults, never as the owner's values. A private repository may name its own hosts.
- **Anchors are an API.** Code and tests that print `README.md#section` bind that heading: grep the repository for `README.md#` before renaming or moving a heading, and keep a test that every emitted anchor is a heading (the check script verifies the current state).
- **Tests bind docs to code** (every tool in the table, every env var in the configuration page): when content moves, the test is repointed, never deleted.

### Prose

Short sentences, present tense, imperative for instructions. No marketing adjectives, no "simply", no "just". A section is a list or a table when its items are parallel; prose only for the pitch and the one sentence after each block.

### docs/

- Page names are reader questions (`architecture.md`, `credentials.md`, `configuration.md`, `cli.md`, `deployment.md`), lower-case, hyphenated; never `misc.md`, `notes.md`, `old-readme.md`.
- Each page opens with one sentence saying who reads it and when.
- A page that would be under 80 words is a section of a neighbour instead.
- In update mode, slice mechanically first: move whole sections of the old README into their `docs/` pages unchanged (a script, recorded in the scratchpad), then write the new README fresh, then rewrite each moved page as the current design of its topic with the same facts and no reference to how things were. Rewriting in the same pass as the move stays long.

### Mechanical check

Run before Present and again before Output; fix every FAIL, never present a failing README:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-repo-quickstart/bin/check_readme.zsh --repo <repo root>
```

It reports: word count against the cap, the line of the first fenced block, every relative link and image that does not resolve, every placeholder or prompt in the run block, every scar word, every `docs/*.md` not linked from the README, every `README.md#anchor` the code emits that is not a heading, and (WARN) every email address.

## Investigation folder

Root path: `/tmp/hemingway/structure-repo-quickstart/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`.

Scratchpad fields appended after `Last phase`:
```
- **Repo**: <path> @ <sha>
- **Moved to docs/**: <section → docs/page.md, ...> (update mode)
- **Screenshots**: <script that makes them> | none
```

## File storage

- `templates/readme.md` — the skeleton with every required section and a comment per slot.
- `bin/check_readme.zsh` — read-only mechanical check; `--repo` names the repository root; exits 1 on any FAIL.

## Workflow

### Determine mode

A README exists at the repository root → **update**. Otherwise → **research**. Print `Inferred **{mode}**: {evidence}.` and continue; the user overrides by naming a mode.

### Gather pointers

Collect the repository root, the audience (a newcomer who has never seen the project), and whether a UI exists (then which script takes screenshots). Derive `{topic-slug}` from the repository name and create the investigation folder per `/ari-hemingway--lib` with `--skill-name structure-repo-quickstart`. Write the initial scratchpad (Subject, Mode, Repo, Screenshots).

### Restore context

Follow `Restore context` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Investigate

Read, in this order, appending to `sources.md` per the lib cadence: the build or task runner file (`Makefile`, `package.json`, `pyproject.toml`), the entry point, the CI workflow, the existing README and `docs/`, and the test that exercises the UI if any. Run the quick start yourself in a scratch directory when the tooling allows; a run block that was never run is a `[TODO: verify]`.

In update mode, classify every existing section as **stays** (needed to start), **moves** (to which `docs/` page), or **goes** (history, duplicates), record the table in the scratchpad before writing, and grep the repository for `README.md#` so every heading the code points at keeps its slug or the code is repointed in the same change.

Print: `Investigate complete — {n} files read, run block {verified|unverified}. Next: Draft.`

### Draft

Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Start from `templates/readme.md`. Write `docs/` pages in the same pass, each rewritten whole. Take or refresh the screenshots with the repository's own script and record the command in the scratchpad. Run the mechanical check.

Print: `Draft complete — README {words} words, {k} docs pages, check {PASS|n FAIL}. Next: Fact-check.`

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`, scoped to: every command in a fenced block exists with those flags; every path in the layout exists; every claim about data or behaviour is anchored to a file; every link resolves.

Print: `Fact-check complete — {n} claims verified, {k} marked [TODO: verify]. Next: Present.`

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. In update mode, print the stays/moves/goes table first, then the `Draft ready` line.

### Output

The output is the repository: write `README.md` and `docs/*.md` into the working tree (not `output.md`), run the mechanical check once more, and stop before committing; the commit is the user's or the calling workflow's. Print: `Output complete — README.md ({words} words), docs/: {pages}. Check: PASS.`
