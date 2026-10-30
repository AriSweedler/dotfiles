# Briefing example

Rendered from `frontier.example.json` by the spec in `briefing.md`. Every sentence below traces to a field of that file.

---

Ready 2, in progress 1, human 1, blocked 1, stale 1; laptop abc1234 dirty 1; read 09:07Z; fresh read

**First principles.** The work is tracked as *beads* (one tracked issue each) in the `bd` workspace `~/beads` on the host `laptop`, which Claude reaches only by typing into one tmux *pane* (`machine=personal|ID=%18|pane=3.1|nickname=homelab`: the machine, tmux's fixed pane id, the window.pane on the screen, and the window's name); the project checkout there is `~/homelab`, and on this Mac `/Users/you/homelab`; a bead is *ready* (open, nothing blocks it), *in progress* (claimed), a *human gate* (only Ari can answer it) or *blocked* (waits on another bead); *doctor* is `bin/doctor.sh`, the project's own health command.

**State right now**
- 2 ready; the top is beads-abc "Fix the widget" (P1), which beads-bl1 waits on.
- 1 in progress: beads-ip1 "Half done", held by claude, stale.
- 1 waits on you: beads-h1 "Which indexers?".
- Laptop checkout `~/homelab`: `bin/lab` modified and uncommitted; last commits abc1234 first subject, bcd2345 second subject, cde3456 third subject.
- `bin/doctor.sh` has not been run this capture.

| # | Action | Priority | Who | Why now |
|---|--------|----------|-----|---------|
| 1 | Answer beads-h1 "Which indexers?" (my recommendation: the two already listed in its text) | P1 | Ari | the answer unblocks work under beads-abc |
| 2 | **destroys:** the uncommitted edit to `bin/lab`, or commits it | P1 | Ari | a dirty checkout hides what beads-abc will change |
| 3 | beads-abc "Fix the widget" | P1 | Claude | unblocks beads-bl1 |
| 4 | Run `bin/doctor.sh` on the laptop | P2 | Ari | health unknown this capture |
| 5 | beads-def "Polish the frob" | P2 | Claude | next ready, frees nothing |

Row 1, typed into `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered:
```zsh
bd -C ~/beads human respond beads-h1 -r "the two already listed"
```
Records the answer on the bead and closes it. Prints the bead id and `closed`.

Row 2, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed yet:
```zsh
git -C ~/homelab diff bin/lab
```
Shows the uncommitted change to `bin/lab` before you decide. Prints a unified diff, or nothing when only the mode changed.

Row 4, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed yet:
```zsh
cd ~/homelab && bin/doctor.sh
```
Runs the project's health check. Prints one PASS, FAIL or SKIP line per check and exits 0 when none FAIL.

Blocked: 1 (beads-bl1 on beads-abc). Deferred: 2. Stale: 1 (beads-ip1, 1d).

A no is a correction. Row 1 next?

---

## The run behind Row 1

Before the rendering above went out, this ran once, and its `TYPED:` line is what the key "typed into …, not entered" reports; the block shows the bare command, `run.zsh` wrapped it in `run_log` on his prompt:

```zsh
zsh $HOME/.claude/skills/ari-driving-remote/bin/run.zsh --host-definition laptop --target %18 --no-enter --cmd 'bd -C ~/beads human respond beads-h1 -r "the two already listed"'
```
```
TYPED: run_log 'bd -C ~/beads human respond beads-h1 -r "the two already listed"'
SENT
```

## A row the pane refused

The same run exited 75 with `REFUSED: machine=personal|ID=%18|pane=3.1 running nvim, not a shell`; the row renders with the why and is typed once on his yes:

```
Row 1, for `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not typed: running nvim, not a shell:
```zsh
bd -C ~/beads human respond beads-h1 -r "the two already listed"
```
Records the answer on the bead and closes it. Prints the bead id and `closed`. I type it when you say the pane is free.
```

Not this: typing it again next turn without his word, or typing it with Enter.

## A local row

When the pane is this Mac's, the command is the click-to-type link `/ari-driving-tmux` mints:

```
Row 2, this Mac:
[type: git -C /Users/you/homelab diff bin/lab](<the link that skill minted>)
Shows the uncommitted change. Prints a unified diff.
```

## After row 1 landed

```
Ready 2, in progress 1, human 0, blocked 1, stale 1; laptop abc1234 dirty 1; read 09:12Z; after row 1

Row 1 printed `beads-h1 closed`; the capture no longer lists it under human.

| # | Action | … |
…
A no is a correction. Row 1 next?
```

## Cut off

The whole reply, nothing before or after it:

```
**P0, cut off from the tracker.** The pane `machine=personal|ID=%18|pane=3.1` holds un-entered text on its prompt; clear it or run it, then tell me; I read nothing from the tracker or the host checkout this turn. Its prompt holds, verbatim: `at 01:00:00 UTC ❯ cd ~/homelab && bin/lab up apps/torrent`. Unread: ready, in_progress, human, blocked, stale, deferred, host_git. This is yours to clear; I do nothing else until it is. Tell me when it is clear, or name another pane?
```

Not this: the same paragraph followed by "Meanwhile this Mac's checkout is clean at f00ba12, so I could start the docs row." `local_git` did fill; it is still not said.

## My own command in the pane

When the capture ended `own_command`, the whole reply is this one line, and his next message captures again:

```
Waiting on `machine=personal|ID=%18|pane=3.1`, busy with `another caller is typing into it`; nothing of yours to clear. Read again?
```

Not this: the P0 paragraph above, which tells Ari to clear a pane that is busy with Claude's own work; or a second read in the same turn.

## His row still on the prompt

When the capture (run with `--pending`) found his un-entered row on the prompt, the whole reply is this one line:

```
Your row is on your prompt in `machine=personal|ID=%18|pane=3.1`, not entered: press Enter there, or clear it, then tell me?
```

Not this: the P0 paragraph quoting Claude's own typed row as text Ari must clear.
