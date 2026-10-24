---
name: ari-bead-driven-development
description: "Work Ari's projects through beads (bd) and the Scotty UI in front of them: every wish, follow-up, decision or fix becomes a bead before any code, work is picked from `bd ready` and claimed, what is learned goes back into the bead, and a close carries its evidence. Use whenever Ari voices an intention mid-work (\"I want…\", \"we should…\", \"later…\"), asks what is next or what is ready, says \"file that\", \"make a bead\", \"put it in the backlog\", \"what did we decide\", or mentions bd, beads or Scotty, in any project that has a `.beads/` directory. Not for a session with no beads workspace anywhere: that is /ari-hemingway--structure-working-doc."
---

# Bead-driven development

Everything that we desire gets committed as a bead and then we work through it from the bead later. A wish is researched into a bead and waits for a pick; a directive gets its bead and is worked at once. Two surfaces read the same database: `bd` for Claude, Scotty for Ari. Scotty is a thin shell over `bd`, so fields, types and edges are chosen for how they render. This skill names no machine (Delegation); it was checked against bd 1.3.1 and Scotty 0.3.2.

A *bead* is one issue in a `.beads/` *workspace*. It is *ready* when open with no unclosed blocker, *claimed* when assigned and in_progress, *blocked* when a `blocks`, waits-for or conditional-blocks edge, or its parent's own blocker, keeps it out of `bd ready`, *deferred* in Scotty's Backlog, *human* when it carries that label and waits on Ari. A *close reason* is the evidence written once at close; a *memory* is a `bd remember` fact that `bd prime` injects into every session.

## Rules

