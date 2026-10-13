---
name: ari-parallel-play
description: "Orchestrate many small features in parallel on any repo: an orchestrator dispatches every ready ask of a working doc as a lane agent in a fresh worktree, owns CI and merges (per-group PR chains, one CI run per burst, watchers, fix-forward); lane agents only develop and hand off. Everything project-specific (gate, tooling, code rules, CI job, GitHub accounts, optional live check) comes from a repo profile the caller supplies."
---

# Parallel Play

Run many small features at once with two roles: one orchestrator that owns the queue, CI and merges, and plain lane agents that only develop. The skill knows nothing about any one project. Starting the orchestrator dispatches every ready ask of a `/ari-hemingway--structure-working-doc` folder immediately; each lane works in a fresh worktree, ships a rough first pass through the local gate the repo profile names, opens its PR onto the lane below it in a per-group chain or onto main, writes its Result and hands off. The orchestrator chains a burst of lanes in one group behind one CI run, merges the top on green, fixes forward on red, runs the profile's live check once per merge when it has one, and reports each event to the main thread in one line.

## Rules

- **Two roles, never crossed.** The orchestrator dispatches, watches CI, merges, runs the live check, recovers, reports. A lane agent develops, gates locally, opens its PR, writes its Result, hands off, returns. A lane never runs `gh run watch`, `gh pr merge` or a live check; the orchestrator never edits lane code except through a fixer lane.
- **Project facts come from the repo profile, never from this skill.** Gate commands, tooling forms, code rules, dependency sharing, shared paths, CI workflow and gate job, GitHub accounts, lane groups, per-lane environment and the live check are all read from the profile (see Repo profile). A missing optional section means that behavior is skipped, not improvised.
- **Never end a turn waiting.** An agent that stops "until the monitor fires" is dead: nothing wakes it. Poll in foreground loops of at most 60 s, or return.
- **Disjoint files or wait.** Concurrent lanes must own disjoint files, measured by `bin/lane-overlap.zsh` from each lane's merge-base (a diff against `origin/main` overstates a lane once main moved). The profile's shared paths (default `docs/`) count as shared: a lane touching one is the only lane of its group running.
- **Fresh worktree, shared dependencies.** Every lane gets `bin/worktree.zsh --action open`: a new worktree on its own branch plus, when the profile names a shared dependency directory, a symlink to the root's copy. Never install dependencies in a worktree. Handoff is `--action handoff`: unlink first, then `git worktree remove`; the branch stays. A forced remove that follows the symlink wipes the root's copy.
- **GitHub with the profile's accounts.** Reads use the read account, writes the write account; they may be the same. Poll CI no faster than every 60 s. An empty job list is a rate limit, not a red run. Never `gh pr merge --auto`. Never delete a remote branch before `gh pr view --json state` says `MERGED` (a delete after a refused merge auto-closes the PR).
- **A permission denial is the user's decision.** Record it in the Result and route around; never re-run the same action in another form (a wrapper, other flags, a subshell).
- **Never `SendMessage` a Workflow subagent.** The harness resumes a second copy into the same worktree. Message plain Agent lanes only; change a Workflow by stopping and resuming its script.
- **Chain a burst.** Two or more lanes in one group land as a chain in the working doc's row order: lane 1 branches from `origin/main`, lane k from lane k-1's branch, and each PR targets the branch it came from (lane 1's PR targets main). Every chain head carries `[skip ci]`, so no chain PR runs CI on its own. When the whole chain has handed off, the orchestrator finalizes it (see Watch and merge): the top PR is retargeted to main and gets one empty commit without `[skip ci]`, CI runs once, the watcher merges it with a merge commit, and the lower PRs are closed with a comment naming the top (their commits are in the merge). A red top is fixed forward on the top branch. Lanes outside any group go to main alone. Never squash sub-PRs into an integration branch yourself: that is a merge without review, and only the owner may run it.
- **Every agent carries its role and lane in its name.** The Agent tool's `description` is the name the user sees: `orchestrator <repo>` for the orchestrator, `lane <id>` for a lane, `fixer <id>` for a fixer. Never spawn one described only by its type.
- **Commits and PR bodies** follow `templates/fast-path.md` (the trailer, the `/dev/tty` hook fallback) and `/ari-pr`.

## Input

The working-doc folder (or its subject, for resume mode), the repo root, and the repo profile (a path, or the profile's text). Nothing else: every other fact is in the profile.

## Repo profile

One markdown file per repo, owned by the caller (a path like `<repo>/.parallel-play.md`, or text pasted into the orchestrator's prompt). Start from `templates/repo-profile.md`. Its `##` sections, each read verbatim into the lane prompt or into a script flag:

| Section | Required | Feeds |
|---|---|---|
| `## Tooling` | yes | how to run the toolchain without a global install (e.g. `node node_modules/<tool>/...` forms when `npx` is denied) and how to run a tool script |
| `## Gate` | yes | the numbered local gate: typecheck, lint on touched files, tests on touched files; nothing the whole tree would run |
| `## Code rules` | yes | the project's conventions in one paragraph |
| `## Dependencies` | yes | a `- Link: <dir>` line naming the shared dependency directory to symlink from the root (`node_modules`, `.venv`, …) or `none`, then the install rule |
| `## Shared paths` | no | path prefixes only one lane of a group may touch; default `docs/` |
| `## CI` | yes | the workflow name and the gate job name the watcher merges on |
| `## GitHub` | yes | `- Read account:`, `- Write account:` (the same account is fine) and `- Unset first:` lines: the gh accounts and any env var to unset so gh uses them |
| `## Groups` | no | the areas whose lanes chain together, and how an ask maps to one; absent means every lane is solo |
| `## Lane environment` | no | per-lane values the lane needs (a port offset formula, an env var); rendered into the prompt as given |
| `## Live check` | no | the URL per group and the command that verifies a merge is live; absent means no live check |
| `## Commit` | no | extra commit or PR-body rules beyond `/ari-pr`; the fast path's trailer and hook fallback always apply |

## Investigation folder

```
/tmp/parallel-play/{topic-slug}/{timestamp}/
├── profile.md          # the repo profile as given, so lanes and fixers read one copy
├── prompt-<id>.md      # each lane's rendered prompt
├── lanes.json          # [{id, group, worktree, branch, base, chain, pr, env, status, files_owned}]
└── watch-<branch>.log  # one watcher log per PR
```

`worktree` is null after the handoff; `chain` is `solo`, `bottom`, `middle` or `top`; `env` holds the lane's rendered Lane environment, or null. One entry:

```json
{"id": "export-csv", "group": "reports", "worktree": null, "branch": "export-csv", "base": "filters", "chain": "middle", "pr": 125, "env": null, "status": "review", "files_owned": ["src/reports/export.ts"]}
```

The working doc stays where `/ari-hemingway--structure-working-doc` put it; this folder holds only orchestration state. It is under `/tmp`: say so once.

## File storage

- `bin/lane-overlap.zsh` — read-only: each lane's owned files from its merge-base diff plus working tree and untracked files (or from `origin/<branch>` for a handed-off lane), the pairwise overlap matrix, and the ready set against the lanes marked `--running`. `--shared` takes the profile's prefixes. JSON on stdout.
- `bin/watch-merge.zsh` — one PR's life: waits for the PR, follows CI per head with the read account, merges on the gate job's green with the write account (a merge commit by default; `--merge-method squash` for a lone lane), verifies `MERGED`, then deletes the remote branch and watches the base branch's run. `--url` adds the live curl; without it the live step is skipped. `--dry-run` logs the merge instead.
- `bin/worktree.zsh` — `--action open` (worktree on `--branch` from `--base`; `--link DIR` symlinks the root's shared dependency directory; idempotent; errors when the directory holds another branch) and `--action handoff` (unlink, then remove; the branch stays).
- `bin/render-lane-prompt.zsh` — read-only: the lane prompt on stdout from the profile, the ask file and the lane's coordinates; fills every fast-path slot (the gh write prefix from the GitHub section, `--link` from the Dependencies `- Link:` line) and fails on a missing section or an unrendered slot.
- `templates/repo-profile.md` — the profile skeleton a caller fills in once per repo.
- `templates/lane-prompt.md` — the lane agent's prompt: the ask file's Ask, Context and Brief verbatim, the lane's coordinates, then the rendered fast path.
- `templates/fast-path.md` — the lane rules with `{{...}}` slots the profile fills: one feature per PR, the local gate, the commit form, the landing steps, the handoff, the 25-minute budget.

## Workflow

### Orchestrator

Spawned once by the main thread as a long-lived general-purpose Agent described `orchestrator <repo>` (never a fork: a fork cannot spawn the lanes). It returns only when every row is `done`, `dropped` or `review`.

#### Resume the doc

Follow `Restore context` of `/ari-hemingway--structure-working-doc` for the given folder; run its `check` and read `asks.json`. Create the investigation folder, copy the repo profile to `profile.md`, and write `lanes.json` with one entry per `todo` or `running` row.

#### Dispatch everything ready

Every `todo` row whose Needs are settled and whose owner is `agent:*` is dispatchable; a `user`-owned row stays `review` for the user. No dispatchable row: one line to `main`, return. For each dispatchable row, in one pass: the branch is `<id>`; the group is the one the profile's Groups section maps the row to (or none); the chain position follows the doc's row order among that group's dispatchable and running rows (`solo` when alone, else `bottom`, `middle`, `top`); the base is `origin/main` for `solo` and `bottom`, else the branch of the lane below; the lane environment is the profile's Lane environment rendered for this lane, or none. Open its worktree (`--link` only when the profile's Dependencies section names a directory):

```zsh
zsh $HOME/.claude/skills/ari-parallel-play/bin/worktree.zsh --action open --root <root> --dir <invest>/wt-<id> --branch <id> --base <base> --link <shared-dir>
```

Before starting lanes concurrently, clear them (a handed-off lane is given as `<id>=<branch>`; one `--shared` per profile prefix):

```zsh
zsh $HOME/.claude/skills/ari-parallel-play/bin/lane-overlap.zsh --root <root> --base origin/main --lane <id>=<invest>/wt-<id> --running <id-of-a-running-lane> --shared <prefix>
```

A lane in the ready set starts now; one that overlaps a running lane waits for that lane's PR. Render its prompt (`--chain yes` for `bottom`, `middle` and `top`, `no` for `solo`; `--lane-env` only when the profile's Lane environment needs per-lane values filled in):

```zsh
zsh $HOME/.claude/skills/ari-parallel-play/bin/render-lane-prompt.zsh --profile <invest>/profile.md --ask-file <doc>/asks/<id>.md --id <id> --repo-name <owner/name> --root <root> --worktree <invest>/wt-<id> --branch <id> --base <base> --pr-base <pr-base> --chain <yes|no> --other-lanes "<ids>" > <invest>/prompt-<id>.md
```

Spawn a general-purpose Agent described `lane <id>` with that file's text, record the row and the lane:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-working-doc/bin/asks.zsh set --file <doc>/asks.json --id <id> --status running --owner agent:<id> --dispatch agent:<id>
```

Report one line to `main`: the lanes started and the ones waiting.

#### Watch and merge

A `solo` lane's PR gets a watcher the moment the lane reports it (`--url` only when the profile has a Live check; `--write-user` only when it differs from the read account):

```zsh
zsh $HOME/.claude/skills/ari-parallel-play/bin/watch-merge.zsh --branch <branch> --base main --workflow <ci-workflow> --gate <gate-job> --read-user <read-account> --write-user <write-account> --url <live-url> --merge-method squash > <invest>/watch-<branch>.log 2>&1 &
```

A chain waits until every lane of it has handed off, then the orchestrator finalizes it in a fresh worktree on the top branch (`--action open --base <top-branch>`): rebase lane 2 onto lane 1's final head, lane 3 onto lane 2's, up to the top, pushing each with `--force-with-lease`; `gh pr edit <top> --base main`; one empty commit on the top (`git commit --allow-empty -m "ci: run the chain"`, no `[skip ci]`), pushed; then the watcher above with `--merge-method merge` (the default) and `--keep-branch`. When the top merges, close each lower PR with `gh pr close <n> --comment "Landed through #<top>"` and delete its branch, then the top's. A red top gets a fixer on the top branch (see Recover). A merge the permission classifier denies stays with the watcher; tell `main` once.

#### Recover

A lane whose PR is red and whose agent has been silent for 15 minutes gets a fixer: a fresh Agent described `fixer <id>` in a fresh worktree on that branch (`--action open` with `--base <branch>`), the failed job's log (`gh run view <id> --log-failed` with the read account), the ask file's Brief and `profile.md`. A lane past 25 minutes reports what is left and stops. A chain lane with no PR at its budget is dropped: the lanes above it rebase onto its base, its row goes `review` with the reason.

#### Live check

Only when the profile has a Live check section. Once per merge to main, after the watcher prints its live line, run the profile's verification command for the lane's group and read its result. A check that reads wrong: the row goes `review` and `main` gets one line. Record the outcome in the row's Result. Without the section, a verified `MERGED` is the outcome.

#### Track

On each lane Result or merge: `done` when merged and the live check (if any) passed, else `review`, through the `asks.zsh set` form above; run `check`, re-render `draft.md`, update `lanes.json` (a merged lane leaves the overlap inputs: its remote branch is gone), and send `main` one line: `<lane> merged as PR #n (sha); next: <lane>`. When no row is `todo` or `running`, return a summary: lanes, PRs, what remains.

### Lane agent

A plain general-purpose Agent described `lane <id>`, given the rendered prompt. Its whole life is the rendered `templates/fast-path.md`:

1. **Open**: work only in the given worktree, with the profile's tooling forms.
2. **Develop**: one feature, a working first pass.
3. **Gate**: the profile's gate, on the touched files and suites only.
4. **Land**: `[skip ci]` on the head commit of a chain lane; fetch and rebase onto the base branch right before pushing; push `--force-with-lease`; `gh pr create --base <base branch>`.
5. **Result**: append outcome, PR URL, head sha, files, gates run and what is left to the ask file's `## Result`.
6. **Handoff**: `bin/worktree.zsh --action handoff`, then return. Past 25 minutes: land what is green, list the rest, return.
