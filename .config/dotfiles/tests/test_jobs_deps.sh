#!/usr/bin/env bash
# Job deps: a plugin's `# deps:` names run before it, their NAME=VALUE stdout becomes its
# environment, the local root wins over the shared one, and a dep that is unknown, fails, or
# prints anything else blocks the plugin with rc 125 and a log line naming it.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new

JOBS_DF="${HOME}/.config/dotfiles/jobs"
DEPS_DF="${HOME}/.config/dotfiles/deps"
DEPS_LDF="${XDG_DATA_HOME}/dotfiles/deps"
STATE="${XDG_STATE_HOME}/dotfiles/jobs"
mkdir -p "${JOBS_DF}" "${DEPS_DF}" "${DEPS_LDF}"

# plugin NAME HEADER-LINE: a plugin that reports its environment and argument.
plugin() {
  printf '#!/usr/bin/env zsh\n%s\nprint -r -- "ran greeting=${GREETING:-unset} from=${DEP_FROM:-unset} arg=${DEP_ARG:-unset} trigger=$1"\n' "$2" > "${JOBS_DF}/$1"
  chmod +x "${JOBS_DF}/$1"
}
# dep ROOT NAME BODY: an executable dep in one root.
dep() {
  printf '#!/usr/bin/env zsh\n%s\n' "$3" > "$1/$2"
  chmod +x "$1/$2"
}

plugin probe '# deps: greet'
dep "${DEPS_LDF}" greet 'print -r -- "GREETING=hello"; print -r -- "DEP_FROM=ldf"; print -r -- "DEP_ARG=$1"; print -u2 -r -- "greet: setup chatter"'
dep "${DEPS_DF}" greet 'print -r -- "GREETING=hello"; print -r -- "DEP_FROM=df"'

nm jobs run probe
assert_eq "probe: rc 0" 0 "${RC}"
assert_contains "probe: the dep ran first, from the local tier" "${OUT}" "# dep greet ok | tier='ldf' vars='3'"
assert_contains "probe: the plugin saw the dep's environment, the dep saw the plugin's name" "${OUT}" "ran greeting=hello from=ldf arg=probe trigger=manual"
assert_contains "probe: the dep's stderr is in the log" "${OUT}" "greet: setup chatter"
assert_eq "probe: rc recorded" 0 "$(cat "${STATE}/probe.rc")"
assert_contains "probe: the log file has the run" "$(cat "${STATE}/probe.log")" "ran greeting=hello"

rm "${DEPS_LDF}/greet"
nm jobs run probe
assert_contains "shared dep is the fallback" "${OUT}" "# dep greet ok | tier='df'"
assert_contains "shared dep's environment reaches the plugin" "${OUT}" "from=df"

plugin plain ''
nm jobs run plain
assert_eq "no deps: rc 0" 0 "${RC}"
assert_contains "no deps: the plugin runs untouched" "${OUT}" "ran greeting=unset"
assert_not_contains "no deps: no dep line" "${OUT}" "# dep"

plugin blocked '# deps: bad'
dep "${DEPS_LDF}" bad 'print -u2 -r -- "bad: boom"; exit 3'
nm jobs run blocked
assert_eq "failing dep: rc 125" 125 "${RC}"
assert_contains "failing dep: the log names it" "${OUT}" "# dep bad: failed | rc='3'"
assert_contains "failing dep: its stderr is in the log" "${OUT}" "bad: boom"
assert_not_contains "failing dep: the plugin did not run" "${OUT}" "ran greeting"
assert_eq "failing dep: rc recorded" 125 "$(cat "${STATE}/blocked.rc")"
assert_file "failing dep: the run is stamped, so the schedule waits for its next moment" "${STATE}/blocked.ran"
assert_contains "failing dep: the engine says blocked" "${ERR}" "job blocked, a dep failed"

plugin chatty '# deps: talker'
dep "${DEPS_LDF}" talker 'print -r -- "GREETING=hi"; print -r -- "not an assignment"'
nm jobs run chatty
assert_eq "chatty dep: rc 125" 125 "${RC}"
assert_contains "chatty dep: the stray line is quoted" "${OUT}" "# dep talker: stdout must be NAME=VALUE lines | got='not an assignment'"
assert_not_contains "chatty dep: the plugin did not run" "${OUT}" "ran greeting"

plugin orphan '# deps: nope'
nm jobs run orphan
assert_eq "unknown dep: rc 125" 125 "${RC}"
assert_contains "unknown dep: named" "${OUT}" "# dep nope: unknown"

plugin two '# deps: greet bad'
nm jobs run two
assert_eq "deps run in order, the first failure stops: rc 125" 125 "${RC}"
assert_contains "deps run in order: greet ran" "${OUT}" "# dep greet ok"
assert_contains "deps run in order: bad blocked" "${OUT}" "# dep bad: failed"

nm jobs list
assert_eq "list: rc 0" 0 "${RC}"
assert_contains "list: the deps block" "${OUT}" "deps ("
assert_contains "list: a dep with its tier" "${OUT}" "df   greet"
assert_contains "list: a wanted dep no root holds" "${OUT}" "(missing)"

report
