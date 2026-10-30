#!/usr/bin/env zsh
#: A deadline: await::run --timeout 4 shows (n/4s) on the line and, when the step is still running
#: at 4 s, kills it and ends the line as ✗ "timed out". Exit code 124, the same code `timeout` uses.
source "${0:A:h}/_prelude.zsh"
await::run --timeout 4 "waiting for something that never comes…" -- sleep 60
