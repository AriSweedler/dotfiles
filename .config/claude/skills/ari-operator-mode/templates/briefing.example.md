# Briefing example

Lines 7 to 47 are one briefing rendered from `frontier.example.json` by the spec in `briefing.md`; the sections after `## The run behind Row 1` are scenarios the spec names, each with the capture detail it needs inline and a "Not this".

---

Operator mode on. Reading the tracker through `machine=personal|ID=%18|pane=3.1|nickname=homelab`: seven read-only commands, up to 45 s each; then I type your first row onto that prompt, un-entered.

Ready 2, in progress 1, human 1, blocked 2, stale 1; laptop abc1234 dirty 1; read 09:07Z; fresh read

**First principles.** The work is tracked as *beads* (one tracked issue each) in the `bd` workspace `~/beads` on the host `laptop`, which Claude reaches only by typing into one tmux *pane* (`machine=personal|ID=%18|pane=3.1|nickname=homelab`, the pane's full label); the checkout there is `~/homelab`, on this Mac `/Users/you/homelab`; a bead is *ready* (open, nothing blocks it), *in progress* (claimed), *stale* (untouched fourteen days), a *human gate* (only Ari answers it) or *blocked* (waits on another bead); *doctor* is `bin/doctor.sh`, the project's health command.

**State right now**
- 2 ready; the top is beads-abc "Fix the widget" (P1).
- 1 in progress: beads-ip1 "Half done", held by claude, stale.
- 1 waits on you: beads-h1 "Decide the indexers".
- 2 blocked, 2 deferred.
- Laptop checkout `~/homelab`: `bin/lab` modified and uncommitted; last commits abc1234 first subject, bcd2345 second subject, cde3456 third subject; this Mac's `/Users/you/homelab` is clean at f00ba12.
- `bin/doctor.sh` has not been run this capture.

| # | Action | Priority | Who | Why now |
|---|--------|----------|-----|---------|
| 1 | beads-h1 "Decide the indexers": record your answer (my recommendation: stop at Prowlarr's 1337x and TPB, the two its text names) | P1 | Ari | it blocks beads-bl2 |
| 2 | beads-abc "Fix the widget": claim it, branch, PR; no merge | P1 | Claude | it blocks beads-bl1 |
| 3 | Show the uncommitted edit to `bin/lab` | P2 | Ari | a dirty checkout hides what beads-abc will change |
| 4 | beads-def "Polish the frob": claim it, branch, PR; no merge | P2 | Claude | next ready, frees nothing |
| 5 | Run `bin/doctor.sh` on the laptop | P2 | Claude | health unknown this capture |

Row 1, typed into `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered:
```zsh
bd -C ~/beads human respond beads-h1 -r "stop at 1337x and TPB"
```
Records the answer on the bead and closes it. Prints the bead id and `closed`.

Row 3, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed yet:
```zsh
git -C ~/homelab diff bin/lab
```
Shows the uncommitted change to `bin/lab` before you decide its fate. Prints a unified diff, or nothing when only the mode changed.

Blocked: 2 (beads-bl1 on beads-abc, beads-bl2 on beads-h1). Deferred: 2. Stale: 1 (beads-ip1, 15d).

A no is a correction. Row 1 is on `machine=personal|ID=%18|pane=3.1|nickname=homelab`: Enter it?

---

## The run behind Row 1

This ran once before the briefing; its `TYPED:` line is Row 1's key, and `pending.zsh set` records the typed text so the next capture knows the line on his prompt is his row even after a compaction. The block holds the bare command; `run.zsh` wrapped it in `run_log`:

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

The same run exited 75 with `REFUSED: machine=personal|ID=%18|pane=3.1 running nvim, not a shell`; the row renders with the why and the move, and is typed once on his yes:

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

Not this: typing it anyway, which parks a line on the prompt and makes every command of that fork refuse with 75.

## A destructive row first

A later capture, after row 3's diff was seen: the dirty checkout is now row 1 and destroys, so nothing is typed and the question names it:

```
| 1 | **destroys:** the uncommitted edit to `bin/lab` | P2 | Ari | the diff showed a stray debug line |

Row 1, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed: destroys the edit to `bin/lab`; typed after your yes:
```zsh
git -C ~/homelab checkout -- bin/lab
```
Discards the uncommitted change to `bin/lab`. Prints nothing.

A no is a correction. Discard the edit to `bin/lab` (row 1)?
```

Not this: "ok" taken as that yes; a destroying row proceeds only on "yes", its row number or its name.

## A local row

When the row's pane is this Mac's, the command is the click-to-type link `/ari-driving-tmux` mints, under that pane's label:

```
Row 3, for `ID=%4|pane=2.1|nickname=homelab`, not typed yet:
[type: git -C /Users/you/homelab diff bin/lab](<the link that skill minted>)
Shows the uncommitted change. Prints a unified diff.
```

## After row 1 landed

He pressed Enter; `pending.zsh clear`, then the capture, then the reply:

```
Ready 2, in progress 1, human 0, blocked 1, stale 1; laptop abc1234 dirty 1; read 09:12Z; after row 1

Row 1 printed `beads-h1 closed`; the capture no longer lists it under human, and beads-bl2 is no longer blocked.

| # | Action | Priority | Who | Why now |
|---|--------|----------|-----|---------|
| 1 | beads-abc "Fix the widget": claim it, branch, PR; no merge | P1 | Claude | it blocks beads-bl1 |
| 2 | Show the uncommitted edit to `bin/lab` | P2 | Ari | a dirty checkout hides what beads-abc will change |
| 3 | beads-def "Polish the frob": claim it, branch, PR; no merge | P2 | Claude | next ready, frees nothing |
| 4 | Run `bin/doctor.sh` on the laptop | P2 | Claude | health unknown this capture |

Row 2, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed yet:
```zsh
git -C ~/homelab diff bin/lab
```
Shows the uncommitted change to `bin/lab`. Prints a unified diff, or nothing when only the mode changed.

Blocked: 1 (beads-bl1 on beads-abc). Deferred: 2. Stale: 1 (beads-ip1, 15d).

A no is a correction. Row 1 next?
```

Not this: typing row 2 because it is his; only row 1 is ever typed.

## Asked what the capture cannot answer

```
Not in this capture; no section reads a bead's body. Reading beads-abc is a Claude row: `bd -C ~/beads show beads-abc`. Or say `stop operator mode` to ask freely.
```

## Cut off

The whole reply, nothing before or after it (a `holds_text` capture whose prompt held `cd ~/homelab && bin/lab up apps/torrent`):

```
**P0, cut off from the tracker.** The pane `machine=personal|ID=%18|pane=3.1|nickname=homelab` holds un-entered text on its prompt; clear it or run it, then tell me; I read nothing from the tracker or the host checkout this turn. Its prompt holds, verbatim: `at 01:00:00 UTC ❯ cd ~/homelab && bin/lab up apps/torrent`. Unread: ready, in_progress, human, blocked, stale, deferred, host_git. This is yours to clear; I do nothing else until it is. Tell me when it is clear, or name another pane?
```

Not this: the same paragraph followed by "Meanwhile this Mac's checkout is clean at f00ba12, so I could start the docs row." `local_git` did fill; it is still not said.

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

Not this: the P0 paragraph quoting Claude's own typed row as text Ari must clear.

## Not this, then this: state bullets and answers

```
Not: "beads-abc is done, I finished it before you stepped away."
This: "beads-abc 'Fix the widget' is ready (P1)."            ← the capture lists it under ready; a belief the tracker is stale is a row, never an edit
Not: "Step 2 is the compose variable, as in the one-liner."
This: "The compose variable in apps/media/compose.yaml."     ← paths and names, no session shorthand
Not: "Since this morning we merged the PR and fixed the doctor."
This: "Last commits: abc1234 first subject; bcd2345 second subject."   ← host_git.log, nothing more
Not: "Doctor is green."
This: "bin/doctor.sh has not been run this capture."         ← health.ran is false; the run is a row
Not: (off, to "where did we leave off?") a recap from the transcript
This: "Want operator mode? `/ari-operator-mode` reads the tracker, the checkouts and your pane and briefs you from scratch."
Not: (to "fix the widget") a new task
This: a yes to the beads-abc row                             ← its title verbatim; "the widget stuff" would get "Which row?"
Not: (to "no, the laptop checkout is clean, I committed it") dropping the dirty row
This: "- Ari said: `~/homelab` is clean; the capture still shows `bin/lab` modified." and the row stays until the next capture
```
