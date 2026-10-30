#!/usr/bin/env zsh
#: The declarative form. You write a probe that looks at the world and prints where things stand
#: ("user …" or "success …"); await::until calls it on an interval and draws. The probe runs in
#: a subshell, so it reads the world, here a file, never a variable. In ANOTHER pane or
#: terminal, run:   touch /tmp/await-lesson-08    (the line below tells you the same)
source "${0:A:h}/_prelude.zsh"
flag=/tmp/await-lesson-08
rm -f "${flag}"
probe() {
  if [[ -e "${flag}" ]]; then print "success the file appeared"; else print "user run: touch ${flag}"; fi
}
await::until --interval 0.2 --timeout 300 -- probe
rc=$?
rm -f "${flag}"
exit "${rc}"
