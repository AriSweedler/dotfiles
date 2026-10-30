#!/usr/bin/env zsh
#: The person's turn. Inside the step, await::user "msg" turns the line magenta, pulses, and
#: rings the bell once; the work of that turn sits in an indented { } group right after it, so
#: whose turn it is reads at a glance. Press any key to give the turn back. Exit code 0.
source "${0:A:h}/_prelude.zsh"
step() {
  await::user "your turn: press any key"; {
    wait_key
  }
}
await::run "waiting on you…" -- step
