---
name: ari-bead-driven-development
description: "Work Ari's projects through beads (bd) and the Scotty UI in front of them: every wish, follow-up, decision or fix becomes a bead before any code, work is picked from `bd ready` within this session's own epics and claimed (another session's beads in a shared workspace are never its frontier, its pick or its write), what is learned goes back into the bead, and a close carries its evidence. Use whenever Ari voices an intention mid-work (\"I want…\", \"we should…\", \"later…\"), asks what is next or ready, or for the frontier, says \"file that\", \"make a bead\", \"put it in the backlog\", \"what did we decide\", or mentions bd, beads or Scotty, in any project that has a `.beads/` directory. Not for a session with no beads workspace anywhere: that is /ari-hemingway--structure-working-doc."
---

# Bead-driven development

Everything that we desire gets committed as a bead and then we work through it from the bead later. A wish is researched into a bead and waits for a pick; a directive gets its bead and is worked at once. Two surfaces read the same database: `bd` for Claude, Scotty for Ari. Scotty is a thin shell over `bd`, so fields, types and edges are chosen for how they render. This skill names no machine (Delegation).

A *bead* is one issue in a `.beads/` *workspace*. It is *ready* when open with no unclosed blocker, *claimed* when assigned and in_progress, *blocked* when a `blocks`, waits-for or conditional-blocks edge, or its parent's own blocker, keeps it out of `bd ready`, *deferred* in Scotty's Backlog, *human* when it carries that label and waits on Ari. A session's *scope* is the top epic above each bead it filed or claimed, each such bead that has no parent, and every id Ari named, with their descendants; `all`, the whole workspace, only when he says so or the workspace holds no epic (Scope). The *frontier* is the scope's state of play the tracker reports now, ready, in progress, blocked and waiting on Ari: the commands of Read the frontier, never recalled. A *close reason* is the evidence written once at close; a *memory* is a `bd remember` fact that `bd prime` injects into every session. *unfiled:* and *unremembered:* are the two chat ledgers for what the tracker could not take this turn: a wish or directive quoted verbatim, a fact with its key; each is written on the first command once the tracker answers.

## Rules