- **A wish left in chat is forgotten.** A wish ("I want…", "later…") is researched into a bead in the same turn, and the turn stops there. A directive ("do it now") is filed, claimed and worked in the same turn: `bd create --json`, then `--claim`; bead first either way. A fix already made still gets its bead, created and closed together (Close). Otherwise a pick happens when Ari asks for next work, names a bead, or gives nothing. NEVER track work in TodoWrite, TaskCreate or a markdown list where a `.beads/` exists.
- **Search before filing.** `bd search "<words>"` first; it searches every status by default, closed included (`-s open` narrows). A match is the same outcome in other words. Open → `bd comment <id>` with the new words, never a new bead. Closed → say it was done (id, close reason) and ask whether this is new; if it is, file fresh with `--deps discovered-from:<closed-id>`; reopen only under the Confirm rule. `bd duplicate` and `bd supersede` are for two beads that already exist and close one of them.
- **bd writes are Claude's to run.** Ari's standing instruction covers every create, comment, dep, claim, close-with-evidence and update, except what the Confirm rule names; `/ari-clipboard-handoff` is for what needs his identity, his browser or his terminal (`bd human respond`, a Scotty click, Dolt or backup commands).
- **Every write runs as `BEADS_ACTOR=claude bd …`.** Scotty renders actors on its human allowlist as 👤 and everything else as 🤖; a bare `bd` on Ari's machine is attributed to him. The prefix reaches one command: never chain a second write behind `&&`. Reference tables show bare syntax; every Workflow command that writes carries the prefix.
- **Resolve the workspace each time.** `command -v bd` first. A host or window Ari named this session wins over cwd until he names another or says "here"; say which workspace each turn's writes went to, and every command there goes through `/ari-remote-tmux`, one command per call. A directory he named on this machine: `bd -C <dir> …` on every command, never `cd`. He named none and cwd or a parent has `.beads/` → run here. `.beads/` here and no `bd`: say so; ask whether the tracker lives on a host (`/ari-remote-tmux`) or `bd` should be installed. Neither → ask which project; never guess a path. NEVER `bd init` unasked: it makes a second, empty database Scotty does not read. `bd info` confirms the database; report the prefix of its ids (the part before the dash in any `bd ready --json` id), never its path.
- **Multi-line text goes through a file.** `--body-file`, `--design-file`, `--reason-file`, `bd comment --file`, `bd note --file`, written to the scratchpad. Remote, the file must reach the host first: `/ari-remote-tmux` owns user@host and runs the copy, then the command names the remote path; when that is more than the text deserves, keep remote text to one-line flags. A heredoc typed into a tmux window becomes several broken commands. NEVER `bd edit`: it opens `$EDITOR` and blocks; use `bd update <id> --description|--design|--acceptance|--append-notes`.
- **One bd command at a time per workspace.** Embedded Dolt has a single writer and every call, even `show`, touches the store; never fan out parallel agents against one database. Many beads at once go through `bd create -f <file.md>`, one issue per `##` heading.
- **`--json` for anything parsed.** `bd show <id> --json` returns an array even for one id; `bd list`, `bd ready` and `bd children` return arrays; `bd create --json` an object; `--silent` prints only the id.
- **Priorities are numbers.** `0` Critical, `1` High, `2` Medium (default), `3` Low, `4` Backlog; `P1` is accepted, `high` is rejected, and `bd ready -p` takes a bare integer.
- **`bd dep add <issue> <depends-on>`: the first id waits.** Say "A is blocked by B" aloud before typing `bd dep add A B`; `--deps blocks:X` on create reverses the edge. A wrong edge comes out with `bd dep remove <issue> <depends-on>`, same order.
- **Read, then claim, then release.** `bd show <id> --json` before `bd update <id> --claim`; `BEADS_ACTOR=claude bd unclaim <id> --if-assignee claude` plus a `bd note` of where it stands when work pauses, so Scotty's In Progress column is never a lie. NEVER claim a bead assigned to someone else or take a live claim with `--force`; `bd unclaim` only Claude's own stale claim, and `--if-assignee claude` makes a foreign claim a refusal, not a release.
- **Done without proof is not done.** `bd close <id> --reason "…"` with the commit, the check output or the observed state, at least twenty characters (this skill's floor, not bd's); a bare `bd close` stores the literal "Closed", which Scotty hides. NEVER `--force` past open children or a live blocker; close them first.
- **Decisions only Ari can make get the `human` label and no claim.** NEVER answer a `human`-labelled question yourself; there is no `bd human <id>` command despite what `bd prime` prints.
- **Project knowledge goes to `bd remember`, not MEMORY.md.** A fact about how this project's things work, which every session and account needs, is a memory; preferences about Ari himself stay in Claude's own memory; facts about a host go to `/ari-remote-tmux --describe`.
- **Confirm before `bd delete` of any bead, and before `reopen`, `defer`, `--status`, `-p`, `duplicate` or `supersede` on a bead Ari created.** Ari created it when `created_by` in `bd show <id> --json` is not `claude`; no confirm when he named the bead and the action this turn. Claude's own bead: act and say so. Prefer `bd duplicate` or `bd supersede` over delete.
- **No offsite copy exists until you make one.** No Dolt remote exists by default: NEVER `bd dolt remote add`, push or pull; `.beads/` is not committed; `bd export` or `bd backup` is the copy (see Keep the tracker honest).

## Reference

### Types (`-t`)

| type | use it for |
|---|---|
| task (default) | a unit of work with a known shape |
| bug | something observed broken; description carries repro and impact |
| feature | a new capability, researched before it is built |
| chore | upkeep with no user-visible change |
| epic | the container for `--parent` children; Epics view shows closed ÷ children |
| decision | a choice to record; options in the description, outcome in `--design` |
| spike | a timeboxed investigation, when the research needs what this turn cannot reach: a host, hardware, Ari's data; otherwise research now and file a feature. The finding goes in the close reason |
| milestone | no work itself; `bd dep add <milestone> <each>` makes it ready when all close |

