# Briefing example

The briefing runs between the first two `---` lines, rendered from `frontier.example.json` by the spec in `briefing.md`; the sections after it are scenarios the spec names, each with the capture detail it needs inline and a "Not this". Every line a script prints (the header, a cut-off paragraph, a waiting line, the away line) is pasted as printed, never retyped.

---

Operator mode on. Reading the tracker through `machine=personal|ID=%18|pane=3.1|nickname=homelab`, scoped to this session's `beads-epic`: eight read-only commands, up to 45 s each; the table lists only what you can do, and I type row 1 onto that prompt, un-entered, unless it destroys or ships work; Enter is your yes. Answers: yes, row N, a bead id (I start that bead), no, or `stop operator mode`.

Ready 3, in progress 1, human 1, blocked 2, stale 1; laptop abc1234 dirty 1; read 09:07Z; fresh read

**First principles.** The work is tracked as *beads* (one tracked issue each) in the `bd` workspace `~/beads` on the host `laptop` (shown: the *scope*, this session's epic `beads-epic`), which Claude reaches only by typing into one tmux *pane* (`machine=personal|ID=%18|pane=3.1|nickname=homelab`, the pane's full label); the checkout there is `~/homelab`, on this Mac `/Users/you/homelab`; a bead is *ready* (open, nothing blocks it), *in progress* (claimed), *stale* (untouched fourteen days), a *human gate* (only Ari answers it) or *blocked* (waits on another bead); *doctor* is `bin/doctor.sh`, the project's health command.

**State right now**
- 3 ready; the top is beads-abc "Fix the widget" (P1).
- 1 in progress: beads-ip1 "Half done", held by claude, stale.
- 1 waits on you: beads-h1 "Decide the indexers".
- 2 blocked, 2 deferred.
- Laptop checkout `~/homelab`: `bin/lab` modified by this session and uncommitted; last commits abc1234 first subject, bcd2345 second subject, cde3456 third subject; this Mac's `/Users/you/homelab` is clean at f00ba12.
- `bin/doctor.sh` has not been run this capture.

| # | Action | Priority | Why now |
|---|--------|----------|---------|
| 1 | beads-h1 "Decide the indexers": record your answer (my recommendation: stop at 1337x and TPB) | P2 | it blocks beads-bl2 |
| 2 | Show the uncommitted edit to `bin/lab` | P2 | `bin/lab` is uncommitted on the host; no bead waits on it |

Row 1, typed into `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered:
```zsh
bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"
```
Records the answer on the bead and closes it. Prints the bead id and `closed`.

Row 2, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed yet:
```zsh
git -C ~/homelab diff bin/lab
```
Shows the uncommitted change to `bin/lab` before you decide its fate. Prints a unified diff, or nothing when only the mode changed.

Blocked: 2 (beads-bl1 on beads-abc, beads-bl2 on beads-h1). Deferred: 2. Stale: 1 (beads-ip1, 15d).

A no is a correction. Row 1 is on `machine=personal|ID=%18|pane=3.1|nickname=homelab`: Enter it?

---

## Why the rows sit where they do

Both rows are his: beads-h1 first on blockers (it frees beads-bl2), then the show row, for the edit to `bin/lab` that `host_git.own` lists as this session's. The show row has no bead and no bead waits on it, so it is P2; a row that stood in front of a P1 bead would be P1, said in Why now. The recommendation is the `Recommendation:` line of `human.text`. Everything else is Claude's and only a state bullet: beads-abc and beads-def (ready), beads-ip1 (held by claude), the `bin/doctor.sh` run, and beads-epic (`type` `epic`, the parent of beads-abc), which counts among the 3 ready and is never named.

Not this: a row for beads-abc, beads-ip1, the doctor run, or "beads-epic: no write; it closes once its children close"; none is his to do. Not this either: the human row at P1 because what it blocks is P1; a row with a bead keeps that bead's priority.

## How row 1 was typed

Row 1 is on the capture's pane, neither destroys nor irreversible, and no agent is using the pane, so it is typed before the table is shown; its `TYPED:` line is the key, and `pending.zsh set` records the typed text so the next capture knows the line on his prompt is his row even after a compaction. The block holds the bare command; `run.zsh` wrapped it in `run_log` (the capture's `typed` entries quote paths as `~/"beads"`; that is the script's own quoting, his row is bare):

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %18 --no-enter --cmd 'bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"'
```
```
TYPED: run_log 'bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"'
SENT
```
```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/pending.zsh set --text 'run_log '"'"'bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"'"'"''
```

Not this: typing it with Enter, or typing it again next turn without his word.