- **A wish left in chat is forgotten.** A project wish ("I want…", "later…") is researched into a bead in the same turn, its body through `--body-file`, and the turn stops there. Until the bead exists the wish is unfiled, however much of it sits in a draft, and no memory holds the wish itself; a preference voiced with it is a `bd remember` memory as usual. A fix already made still gets its bead, created and closed together (Close with evidence). Otherwise a pick happens when Ari asks for next work, names a bead, or gives nothing. NEVER track work in TodoWrite, TaskCreate or a markdown list where a `.beads/` exists.
- **A directive is filed, claimed and worked in the same turn.** A directive is any order to act in this turn ("fix X now", "do it", "go"), with or without a priority: `bd search` as for a wish, then `BEADS_ACTOR=claude bd create "<title>" -p <n> -l <label> --body-file "$desc" --json`, then `BEADS_ACTOR=claude bd update <id> --claim`, then the work; bead first, no exceptions. A message that states a problem or need with no order aimed at Claude and no "later" ("the doctor check is failing", "Graph is unreadable with closed beads") is unclear: NEVER default it to either; file it as a directive but leave it unclaimed, and end the turn with one question, "<id>: work it now, or leave it for a pick? recommended: <now | pick> — <why>", recommending `now` when it files at P1, else `pick`; his "now" claims and works it, his "pick" leaves it waiting like a wish. `<n>` is the number Ari said; a word the Priorities table lacks ("urgent") is no priority; no priority means P1 when today's work waits on it (a claimed bead or the session's stated goal cannot close without it), else P2, and the chat line names the number and its reason ("P1: today's deploy waits on it"). A P0 while another bead is in hand: create the P0 first, then `BEADS_ACTOR=claude bd note <held-id> "<where it stands>"` and `BEADS_ACTOR=claude bd unclaim <held-id> --if-assignee claude`, then claim the P0 (a failed create leaves the held bead held); the P0 is the only bead worked until it closes. A directive whose search finds an open bead in the scope, or that names an open bead, works that bead instead of a create: his words in a comment, then the read and the claim (Read, then claim, then release); its priority moves only when he gives one. A `bd create` that fails is a refusal (Refusals): quote the error, claim nothing, and the directive sits under "unfiled:" like a wish; cut off, the same (Cut off rule).
- **Search before filing.** `bd search "<words>"` first; it searches every status by default, closed included (`-s open` narrows). A match is the same outcome in other words. Open in the scope → `bd comment <id>` with the new words, never a new bead. Open outside it → not this session's: write nothing to it, file this one, and name the match with its `created_by` in the chat line ("beads-amm, another Claude session's, is close; name it to fold this in", "…, yours, …"); once Ari names it, it is in the scope: `bd comment` the new words on it and `BEADS_ACTOR=claude bd duplicate <new> --of <it>`. Closed → say it was done (id, close reason) and ask whether this is new; if it is, file fresh with `--deps discovered-from:<closed-id>`, an edge on the new bead and so allowed to any bead; reopen only a bead in the scope, under the Confirm rule. `bd duplicate` and `bd supersede` are for two beads that already exist and close one of them.
- **bd writes are Claude's to run.** Ari's standing instruction covers every create, comment, dep, claim, close-with-evidence and update, except what the Confirm rule names; `/ari-driving-tmux` is for what needs his identity, his browser or his terminal (`bd human respond`, a Scotty click, Dolt or backup commands).
- **Every write runs as `BEADS_ACTOR=claude bd …`.** Scotty renders actors on its human allowlist as 👤 and everything else as 🤖; a bare `bd` on Ari's machine is attributed to him. The prefix reaches one command: never chain a second write behind `&&`. Rules and Reference show bare syntax; every write you run carries the prefix, as the Workflow's do.
- **Resolve the workspace each time.** `command -v bd` first. A host or window Ari named this session wins over cwd until he names another or says "here"; say which workspace each turn's writes went to, and every command there goes through `/ari-driving-remote`, one command per call. That host is reachable only through a pane the sibling's The gate accepts; a refusal is the Cut off rule below. A directory he named on this machine: `bd -C <dir> …` on every command, never `cd`. He named none and cwd or a parent has `.beads/` → run here. `.beads/` here and no `bd`: say so; ask whether the tracker lives on a host (`/ari-driving-remote`) or `bd` should be installed. Neither → ask which project; never guess a path. NEVER `bd init` unasked: it makes a second, empty database Scotty does not read. `bd info` confirms the database; report the prefix of its ids (the part before the dash in any `bd ready --json` id), never its path.
- **This session's beads only.** A workspace can hold another session's epics, and every session writes as `claude`, so an assignee never tells them apart: NEVER count a bead outside the scope (Scope) in this session's frontier, pick it, or write to it (comment, note, dep, `--parent` under it, claim, unclaim, close, label, gate), a stale claim included; reading it (search, show, a decision) is fine. NEVER run a command the Scope table marks as reaching other sessions except in its scoped form. No scope known (no root this session, none in a compaction summary) and the bead map holds an epic: the frontier reply is the one question "Which epic is this session's?", alone, and no other frontier command runs.
- **Cut off from the tracker: the turn is a report, not an answer.** When `/ari-driving-remote` refuses the pane (its The gate and Exit codes say when) and `PANES:` lists no other ✦ shell pane, nothing in the tracker can be read or written this turn. The report is the pane's full label, what it holds, and that clearing it is Ari's first move, said in chat, never a bead. Then nothing else that turn: no frontier, bead text or status recalled from memory, a summary or a transcript, since a bead not read this turn is unknown; a wish or directive voiced meanwhile is quoted verbatim under "unfiled:", a fact or preference to remember under "unremembered:" with its key, all written nowhere, so `bd create` and then `bd remember` are the first commands once a pane returns; a claim Claude holds stays held, with `BEADS_ACTOR=claude bd unclaim <id> --if-assignee claude` printed for Ari to run.
- **Text with a newline, or over 200 bytes, is a file.** Write it to the scratchpad and pass it with `--body-file`, `--design-file`, `--reason-file`, `bd comment --file` or `bd note --file`; never flatten or trim it to fit a flag. On a host Ari named, three steps with nothing between: write the file; put it with `/ari-driving-remote` (`--put FILE --project <repo>/beads --name <subject>`: the repo the tracker serves plus `/beads`, `homelab/beads`; the bead's subject as a lowercase hyphenated slug, `open-only-toggle`; its **Put a file on the host** has the bead-body row); run the bd command with the path from the `PUT:` line pasted whole into the flag. An edited file is a new put. No `PUT:` line: no bd command (Refusals). Text typed into the pane in any form, a heredoc, base64, `printf > FILE`, loses bytes, and that skill refuses it.
- **NEVER `bd edit`.** It opens `$EDITOR` and blocks; use `bd update <id> --description|--design|--acceptance|--append-notes`.
- **One bd command at a time per workspace.** Embedded Dolt has a single writer and every call, even `show`, touches the store: one bd command per tool call, one call at a time, never several in one response's batch, never parallel agents against one database. A fenced block below with several commands is that many calls, in order, each id taken from the previous call's output. Many beads at once go through `bd create -f <file.md>`, one issue per `##` heading.
- **`--json` for anything parsed.** `bd show <id> --json` returns an array even for one id; `bd list`, `bd ready` and `bd children` return arrays; `bd create --json` an object; `bd human list --json` prints `null` when empty; `--silent` prints only the id.
- **A bead id in chat is its link.** Every id a chat line names is the line `zsh $HOME/.claude/skills/ari-bead-driven-development/bin/bead_link.zsh --bead <id> --title '<title>' --status <status> --priority <n>` printed for it, `[beads-o27](tmux-tooltip://show?title=beads-o27&text=…&field=status%3Dopen&color=<c>&field=priority%3DP2&color=<c>)`, each `<c>` the color Ari's beads.conf gives (Delegation), never a hand-built URL; a click in tmux opens a card above it with the title and the colored status and priority. One call per message, a `--bead` record per id, run on this machine even for a workspace on a host; a title holding `'` is quoted `$'…'`. Title, status and priority come from a bd read this turn (`bd list`, `show`, `ready` and `create --json` carry all three), output already in hand included, never from memory or a summary; a field the read lacks is left off, and an id whose title was not read this turn, or every id when the script fails, stays bare. This skill's other chat examples show ids bare for brevity.
- **Priorities are numbers.** `0` Critical, `1` High, `2` Medium (default), `3` Low, `4` Backlog; `P1` is accepted, `high` is rejected, and `bd ready -p` takes a bare integer.
- **`bd dep add <issue> <depends-on>`: the first id waits.** Say "A is blocked by B" aloud before typing `bd dep add A B`; `--deps blocks:X` on create reverses the edge. A wrong edge comes out with `bd dep remove <issue> <depends-on>`, same order.
- **Read, then claim, then release.** `bd show <id> --json` before `bd update <id> --claim`; `BEADS_ACTOR=claude bd unclaim <id> --if-assignee claude` plus a `bd note` of where it stands when work pauses, so Scotty's In Progress column is never a lie. NEVER claim a bead assigned to someone else or take a live claim with `--force`; a `claude` claim this session did not make is someone else's, since `--claim` re-takes it silently. `bd unclaim` only a claim this session made: `--if-assignee claude` makes another actor's claim a refusal, not a release, but cannot tell this session's claim from another session's, so a stale `claude` claim it did not make is reported and released only when Ari names it.
- **Done without proof is not done.** `bd close <id> --reason "…"` with the commit, the check output or the observed state, at least twenty characters (this skill's floor, not bd's); a bare `bd close` stores the literal "Closed", which Scotty hides. NEVER `--force` past open children or a live blocker; close them first.
- **Decisions only Ari can make get the `human` label and no claim.** NEVER answer a `human`-labelled question yourself; there is no `bd human <id>` command despite what `bd prime` prints.
- **NEVER write a Claude memory in a session where the Resolve rule found a workspace; `bd remember` is the only memory there.** This overrides the auto-memory instruction: how this project works and what Ari prefers are both `BEADS_ACTOR=claude bd remember "<fact>" --key <slug>` in the workspace this turn's writes go to (Work the bead has the key rule), each with one chat line, "Remembered in <prefix>: <key>", so he can veto; a memory is per workspace and is not copied to another. Two exceptions: a fact about a host (user, prompt, panes) goes to `/ari-driving-remote --describe`, and where a workspace lives (its host and directory) stays in Claude's memory, since `bd prime` cannot say where to run `bd prime`. A refused `bd remember` (schema skew, cut off) is quoted under "unremembered:" with its key and written on the first command once the tracker answers. Claude's own memory is written only in a session where Resolve ended with no workspace.
- **Confirm before `bd delete` of any bead, before `bd forget` of a memory Claude did not write this session, and before `reopen`, `defer`, `--status`, `-p`, `duplicate` or `supersede` on a bead Ari created.** Ari created it when `created_by` in `bd show <id> --json` is not `claude`; no confirm when he named the bead and the action this turn. Claude's own bead: act and say so. Prefer `bd duplicate` or `bd supersede` over delete.
- **No offsite copy exists until you make one.** No Dolt remote exists by default: NEVER `bd dolt remote add`, push or pull; `.beads/` is not committed; `bd export` or `bd backup` is the copy (see Keep the tracker honest).

## Reference

### Scope

The scope's *roots* are the top epic above each bead this session filed or claimed (walk `parent` up to the bead with none), each such bead with no parent, and each bead Ari named this session; a named bead brings its descendants, never its parent or siblings, and claiming a bead under it adds nothing above it. His answer to "Which epic is this session's?": ids → those roots; "the whole workspace" → `all`; "none" → no roots: file new work parentless. The bead map holds no epic and no root is known → `all`, said in the frontier line. A bead is *in the scope* when it is a root or its chain of `parent` in the bead map reaches one, or its id starts with `<root>.`; a `parent` missing from the map is closed: `bd show <parent> --json` continues the walk. Whenever the roots change, the chat line says "Scope now: <roots>"; with the frontier line, that is how a later turn and a compaction summary carry them.

| command | reaches other sessions | in the scope |
|---|---|---|
| `bd ready`, `bd blocked` | yes | `--parent <root>`, one per command: every descendant, adopted beads included, never the root itself; a comma list or an unknown id returns `[]` with exit 0, and a second `--parent` replaces the first |
| `bd list --parent <id>` | no | direct children only, so in flight is the bead map's in-scope `in_progress` and `hooked` rows |
| `bd human list`, `bd stale` | yes; no `--parent` | the rows whose id is an in-scope row of the bead map |
| `bd ready --explain` | yes; ignores `--parent` | scope `all` only |
| `bd gate check` | closes every resolved gate | scope `all` only; otherwise `--dry-run`, then `bd gate resolve` per listed gate that a scope bead's `bd show --json` lists under `dependencies` |
| `bd epic close-eligible` | closes every listed epic | scope `all` only; otherwise `--dry-run`, then `bd close <epic>` per listed scope epic |

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
| 1 | High | today's work waits on it, e.g. a failing check on the path to today's deploy; a directive with no priority lands here on that test alone | yes |
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

"What am I on" is the bead map's in-scope `in_progress` rows (`bd list -s in_progress` for scope `all`), never `bd ready`; "what is in Backlog" is its in-scope `deferred` rows (`bd list -s deferred` for scope `all`; `--deferred` lists only a defer date, which an iceboxed bead lacks). Backlog has two doors: `bd defer <id> --reason "…"` is the icebox, open again only through `bd undefer <id>`; `bd defer <id> --until <date>` is a snooze that wakes to open on its own. NEVER set status `pinned`: it fits no column, so Board and List both drop it and Ari never sees it; a non-epic bead to keep in view gets `-p 1` (Focus Next up; Confirm rule if Ari created it). Epics never appear on Board or List; they do appear in Epics, Graph, the drawer, and in Focus whenever their status or priority qualifies, so keep epics at P2–P4 and never claim one.

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
| labels | project and cross-cutting tags, comma-separated; a new one is lowercase and hyphenated (`^[a-z0-9][a-z0-9-]*$`) and exists by appearing on `-l`; `human` and `archived` are load-bearing and never a picker's choice | `-l a,b`, `--add-label`, `--remove-label`, `bd label add <id> <label>` |
| external_ref | the PR or upstream issue id, for `bd list --external-ref` and a `gh:pr` gate; Scotty never shows it, so paste the URL into the description, notes or a comment too | `--external-ref gh-9` |

A quoted space makes one label. `--set-labels ""` is silently dropped; empty with `--remove-label`. Due dates, estimates, defer dates and external_ref do not render in Scotty; say a date in notes too.

### What is not a bead

A chat question, a clarification, reading code to answer Ari, a step inside a claimed bead (that is a `bd note`). A wish with no next step yet gets a bead at `-p 4`, then `BEADS_ACTOR=claude bd defer <id> --reason "no route yet"` so it sits in Backlog; `--until <date>` instead when a date, not a route, is what it waits for.

### Scotty

"You should just learn about Scotty to recommend the best action for me." So a recommendation names the view where Ari will see its effect, never a URL; the bead link shape is `/p/<project>?bead=<id>` and Ari's bookmark supplies the origin. Views and buttons here were checked against Scotty 0.3.2; where his screen differs, his screen is the authority.

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
| close of a closed bead | exit 0 and a `✓ Closed` line quoting the new reason, but nothing written: the old reason stays | check `bd show --json` status before re-closing; new evidence is a `bd comment`, never a second close |
| frontier ready bucket empty | an empty bucket, not a refusal: "No open issues", "No ready work found" and `[]` alike; with `--parent` bd always says "No ready work found", so the bead map says which | No open in-scope row → list the in-scope `deferred` rows (`bd list -s deferred` for scope `all`) and ask which to bring back; on his pick `BEADS_ACTOR=claude bd undefer <id>`, then Pick; none deferred → ask for the next wish. Only `in_progress` rows → resume this session's claim from its notes. Only `human` rows → the move is Ari's (Needs You). Otherwise report the blocked bucket; `bd ready --explain` only for scope `all` |
| `bd prime` schema error | binary and database versions differ | `bd info`, `bd doctor`, report; no writes, never `--ignore-schema-skew` unasked |
| `bd create` fails (Dolt lock, schema skew, a rejected `-p`, `--parent` or label) | nothing was filed | quote the error; no claim; the wish or directive sits under "unfiled:"; retry once without the optional flag the error names, a rejected label with `bd label add` after |
| exit 124 via `/ari-driving-remote` | still running | capture only; never resend |
| `--put` printed no `PUT:` line | the text never reached the host; nothing filed | the row the `[ERROR]` line names in `/ari-driving-remote`'s Exit codes `--put` table; nothing put this turn → the wish or directive goes under "unfiled:", no bd command |
| `/ari-driving-remote` refuses the only ✦ shell pane (its Exit codes say why), or exit 70 lists no ✦ shell pane under `PANES:` | cut off from the tracker: nothing typed, nothing readable | the Cut off rule: report, Ari's first move, nothing else this turn. Exit 70 with a ✦ pane listed: ask Ari which pane |

A flag refused as unknown: `bd <cmd> --help` on that machine is the authority, not this skill. This skill's flags were checked against the bd 1.3.1 help and source, the Scope table's against bd 1.3.4; the quoted messages marked as varying were not, so match on the sense, not the string.

### Delegation

- Commands on a host Ari named: `/ari-driving-remote`, one command per call; it owns host details and the `--put` that carries a file there (the Text rule). Text Ari runs himself, and fetching a remote export: `/ari-driving-tmux`.
- A bead tree with statuses bound for a PR or issue: `/ari-diagram-gh-todo` (open/blocked red, in_progress yellow, closed green); any other diagram: `/ari-diagram-mermaid`, starting from `bd dep tree <id>`. `bd graph --dot` is Graphviz input, not Mermaid.
- A design that outgrows `--design`: `/ari-hemingway--structure-design-doc`; the bead keeps the link in `--external-ref` and in a comment, where Scotty shows it.
- A bead id's link: `bin/bead_link.zsh` wraps `tmux-tooltip link` from Ari's dotfiles (`$HOME/.config/bin/tmux-tooltip`), which also opens the card on a click (a click or Esc closes it); a change to the card itself goes there, and the status and priority colors are Ari's `$HOME/.config/tmux-tooltip/beads.conf` (`FIELD VALUE COLOR` lines; a value with no line is uncolored).

## Workflow

### Read the frontier

Run `bd info`, then `bd prime`, at session start and again after compaction; `bd prime` prints memories and the close protocol. No `bd`, or no `.beads/` here and no host named: the Resolve rule says what to ask, and nothing runs before the answer. Then the frontier, one command per tool call, never chained: `&&` stops at the first nonzero exit and `/ari-driving-remote` takes one command per call. An empty result is an empty bucket, not a refusal; a refusal is a lock, schema or flag error, or a `/ari-driving-remote` refusal. A frontier answer MUST follow these commands this turn; the first refusal stops the sequence, what did return is reported as partial, and the rest is never filled in:

1. The bead map, always first: `bd list -n 0 -s open,in_progress,blocked,deferred,hooked --brief --json`.
2. The roots (Scope). None known: the map holds an epic → the question of the This session's beads rule, and stop; no epic → scope `all`.
3. Per root with a child in the map: `bd ready --exclude-label human --parent <root> --json`, then `bd blocked --parent <root> --json`.
4. `bd human list --json`, then `bd stale -d 14 -s in_progress --json`, each kept to its in-scope rows.

Ready is step 3's ready rows plus each non-epic root whose map row is open, has no `human` label, and whose `bd show <id> --json` lists no open `blocks` dependency; in flight is the map's in-scope `in_progress` and `hooked` rows; blocked is step 3's blocked rows plus each root that is blocked or has an open blocker; waiting on you is step 4's `bd human list` rows; stale is its `bd stale` rows. Scope `all`: steps 3 and 4 with no `--parent` and no in-scope filter (`--exclude-label human` stays), in flight `bd list -n 0 -s in_progress,hooked`.

An empty ready bucket: Refusals. Waiting on you non-empty means the next move is Ari's; stale non-empty means a tidy (Keep the tracker honest). Chat, one line naming the roots and every bucket's ids, each a link from the map's row (A bead id in chat is its link): "Frontier (scope beads-xy9, beads-q2r): ready beads-xy9.2 (P1), beads-q2r; in flight beads-xy9.1; blocked beads-xy9.4 on beads-xy9.2; waiting on you beads-xy9.5; stale none." "Frontier (scope all: no epic in the workspace): …". Partial: "Frontier (scope beads-xy9), partial: ready beads-xy9.2 (P1); `bd blocked --parent beads-xy9 --json` refused ("<error>"); blocked, waiting on you, stale unread." A refusal: "Cut off from the tracker: `machine=personal|ID=%18|pane=3.1` holds an un-entered command; clearing it is your first move." Never: "From the last summary, two ready and one in flight." Never: "Frontier: ready beads-amm (P1) …" when beads-amm is another session's epic.

### Answer what was decided

"What did we decide about …": `bd search "<words>"` (every status), then `bd show <id> --json` for `design` and `close_reason`, `bd comments <id>` for the thread in order, and `bd memories <word>` for a fact that outlived its bead. Answer with the id and the field's words, not a paraphrase. Nothing found anywhere → there was no decision: file one (Ask Ari a decision), never guess. Chat: "beads-o27's design: toggle, not a view; closed with ab4c456."

### Hear a wish, research it, file it

`bd search` first. Read enough of the code to know what exists today and what route is recommended; write the description to a file in the scratchpad:

```markdown
## Goal
Graph view hides closed and blocked beads behind an Open-only toggle, so an epic's open work is readable.

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

Then the label, before the filing line: the main thread runs `bd label list-all` (through `/ari-driving-remote` when the workspace is remote) and no other bd command until the pick returns; a picker (the Agent tool; done inline when no Agent tool is available) gets that list, the title and one line of the goal, runs no command, and returns one line; the main thread has final say and puts the label on `-l`. The brief and its answer:

```
Labels in use: scotty, homelab, doctor, torrent. Title: Graph view: Open-only toggle hides closed and blocked beads. Goal: an epic's open work is readable in Graph.
Return one line, `label: <name> (existing|new)`: the one existing label that fits, else one new lowercase hyphenated word; never human or archived; run no command.
→ label: scotty (existing)
```

A prose or malformed answer, a timeout, or a label bd rejects means file with no `-l`, say "no label yet", and `BEADS_ACTOR=claude bd label add <id> <label>` later: the bead never waits on the label, and a P0 files first and labels after.

```zsh
BEADS_ACTOR=claude bd create "Graph view: Open-only toggle hides closed and blocked beads" -t feature -p 2 -l scotty --body-file "$desc" --json
```

On a host Ari named (the Text rule), the file goes first and the create carries the printed path:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --put "$desc" --project homelab/beads --name open-only-toggle --execute
```

```
PUT: /tmp/homelab/beads/open-only-toggle.<sha>.txt
```

```zsh
BEADS_ACTOR=claude bd create "Graph view: Open-only toggle hides closed and blocked beads" -t feature -p 2 -l scotty --body-file /tmp/homelab/beads/open-only-toggle.<sha>.txt --json
```

Found while on another bead: add `--deps discovered-from:<current-id>`. Part of an epic in the scope: `--parent <epic>`, never under one outside it (file parentless instead); the epic, decision and fix-already-made creates below carry `-l` the same way. Already fixed: see Close with evidence, filed and closed. A wish ends the turn here. Chat, the id linked from the create's own `--json`: "Filed [beads-o27](tmux-tooltip://show?title=beads-o27&text=Graph%20view%3A%20Open-only%20toggle%20hides%20closed%20and%20blocked%20beads&field=status%3Dopen&color=<c>&field=priority%3DP2&color=<c>) (feature, P2, label scotty); it waits for a pick.", or "(label torrent-queue, new)" for a coined one. An unclear message ends the same way plus its question (the directive rule): "Filed beads-o27 (feature, P2, label scotty). beads-o27: work it now, or leave it for a pick? recommended: pick — nothing today waits on it." A directive does not wait for a pick: `-p` on its `bd create` is the number from the directive rule, and the same turn goes straight to Pick from `bd ready` and claim, and claims the new id. With a priority, "P0: the doctor is failing on the laptop, fix it now", while beads-o27 is claimed:

```zsh
BEADS_ACTOR=claude bd create "Doctor: API check fails on the laptop" -t bug -p 0 -l doctor --body-file "$bug" --json
BEADS_ACTOR=claude bd note beads-o27 "paused for P0 beads-p3k; edge hiding next"
BEADS_ACTOR=claude bd unclaim beads-o27 --if-assignee claude
BEADS_ACTOR=claude bd update beads-p3k --claim
```

Chat: "Filed beads-p3k (bug, P0, label doctor), claimed; beads-o27 parked; on it now." Without a priority, "fix the doctor check" while today's deploy waits on it is `-p 1` and the chat says "P1: today's deploy waits on it"; the same words on a day with no deploy are `-p 2`.

### Pick from `bd ready` and claim

Highest priority first from the frontier's ready bucket (Read the frontier); a bead outside the scope is never picked, even as the only ready one. Read it; skip it when `show` says its type is `epic`, its labels include `human`, its assignee is set (`claude` included, unless this session claimed it), or its status is not open; only then claim, as a second call:

```zsh
bd show beads-o27 --json
BEADS_ACTOR=claude bd update beads-o27 --claim
```

Scotty's Ready column still lists a `human` bead. `--claim` is atomic and idempotent, so it re-takes another session's `claude` claim without a refusal; a refusal means another actor holds it, so pick the next or ask. Chat the title and the definition of done you are working to.

### Work the bead

Comments, notes and design each have one job (Fields); the commands:

```zsh
BEADS_ACTOR=claude bd comment beads-o27 "Toggle wired; edge hiding next"
BEADS_ACTOR=claude bd update beads-o27 --design "Reused the live-filter helper; toggle state is React-local"
```

A bug or follow-up found on the way is its own bead with `--deps discovered-from:beads-o27`; if the current work cannot finish without it, also `BEADS_ACTOR=claude bd dep add beads-o27 <new-id>`. A memory (the NEVER-a-Claude-memory rule): `BEADS_ACTOR=claude bd remember "Scotty reads the whole tracker through bd export --json, so export shape is its API" --key scotty-export-is-api` for a project fact, `BEADS_ACTOR=claude bd remember "Ari wants a close reason to name the commit before the check output" --key ari-close-reason-order` for a preference, whose `ari-` key lets `bd memories ari` list his preferences apart from facts. `--key` always, or a slug-like text recalls instead of storing; `bd memories <key>` first, and a changed sense is `BEADS_ACTOR=claude bd forget <key>` then remember, saying what it replaced. Stopping unfinished: `BEADS_ACTOR=claude bd note beads-o27 "Edges still drawn for hidden nodes"`, then `BEADS_ACTOR=claude bd unclaim beads-o27 --if-assignee claude`. A bead Claude claimed cannot be closed by Ari from Scotty (bd refuses a close whose actor is not the assignee): unclaim or reassign before handing one over.

### Structure an epic

Epic when a step can be claimed, closed or handed over on its own, or spans a session; otherwise a checklist in one bead. Each step is a child, never a checklist line in the epic; order between children is a `blocks` edge. The epic body holds `## Goal` and `## Success Criteria` as a `- [ ]` list, in the shape of the wish body above; its checks are outcomes ("the compose file names a digest"), not steps.

`BEADS_ACTOR=claude bd create "Scotty runs from a pinned image" -t epic -p 2 -l scotty --body-file "$epic" --json`, then `BEADS_ACTOR=claude bd create "<step>" --parent <epic> --body-file "$step"` per step (children inherit the label), `BEADS_ACTOR=claude bd update <existing-id> --parent <epic>` for a bead in the scope that already exists, `BEADS_ACTOR=claude bd dep add <later-step> <earlier-step>` where one must follow another, and `bd children <epic>` to check. Chat: "Epics shows progress; Graph scoped to it shows the order."

### Ask Ari a decision

Write the question, the options and what each unblocks to a file, file it as a decision, and block the waiting work on it:

```zsh
BEADS_ACTOR=claude bd create "Decide: keep Open-only as a toggle or a view" -t decision -p 1 -l scotty,human --body-file "$q" --json
BEADS_ACTOR=claude bd dep add beads-o27 <decision-id>
```

Do not claim it. A question about a bead that already exists needs no new bead: `BEADS_ACTOR=claude bd comment <id> "<question and options>"`, then `BEADS_ACTOR=claude bd update <id> --add-label human`, after unclaiming it if Claude held it. Chat: "Waiting on you in Needs You: <title>." The answer shows at the next state of play: the bead has left `bd human list` and `bd comments <id>` has a new 👤 comment (Respond in Scotty leaves the bead open; `bd human respond` closes it). Label gone and no new comment means Ari pressed Dismiss: do not proceed on a guess; ask in chat or re-file the question. Record the outcome with `BEADS_ACTOR=claude bd update <decision-id> --design "…"`, then, if the bead is still open, `BEADS_ACTOR=claude bd close <decision-id> --reason "Ari chose <option>: <where he said so>" --suggest-next`. Only a closed decision unblocks the dependent; confirm it in the frontier's ready bucket. Decision: Ari picks among options and the pick is recorded in `--design` (toggle or view?). Gate: a yes/no on one action with nothing to record (apply the new compose file? delete it?): `BEADS_ACTOR=claude bd gate create --type human --blocks <id> --reason "…"`. Ari approves in Needs You, or says yes in chat and Claude runs `BEADS_ACTOR=claude bd gate resolve <gate-id> -r "Ari: yes, <where>"`; either way the blocked bead is back in the frontier's ready bucket, which is how Claude notices.

### Close with evidence

```zsh
BEADS_ACTOR=claude bd close beads-o27 --reason "Commit ab4c456: Open-only toggle hides closed and blocked beads; doctor check PASS" --suggest-next
```

The reason names each of the commit, the check and the observed state that exists; a decision or a host change with no commit names where it was settled or seen. One id: `--suggest-next` prints what the close unblocked, which is the next pick when it is in the scope. Several ids: `BEADS_ACTOR=claude bd close a b --reason "x" --reason "y"` (exactly one reason, or one per id in order), no `--suggest-next`: bd refuses it ("only works when closing a single issue"); read the frontier after. An epic whose children are all closed: `BEADS_ACTOR=claude bd close <epic> --reason "<evidence naming the children>"` like any bead; `bd epic close-eligible` is the tidy sweep only. Already closed, or children open: Refusals. Wrong bead closed: read `created_by` in `bd show <id> --json`; not `claude` → confirm; then `BEADS_ACTOR=claude bd reopen <id> -r "…"`. Chat: "Closed beads-o27 (ab4c456, doctor PASS); unblocked beads-p3k, picking it next." or "…nothing unblocked; scope beads-xy9 shows two ready."

Work that waits for a PR: close the implementation bead with the PR in `--reason` and `BEADS_ACTOR=claude bd update <id> --external-ref gh-<pr#>`; the follow-up that needs the merge waits behind `BEADS_ACTOR=claude bd gate create --type gh:pr --await-id <pr#> --blocks <follow-up> --reason "needs PR <pr#> merged"`. When a frontier's blocked bucket holds a bead whose `bd show --json` `dependencies` list an open `gate`, run `bd gate check --dry-run`; for each gate it says would resolve that a scope bead depends on, `BEADS_ACTOR=claude bd gate resolve <gate-id> -r "PR <pr#> merged"`. A bare `bd gate check` closes every resolved gate, other sessions' included: scope `all` only (Scope). The follow-up is then back in the ready bucket.

A fix already made is filed and closed together, the proof in the close reason; `bd lint` reads open beads, so this bug carries no `## Steps to Reproduce`:

```zsh
BEADS_ACTOR=claude bd create "Doctor: API check passes on an empty list" -t bug -p 2 -l doctor -d "Doctor reported FAIL on a tracker with zero beads: the check read a key an empty list lacks" --json
BEADS_ACTOR=claude bd close beads-orc --reason "Fixed in commit ab4c456 and deployed: doctor check PASS, API lists beads"
```

### Close the session

Before saying "done": file a bead for every remaining ask; unclaim, with a note, each bead this session claimed and did not finish; close what it finished with reasons; run the project's quality gates; `git status`; report the handoff for the scope, naming its roots, with each bead's id and state. No push, pull or Dolt sync.

### Keep the tracker honest

When Ari asks for a tidy, or the frontier's stale bucket is non-empty, run the reads one per line: `bd stale -d 14 -s in_progress`, `bd lint`, `bd doctor`, `bd dep cycles`, `bd epic close-eligible --dry-run`. A nonzero exit from `bd lint` or `bd doctor` is a report, not a stop. Chat the findings: `bd stale`, `bd lint` and `close-eligible` for in-scope beads only, with a count of the rest; `bd doctor` and `bd dep cycles` whole, as workspace health. Then:

- Stale: `BEADS_ACTOR=claude bd unclaim <id> --if-assignee claude` only on claims this session made; report the scope's other stale claims, Ari's and other sessions', and release one only when Ari names it.
- Sweep: `bd epic close-eligible` CLOSES every listed epic, other sessions' included, when run without `--dry-run`. First turn: chat the dry-run's scope epics (all of them for scope `all`) and ask for a yes. Only after Ari's yes: `BEADS_ACTOR=claude bd epic close-eligible -r "<reason>"` for scope `all`, otherwise `BEADS_ACTOR=claude bd close <epic> --reason "<evidence naming the children>"` per scope epic he said yes to.
- Archive, when Ari wants Done decluttered: the bead must already be closed and in the scope (any bead for scope `all`), then `BEADS_ACTOR=claude bd label add <id> archived`; NEVER on an open bead, which Scotty would hide from every view while it is still live.
- Export: the first time, ask where exports go and `BEADS_ACTOR=claude bd remember "<dir>" --key export-dir`. Then `bd export --include-memories -o <export-dir>/<prefix>-<YYYY-MM-DD>.jsonl`, outside `.beads/`; memories are left out by default, so without the flag the copy drops every `bd remember` fact. Name the path in chat; a remote export stays on that host until Ari fetches it (Delegation).