`story` exists; it rarely fits home-lab work. `bd lint` reads open beads only (a bug closed on create is exempt) and wants `## Acceptance Criteria` for task, feature and bug, `## Steps to Reproduce` as well for bug, `## Success Criteria` for epic, nothing for chore. Acceptance has one home: a `- [ ]` checklist in the description when there is more than one check, `--acceptance` for a one-liner; never both.

### Priorities (`-p`)

| n | name | use it for | Focus Next up? |
|---|---|---|---|
| 0 | Critical | data loss, security, broken build | yes |
| 1 | High | Ari wants it this session, or today's work waits on it, e.g. a failing check on the path to today's deploy | yes |
| 2 | Medium | a wish voiced mid-work with a route and no deadline (the common case); the default | no |
| 3 | Low | polish | no |
| 4 | Backlog | a future idea, e.g. a someday mobile layout; still `bd defer` it | no |

### Statuses and Scotty columns

| status | `bd ready` | Scotty |
|---|---|---|
| open, unblocked | yes | Board Ready; Focus Next up when P0–P1 |
| open with a live blocker, or blocked | no | Board Blocked; Focus Blocked |
| in_progress, hooked | no | Board In Progress; Focus In flight |
| deferred | no | Board Backlog |
| closed | no | Board Done; Graph until "Live dependencies only" is on; Focus Recently finished when that column is toggled on. With the `archived` label: hidden from every view until the Archived toggle in the filter bar is on |

"What am I on" is `bd list -s in_progress`, never `bd ready`; "what is in Backlog" is `bd list -s deferred` (`--deferred` lists only a defer date, which an iceboxed bead lacks). Backlog has two doors: `bd defer <id> --reason "…"` is the icebox, open again only through `bd undefer <id>`; `bd defer <id> --until <date>` is a snooze that wakes to open on its own. NEVER set status `pinned`: it fits no column, so Board and List both drop it and Ari never sees it; a non-epic bead to keep in view gets `-p 1` (Focus Next up; Confirm rule if Ari created it). Epics never appear on Board or List; they do appear in Epics, Graph, the drawer, and in Focus whenever their status or priority qualifies, so keep epics at P2+ and never claim one.

### Dependency types

| edge | blocks `bd ready` | how |
|---|---|---|
| blocks | yes | `bd dep add <issue> <depends-on>`; `--deps <id>` or `--deps blocked-by:<id>` at create; `--deps blocks:<id>` reverses; `bd dep remove <issue> <depends-on>` deletes |
| parent-child | via the parent | `bd create … --parent <epic>`; `bd update <id> --parent <epic>` adopts an existing bead, `--parent ""` detaches; children inherit labels unless `--no-inherit-labels` |
| discovered-from | no | `bd create … --deps discovered-from:<id>`: provenance for a follow-up |
| relates-to | no | `bd dep relate <a> <b>`; `bd dep unrelate` undoes |
| duplicates, supersedes | no | `bd duplicate <id> --of <canonical>`; `bd supersede <old> --with <new>`; both close the first |

Graph draws blocking edges red, parent-child grey, relates dashed; Scotty never names an epic as its child's blocker. `bd dep tree <id>` shows the chain; cycles are refused at write time.

### Fields

| field | holds | write |
|---|---|---|
| title | the outcome, one line, no parentheses (Graph and chips strip them) | positional, `--title` |
| description | why it exists, what is known, the route with evidence, what done looks like; GFM, `- [ ]` lines become a progress checklist of one bead's checks, never an epic's steps | `-d`, `--body-file` |
| design | a route chosen, and what was not chosen | `--design`, `--design-file` |
| acceptance | a one-check definition of done; more than one check is the description's checklist instead | `--acceptance` (single line) |
| notes | where to resume; may be overwritten; `bd defer --reason` lands here | `bd note <id> text`, `--append-notes`; `--notes` REPLACES |
| comments | a finished step or a question for Ari; permanent, read in order | `bd comment <id> text`; read with `bd comments <id>` |
| close_reason | evidence, written once | `bd close --reason`, `--reason-file` |
| labels | project and cross-cutting tags, comma-separated; `human` and `archived` are load-bearing | `-l a,b`, `--add-label`, `--remove-label`, `bd label add <id> <label>` |
| external_ref | the PR or upstream issue id, for `bd list --external-ref` and a `gh:pr` gate; Scotty never shows it, so paste the URL into the description, notes or a comment too | `--external-ref gh-9` |

