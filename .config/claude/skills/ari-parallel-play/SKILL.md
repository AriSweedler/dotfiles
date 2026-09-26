---
name: ari-parallel-play
description: "Orchestrate many small features in parallel: an orchestrator dispatches every ready ask from a working doc as a lane agent in a fresh worktree, owns CI and merges (per-game PR chains, one CI run per burst, watchers, fix-forward), checks live once per merge; lane agents only develop and hand off."
---

# Parallel Play

Run many small features at once with two roles: one orchestrator that owns the queue, CI and merges, and plain lane agents that only develop. Starting the orchestrator dispatches every ready ask of a `/ari-hemingway--structure-working-doc` folder immediately; each lane works in a fresh worktree on a shared `node_modules` symlink, ships a rough first pass through a fast local gate, opens its PR onto the lane below it in a per-game chain or onto main, writes its Result and hands off. The orchestrator chains a burst of lanes on one game behind one CI run, merges the top on green, fixes forward on red, checks the live site once per merge, and reports each event to the main thread in one line.

## Rules

- **Two roles, never crossed.** The orchestrator dispatches, watches CI, merges, checks live, recovers, reports. A lane agent develops, gates locally, opens its PR, writes its Result, hands off, returns. A lane never runs `gh run watch`, `gh pr merge` or a live check; the orchestrator never edits lane code except through a fixer lane.
- **Never end a turn waiting.** An agent that stops "until the monitor fires" is dead: nothing wakes it. Poll in foreground loops of at most 60 s, or return.
- **Disjoint files or wait.** Concurrent lanes must own disjoint files, measured by `bin/lane-overlap.zsh` from each lane's merge-base (a diff against `origin/main` overstates a lane once main moved). `docs/**`, `CONTRACT.md`, `e2e/fixtures/**` and story baselines count as shared: a lane touching them is the only lane of its game running.
- **Fresh worktree, shared modules.** Every lane gets `bin/worktree.zsh --action open`: a new worktree on its own branch plus a `node_modules` symlink to the root. Never `npm install`/`npm ci` in a worktree. Handoff is `--action handoff`: `unlink` the symlink first, then `git worktree remove`; the branch stays. A forced remove that follows the symlink wipes the root's modules.
- **GitHub reads with the personal token, writes with the work token.** Poll CI no faster than every 60 s. An empty job list is a rate limit, not a red run. Never `gh pr merge --auto`. Never delete a remote branch before `gh pr view --json state` says `MERGED` (a delete after a refused merge auto-closes the PR).
- **A permission denial is the user's decision.** Record it in the Result and route around; never re-run the same action in another form (a wrapper, other flags, a subshell).
- **Never `SendMessage` a Workflow subagent.** The harness resumes a second copy into the same worktree. Message plain Agent lanes only; change a Workflow by stopping and resuming its script.
- **Chain a burst.** Two or more lanes on one game land as a chain in the working doc's row order: lane 1 branches from `origin/main`, lane k from lane k-1's branch, and each PR targets the branch it came from (lane 1's PR targets main). Every chain head carries `[skip ci]`, so no chain PR runs CI on its own. When the whole chain has handed off, the orchestrator finalizes it (see Watch and merge): the top PR is retargeted to main and gets one empty commit without `[skip ci]`, CI runs once, the watcher merges it with a merge commit, and the lower PRs are closed with a comment naming the top (their commits are in the merge). A red top is fixed forward on the top branch. Lanes outside any game go to main alone. The alternative, squash-merging `[skip ci]` sub-PRs into an integration branch `<game>-stack`, is denied by the permission classifier as "Merge Without Review" (2026-09-25): it exists only when the owner runs those merges himself.
- **Commits and PR bodies** follow `templates/fast-path.md` (the trailer, the `/dev/tty` hook fallback) and `/ari-pr`.

## Input

The working-doc folder (or its subject, for resume mode), the repo root, the games or areas with a port-offset base each, the GitHub users for reads and writes, and the live URL per game.

## Investigation folder

```
/tmp/parallel-play/{topic-slug}/{timestamp}/
├── lanes.json          # [{id, game, worktree, branch, base, chain, pr, offset, status, files_owned}]
└── watch-<branch>.log  # one watcher log per PR
```

`worktree` is null after the handoff; `chain` is `solo`, `bottom`, `middle` or `top`. One entry:

```json
{"id": "deck-viewer", "game": "briscola", "worktree": null, "branch": "deck-viewer", "base": "single-game", "chain": "middle", "pr": 125, "offset": 8200, "status": "review", "files_owned": ["web/games/briscola/src/ui/deck.ts"]}
```

The working doc stays where `/ari-hemingway--structure-working-doc` put it; this folder holds only orchestration state. It is under `/tmp`: say so once.

## File storage

- `bin/lane-overlap.zsh` — read-only: each lane's owned files from its merge-base diff plus working tree and untracked files (or from `origin/<branch>` for a handed-off lane), the pairwise overlap matrix, and the ready set against the lanes marked `--running`. JSON on stdout.
- `bin/watch-merge.zsh` — one PR's life: waits for the PR, follows CI per head with the read user, merges on the gate job's green with the write user (a merge commit by default; `--merge-method squash` for a lone lane), verifies `MERGED`, then deletes the remote branch, watches main's run and curls the live URL for 200 plus the new bundle. `--dry-run` logs the merge instead.
- `bin/worktree.zsh` — `--action open` (worktree on `--branch` from `--base` plus the `node_modules` symlink; idempotent; errors when the directory holds another branch) and `--action handoff` (unlink, then remove; the branch stays).
- `templates/lane-prompt.md` — the lane agent's prompt: the ask file's Ask, Context and Brief verbatim, the lane's coordinates, then `templates/fast-path.md`.
- `templates/fast-path.md` — the lane rules: one feature per PR, the local gate, the commit form, the landing steps, the handoff, the 25-minute budget.

## Workflow

### Orchestrator

Spawned once by the main thread as a long-lived general-purpose Agent (never a fork: a fork cannot spawn the lanes). It returns only when every row is `done`, `dropped` or `review`.

#### Resume the doc

Follow `Restore context` of `/ari-hemingway--structure-working-doc` for the given folder; run its `check` and read `asks.json`. Create the investigation folder and `lanes.json` with one entry per `todo` or `running` row.

#### Dispatch everything ready

Every `todo` row whose Needs are settled and whose owner is `agent:*` is dispatchable; a `user`-owned row stays `review` for the user. No dispatchable row: one line to `main`, return. For each dispatchable row, in one pass: the branch is `<id>`; the game is the row's game (or none); the chain position follows the doc's row order among that game's dispatchable and running rows (`solo` when alone, else `bottom`, `middle`, `top`); the base is `origin/main` for `solo` and `bottom`, else the branch of the lane below; the port offset is the game's base plus 100 times the lane's index. Open its worktree:

```zsh
zsh $HOME/.claude/skills/ari-parallel-play/bin/worktree.zsh --action open --root <root> --dir <invest>/wt-<id> --branch <id> --base <base>
```

Before starting lanes concurrently, clear them (a handed-off lane is given as `<id>=<branch>`):

```zsh
zsh $HOME/.claude/skills/ari-parallel-play/bin/lane-overlap.zsh --root <root> --base origin/main --lane <id>=<invest>/wt-<id> --running <id-of-a-running-lane>
```

A lane in the ready set starts now; one that overlaps a running lane waits for that lane's PR. Render the prompt from `templates/lane-prompt.md` (`{{chain_lane}}` is `yes` for `bottom`, `middle` and `top`, `no` for `solo`), spawn a general-purpose Agent, record the row and the lane:

```zsh
zsh $HOME/.claude/skills/ari-hemingway--structure-working-doc/bin/asks.zsh set --file <doc>/asks.json --id <id> --status running --owner agent:<id> --dispatch agent:<id>
```

Report one line to `main`: the lanes started and the ones waiting.

#### Watch and merge

A `solo` lane's PR gets a watcher the moment the lane reports it:

```zsh
zsh $HOME/.claude/skills/ari-parallel-play/bin/watch-merge.zsh --branch <branch> --base main --url <live-url> --read-user <personal> --write-user <work> --merge-method squash > <invest>/watch-<branch>.log 2>&1 &
```

A chain waits until every lane of it has handed off, then the orchestrator finalizes it in a fresh worktree on the top branch (`--action open --base <top-branch>`): rebase lane 2 onto lane 1's final head, lane 3 onto lane 2's, up to the top, pushing each with `--force-with-lease`; `gh pr edit <top> --base main`; one empty commit on the top (`git commit --allow-empty -m "ci: run the chain"`, no `[skip ci]`), pushed; then the watcher above with `--merge-method merge` (the default) and `--keep-branch`. When the top merges, close each lower PR with `gh pr close <n> --comment "Landed through #<top>"` and delete its branch, then the top's. A red top gets a fixer on the top branch (see Recover). A merge the permission classifier denies stays with the watcher; tell `main` once.

#### Recover

A lane whose PR is red and whose agent has been silent for 15 minutes gets a fixer: a fresh Agent in a fresh worktree on that branch (`--action open` with `--base <branch>`), the failed job's log (`gh run view <id> --log-failed` with the read user), and the ask file's Brief. A lane past 25 minutes reports what is left and stops. A chain lane with no PR at its budget is dropped: the lanes above it rebase onto its base, its row goes `review` with the reason.

#### Live check

Once per merge to main, after the watcher prints the live line: curl the game's URL for 200 and the new bundle, take one 390x844 screenshot with Playwright and read it. A page that reads wrong: the row goes `review` and `main` gets one line. Record the outcome in the row's Result.

#### Track

On each lane Result or merge: `done` when merged and the live check passed, else `review`, through the `asks.zsh set` form above; run `check`, re-render `draft.md`, update `lanes.json` (a merged lane leaves the overlap inputs: its remote branch is gone), and send `main` one line: `<lane> merged as PR #n (sha), live <bundle> ok; next: <lane>`. When no row is `todo` or `running`, return a summary: lanes, PRs, what remains.

### Lane agent

A plain general-purpose Agent with the rendered prompt. Its whole life is `templates/fast-path.md`:

1. **Open**: work only in the given worktree; `npx` is denied, use the `node node_modules/...` forms listed in the template.
2. **Develop**: one feature, a working first pass.
3. **Gate**: typecheck; eslint and prettier on the touched files; only the touched suites; at most one e2e spec at the lane's offset; goldens re-recorded only when a pinned selector changed.
4. **Land**: `[skip ci]` on the head commit of a chain lane; fetch and rebase onto the base branch right before pushing; push `--force-with-lease`; `gh pr create --base <base branch>`.
5. **Result**: append outcome, PR URL, head sha, files, gates run and what is left to the ask file's `## Result`.
6. **Handoff**: `bin/worktree.zsh --action handoff`, then return. Past 25 minutes: land what is green, list the rest, return.
