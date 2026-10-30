#!/usr/bin/env zsh
#: The turns hand off as many times as needed, and every message states where you are in the
#: sequence: the machine frobs (1/3), then needs you (2/3, a key), then frobs again on what you
#: gave it (3/3), then is done. Every state call is followed by its { } group.
#: computer → user → computer → ✓. Press a key when the pulse asks. Exit code 0.
source "${0:A:h}/_prelude.zsh"
step() {
  await::computer "frobbing the widget (1/3)…"; {
    sleep 2
  }
  await::user "your turn: press any key (2/3)"; {
    wait_key
  }
  await::computer "key received, frobbing some more (3/3)…"; {
    sleep 2
  }
}
await::run "frobbing the widget…" -- step