A quoted space makes one label. `--set-labels ""` is silently dropped; empty with `--remove-label`. Due dates, estimates, defer dates and external_ref do not render in Scotty; say a date in notes too.

### What is not a bead

A chat question, a clarification, reading code to answer Ari, a step inside a claimed bead (that is a `bd note`). A wish with no next step yet gets a bead at `-p 4`, then `BEADS_ACTOR=claude bd defer <id> --reason "no route yet"` so it sits in Backlog; `--until <date>` instead when a date, not a route, is what it waits for.

### Scotty

"You should just learn about Scotty to recommend the best action for me." So a recommendation names the view where Ari will see its effect, never a URL; the bead link shape is `/p/<project>?bead=<id>` and Ari's bookmark supplies the origin.

| question | view |
|---|---|
| what is waiting on me | Needs You: `human`-labelled beads not closed or deferred, plus ready human gates |
| what is in flight, stuck, next | Focus: In flight, Blocked, Next up (ready P0–P1); Recently finished is an optional fourth column |
| where does each bead sit | Board; drag sets status, Backlog = deferred; manual order is Scotty-local |
| groom priorities and the backlog | List: every bead under its Board column heading, priority and labels inline |
| how far is the epic | Epics: closed ÷ children |
| what blocks what | Graph, scoped to the epic, "Live dependencies only" hides closed and unlinked |
| what did we decide | the bead's drawer: design, comments, close reason (Answer what was decided has the `bd` side) |
| what did Claude do, how fast does work flow | Activity: 👤/🤖 feed; Insights: throughput and age, split human vs agent |
| share the tracker | Publish builds a public static showcase of every bead: never recommend it for a private tracker |

Scotty's Respond on Needs You comments and removes the `human` label, leaving the bead open; Dismiss removes the label only; `bd human respond <id> -r "…"` comments and closes it. Read-only mode refuses writes server-side; if Ari says he cannot edit, he clicks the banner to disable it. A `- [ ]` checklist in the description shows as a done/total chip on the card; he ticks items in the drawer's description. `bd config set audit.enabled true` writes `.beads/interactions.jsonl`, which Activity and Insights read; without it they fall back to bead timestamps. Recommend it once, never flip it unasked.

### Refusals

| sign | meaning | do |
|---|---|---|
| exit 13 | an `--if-status`/`--if-assignee` guard was stale; nothing written | re-read with `bd show --json`; never retry blindly |
| "already claimed" | another actor holds the bead | leave it; report in chat |
| close refused: open children or live blocker | bd protects the tree | close them first, then `bd close <epic> --reason`; never `--force` |
| close refused because the actor is not the assignee (wording varies) | another actor holds the claim, or the `BEADS_ACTOR=claude` prefix was dropped | fix the prefix; else report, the holder closes or unclaims; never `--force` or unclaim another's claim |
| unclaim refused: `is not assigned`, or the bead is closed | nothing to release: the claim is already gone, or the bead is closed | report and move on; never `--force` |
| close of a closed bead | exit 0, nothing written, the old reason stays | check `bd show --json` status before re-closing; new evidence is a `bd comment`, never a second close |
| `bd ready` empty | "No open issues": nothing to do; "No ready work found": every open bead is held | No open issues → `bd list -s deferred`; a bead Ari picks: `BEADS_ACTOR=claude bd undefer <id>`, then claim; Backlog empty too → ask for the next wish. No ready work found → `bd ready --explain`, `bd blocked` |
| `bd prime` schema error | binary and database versions differ | `bd info`, `bd doctor`, report; no writes, never `--ignore-schema-skew` unasked |
| exit 124 via `/ari-remote-tmux` | still running | capture only; never resend |

