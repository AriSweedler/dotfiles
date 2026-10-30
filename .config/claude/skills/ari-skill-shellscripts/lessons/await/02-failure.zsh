#!/usr/bin/env zsh
#: The step's exit code is the outcome, and the library never lets it be reported twice. A step
#: that returns 1 ends the line as a red ✗ with the same message, rc='1', and the lesson exits 1.
source "${0:A:h}/_prelude.zsh"
step() {
  sleep 2
  return 1
}
await::run "frobbing the widget…" -- step
