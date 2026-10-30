#!/usr/bin/env zsh
#: Ctrl-C is an outcome too. The step here never finishes; press ctrl-c. The library kills the
#: step, ends the line as ✗ "interrupted", and the lesson exits 130, the shell's code for SIGINT.
source "${0:A:h}/_prelude.zsh"
await::run "this never finishes; press ctrl-c" -- sleep 600
