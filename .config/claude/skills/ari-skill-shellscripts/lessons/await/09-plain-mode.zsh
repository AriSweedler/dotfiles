#!/usr/bin/env zsh
#: When stderr is not a terminal (a log file, a pipe, an agent reading the output), there is
#: nothing to redraw. The same step as lesson 04, minus the key, then prints one [AWAIT] line per
#: change of state and nothing on a tick, with the elapsed seconds, so a transcript stays
#: readable. This lesson pipes its own stderr through cat to show it. AWAIT_INTERACTIVE=0 forces
#: the same thing on a tty. Exit code 0.
source "${0:A:h}/_prelude.zsh"
step() {
  await::computer "frobbing the widget (1/3)…"; {
    sleep 1
  }
  await::progress 1
  await::user "your turn (2/3): nothing to press, this lesson only waits a second"; {
    sleep 1
  }
  await::computer "frobbing some more (3/3)…"; {
    sleep 1
  }
}
{ await::run --slots 2 "frobbing the widget…" -- step; } 2>&1 | cat