A flag refused as unknown: `bd <cmd> --help` on that machine is the authority, not this skill. Flags here were checked against the 1.3.1 help and source; the quoted messages marked as varying were not, so match on the sense, not the string.

### Delegation

- Commands on a host Ari named: `/ari-remote-tmux`, one command per call; it owns host details and copies files there. Text Ari runs himself, and fetching a remote export: `/ari-clipboard-handoff`.
- A bead tree with statuses bound for a PR or issue: `/ari-diagram-gh-todo` (open/blocked red, in_progress yellow, closed green); any other diagram: `/ari-diagram-mermaid`, starting from `bd dep tree <id>`. `bd graph --dot` is Graphviz input, not Mermaid.
- A design that outgrows `--design`: `/ari-hemingway--structure-design-doc`; the bead keeps the link in `--external-ref` and in a comment, where Scotty shows it.

## Workflow

### Resolve the workspace and prime

Run `bd info`, then `bd prime`, at session start and again after compaction; `bd prime` prints memories and the close protocol. No `bd`, or no `.beads/` here and no host named: the Resolve rule says what to ask, and nothing runs before the answer. Then the state of play, one command per line, never chained: `&&` stops at the first nonzero exit (an empty `bd ready` hides the rest) and `/ari-remote-tmux` takes one command per call:

```zsh
bd ready --exclude-label human
bd list -s in_progress
bd blocked
bd human list
bd stale -d 14 -s in_progress
```

Nothing ready: Refusals. A non-empty `bd human list` means the next move is Ari's; a non-empty `bd stale` means a tidy (Keep the tracker honest). Chat: "Two ready (P1 first), one in flight, one waiting on you in Needs You."

### Answer what was decided

"What did we decide about …": `bd search "<words>"` (every status), then `bd show <id> --json` for `design` and `close_reason`, `bd comments <id>` for the thread in order, and `bd memories <word>` for a fact that outlived its bead. Answer with the id and the field's words, not a paraphrase. Nothing found anywhere → there was no decision: file one (Ask Ari a decision), never guess. Chat: "beads-o27's design: toggle, not a view; closed with ab4c456."

### Hear a wish, research it, file it

`bd search` first. Read enough of the code to know what exists today and what route is recommended; write the description to a file in the scratchpad:

```markdown
## Goal
Graph view hides closed and blocked beads behind a Frontier toggle, so the open frontier of an epic is readable.

## What exists today
The graph shows every bead of the scope; "Live dependencies only" hides closed and unlinked beads but keeps blocked ones.

## Route (recommended)
Extend the existing live-filter helper with a second predicate; the toggle state stays React-local like the current checkbox. Evidence: the helper already receives the full bead index.

## Not chosen
A new view: duplicates the layout code for one filter.

## Acceptance Criteria
- [ ] Toggle in the Graph header, default off
- [ ] With it on, closed and blocked beads and their edges are absent; epics stay
```

```zsh
BEADS_ACTOR=claude bd create "Graph view: Frontier toggle hides closed and blocked beads" -t feature -p 2 --body-file "$desc" --json
```

Labels come from `bd label list-all` (`-l a,b`). Found while on another bead: add `--deps discovered-from:<current-id>`. Part of an epic: `--parent <epic>`. Already fixed: see Close, filed and closed. A wish ends the turn here. Chat: "Filed beads-o27 (feature, P2); it waits for a pick." A directive goes straight on to Pick and claims the new id.

### Pick from `bd ready` and claim

Highest priority first from `bd ready --exclude-label human`; inside an epic, add `--parent <epic>`. Read it, then claim:

```zsh
bd show beads-o27 --json
BEADS_ACTOR=claude bd update beads-o27 --claim
```

