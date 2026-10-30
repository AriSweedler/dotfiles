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

Row 1, `machine=personal|ID=%18|pane=3.1|nickname=homelab`:
```zsh
bd -C ~/beads human respond beads-h1 -r "the two already listed"
```
Records the answer on the bead and closes it. Prints the bead id and `closed`.

Row 2, `machine=personal|ID=%18|pane=3.1|nickname=homelab`:
```zsh
git -C ~/homelab diff bin/lab
```
Shows the uncommitted change to `bin/lab` before you decide. Prints a unified diff, or nothing when only the mode changed.

Row 4, `machine=personal|ID=%18|pane=3.1|nickname=homelab`:
```zsh
cd ~/homelab && bin/doctor.sh
```
Runs the project's health check. Prints one PASS, FAIL or SKIP line per check and exits 0 when none FAIL.

Blocked: 1 (beads-bl1 on beads-abc). Deferred: 2. Stale: 1 (beads-ip1, 1d).

A no is a correction. Row 1 next?

---

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
