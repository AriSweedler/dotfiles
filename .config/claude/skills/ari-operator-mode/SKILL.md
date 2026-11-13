---
name: ari-operator-mode
description: "Operator mode: Ari is back as a fresh operator who has read no history and holds the permissions Claude lacks. On only when he invokes this skill, off only on \"stop operator mode\"; every reply in it is a briefing from a capture made that turn of this session's own epics and edits (another session's beads in the same workspace never show): state, up to five rows of only what Claude cannot do itself (a `bd` write, an answer he already gave, Claude's work and epics are never rows), a question only when his yes or word is needed; an instruction he gave is started, and Claude's own follow-up done, never asked about. Off, offer it in one line when he asks where we are or what is next."
disable-model-invocation: true
---

# Operator mode

Every reply in this mode is written for a reader who has read nothing, does not remember what sits on his prompt, and can run what the permission layer refused Claude: from a capture made this turn of this session's own epics and edits, state, up to five rows of what Claude cannot do itself, and a question only when something waits on him; what he already said (an answer, an instruction) is acted on, never asked again.

## Rules

- **A mode, not a moment.** Every reply checks `bin/mode.zsh status`, never the transcript; only his invocation switches it on, only `stop operator mode` or `normal mode` off. Off, an orienting question gets the one offer line (Reference › The offer) and nothing from the transcript.
- **The operator knows nothing.** Define every term at first use; name every thing by what it is: a bead by id and title, a file by path, a pane by its full label with his nickname. Never "earlier", "the one-liner", "step 2" or a session's name for something.
- **The script reads, the model renders.** `bin/frontier.zsh` is the only source of facts; every bullet and row traces to one section of its JSON; delete a sentence that traces to none. Asked for something the JSON lacks, the reply is the form in `templates/briefing.md` › Not in this capture.
- **This session's work only.** NEVER a row, a bullet that names it, or a write for another session's bead or an edit this session did not make, even when Ari names it (Reference › Yes and no): every capture carries this session's scope and own paths (Workflow › Resolve the inputs), and a `bd` write goes only to a bead the newest capture lists.
- **Nine named facts may come from outside the JSON** (Reference › Outside facts); nothing else from the session enters a briefing.
- **NEVER run the health command unasked.** Not in the capture, not by hand: it is Claude's work, run once through `run.zsh` only as his instruction, and its output enters through the pane read of that run; it is a row only after the permission layer refuses that run (Reference › Row triage).
- **Cut off is the whole message.** `cut_off` not null: the reply is what `bin/brief.zsh --cut-off` prints and nothing else but the spawn line of a `skill_fix=` update (Workflow › Capture); no second read, no `--local` or other pane as a substitute, no `local_git` or `health` even though they filled; his next message starts with a fresh Capture and authorizes no row. An announced absence is the away line, not his P0 (Reference › Announced absence). This renders `/ari-bead-driven-development`'s Cut off rule (Reference › Overrides).
- **A run's end is a Capture.** Row 1 or Claude's run of his instruction landed, failed, or he reported on it: run Capture before writing one word about the outcome; the outcome sentence names what the new JSON shows plus the command's last printed line, quoted (Reference › Outside facts).
- **Terse, and a question only when he is needed.** A reply is the turn's whole text: at most six state bullets and at most one question mark, the last thing in it but a `skill_fix=` spawn line, inside no code span, and only in a form `templates/briefing.md` › At most one question or its one-line replies name; NEVER any other question. Otherwise the reply ends on a statement. Depth on request is the named section's raw text, verbatim.
- **What he said is not asked again; what Claude can do is not offered.** His instruction in words ("proceed with the stack"), given with the invocation or later, is its own yes: Claude starts it that turn (Workflow › Proceed). His answer to a human gate is Claude's `bd` write that turn (Reference › Yes and no). Claude's own follow-up (watching CI, reading again, fixing its reader) is done or dropped, NEVER offered: "Should I watch the CI and tell you once it passes?" is the defect. A yes authorizes only what the one question names; when it lands, Capture, Brief.
- **Up to five rows, only what Claude cannot do.** A row is an act that needs Ari himself: his identity (his login, his signature, a decision only he can make and has not given), a permission Claude lacks, a physical act, or the edit he decides to discard (a **destroys:** row and its show row, since the diff must reach his eyes and no capture section holds it). A step of Claude's run that ships or destroys is the one question, never a row. NEVER a row for what Claude's tools can do (any `bd` write, recording an answer he gave, a human gate whose act Claude can perform, ready and in-progress beads, the health run, retried reads, an instruction Claude runs), for an epic (`type` `epic`) in any section, or for a candidate with no act of his. Sources, priority, order and pane are Reference › Row triage; the trailing line is `templates/briefing.md` › One trailing line.
- **Only row 1 is typed**, under Workflow › Brief step 3's three conditions; an answer row has nothing to type. Never type while another agent uses the pane (Reference › Shared pane), and never put a second line on his panes while one sits un-entered.
- **Rows name their writes.** The markers are `templates/briefing.md` › The table; a **destroys:** or **irreversible:** row runs only on a yes that names it (the question names the row, so a bare "yes" to that question is one), a discard row only after its show row ran (Reference › Row triage).
- **Chat only.** The briefing is this reply and nothing else: never a Slack post, a doc, an artifact, a bead comment or a pane; his words: "You and I are tools to create the product."
- **No recap.** Never summarise earlier this session; `host_git.log` is the only history, and only on request.

## Reference

### The capture