## A row the pane refused

The same run exited 75 with `REFUSED: machine=personal|ID=%18|pane=3.1 running nvim, not a shell` and, on the next line, `REFUSED_KIND: not_a_shell`; the kind, never the words, makes the reason (`nvim` is no agent's command, so `busy`), the why is the words quoted, and the row is typed once on his yes:

```
Row 1, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed: running nvim, not a shell; wait, or name another pane:
```zsh
bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"
```
Records the answer on the bead and closes it. Prints the bead id and `closed`.
```

Not this: typing it anyway into the editor.

## Another agent in the pane

The capture waited 12 s on a fork's `run_log` command (`waited_s: 12`; the header reads `…; read 09:07Z; waited 12s for machine=personal|ID=%18|pane=3.1; fresh read`), so no run was attempted and the row says why; the same key when `waited_s` is 0 but a background agent this session launched for this pane has not reported back:

```
Row 1, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed: another agent is using this pane; typed when it is free:
```zsh
bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"
```
Records the answer on the bead and closes it. Prints the bead id and `closed`.
```

The next capture finds `waited_s: 0` and no agent out on the pane: the Brief types it, and the key becomes "Row 1, typed into `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered:".

Not this: typing it anyway, which parks a line on the prompt and makes every command of that fork refuse with 75.

## A destructive row first

A later capture, after he pasted row 2's diff: the dirty checkout is now row 1 and destroys, so nothing is typed and the question names it:

```
| 1 | **destroys:** the uncommitted edit to `bin/lab` | P2 | you pasted its diff; keep or discard |

Row 1, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed: destroys the edit to `bin/lab`; typed after your yes:
```zsh
git -C ~/homelab checkout -- bin/lab
```
Discards the uncommitted change to `bin/lab`. Prints nothing.

A no is a correction. Discard the edit to `bin/lab` (row 1)?
```

Not this: "ok" taken as that yes; a destroying row proceeds on "yes", its row number or its name, and the question named it.

## A local row

A capture whose `local_git.own` lists ` M bin/lab` gives a row on this Mac's pane, and every row of a `--local` capture (`pane` is `local`) is one of these: `run.zsh` never types it, and Claude never runs it. A show row carries the click-to-run link `/ari-driving-tmux` mints, so its output comes back; as row 1 it renders, and asks:

```
Row 1, for `ID=%4|pane=2.1|nickname=homelab`, a link:
[run: git -C /Users/you/homelab diff bin/lab](<the link that skill minted>)
Shows the uncommitted change. Prints a unified diff.

A no is a correction. Click row 1's link for `ID=%4|pane=2.1|nickname=homelab`?
```

Its **destroys:** row, after the diff came back, carries the click-to-type link instead, so Enter stays his: "Row 1, for `ID=%4|pane=2.1|nickname=homelab`, a link; it destroys the edit to `bin/lab`:".

Not this: "Type row 1 onto `local`?" (there is no pane named `local`), or Claude running the discard itself on his yes.

## After row 1 landed

He pressed Enter on his typed row; `pending.zsh clear`, then the capture, then the reply:

```
Ready 4, in progress 1, human 0, blocked 1, stale 1; laptop abc1234 dirty 1; read 09:12Z; after row 1

Row 1 printed `beads-h1 closed`; the capture no longer lists it under human, and beads-bl2 is ready.

| # | Action | Priority | Why now |
|---|--------|----------|---------|
| 1 | Show the uncommitted edit to `bin/lab` | P2 | `bin/lab` is uncommitted on the host; no bead waits on it |

Row 1, typed into `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered:
```zsh
git -C ~/homelab diff bin/lab
```
Shows the uncommitted change to `bin/lab`. Prints a unified diff, or nothing when only the mode changed.

Blocked: 1 (beads-bl1 on beads-abc). Deferred: 2. Stale: 1 (beads-ip1, 15d).

A no is a correction. Row 1 is on `machine=personal|ID=%18|pane=3.1|nickname=homelab`: Enter it?
```

Not this: the outcome sentence written before the capture ran. Not this either: a row for beads-bl2 now that it is ready; it is Claude's, a state bullet.

## An instruction with the invocation

He invoked `/ari-operator-mode fix the widget`: an open instruction, so no row; the entry briefing is the one above and only its question changes, while row 1 still waits for his Enter:

```
A no is a correction. Start beads-abc "Fix the widget": claim it, branch, PR; no merge?
```

Mid-mode, "Fix the widget" (the title verbatim) is its own yes and asks nothing; "the widget stuff" gets "Which row?".

Not this: a row 1 "(your instruction)" for work Claude runs; that row is only for an instruction that needs a permission Claude lacks.

## Claude's run reports

He said yes to that question; three progress lines, each the newest capture's header and one sentence with no question mark:

```
Ready 3, in progress 1, human 1, blocked 2, stale 1; laptop abc1234 dirty 1; read 09:07Z; fresh read

Claimed beads-abc "Fix the widget"; branch abc-widget.
```

Then "Committed 8542e79 on abc-widget." and "Opened PR #12 for beads-abc.", each under the same header. At its end, a Capture, then the after-a-run briefing, which opens:

```
Ready 2, in progress 2, human 1, blocked 2, stale 1; laptop abc1234 dirty 1; read 09:15Z; after beads-abc

beads-abc landed: `gh pr create` printed `…/pull/12`; the capture lists beads-abc in progress.
```

Not this: "PR opened for beads-abc" from memory; the end of the run is a Capture, and the outcome sentence names what the new JSON shows plus the command's last printed line, quoted.

## A refused run

He said "run the doctor"; the permission layer refused Claude's `run.zsh` call for `bin/doctor.sh`. The next briefing's row is his until he reports its run:

```
| 1 | Run `bin/doctor.sh` | P2 | my run was refused: "<the refusal, verbatim>" |

Row 1, typed into `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered:
```zsh
bin/doctor.sh
```
Runs the project's health checks. Prints one PASS or FAIL line per check.
```

## Nothing needs you

A later fresh read: no First principles, and Claude's work stays a state bullet that nothing asks about:

```
Ready 1, in progress 1, human 0, blocked 1, stale 0; laptop abc1234 clean; read 09:20Z; fresh read

**State right now**
- 1 ready; the top is beads-def "Polish the frob" (P2).
- 1 in progress: beads-abc "Fix the widget", held by claude.
- 1 blocked, 2 deferred.
- Laptop checkout `~/homelab` clean; last commits abc1234 first subject, bcd2345 second subject, cde3456 third subject.
- `bin/doctor.sh` has not been run this capture.

Nothing needs you.

Blocked: 1 (beads-bl1 on beads-abc). Deferred: 2.

A no is a correction. Nothing needs you; `stop operator mode` leaves. Read again?
```

Not this: "Nothing needs you." when `human` could not be read; that is "Nothing known to need you; `human` could not be read."

## Another session in the same workspace

`~/beads` also holds another session's epics, and that session left `secrets.tf` uncommitted in `~/homelab`. This session had filed no bead yet, so it knew no scope; the capture without `--scope` exited 4 (`scope=needed`) and wrote nothing, and the whole entry reply is:

```
Operator mode on. Reading the tracker through `machine=personal|ID=%18|pane=3.1|nickname=homelab`: eight read-only commands, up to 45 s each; the table lists only what you can do, and I type row 1 onto that prompt, un-entered, unless it destroys or ships work; Enter is your yes. Answers: yes, row N, a bead id (I start that bead), no, or `stop operator mode`.

Which epic is this session's?
```

His next message, "beads-epic", is the scope, not the epic row of Yes and no: the capture runs with `--scope beads-epic --own-paths 'bin/lab'`, and the reply is the briefing at the top without its acknowledgement (already said), its header reading `laptop abc1234 dirty 2`, its checkout bullet counting the other edit, and no row for it:

```
- Laptop checkout `~/homelab`: `bin/lab` modified by this session and uncommitted; 1 uncommitted edit not listed as this session's; last commits abc1234 first subject, bcd2345 second subject, cde3456 third subject; this Mac's `/Users/you/homelab` is clean at f00ba12.
```

Asked to act on a bead the capture does not list: "`<id>` is not among this capture's beads (scope `beads-epic`); I write nothing to it; `add <its epic>` widens the scope.", then the briefing's one question.

Not this: a row for the other session's human gate because bd lists it, a bullet naming its in-progress beads, a show row for `secrets.tf`, a second capture this turn with `--scope all` or with an epic picked from `epics=`, or "beads-epic closes when its children close." as the answer to his scope.

## Asked what the capture cannot answer

Asked "is beads-h1 still open?":

```
Not in this capture; a fresh capture would read `human`. Or say `stop operator mode` to ask freely. A no is a correction. Row 1 is on `machine=personal|ID=%18|pane=3.1|nickname=homelab`: Enter it?
```

Asked what beads-abc's body says:

```
Not in this capture; no section reads a bead's body. Reading beads-abc is Claude's on your word: `bd -C ~/beads show beads-abc`. Or say `stop operator mode` to ask freely. A no is a correction. Row 1 is on `machine=personal|ID=%18|pane=3.1|nickname=homelab`: Enter it?
```

Asked "tell me more about blocked": the `blocked.text` pasted verbatim in a fenced block, then the briefing's one question. Not this: a summary of it.

## Cut off

The whole reply, nothing before or after it (a `holds_text` capture whose prompt held `cd ~/homelab && bin/lab up apps/torrent`):

```
**P0, cut off from the tracker.** The pane `machine=personal|ID=%18|pane=3.1|nickname=homelab` holds un-entered text on its prompt; clear it or run it, then tell me; I read nothing from the tracker or the host checkout this turn. Its prompt holds, verbatim: `at 01:00:00 UTC ❯ cd ~/homelab && bin/lab up apps/torrent`. Unread: ready, in_progress, human, blocked, stale, deferred, host_git. This is yours to clear; I do nothing else until it is. Name another pane by its `ID=%N`, or say `stop operator mode`. Tell me when it is clear, or name another pane?
```

Not this: the same paragraph followed by "Meanwhile this Mac's checkout is clean at f00ba12, so I could start the docs row." `local_git` did fill; it is still not said.

The other reasons his to clear share that shape; the ones that differ:

```
**P0, cut off from the tracker.** The pane `%99` does not exist on the host; the panes there are machine=personal|ID=%18|pane=3.1, machine=personal|ID=%3|pane=1.1; name one by its ID=%N; I read nothing from the tracker or the host checkout this turn. Unread: ready, in_progress, human, blocked, stale, deferred, host_git. This is yours to clear; I do nothing else until it is. Name another pane by its `ID=%N`, or say `stop operator mode`. Tell me when it is clear, or name another pane?
```
```
**P0, cut off from the tracker.** The pane `machine=personal|ID=%18|pane=3.1|nickname=homelab` refused the command text before typing ([ERROR] refused: the command holds a literal newline); a bug in the reader, not yours to clear; I read nothing from the tracker or the host checkout this turn. Unread: ready, in_progress, human, blocked, stale, deferred, host_git. I do nothing else until it is read. Name another pane by its `ID=%N`, or say `stop operator mode`. Shall I rewrite the read on one line and try once?
```
```
**P0, cut off from the tracker.** The pane `%18` could not be reached (ssh: connect to host laptop port 22: No route to host); I read nothing from the tracker or the host checkout this turn. Unread: ready, in_progress, human, blocked, stale, deferred, host_git. I do nothing else until it is read. Name another pane by its `ID=%N`, or say `stop operator mode`. Tell me when `ssh` to the host works from a pane?
```

The last is `host_unreachable` with no absence announced: his P0, with the `ssh` move. The `refused_text` one is Claude's bug; his yes to its question is one rewritten read.

## An agent's command in the pane

The capture ended `own_command`: the whole reply is this one line, and his next message captures again:

```
Waiting on `machine=personal|ID=%18|pane=3.1|nickname=homelab`, busy with `another caller is typing into it`; an agent's command, nothing of yours to clear. Read again?
```

The next capture found the same command still there (`own_command_persists`): still a wait, still not his:

```
Still waiting on `machine=personal|ID=%18|pane=3.1|nickname=homelab`, busy with `running curl, not a shell (run_log 'curl -s http://127.0.0.1:8096/Items') since 2026-10-30T09:02:11Z`; an agent's command, nothing of yours to clear. Wait, or name another pane?
```

Not this: the P0 paragraph, which tells Ari to clear a pane that is busy with Claude's own work; or a second read in the same turn.

## His row still on the prompt

The capture (its `--pending` defaulted from `pending.zsh`) found his un-entered row on the prompt; the whole reply is this one line:

```
Your row is on your prompt in `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered: press Enter there, or clear it, then tell me?
```

Running, the line is this one, and his report of what it printed is the row's result:

```
Your row is running in `machine=personal|ID=%18|pane=3.1|nickname=homelab` (`run_log 'bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"'`); tell me what it printed when it ends?
```

A capture that finds the prompt idle without his row records `pending_seen: false`: the Brief runs `pending.zsh clear` and says "Your typed row is gone from the prompt; the marker is cleared." in one sentence before the table.

Not this: the P0 paragraph quoting Claude's own typed row as text Ari must clear.

## An absence he announced

He said "going to work, so I'll be gone for a bit and you'll lose connectivity and you'll not have access to my personal laptop until I get home". The clause about leaving went on disk the same turn, then the Capture ran (no `--away`: the marker is its default):

```zsh
zsh $HOME/.claude/skills/ari-operator-mode/bin/away.zsh set --text 'going to work, laptop with me'
```

`--list` failed with 255 (`host_unreachable`), so no pane was resolved and the line names the host. The whole reply is this one line, rendered with `--continuing 'lane beads-abc (PR #12 open); lane beads-def'` (two lanes this session launched on this Mac, by bead id, the PR by number); his typed row comes from the capture's `pending`, not from `--continuing`:

```
Away: the host `laptop` is unreachable, as you said (going to work, laptop with me); the tracker is unread, read tried at 21:01Z; your row `run_log 'bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"'` sits on that prompt, not entered; running on from this Mac: lane beads-abc (PR #12 open); lane beads-def; I read again when you say you are back. Back?
```

The header for that capture, used only by a completion-notice line (below), names the host too: `Away: laptop (host_unreachable); tracker unread; read 21:01Z`.

A read that timed out mid-capture is the absence too; the pane was resolved, so it is named:

```
Away: the host `laptop` did not answer a read of mine in `machine=personal|ID=%18|pane=3.1|nickname=homelab`, as you said it would not (going to work, laptop with me); I never resend it; the tracker is unread, read tried at 21:30Z; nothing of mine runs on from this Mac meanwhile; I read again when you say you are back. Back?
```

Nothing running on this Mac: `--continuing` is left off, and the line says `nothing of mine runs on from this Mac meanwhile`.

Not this: the P0 paragraph telling him to open `ssh` to a host he just said is unreachable, or "I do nothing else until it is read" while lanes run on this Mac. Not this either: `--continuing 'lane beads-abc (PR #12 open); is the deploy done?'` (a question mark: refused, exit 1), or `--continuing 'beads-h1 waits on you; the laptop checkout is dirty'` (host facts: the tracker is unread, nothing from it may be said).

### The turns while he is away

He says "go" or asks anything that is not "back": no Capture (it cannot succeed and costs the ssh timeout); the reply is the newest capture's away line, re-printed with `--continuing` refreshed.

A lane finishes (an agent's completion notice, not his message): no Capture, no question mark; the reply is the newest capture's header plus one sentence:

```
Away: laptop (host_unreachable); tracker unread; read 21:01Z

Lane beads-abc finished: PR #12 opened at head 8542e79; not merged.
```

The next away line carries it: `--continuing 'lane beads-abc (PR #12 open, done); lane beads-def'`.

He says "back", "home" or pastes the host's prompt: `away.zsh clear`, then a Capture and a normal briefing; the host still unreachable is then his P0 with the `ssh` move, as above.

A capture that reaches the host while the marker is set ends the absence by itself: the marker is cleared, the JSON holds `away_ended: true`, and the header says so once:

```
Ready 2, in progress 1, human 1, blocked 2, stale 1; laptop abc1234 dirty 1; read 09:07Z; host answered; fresh read
```

Not this: the away line when the capture ended `holds_text` or `busy`; the host answered, so the absence is over and his paragraph stands.

## Not this, then this: state bullets and answers

```
Not: "beads-abc is done, I finished it before you stepped away."
This: "beads-abc "Fix the widget" is ready (P1)."            ← the capture lists it under ready; Claude's belief that the tracker is stale is neither a row nor an edit
Not: "Step 2 is the compose variable, as in the one-liner."
This: "The compose variable in apps/media/compose.yaml."     ← paths and names, no session shorthand
Not: "Since this morning we merged the PR and fixed the doctor."
This: "Last commits: abc1234 first subject; bcd2345 second subject."   ← host_git.log, nothing more
Not: "Doctor is green."
This: "bin/doctor.sh has not been run this capture."         ← health.ran is false; the run is Claude's, on his word, never a row
Not: (off, to "where did we leave off?") a recap from the transcript
This: "Want operator mode? `/ari-operator-mode` reads the tracker, the checkouts and your pane and briefs you from scratch."
Not: (mode on, to "fix the widget") a new task Claude invents
This: Claude works beads-abc, his instruction and its yes      ← its title verbatim; "the widget stuff" would get "Which row?"
Not: (to "do rows 1 to 3") three rows run
This: "Rows run one at a time; this yes is row 1's." then row 1   ← one yes, one row
Not: (to "no, the laptop checkout is clean, I committed it") dropping the dirty row
This: "- Ari said: `~/homelab` is clean; the capture still shows `bin/lab` modified." and the row stays until the next capture
Not: (to "that bead is done" about beads-def) editing the state bullet
This: Claude runs `bd -C ~/beads close beads-def`, then Capture   ← he named the bead and the act: his yes
Not: (to a bare "no") a re-render
This: "What is wrong?"
```
