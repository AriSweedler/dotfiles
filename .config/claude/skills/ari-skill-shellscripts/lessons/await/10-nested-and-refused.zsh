#!/usr/bin/env zsh
#: Waits nest. The outer step here opens an inner await::run for a sub-widget: the outer line is
#: left frozen where it stands, the inner draws its own line one space further in, ends with its
#: own ✓, and the outer resumes on a fresh line with its clock still running. Then the one
#: refusal: a state call with no wait open prints YOU MUST CALL … INSIDE await::run OR
#: await::_guard and returns 2. Exit code 2.
source "${0:A:h}/_prelude.zsh"
sub() {
  sleep 2
}
step() {
  await::computer "frobbing the widget…"; {
    sleep 1
  }
  await::run "frobbing the sub-widget…" -- sub
  await::computer "sub-widget done, frobbing some more…"; {
    sleep 2
  }
}
await::run "frobbing the widget…" -- step
print -u2
await::user "a state call with no wait open"
exit 2