Skip it when `show` says its labels include `human`, its assignee is set, or its status is not open; Scotty's Ready column still lists a `human` bead. `--claim` is atomic and idempotent; a refusal means someone else holds it, so pick another or ask. Chat the title and the definition of done you are working to.

### Work the bead

Comments, notes and design each have one job (Fields); the commands:

```zsh
BEADS_ACTOR=claude bd comment beads-o27 "Toggle wired; edge hiding next"
BEADS_ACTOR=claude bd update beads-o27 --design "Reused the live-filter helper; toggle state is React-local"
```

A bug or follow-up found on the way is its own bead with `--deps discovered-from:beads-o27`; if the current work cannot finish without it, also `BEADS_ACTOR=claude bd dep add beads-o27 <new-id>`. Something learned that outlives every bead: `BEADS_ACTOR=claude bd remember "Scotty reads the whole tracker through bd export --json, so export shape is its API" --key scotty-export-is-api`. `--key` always, or a slug-like text recalls instead of storing; `bd memories <word>` searches, `bd forget <key>` removes. Stopping unfinished: `BEADS_ACTOR=claude bd note beads-o27 "Edges still drawn for hidden nodes"`, then `BEADS_ACTOR=claude bd unclaim beads-o27 --if-assignee claude`. A bead Claude claimed cannot be closed by Ari from Scotty (bd refuses a close whose actor is not the assignee): unclaim or reassign before handing one over.

### Structure an epic

Epic when a step can be claimed, closed or handed over on its own, or spans a session; otherwise a checklist in one bead. Each step is a child, never a checklist line in the epic; order between children is a `blocks` edge. The epic body holds `## Goal` and `## Success Criteria` as a `- [ ]` list, in the shape of the wish body above; its checks are outcomes ("the compose file names a digest"), not steps.

`BEADS_ACTOR=claude bd create "Scotty runs from a pinned image" -t epic -p 2 --body-file "$epic" --json`, then `BEADS_ACTOR=claude bd create "<step>" --parent <epic> --body-file "$step"` per step, `BEADS_ACTOR=claude bd update <existing-id> --parent <epic>` for a bead that already exists, `BEADS_ACTOR=claude bd dep add <later-step> <earlier-step>` where one must follow another, and `bd children <epic>` to check. Chat: "Epics shows progress; Graph scoped to it shows the order."

### Ask Ari a decision

Write the question, the options and what each unblocks to a file, file it as a decision, and block the waiting work on it:

```zsh
BEADS_ACTOR=claude bd create "Decide: keep Frontier as a toggle or a view" -t decision -p 1 -l human --body-file "$q" --json
BEADS_ACTOR=claude bd dep add beads-o27 <decision-id>
```

Do not claim it. A question about a bead that already exists needs no new bead: `BEADS_ACTOR=claude bd comment <id> "<question and options>"`, then `BEADS_ACTOR=claude bd update <id> --add-label human`, after unclaiming it if Claude held it. Chat: "Waiting on you in Needs You: <title>." The answer shows at the next state of play: the bead has left `bd human list` and `bd comments <id>` has a new 👤 comment (Respond in Scotty leaves the bead open; `bd human respond` closes it). Label gone and no new comment means Ari pressed Dismiss: do not proceed on a guess; ask in chat or re-file the question. Record the outcome with `BEADS_ACTOR=claude bd update <decision-id> --design "…"`, then, if the bead is still open, `BEADS_ACTOR=claude bd close <decision-id> --reason "Ari chose <option>: <where he said so>" --suggest-next`. Only a closed decision unblocks the dependent; confirm with `bd ready`. Decision: Ari picks among options and the pick is recorded in `--design` (toggle or view?). Gate: a yes/no on one action with nothing to record (apply the new compose file? delete it?): `BEADS_ACTOR=claude bd gate create --type human --blocks <id> --reason "…"`. Ari approves in Needs You, or says yes in chat and Claude runs `BEADS_ACTOR=claude bd gate resolve <gate-id> -r "Ari: yes, <where>"`; either way the blocked bead is back in `bd ready`, which is how Claude notices.