`bin/frontier.zsh` reads these in this order, through `/ari-driving-remote`'s `run.zsh` on the host (every `bd` call is `bd -C <beads>`, never `cd`), and writes one JSON. After the bead map, the reads cover what `/ari-bead-driven-development` › Read the frontier reads, with this skill's own commands; the script is the authoritative list.

| Section | Host command | JSON | Renders in |
|---|---|---|---|
| `scope` (top level, read first) | `bd list -n 0 -s open,in_progress,hooked,blocked,deferred --json`, cut to its `id`, `parent` and `issue_type` lines, with bd's exit code: the bead map | `{epics, all, unknown, error}`, or null without `--scope` | First principles; `unknown` and `error` a state bullet |
| `ready` | `bd ready --exclude-label human --json` | `[{id, title, priority, type, parent, assignee, holder, updated_at}]` | state bullet |
| `in_progress` | `bd list -s in_progress,hooked --json` (a hooked bead counts as in progress; needs a `bd` whose `list` accepts `hooked`, as 1.3.4 does) | the same list; `holder` is `self` when `assignee` is `claude:` and this session's full UUID, `none` when unassigned, else `other` (another session's claim, a bare `claude`, a person): an `other` bead is never worked or written by this session | state bullet |
| `human` | `bd human list` | `{text, ids, deferred_ids}` | state bullet, his rows; `deferred_ids` nowhere |
| `blocked` | `bd blocked` | `{text, ids, deferred_ids, blockers: {id: count}}` | trailing line; `blockers` ranks rows |
| `stale` | `bd stale -d 14 -s in_progress` | `{text, ids, deferred_ids}` | the in-progress bullet, trailing line |
| `deferred` | `bd list -s deferred --json` | `{count}` | trailing line |
| `host_git` | `git -C <repo> -c core.quotePath=false status --porcelain && git -C <repo> log -3 --oneline` | `{dirty: [], own: [], log: [{hash, subject}]}`, or `{skipped}` without `--repo` | state bullet, his row for each `own` entry |
| `local_git` | the same on this Mac | the same | the checkout bullet when it differs from the host's |
| `health` | none; recorded, never run | `{command, ran: false}` | state bullet; nothing when `command` is null |

- With `--scope`, every `bd` section keeps only those epics and their descendants (the parent chain through the bead map, or a hierarchical id such as `beads-xy9.6.1`); `human`, `blocked` and `stale` keep only those beads' blocks of bd's text, `blockers` counts an edge only when both its beads are in scope (the text calls the other end "a bead outside the scope"), and `deferred.count` counts only the scope's beads. Without `--scope`: exit 4 (Reference › Exit codes).
- `own` is the `dirty` entries whose path `--own-paths` names: this session's uncommitted edits. An untracked directory (`?? notes/`) is `own` when an own path lies under it; its **destroys:** row removes only those own paths, by name, never the directory.
- A section that could not be read holds `{"error": "<why>"}`; `precondition: true` when one cause, such as no `bd` on the host, failed them all.
- A section a cut-off kept unread holds `{"unread": true}`.
- A text section whose id count disagrees with bd's own summary count is an error, not a quiet miss.
- A crash after the reads began still writes the JSON, the unfinished sections as errors.
- The top level: `captured_at`, `session`, `host_definition`, `pane`, `nickname` (the pane's window name), `beads_dir`, `repo`, `local_repo`, `scope`, `pending` and `pending_seen` (true: his typed row was on the pane; false: the prompt was idle without it; null: no row or unknown), `away` and `away_ended` (Reference › Announced absence), `typed` (every command typed, in order), `waited_s`, `cut_off` (`{pane, reason, prompt_holds, busy_cmd, candidates, unread}`). The filled example is `templates/frontier.example.json`.

### Terms

The briefing's two-to-five-word forms of `/ari-bead-driven-development`'s terms, plus this skill's own (scope, pane label, doctor, agent's command, open instruction):

