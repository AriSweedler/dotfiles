#!/usr/bin/env zsh
#: The default shape: await::run "<message>" -- <step>. The library draws one line (a grey spinner
#: and the message) for as long as the step runs, and ends it from the step's exit code: 0 is a
#: green ✓ and the same message. Nothing real happens; the step only sleeps. Exit code 0.
source "${0:A:h}/_prelude.zsh"
step() {
  sleep 3
}
await::run "frobbing the widget…" -- step
