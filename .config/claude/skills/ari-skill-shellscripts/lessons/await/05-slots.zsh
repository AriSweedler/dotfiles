#!/usr/bin/env zsh
#: Progress through a list: --slots 3 draws [   ], every finished item becomes a ✓, and the
#: current item keeps the braille spinner while the frame by the message shows whose turn it is.
#: Three placeholder items, foo, bar and baz: each needs a moment of work and one key from you.
#: await::progress N says how many are done. Exit code 0.
source "${0:A:h}/_prelude.zsh"
step() {
  local -a items=(foo bar baz)
  local i
  for (( i = 1; i <= 3; i++ )); do
    await::computer "working on ${items[i]}…"; {
      sleep 1
    }
    await::user "press a key for ${items[i]} (${i}/3)"; {
      wait_key
    }
    await::progress "${i}"
  done
}
await::run --slots 3 "foo, bar and baz…" -- step
