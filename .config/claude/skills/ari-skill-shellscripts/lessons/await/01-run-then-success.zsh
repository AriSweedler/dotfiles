#!/usr/bin/env zsh
#: The default shape, and where a step's log lands: await::run "<message>" -- <step>. The library
#: draws one line (a grey spinner and the message) for as long as the step runs, and ends it from
#: the step's exit code: 0 is a green ✓ and the same message. What the step logs to stderr (here
#: one log::info) lands above the line. Nothing real happens; the step only sleeps. Exit code 0.
source "${0:A:h}/_prelude.zsh"
step() {
  sleep 1
  log::info "Halfway there | widget='the widget'"
  sleep 2
}
await::run "frobbing the widget…" -- step