| Term | Definition, as the briefing gives it |
|---|---|
| bead | one tracked issue in the `bd` tracker |
| epic | a bead that holds children; in the JSON, `type` `epic` (being another bead's `parent` does not make one) |
| ready | open with nothing blocking it |
| in progress | claimed and being worked, or hooked (`bd` status `hooked`); the header and the bullet count both as in progress |
| human gate | a bead that waits on Ari |
| destroys, ships | a step that loses work (a discard, a delete) or puts work where others get it (a merge, a deploy, a push to main); a `bd` write is neither; marked **destroys:** and **irreversible:** |
| blocked | waiting on another bead |
| stale | in progress and untouched for fourteen days; `bd stale` rejects `hooked`, so a hooked bead is never listed stale |
| scope | this session's epics and their beads; other sessions' beads are left out |
| pane label | `machine=ozone|ID=%18|pane=3.1|nickname=homelab`: the host's `dotfiles machine-name` (`ozone`, reached through the host definition `laptop`; never a `--host-definition`), tmux's fixed pane id, the window.pane on the screen, the window's name; a pane on this Mac carries this Mac's own `dotfiles machine-name`, or no `machine=` part without the dotfiles harness |
| doctor | the project's own health command, `health.command` |
| agent's command | a command a Claude session, fork or lane typed through `run.zsh` (wrapped in `run_log`), or a `BEADS_ACTOR=claude:<session uuid> bd` write (a bare `BEADS_ACTOR=claude` is the older form); Ari types bare |
| open instruction | work he gave Claude in words, with the invocation or later, that names no bead: its words are the yes, so Claude files it as a bead and starts it the turn he gives it (Workflow › Proceed); it stays open while a step that ships or destroys, a permission row, or a retry waits on him, and ends when the run ends, on a no or correction that withdraws it, or on `stop operator mode`; its claimed bead carries it across a compaction |

### Row triage

A row is only what Claude cannot do itself (Rules › Up to five rows); whatever Claude's tools can do is Claude's, a `bd` write above all. These sources are the only ones; NEVER a row from anything else.

| Source | Row |
|---|---|
| `human` (`ids`, never `deferred_ids`, never an epic), a gate that waits on a decision he has not given | an *answer row*: `<id> "<title>": your answer; I record it`, with "(my recommendation: <the `Recommendation:` line>)" when `human.text` holds one; the title is the text after the id up to the first `: `; no command of his; Why now "it blocks <id>", else "waits on you" |
| `host_git.own` or `local_git.own` (this session's uncommitted edit) | his because a discard destroys work and the diff must reach his eyes: a show row first (`git diff`, what a discard would lose), a **destroys:** row only in a capture after the show row ran (he pasted its output, or the row landed per Proceed) |
| a refused command (Reference › Outside facts) | the command verbatim, with the refusal; a refused health run is the bare `health.command` on the capture's pane; a refused step of his instruction takes P0 and Why now "your instruction; my run was refused: <the refusal>"; the row drops once he reports its run |
| a section with `error` and `precondition: true` | one row for all of them: the failing read, by hand, on the capture's pane, since the fix (installing `bd`, his login) is on his host |
| a missing prerequisite on this Mac (Workflow › Capture) that Claude's install was refused or needs sudo for | his P0: the install command |
| a step of his instruction not yet run that needs his identity, a permission Claude lacks (sudo, a secret) or a physical act | row 1 "(your instruction)", priority `P0`, Why now "your instruction" |

Never rows, and where they go instead:

| Source | Instead |
|---|---|
| a human gate whose answer he gave this session (his words; output he pasted only when it states the fact the gate asks for) | Claude's `bd` write that turn (Reference › Yes and no), then Capture; the outcome sentence quotes the answer recorded |
| a human gate whose act Claude's tools can perform: its text names a command or a `bd` write, offers no choice and holds no `Recommendation:` line (in doubt: an answer row) | Claude's work, as a ready bead: the `human` bullet marks it "mine"; his naming it or his instruction starts it, and it closes with its evidence |
| `ready`, `in_progress` | Claude's work: the state bullets; he starts it by naming a bead (Reference › Yes and no) |
| a bead outside the scope | nowhere: the capture drops it, and nothing names it or writes to it |
| a `dirty` entry not in `own` | the checkout bullet, as a count of edits not listed as this session's; never its path, never a row |
| an epic, in any section | nobody's work, never claimed: counted in `ready`, never named |
| `health` not refused | the state bullet; run only as his instruction |
| an `error` without `precondition` | the state bullet; the next capture reads it again |
| his instruction, where Claude can run it | Claude's run, started the turn he gives it (Workflow › Proceed); only its step that ships or destroys is the one question |
| `blocked`, `deferred`, `stale` | the trailing line |
| anything, when `cut_off` is not null | no rows at all |

Priority is `P` plus the bead's integer (a `human` bead's is its `Priority:` line; null reads P2); a row with no bead inherits the priority of the highest-priority bead that cannot proceed until this row has run (named in Why now), else P2; a row with a bead keeps that bead's priority. Sort: 1 priority ascending; 2 `blockers` count descending; 3 oldest `updated_at` first. Pane: a row from a host section is the capture's pane; a `local_git` row is this Mac; a refused-command row is where the refusal happened. The sixth row and beyond go to the trailing line as "Also yours: …".

### Outside facts

The only facts a briefing may carry that are not in the capture's JSON:

| Fact | Source | Enters as |
|---|---|---|
| a refused command | the permission layer's refusal this session, quoted verbatim | his row, with the refusal |
| his open instruction | his words this session (Reference › Terms) | Claude's run, started that turn; the one question only for its step that ships or destroys, or a retry |
| his answer | his words this session, or output he pasted that states the fact a gate asks for | Claude's `bd` write; the outcome sentence quotes it |
| a read he asked for | the output of the read his question called for (a bead's body through `run.zsh`), this turn | the answer, verbatim |
| the typed result | this turn's `TYPED:`, or `REFUSED:` and the `REFUSED_KIND:` line after it, from `run.zsh --no-enter` on row 1 | row 1's key; the kind picks the move (Reference › How a 75 is classified) |
| a background agent | one this session launched for this pane whose completion notice has not arrived | the pane is another agent's (Reference › Shared pane) |
| the run's last line | the last line row 1's command, Claude's run of his instruction, or Claude's `bd` write of his answer printed, quoted | the outcome sentence after that run's Capture |
| Ari said | a fact he states that the tracker does not hold | one bullet "Ari said: …"; the capture's fact stays until the next capture |
| the announced absence | his words through `bin/away.zsh set`; the work on this Mac through `--continuing` | the away line (Reference › Announced absence) |

### Cut-off reasons

| Reason | From | The move |
|---|---|---|
| `not_opted_in` | `run.zsh` exit 77 | run `ari-driving on` there |
| `other_session` | exit 76 | `ari-driving off` then `on` there, or another pane |
| `busy` | exit 75, the pane running a command Ari typed (an editor, a TUI, a bare command), in copy mode or synchronized, or refused for a reason `run.zsh` could not name (Reference › How a 75 is classified) | wait, or name another pane |
| `lock_unavailable` | exit 75 of kind `lock_unavailable`: the host's lock root is unwritable or a stale lock will not clear; the words are quoted | the host's problem, not the pane's: another pane there fails too, no retry; he fixes the lock root, then tells me |
| `holds_text` | exit 75, un-entered text on the prompt that is not his pending row, whoever typed it; the line is quoted | clear it or run it, then tell me |
| `own_command` | exit 75, the pane ran an agent's command for the whole capture budget | a wait, not his: one waiting line, no question; his next message captures again |
| `own_command_persists` | exit 75, the previous capture by this session on this pane already waited on that same command | the same wait, no question; the line says he may name another pane |
| `row_pending` | exit 75, his pending row sits un-entered on the prompt | his: press Enter there, or clear it, then tell me |
| `row_running` | exit 75, his pending row is running | his: tell me what it printed when it ends |
| `no_pane` | exit 70 (the pane closed before or during the gate), or a 75 of kind `pane_gone`; the host's panes are listed | name one by its `ID=%N` |
| `ambiguous_pane` | the target matched two panes; both listed | name one by its `ID=%N` |
| `read_timed_out` | exit 124 with no complete stream; a read is still running there | tell me when its prompt is back; never resent; with `away`, the away line |
| `host_unreachable` | exit 255 from ssh, on a read or on `--list`; the error is quoted | open `ssh` to the host once in a pane; with `away`, the away line |
| `bad_definition` | `--list` failed with another code (an unknown definition, a bad flag); the error is quoted | Claude's to fix, never his, never the absence: Claude fixes it that turn, before the reply, whose paragraph ends "I fix the definition now; your next message reads again.", no question |
| `refused_text` | exit 1; the reader's own text was refused | a bug in the reader, not his to clear: the paragraph ends "I rewrite the read now; your next message reads again.", no question, and the next capture reads on one line |

The host reads stop at the first cut-off and the rest are unread; `local_git` and `health` still fill. The paragraphs' words are `bin/brief.zsh`'s, which wins over this table. Every P0 paragraph ends with the standing alternatives as statements (name another pane by its `ID=%N`, or `stop operator mode`), then its one question when the clear is his, else what Claude does next as a statement.

### How a 75 is classified

By the `REFUSED_KIND:` line right after `run.zsh`'s first `REFUSED:` line (`/ari-driving-remote` › The gate). **NEVER by the `REFUSED:` words**: they may change, and the gate's "last line does not end in the prompt (busy, or text already on the line)" names `busy` for what is `holds_text`. The words are only quoted.

| Kind | Reason |
|---|---|
| `copy_mode`, `synchronized` | `busy` |
| `pane_gone` | `no_pane`, the candidates from a fresh `--list` (as for a 70) |
| `lock_unavailable` | `lock_unavailable`, never `busy`: waiting or another pane does not clear it |
| `other_caller` (another `run.zsh` holds the pane's lock) | the agent's-command wait below |
| `not_a_shell`, `not_at_prompt` | the pane tail decides, below |
| `unknown`, no kind line, or a kind not in this table | his pending row on the tail is `row_pending` or `row_running`; else `busy`; `skill_fix=` names the skill to update (Workflow › Capture) |

The pane tail, the last prompt line's command joined across its wrapped lines, in order:

1. the pending row, the whole command (`--pending`, defaulted from `bin/pending.zsh`): `row_pending` un-entered, `row_running` running.
2. un-entered text that is not his row: `holds_text`, whoever typed it; no wait clears it.
3. a running agent's command (Reference › Terms): retry every 5 s (`FRONTIER_RETRY_S`) within the budget (`--timeout`); `own_command` when the budget is spent; `own_command_persists` when the previous capture already waited on it.
4. anything else running: `busy`.

### Shared pane

Another agent of this session (its own earlier read, a fork or a lane he launched, a subagent of Claude's, Claude's own run of his instruction there this turn) uses the pane when the capture waited on it (`waited_s` > 0), a background agent launched for this pane has not reported back (Reference › Outside facts › a background agent), or Claude's run of his instruction starts on it this turn. Then nothing is typed there: row 1 of his keeps the key "not typed: another agent is using this pane; typed when it is free", and the next Brief after a capture that did not wait types it.

### Announced absence

- **Trigger.** An absence is the host itself going away: the laptop taken, closed, off its network. A pause with the laptop on ("brb", lunch) is not one: no marker, a cut-off keeps its paragraph.
- **Lifetime.** From the turn he says so until he says he is back or a capture reaches the host. His words go on disk the turn he says them, as the clause about leaving (under twelve words, no question mark), never his whole message: `zsh $HOME/.claude/skills/ari-operator-mode/bin/away.zsh set --text '<his words>'`. `frontier.zsh` reads the marker as its default `--away`; a capture that reaches the host (no cut-off, or a reason outside `host_unreachable` and `read_timed_out`) clears it and records `away_ended: true`; he says he is back: `away.zsh clear`.
- **Render.** A `host_unreachable` or `read_timed_out` cut-off with `away` set is the away line, the whole reply, with no question (nothing waits on him until he is back): `brief.zsh --cut-off --continuing '<what runs on from this Mac>'`. The script names the host, his typed row from `pending`, and the work from `--continuing`: items separated by `; `, each a lane by bead id or a PR by number from this session, nothing from the host; omitted, the line says nothing of Claude's runs on. The rendered forms are `templates/briefing.example.md` › An absence he announced.
- **Other turns while away.** His message that says he is back (or pastes the host's output): `away.zsh clear`, then Capture. Any other message of his: no Capture (it cannot succeed and costs the ssh timeout); the reply is the newest capture's away line, re-printed with `--continuing` refreshed. An agent's completion notice: no Capture; the reply is the newest capture's `--header` plus one sentence naming the lane and what it left (PR number, hash), no question mark; the next away line carries it in `--continuing`.
- **Never.** No second read, no local `bd` or `git` as the tracker, no polling, no new row: an absence starts nothing; what was running when he left runs to its end and is reported.

### Yes and no

The first row that matches wins.

| Ari says | It means |
|---|---|
| his answer to "Which epic is this session's?" (one or more bead ids, or "the whole workspace"), or words that set the scope later ("this session is beads-xy9", "add beads-xy9.4", "drop beads-def") | the `--scope` for this and every later capture (`all` for the whole workspace): Capture with it |
| "none", "not yet" to that question | "No bead is this session's yet; the briefing needs one." and the one question "Name an epic, or `stop operator mode`?" |
| "back", "home", "I'm back", or pasted host output, while the away marker is set | the end of an absence: `away.zsh clear`, then Capture |
| "still out", "not yet", or anything else, while the away marker is set | still away: the away line re-printed, no Capture (Reference › Announced absence) |
| "yes", the row number or the row's name, when the one question names a **destroys:** or **irreversible:** row or step | the named yes; "ok", "go" or a yes inside a message that also corrects something re-renders and asks once more |
| "yes", "y", "go", "ok", "do it" | a yes to what the one question names: row 1 (an answer row with a recommendation: the recommendation is his answer; with none: the no-recommendation form again, nothing recorded), or the step of Claude's run it names |
| "do all of them", "rows 1-3" | a yes to row 1 only, said as a statement before the question |
| "row N" (row 1 included), a row's bead id or title verbatim | a yes to that row, re-rendered as row 1 without a capture |
| a bead's id or title verbatim, alone or after a verb ("do beads-abc"), for a bead that is ready, held by this session (`holder` `self`), or a human gate whose act Claude can perform, and not an epic | his instruction and its yes: Claude works it that turn (Workflow › Proceed); inside a question ("why is beads-abc ready?") it is a question, answered |
| an epic's id | "beads-epic closes when its children close.", then the briefing's one question when it has one |
| a bead id the capture does not list (outside the scope, or closed), alone or in an instruction or correction | "`<id>` is not among this capture's beads (scope `<scope>`); I write nothing to it; `add <its epic>` widens the scope.", then the briefing's one question when it has one |
| "stop", "wait", "hold", while Claude's run is going | halt it at the next commit, then Capture; nothing is unclaimed without a yes that names it |
| Enter in his pane | the yes for his own typed row; no chat yes is needed |
| an imperative that names no bead, with the invocation or later ("let's proceed with the stack") | his open instruction (Reference › Terms), and its own yes: Claude starts it that turn (Workflow › Proceed); a step that ships or destroys becomes the one question, a step only he can do row 1 "(your instruction)" (Reference › Row triage); an intention ("later", "we should", "I want") is filed as a bead per `/ari-bead-driven-development`, not run |
| a question | answered from the newest JSON; one it lacks is his instruction to read it (`templates/briefing.md` › Not in this capture) |
| his answer to a human gate the capture lists, at any time this session: his words while an answer row is asked and they match no row above, or words or pasted output that state what a gate asks | Claude records it that turn, never a row (Workflow › Proceed › Record an answer), then Capture |
| pasted output that answers no gate | that row's result |
| a partial match, or words matching two rows or beads | the one question "Which bead or row?" |
| a tracker correction ("that bead is done") about a bead the capture lists | he named the bead and the act: Claude runs the `bd` write, then Capture |
| a rendering correction | re-render, no capture |
| a yes that re-orders or drops rows | a yes to the changed table, re-rendered without a capture and asked again; nothing new typed while a typed line sits un-entered |
| a fact outside the tracker | one bullet "Ari said: …" (Reference › Outside facts) |
| a bare no | "What is wrong?" |
| "I'm leaving", "taking the laptop", "you'll lose the host" | the start of an absence: `away.zsh set`, then Capture (Reference › Announced absence) |

### Overrides

| Base skill › section | What this skill does instead | Why |
|---|---|---|
| `/ari-driving-remote` › Exit codes › 75, "never retry on your own" | `frontier.zsh` retries every 5 s within the capture budget when the pane runs an agent's command | the pane is busy with Claude's own work, not Ari's; waiting is the only move that is not his |
| `/ari-bead-driven-development` › Cut off | the cut-off output is `brief.zsh --cut-off` and the whole reply | one renderer for the base rule |

### Exit codes

| Script | Codes |
|---|---|
| `bin/frontier.zsh` | 0 the JSON was written, cut off or not; 4 no `--scope` while the workspace holds an open epic: nothing written, stdout `scope=needed` and `epics=` (never the reply's to pick from); without `--scope`, a bead map that could not be read is no exit 4 but every bd section's precondition error; 1 a missing prerequisite (`jq git base64 gzip gunzip awk`, and `timeout` or `gtimeout` in host mode), a bad flag, an unreadable `--previous`, a bad `--prefix`, a `--scope` id that is not a bead id, `--away` empty or holding a newline, question mark or backtick, `--away` with `--local`, `--timeout` under 5, `FRONTIER_RETRY_S` not a positive integer, or `CLAUDE_CODE_SESSION_ID` unset without `--local` |
| `bin/brief.zsh` | 0 printed; 3 the cut-off output was printed (the paragraph, a waiting line, or the away line); 1 a bad call, `--continuing` holding a newline, question mark or backtick, or a file that is not a capture |
| `bin/mode.zsh` | 0 on, or done; 3 off (`status`); 1 a bad call |
| `bin/pending.zsh` | 0 done, or shown; 3 nothing recorded (`show`); 1 a bad call, or `--text` carrying the `TYPED: ` prefix |
| `bin/away.zsh` | 0 done, or shown; 3 nothing recorded (`show`); 1 a bad call, or `--text` empty, over twelve words, or holding a newline, question mark or backtick |

### The offer

Off, on an orienting question, this line and nothing else: "Want operator mode? `/ari-operator-mode` reads the tracker, the checkouts and your pane and briefs you from scratch." Orienting: "where are we", "what's next", "catch me up", "remind me what's going on", "I haven't read any of this", a return after a gap that opens with a question about state. Not orienting: a specific question, an instruction, anything while the mode is on.

## Workflow

### Every turn, first

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh status
```

Exit 0: the mode is on and the reply follows **Proceed**. Exit 3: off; an orienting question gets the offer, anything else the default style. Exit 1: its error line verbatim and "Operator mode state is unreadable; I answer in the default style.", no capture.

### Resolve the inputs

`<host-definition>` and `<pane>` come from his words this turn, else `run.zsh --hosts` then `--list` (`/ari-driving-remote` › Read the known hosts), never a `%N` from the transcript; a later capture reuses `host_definition` and `pane` from the newest `frontier.json` whose `session` is this session's. `<beads>` and `<repo>` come from his words, the project's `CLAUDE.md` or memory; `<health>` is the project's doctor command (`bin/doctor.sh` in the homelab).

- `<scope>`, comma-separated: the top epic (`type` `epic`) above each bead this session filed (`bd create`) or claimed (`bd update --claim`), each such bead that has no parent, and every id his words named (Reference › Yes and no); `all` only when he said the whole workspace. A later capture takes the newest own capture's `scope.epics` (or `all`) plus what this session filed or claimed since. **NEVER guess it, and NEVER take it from `epics=`:** with none known, leave `--scope` off.
- `<own-paths>`, comma-separated: every file this session wrote (Edit, Write, or a command it ran) in a checkout and has not committed, relative to that checkout's root; after a compaction, the paths of the newest own capture's `own` entries (the text after the two status columns) plus any written since. NEVER from `git status` or `dirty`. One list covers both checkouts. With none, leave the flag off, and no dirty path is a row.
- An unknown pane makes the entry reply the acknowledgement plus the one question "Which pane holds the tracker?" and no capture. An unknown scope does the same with "Which epic is this session's?" (mid-mode, the question alone) once Capture without `--scope` exits 4, which wrote nothing; his answer is the scope (Reference › Yes and no).

### Enter the mode

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh on
```

Text first, then the Capture call, so the wait is announced: "Operator mode on. Reading the tracker through `<label with nickname>`, scoped to this session's `<scope>`: eight read-only commands, up to 45 s each; the table lists only what I cannot do myself, and I type row 1 onto that prompt, un-entered, unless it destroys or ships work; Enter is your yes. Answers: yes, row N, a bead id or an instruction (I start it), no, or `stop operator mode`." With `--local`: "Operator mode on. Reading the tracker on this Mac, scoped to this session's `<scope>`: eight read-only commands, up to 10 s each; the table lists only what I cannot do myself, each row a link for your pane `<local pane label>`. Answers: yes, row N, a bead id or an instruction (I start it), no, or `stop operator mode`." With no scope known yet, the clause ", scoped to this session's `<scope>`" is left out. An instruction with the invocation is its own yes (Reference › Yes and no): **Capture** and **Brief**, then **Proceed** with it, all in the same turn.

### Capture

One call, the Bash tool's timeout at 600000 ms and never in the background (the capture's budget is `--timeout`, 45 s, times its eight host reads, retries included; the two local reads take 10 s each):

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --host-definition <host-definition> --target <pane> --beads <beads> --scope <scope> --repo <repo> --local-repo "$PWD" --own-paths '<own-paths>' --health '<health>'
```

A tracker and checkout on this Mac:

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/frontier.zsh --local --beads <beads> --scope <scope> --local-repo "$PWD" --own-paths '<own-paths>' --health '<health>'
```

`--scope` and `--own-paths` are left off only as Workflow › Resolve the inputs says. The pending row and the absence are read from their markers (`bin/pending.zsh`, `bin/away.zsh`), so `--pending` and `--away` are passed only to override them. It prints `dir=`, `json=`, `cut_off=` and `skill_fix=`; the folder is the investigation folder below. **`skill_fix=` not empty MUST be a skill update that turn**: `/ari-skill-update <skill_fix>` with the stderr warning that names it as its line (`/ari-skill-update` › A mistake is a skill update); its one spawn line follows the briefing, the one line Rules › Cut off is the whole message allows after the cut-off output.

**Exit 4 is the unknown-scope reply (Workflow › Resolve the inputs) and ends the turn: NEVER capture again this turn, not with `--scope all` and not with ids from its `epics=`.**

Another non-zero exit from a bad flag or an unset session id is Claude's to fix and run once more; a missing prerequisite on this Mac Claude installs and runs once more, and only an install refused or needing sudo is his P0 (Reference › Row triage) with the one question "Fixed?"; a second non-zero exit in one turn is the whole reply: the error line verbatim and "I stop reading this turn; your next message tries again, and `stop operator mode` leaves." (no question: Claude's retry is never offered).

### Brief

**MUST read `templates/briefing.md` and `templates/briefing.example.md` before the first Capture of a session, and again after a compaction.**

1. `cut_off=` is not `none`: the reply is this stdout and nothing else (Rules › Cut off); on an away capture add `--continuing '<what runs on from this Mac>'` (Reference › Announced absence).
   ```zsh
   zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir <dir> --cut-off
   ```
2. The capture says `pending_seen: false`: his typed row is gone from the prompt; clear the marker and say so in one sentence.
   ```zsh
   zsh $HOME/.claude/skills/ari-operator-mode/bin/pending.zsh clear
   ```
3. Triage the rows (Reference › Row triage) before typing anything: row 1 is the first row of that table, never a ready bead, and never a gate he already answered (record it, then Capture: Reference › Yes and no). An answer row has nothing to type. Otherwise row 1 is typed when all three hold, each read from the JSON and the table: its pane is the capture's `pane` and not `local`, and it is not a `local_git` row; its Action opens with neither **destroys:** nor **irreversible:**; `waited_s` is 0, no background agent of this session is out on this pane, and no run of his instruction starts on it this turn (Reference › Shared pane). Any false: not typed, with the matching key from `templates/briefing.md` › The table. A row on this Mac (a `local_git` row, or any row of a `--local` capture) carries the link `/ari-driving-tmux` mints instead: click-to-run for a show row, so its output comes back, click-to-type for a **destroys:** row.
   ```zsh
   zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition <host-definition> --target <pane> --no-enter --cmd '<row 1 command>'
   zsh $HOME/.claude/skills/ari-operator-mode/bin/pending.zsh set --text '<the text after TYPED:>'
   ```
   The key reports the run per `templates/briefing.md` › The table; exit 1 (the reader's own text refused) means rewrite the command on one line and type again, never wait.
4. Line 1 is `brief.zsh --header`, pasted as printed (`templates/briefing.md` › Line 1 names the exceptions); then render `templates/briefing.md` from the JSON, in its order, adding nothing; `templates/briefing.example.md` is what it looks like filled.
5. **Before sending, check every `?` in the reply.** Each MUST be the one question, in a form `templates/briefing.md` › At most one question or its one-line replies name. A "Should I…", "Want me to…" or "Shall I…" question is deleted: its work is done that turn or dropped, and the reply says which in a statement.

### Proceed

On a yes, his instruction or his answer (Reference › Yes and no):

1. A yes to row 1: an answer row is his answer (step 3); typed, his Enter is the yes and there is nothing to do until he reports; not typed because it destroys or ships, or because the run was refused (75, 70, 76, 77 or 255), type it once now when Brief step 3's pane conditions hold and report that run the same way; not typed because another agent uses the pane, it waits for a capture that finds the pane free (Reference › Shared pane). Never retype a row whose run printed `TYPED:`; a second refusal re-renders the row with "not typed: <why>" and the busy-pane form of the one question. A row on this Mac is never run by Claude, a yes included: its link is his to click.
2. His instruction (its words are the yes), a bead he named, or a yes to the step the question named: for a bead, confirm that the newest JSON lists it as ready, held by this session (`holder` `self`), or a human gate whose act Claude can perform (never a fresh `bd show`, which ignores the scope); then Claude does it that turn through `/ari-bead-driven-development` (an instruction naming no bead is filed and claimed first, per its directive rule; Pick, Close) and `/ari-driving-remote`. The start line ends in a period and the run's first tool call follows it in the same turn; with the invocation, the start line follows the entry briefing in place of its question (`templates/briefing.md` › Which parts each reply carries).
   - His words cover every step that neither ships nor destroys: claim, branch, commit, opening a PR, and what he named ("request review, mark it ready"); a step that destroys or ships (Reference › Terms) stops the run and becomes the one question, naming it; a step only he can do becomes row 1 "(your instruction)". A step already done (the bead held by this session, the branch, an open PR for it) is skipped and said in one statement, never redone.
   - Claude's follow-up of the run (its CI, a review) is watched only by a background watcher launched that turn and named ("PR #12's CI runs; a watcher reports when it ends."), else dropped and said ("PR #12's CI is not watched."); the watcher's notice is the run's end.
   - While his typed row sits un-entered on that pane, the run does not type there (Rules › Only row 1 is typed); it waits for his Enter or clear.
   - A long run reports at three points, each the newest header and one sentence, no question: claimed, committed (hash), closed or PR opened.
   - Its end is a Capture (Rules): landed or failed, Capture before one word about it.
   - A run that fails: Claude reads why and whether the write landed; a cause it can fix, it fixes and the run goes on as a progress line. Otherwise Capture, then the header, "<bead id or instruction> failed: <last line>", then the table; a refused command becomes his row verbatim, else the retry is the one question (`templates/briefing.md` › At most one question); never a retried write without a yes.
3. **Record an answer.** His answer to a listed human gate (Reference › Yes and no) is written that turn as `/ari-bead-driven-development` › Ask Ari a decision records an outcome, by the bead's kind (`issue_type` from `bd -C <beads> show <id> --json`, a bead the capture lists): a decision, `update <id> --design "<his answer>"`, then `close <id> --reason "Ari chose <his answer>: his words at <HH:MMZ>"` while it is open; a gate, `gate resolve <id> -r "Ari: <his answer>, at <HH:MMZ>"`; a work bead labelled `human` for a question, a comment with his answer and `--remove-label human`, never a close. Each write is one `run.zsh` call on the capture's pane with `BEADS_ACTOR=claude:<this session's full UUID> bd -C <beads>`, the UUID written out because the host has no `CLAUDE_CODE_SESSION_ID`; his words go single-quoted with `'` escaped, and over one line or 200 bytes as a file (`run.zsh --put`). A gate already closed is skipped and said. The write waits while his typed row sits un-entered there; a refused write is his row verbatim, his words filled in. Then **Capture**; the outcome sentence quotes the answer recorded.
4. He reports an outcome (entered, pasted its output, cleared; a bead changed, a commit, a file written): `bin/pending.zsh clear` when it was his typed row, then **Capture**. His message that is only a question is answered from the newest JSON, no Capture; one the JSON lacks is `templates/briefing.md` › Not in this capture.
5. He says the host will be unreachable: `away.zsh set --text '<his words>'`, then **Capture**. While the marker is set, his other messages and agents' notices follow Reference › Announced absence › Other turns while away.
6. **Brief** again, in the after-a-run shape (`templates/briefing.md` › Which parts each reply carries): cut-off check, triage and type the new row 1, header with `--phase 'after row N'` (or `'after <bead id or instruction>'` for Claude's run), the outcome sentence (Rules › A run's end is a Capture), the table, the one question when one fits.

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/brief.zsh --dir <dir> --header --phase 'after row 1'
```

On a no: the row in Reference › Yes and no; **Capture** and **Brief** when the tracker was corrected, a re-render otherwise.

### Leave the mode

On `stop operator mode` or `normal mode`: `zsh $HOME/.claude/skills/ari-operator-mode/bin/mode.zsh off`, one line "Operator mode off.", then the default style.

### Not this, then this

The rows and runs; the state bullets and answers are `templates/briefing.example.md` › Not this, then this.

```
Not: | 5 | `beads-epic` epic: no write; it closes once its open children close | P2 | ready |
This: no row; beads-epic counts among the 3 ready, never named    ← an epic, and a row with nothing to do: never a row
Not: | 1 | beads-abc "Fix the widget": claim it, branch, PR; no merge | P1 | it blocks beads-bl1 |
This: - 3 ready; the top is beads-abc "Fix the widget" (P1).     ← Claude's work is a state bullet; he starts it by naming it
Not: | 1 | beads-h1 "Decide the indexers" | P2 | it blocks beads-bl2 |
This: | 1 | beads-h1 "Decide the indexers": your answer; I record it | P2 | it blocks beads-bl2 |   ← the Action names its writes
Not: | 1 | beads-h1 "Decide the indexers": record your answer | … |  with the key's command `bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"`
This: an answer row with no command; his "yes" or his words are the answer, and Claude records it   ← a `bd` write is Claude's to run
Not: | 1 | beads-h1 "Decide the indexers": your answer … |   (he said "stop at 1337x and TPB" earlier this session)
This: no row: Claude records that answer and closes beads-h1, then Capture   ← an answer he gave is never asked again
Not: | 1 | beads-amm.1 "Pin their version": your answer; I record it | P1 | waits on you |   (another session's human gate)
This: no row and no bullet: the capture, scoped to beads-xy9, does not list it   ← another session's bead
Not: | 2 | Show the uncommitted edit to `secrets.tf` | P2 | uncommitted on the host |   (an edit this session never made)
This: - The `laptop` checkout `~/homelab`: 1 uncommitted edit not listed as this session's; …   ← not in `own`: a count, never a row
Not: "I've written this up as a bead comment on beads-abc so it persists."
This: the briefing in the reply, nowhere else
Not: "PR opened for beads-abc." (from memory, no capture)
This: Capture, then the header, then "beads-abc landed: `gh pr create` printed `…/pull/12`; the capture lists beads-abc in progress."
Not: (his message: "Let's proceed with the stack") "… Start the stack: request review, mark ready, check CI; no merge?"
This: "Starting the stack: request review, mark ready, check CI; the merge waits on your yes." and the run that turn; the question waits for the merge   ← his words were the yes
Not: "PR #12 is open. Should I watch its CI and tell you once it passes?"
This: "PR #12 is open; its CI runs, and a watcher reports when it ends." with a background watcher launched that turn, else "PR #12's CI is not watched."   ← Claude's follow-up is done or dropped, never offered
```

## Investigation folder

```
/tmp/operator-mode/
├── ON-<session id>          # the mode marker: present while the mode is on, holds the time it was switched on (bin/mode.zsh)
├── PENDING-<session id>     # the row typed onto his prompt and not yet entered or cleared (bin/pending.zsh)
├── AWAY-<session id>        # his words when he said the host would be unreachable; cleared when he is back or the host answers (bin/away.zsh)
└── <UTC stamp>/
    └── frontier.json        # one capture; frontier.zsh makes the folder and prints its path as dir=
```

The markers live under `/tmp`: a reboot clears them, and the mode is then off with no "Operator mode off." said.

## File storage

- `bin/frontier.zsh` — the one reader of state, and the only script here that touches a pane, through `/ari-driving-remote`'s `run.zsh`; needs `/ari-skill-shellscripts`' `lib/logging.zsh`, `lib/run_with_timeout.zsh` and `lib/investigation_folder.zsh`.
- `bin/brief.zsh` — the header line and the cut-off output (the paragraph, a waiting line, or the away line), from a capture.
- `bin/mode.zsh`, `bin/pending.zsh`, `bin/away.zsh` — the three markers (on, the typed row, the announced absence), on `lib/marker.zsh`.
- `templates/briefing.md` — the render spec; `templates/briefing.example.md` — the spec filled, plus the scenarios; `templates/frontier.example.json` — the capture it renders.
- `tests/frontier.test.zsh` — the suite for all five scripts, against `tests/fake-run.zsh`, a fake `run.zsh`; run it after any edit to `bin/`, `lib/` or `templates/`: `zsh $HOME/.claude/skills/ari-operator-mode/tests/frontier.test.zsh`. An edited script also takes `zsh -n` and `/ari-skill-shellscripts` › Validation's conventions test.