### Close with evidence

```zsh
BEADS_ACTOR=claude bd close beads-o27 --reason "Commit ab4c456: Frontier toggle hides closed and blocked beads; doctor check PASS" --suggest-next
```

The reason names the commit, the check and what was observed. One id: `--suggest-next` prints what the close unblocked, which is the next pick. Several ids: `BEADS_ACTOR=claude bd close a b --reason "x" --reason "y"` (exactly one reason, or one per id in order), no `--suggest-next`: bd refuses it ("only works when closing a single issue"); run `bd ready` after. An epic whose children are all closed: `BEADS_ACTOR=claude bd close <epic> --reason "<evidence naming the children>"` like any bead; `bd epic close-eligible` is the tidy sweep only. Already closed, or children open: Refusals. Wrong bead closed: read `created_by` in `bd show <id> --json`; not `claude` → confirm; then `BEADS_ACTOR=claude bd reopen <id> -r "…"`. Chat: "Closed beads-o27 (ab4c456, doctor PASS); unblocked beads-p3k, picking it next." or "…nothing unblocked; `bd ready` shows two ready."

Work that waits for a PR: close the implementation bead with the PR in `--reason` and `BEADS_ACTOR=claude bd update <id> --external-ref gh-<pr#>`; the follow-up that needs the merge waits behind `BEADS_ACTOR=claude bd gate create --type gh:pr --await-id <pr#> --blocks <follow-up> --reason "needs PR <pr#> merged"`. At a later state of play `BEADS_ACTOR=claude bd gate check` closes the gate once the PR merged, and the follow-up is back in `bd ready`.

A fix already made is filed and closed together, the proof in the close reason; `bd lint` reads open beads, so this bug carries no `## Steps to Reproduce`:

```zsh
BEADS_ACTOR=claude bd create "Doctor: API check passes on an empty list" -t bug -p 2 -d "Doctor reported FAIL on a tracker with zero beads: the check read a key an empty list lacks" --json
BEADS_ACTOR=claude bd close beads-orc --reason "Fixed in commit ab4c456 and deployed: doctor check PASS, API lists beads"
```

### Close the session

Before saying "done": file a bead for every remaining ask; unclaim what is not finished with a note; close what is finished with reasons; run the project's quality gates; `git status`; report the handoff with each bead's id and state. No push, pull or Dolt sync.

### Keep the tracker honest

When Ari asks for a tidy, or the state of play shows an in_progress bead nobody has touched in two weeks (`bd stale -d 14 -s in_progress` non-empty), run the reads one per line: `bd stale -d 14 -s in_progress`, `bd lint`, `bd doctor`, `bd dep cycles`, `bd epic close-eligible --dry-run`. A nonzero exit from `bd lint` or `bd doctor` is a report, not a stop. Chat the findings, then:

- Stale: `BEADS_ACTOR=claude bd unclaim <id> --if-assignee claude` only Claude's own stale claims; report Ari's.
- Sweep: `bd epic close-eligible` CLOSES every listed epic when run without `--dry-run`; run `BEADS_ACTOR=claude bd epic close-eligible -r "<reason>"` only after Ari replies yes to the list in chat; the dry-run alone never leads to the sweep in the same turn.
- Archive, when Ari wants Done decluttered: the bead must already be closed, then `BEADS_ACTOR=claude bd label add <id> archived`; NEVER on an open bead, which Scotty would hide from every view while it is still live.
- Export: the first time, ask where exports go and `BEADS_ACTOR=claude bd remember "<dir>" --key export-dir`. Then `bd export --include-memories -o <export-dir>/<prefix>-<YYYY-MM-DD>.jsonl`, outside `.beads/`; memories are left out by default, so without the flag the copy drops every `bd remember` fact. Name the path in chat; a remote export stays on that host until Ari fetches it (Delegation).
