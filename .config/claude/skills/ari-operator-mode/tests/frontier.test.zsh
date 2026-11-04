#!/usr/bin/env zsh
# Tests for bin/frontier.zsh, bin/brief.zsh, bin/mode.zsh, bin/pending.zsh and bin/away.zsh against
# tests/fake-run.zsh: the JSON shape of a full read, every cut-off reason, reads that fail after the
# gate, --local, the header, the cut-off paragraph, the away line, the three markers and the example
# capture. No tmux, no network.
# Run: zsh $HOME/.claude/skills/ari-operator-mode/tests/frontier.test.zsh
set -uo pipefail

readonly HERE="${0:A:h}"
readonly SKILL="${HERE:h}"
readonly FRONTIER="${SKILL}/bin/frontier.zsh"
readonly BRIEF="${SKILL}/bin/brief.zsh"
readonly MODE="${SKILL}/bin/mode.zsh"
readonly AWAY="${SKILL}/bin/away.zsh"
readonly FAKE="${HERE}/fake-run.zsh"
readonly EXAMPLE="${SKILL}/templates/frontier.example.json"
readonly T="${TMPDIR:-/tmp}/operator-mode-test-$$"
mkdir -p "${T}/canned" "${T}/repo" "${T}/root"
trap 'rm -rf "${T}"' EXIT
export LOG_COLOR=0 CLAUDE_CODE_SESSION_ID=test-session

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | want='${2}' got='${3}'"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | needle='${2}' in='${3}'"; fi
}
lacks() {   # <name> <needle> <haystack>
  if [[ "${3}" != *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | unwanted='${2}' in='${3}'"; fi
}
q() { jq -r "${2}" "${1}"; }   # <file> <filter>

# A capture; prints the json= path frontier.zsh reported. Arguments: [env assignments…] -- [frontier flags…]
capture() {
  local -a envs
  while [[ "${1}" != -- ]]; do envs+=("${1}"); shift; done; shift
  local out rc=0
  out="$(env "${envs[@]}" zsh "${FRONTIER}" "$@" 2>"${T}/last.err")" || rc=$?
  LAST_RC="${rc}"
  print -r -- "${out}" | awk -F= '/^json=/ { print $2 }'
}
typeset -g LAST_RC=0

# canned tracker and checkout answers
cat > "${T}/canned/ready.json" <<'J'
[{"id":"beads-abc","title":"Fix the widget","priority":1,"issue_type":"task","parent":"beads-epic","assignee":null,"updated_at":"2026-10-30T01:00:00Z"},
 {"id":"beads-def","title":"Polish the frob","priority":2,"issue_type":"feature","parent":null,"assignee":null,"updated_at":"2026-10-30T00:00:00Z"}]
J
cat > "${T}/canned/in_progress.json" <<'J'
[{"id":"beads-ip1","title":"Half done","priority":2,"issue_type":"task","assignee":"claude","updated_at":"2026-10-29T00:00:00Z"}]
J
print -r -- $'beads-h1  Which indexers?\n' > "${T}/canned/human.txt"
print -r -- $'beads-bl1  Needs the PR\n  blocked by: beads-abc\nbeads-bl2  Needs the other PR\n  blocked by: beads-abc, beads-def\n' > "${T}/canned/blocked.txt"
print -r -- $'beads-ip1  Half done  (1d)\n' > "${T}/canned/stale.txt"
print -r -- '[{"id":"beads-d1"},{"id":"beads-d2"}]' > "${T}/canned/deferred.json"
print -r -- $' M bin/lab\nabc1234 first subject\nbcd2345 second subject\ncde3456 third subject' > "${T}/canned/hostgit.txt"
( cd "${T}/repo" && git init -q && git -c core.hooksPath=/dev/null -c user.email=t@example.invalid -c user.name=t commit -q --allow-empty -m "local subject" && print x > dirty.txt )
export FAKE_DIR="${T}/canned"
common=(--host-definition laptop --target %18 --beads '~/beads' --repo '~/homelab' --local-repo "${T}/repo" --health 'bin/doctor.sh' --run-zsh "${FAKE}" --root "${T}/root")

# 1. a full read
full="$(capture -- "${common[@]}")"
check "full read exits 0" 0 "${LAST_RC}"
check "full read wrote into the investigation root" "${T}/root/operator-mode/" "${full%/*/frontier.json}/"
check "full read is JSON" true "$(jq -e . "${full}" >/dev/null 2>&1 && print true || print false)"
check "full read: cut_off is null" null "$(q "${full}" '.cut_off')"
check "full read: pane label" "machine=personal|ID=%18|pane=3.1" "$(q "${full}" '.pane')"
check "full read: nickname from the window name" homelab "$(q "${full}" '.nickname')"
check "full read: where the state lives is recorded" "~/beads ~/homelab ${T}/repo" "$(q "${full}" '"\(.beads_dir) \(.repo) \(.local_repo)"')"
check "full read: seven commands typed, in order" 7 "$(q "${full}" '.typed | length')"
check "full read: nine sections in order" "ready,in_progress,human,blocked,stale,deferred,host_git,local_git,health" "$(q "${full}" '[keys_unsorted[] | select(. as $k | ["captured_at","session","host_definition","pane","nickname","beads_dir","repo","local_repo","pending","pending_seen","away","away_ended","typed","waited_s","cut_off"] | index($k) | not)] | join(",")')"
check "ready: first id" beads-abc "$(q "${full}" '.ready[0].id')"
check "ready: type from issue_type" task "$(q "${full}" '.ready[0].type')"
check "in_progress: holder" claude "$(q "${full}" '.in_progress[0].assignee')"
check "human: id parsed" beads-h1 "$(q "${full}" '.human.ids[0]')"
check "blocked: ids parsed" "beads-bl1,beads-bl2" "$(q "${full}" '.blocked.ids | join(",")')"
check "blocked: blockers counted" "2 1" "$(q "${full}" '"\(.blocked.blockers["beads-abc"]) \(.blocked.blockers["beads-def"])"')"
check "stale: id parsed" beads-ip1 "$(q "${full}" '.stale.ids[0]')"
check "deferred: a count only" 2 "$(q "${full}" '.deferred.count')"
check "host_git: three commits, first hash" "3 abc1234" "$(q "${full}" '"\(.host_git.log | length) \(.host_git.log[0].hash)"')"
check "host_git: dirty path" " M bin/lab" "$(q "${full}" '.host_git.dirty[0]')"
check "local_git: one commit" "local subject" "$(q "${full}" '.local_git.log[0].subject')"
check "local_git: dirty file" "?? dirty.txt" "$(q "${full}" '.local_git.dirty[0]')"
check "health: recorded, not run" "bin/doctor.sh false" "$(q "${full}" '"\(.health.command) \(.health.ran)"')"
typed_log="$(<"${T}/canned/typed.log")"
contains "reads use bd -C, never cd" 'bd -C ~/"beads" ready' "${typed_log}"
lacks "reads never cd" "cd " "${typed_log}"
contains "typed lines lead with a space for HIST_IGNORE_SPACE" $'\n M=$(' "${typed_log}"
contains "the marker is built at run time" "tr Q @" "${typed_log}"
check "the typed reads never contain the marker itself" 0 "$(grep -c '@@' "${T}/canned/typed.log" || true)"
contains "the stream carries the host command's rc" "__RC=" "${typed_log}"

# 1a. bd 1.3.1's blocked shape: a priority tag before the id, the blockers bracketed on the next line
mkdir -p "${T}/canned131"
cp "${T}"/canned/{ready.json,in_progress.json,human.txt,stale.txt,deferred.json,hostgit.txt} "${T}/canned131/"
print -r -- $'\n🚫 Blocked issues (2):\n\n[P1] beads-bl1: Needs the PR\n  Blocked by 1 open dependencies: [beads-abc]\n\n[P2] beads-bl2: Needs the other PR\n  Blocked by 2 open dependencies: [beads-abc, beads-def]\n' > "${T}/canned131/blocked.txt"
file="$(capture "FAKE_DIR=${T}/canned131" -- "${common[@]}")"
check "blocked (bd 1.3.1 shape): ids parsed past the priority tag" "beads-bl1,beads-bl2" "$(q "${file}" '.blocked.ids | join(",")')"
check "blocked (bd 1.3.1 shape): blockers counted from the bracketed list" "2 1" "$(q "${file}" '"\(.blocked.blockers["beads-abc"]) \(.blocked.blockers["beads-def"])"')"
check "blocked (bd 1.3.1 shape): the summary line is not an id" false "$(q "${file}" '.blocked.ids | index("issues") != null')"
contains "blocked (bd 1.3.1 shape): the header counts them" ", blocked 2," "$(zsh "${BRIEF}" --json "${file}" --header)"
# 1c. bd's text shapes that must not mislead: a hyphenated word, a count that disagrees, a deferred human bead
mkdir -p "${T}/cannedtxt"
cp "${T}"/canned/{ready.json,in_progress.json,stale.txt,deferred.json,hostgit.txt} "${T}/cannedtxt/"
print -r -- $'\nHuman-needed beads (3 found)\n\n  beads-h1 Which indexers?\n    re-run the doctor after\n    Priority: P2\n\n  beads-h2 Decide: e-mail or push\n    Status: deferred\n    Priority: P2\n\n  beads-h3 Decide: the look\n    Priority: P3' > "${T}/cannedtxt/human.txt"
print -r -- $'\n🚫 Blocked issues (3):\n\n[P1] beads-bl1: Needs the PR, blocked by nothing else\n  Blocked by 1 open dependencies: [beads-abc]\n\n[P2] beads-bl2: Needs the other PR\n  Blocked by 1 open dependencies: [beads-def]\n' > "${T}/cannedtxt/blocked.txt"
file="$(capture "FAKE_DIR=${T}/cannedtxt" -- "${common[@]}")"
check "human: a hyphenated word on a continuation line is not an id" "beads-h1,beads-h3" "$(q "${file}" '.human.ids | join(",")')"
check "human: a deferred bead is listed apart, never a row" "beads-h2" "$(q "${file}" '.human.deferred_ids | join(",")')"
contains "human: the header counts the ones that wait on him" ", human 2," "$(zsh "${BRIEF}" --json "${file}" --header)"
contains "blocked: a count that disagrees with the ids parsed is an error, not a quiet miss" "parsed 2 ids of 3 listed" "$(q "${file}" '.blocked.error')"
contains "blocked: the header says failed for it" ", blocked failed," "$(zsh "${BRIEF}" --json "${file}" --header)"
check "blocked: a title that mentions blocked by is not a blocker line" null "$(q "${file}" '.blocked.blockers')"
file="$(capture "FAKE_DIR=${T}/cannedtxt" -- "${common[@]}" --prefix hl)"
contains "--prefix pins the id shape: no beads-* token is an id, so the count check fires" "parsed 0 ids of 3 listed" "$(q "${file}" '.human.error')"
check "--prefix must be letters" 1 "$(zsh "${FRONTIER}" "${common[@]}" --prefix 'beads-1' >/dev/null 2>&1; print $?)"

# 1b. the typed line, run for real against a fake bd, decodes to the canned output with its rc
mkdir -p "${T}/fakebin" "${T}/beads"
cat > "${T}/fakebin/bd" <<'B'
#!/usr/bin/env zsh
[[ "${1}" == -C ]] && shift 2
case "$*" in
  "ready --exclude-label human --json") cat "${FAKE_DIR}/ready.json" ;;
  "list -s in_progress --json") cat "${FAKE_DIR}/in_progress.json" ;;
  "human list") cat "${FAKE_DIR}/human.txt" ;;
  "blocked") cat "${FAKE_DIR}/blocked.txt" ;;
  "stale -d 14 -s in_progress") cat "${FAKE_DIR}/stale.txt" ;;
  "list -s deferred --json") cat "${FAKE_DIR}/deferred.json" ;;
  "exit7") exit 7 ;;
  *) print -u2 "fake bd: unknown $*"; exit 2 ;;
esac
B
chmod +x "${T}/fakebin/bd"
first_typed="$(awk 'NR == 1' "${T}/canned/typed.log")"
real_stream="$(PATH="${T}/fakebin:${PATH}" HOME="${T}" zsh -c "${first_typed}" 2>&1)"
nonce="${first_typed#*printf \'Q%sQ\' }"; nonce="${nonce%% *}"; marker="@${nonce}@"
payload="$(print -r -- "${real_stream}" | awk -v m="${marker}" -v l=$(( ${#nonce} + 2 )) '$0 == m "BEGIN" { on=1; next } index($0, m "END ") == 1 { on=0 } on && index($0, m) == 1 { printf "%s", substr($0, l + 1) }')"
check "typed line, run for real: END carries the payload length" "${marker}END ${#payload}" "$(print -r -- "${real_stream}" | awk -v m="${marker}" 'index($0, m "END ") == 1 { print }')"
check "typed line, run for real: the marker carries a nonce, never bare @@" 0 "$(print -r -- "${real_stream}" | grep -c '^@@' || true)"
decoded="$(print -r -- "${payload}" | base64 -d | gunzip -c)"
contains "typed line, run for real: the output is inside" '"id":"beads-abc"' "${decoded}"
contains "typed line, run for real: the rc is inside" $'\n__RC=0' "${decoded}"

# 2. the cut-off reasons from run.zsh's exit codes
run_cut() {   # <name> <expected reason> [env assignments…]
  local name="${1}" want="${2}"; shift 2
  local file
  file="$(capture "$@" -- "${common[@]}")"
  check "${name}: exit 0" 0 "${LAST_RC}"
  check "${name}: reason" "${want}" "$(q "${file}" '.cut_off.reason')"
  check "${name}: seven host sections unread" 7 "$(q "${file}" '.cut_off.unread | length')"
  check "${name}: ready marked unread" true "$(q "${file}" '.ready.unread')"
  check "${name}: local_git still read" "local subject" "$(q "${file}" '.local_git.log[0].subject')"
  CUT_FILE="${file}"
}
typeset -g CUT_FILE=''
run_cut not_opted_in not_opted_in FAKE_RC=77 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 not opted in; Ari runs 'ari-driving on' in that pane"
run_cut other_session other_session FAKE_RC=76 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 bound to another Claude session d60c; get a pane of your own"
readonly GATE_TEXT='last line does not end in the prompt (busy, or text already on the line)'
run_cut holds_text holds_text FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ cd ~/homelab && bin/lab up apps/torrent"
check "holds_text: the prompt's line, verbatim" 'at 01:00:00 UTC ❯ cd ~/homelab && bin/lab up apps/torrent' "$(q "${CUT_FILE}" '.cut_off.prompt_holds')"
run_cut busy busy FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running nvim, not a shell" "FAKE_TAIL=at 01:00:00 UTC ❯ nvim notes.md"
check "busy: what runs there, with the command" "running nvim, not a shell (nvim notes.md)" "$(q "${CUT_FILE}" '.cut_off.prompt_holds')"
run_cut copy_mode busy FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 in copy mode (press q there)"
check "copy mode: his to clear" "in copy mode (press q there)" "$(q "${CUT_FILE}" '.cut_off.prompt_holds')"
run_cut read_timed_out read_timed_out FAKE_RC=124 "FAKE_REFUSED=" "FAKE_TAIL=at 01:00:00 UTC ❯ M=…still running"
run_cut host_unreachable host_unreachable FAKE_RC=255 "FAKE_REFUSED="
run_cut refused_text refused_text FAKE_RC=1 "FAKE_REFUSED="
file="$(capture FAKE_LIST_RC=255 -- "${common[@]}")"
check "list fails: host_unreachable" host_unreachable "$(q "${file}" '.cut_off.reason')"
contains "list fails: the ssh error is kept" "No route to host" "$(q "${file}" '.cut_off.prompt_holds')"
file="$(capture FAKE_LIST_RC=1 -- "${common[@]}")"
check "list fails with 1: bad_definition, not the host" bad_definition "$(q "${file}" '.cut_off.reason')"
contains "bad_definition: mine to fix, not his" "mine to fix, not yours" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
lacks "bad_definition: never his to clear" "yours to clear" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
file="$(capture -- "${common[@]}" --target %99)"
check "no_pane: reason" no_pane "$(q "${file}" '.cut_off.reason')"
check "no_pane: the label tried" '%99' "$(q "${file}" '.cut_off.pane')"
check "no_pane: the panes that exist are listed" 3 "$(q "${file}" '.cut_off.candidates | length')"
file="$(capture -- "${common[@]}" --target 1.1)"
check "exact match: 1.1 does not match pane 11.1" "machine=personal|ID=%3|pane=1.1" "$(q "${file}" '.pane')"
check "exact match: W.P form finds the pane" null "$(q "${file}" '.cut_off')"
file="$(capture "FAKE_LIST=machine=personal|ID=%18|pane=3.1 ✦ bound=none zsh 0: homelab -- laptop
machine=other|ID=%18|pane=4.1 ✦ bound=none zsh 0: lab -- desk" -- "${common[@]}")"
check "ambiguous_pane: two machines with the same id" ambiguous_pane "$(q "${file}" '.cut_off.reason')"
check "ambiguous_pane: both labels offered" "machine=personal|ID=%18|pane=3.1,machine=other|ID=%18|pane=4.1" "$(q "${file}" '.cut_off.candidates | join(",")')"
file="$(capture -- "${common[@]}" --target 'machine=personal|ID=%18|pane=3.1')"
check "exact match: the full label finds the pane" "machine=personal|ID=%18|pane=3.1" "$(q "${file}" '.pane')"
file="$(capture "FAKE_PROMPT_LINE=at 01:00:02 UTC ❯   " -- "${common[@]}")"
check "a trailing space after the prompt is not a cut-off" null "$(q "${file}" '.cut_off')"

# 3. a read refused after the gate passed is a cut-off from that section on
file="$(capture "FAKE_RC_FOR=human list:75" "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running nvim, not a shell" "FAKE_TAIL=at 01:00:00 UTC ❯ nvim notes.md" -- "${common[@]}")"
check "mid-run refusal: cut off" busy "$(q "${file}" '.cut_off.reason')"
check "mid-run refusal: the sections before it were read" beads-abc "$(q "${file}" '.ready[0].id')"
check "mid-run refusal: the rest are unread" "human,blocked,stale,deferred,host_git" "$(q "${file}" '.cut_off.unread | join(",")')"
check "mid-run refusal: human marked unread" true "$(q "${file}" '.human.unread')"
file="$(capture "FAKE_RC_FOR=blocked:124" -- "${common[@]}")"
check "mid-run timeout: read_timed_out" read_timed_out "$(q "${file}" '.cut_off.reason')"
check "mid-run timeout: ready and human were read" "beads-abc beads-h1" "$(q "${file}" '"\(.ready[0].id) \(.human.ids[0])"')"

# 3b. a 75 is classified by the pane tail: this session's own command waits, his row is his, the rest is a cut-off
own_tail=$'at 01:00:00 UTC ❯  M=$(printf \'Q%sQ\' 4242 | tr Q @); printf \'%sBEGIN\\n\' "$M"; { bd -C ~/"beads" blocked; }\n@4242@BEGIN'
lane_tail="at 01:00:00 UTC ❯ run_log 'BEADS_ACTOR=claude bd -C ~/beads update beads-g5l --claim'"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 FAKE_RC_TIMES=2 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 another caller is typing into it" FRONTIER_RETRY_S=1 -- "${common[@]}")"
check "own command clears: no cut-off" null "$(q "${file}" '.cut_off')"
check "own command clears: the read landed after the retries" beads-abc "$(q "${file}" '.ready[0].id')"
check "own command clears: two refusals were waited through" 2 "$(<"${T}/canned/refusals.count")"
check "own command clears: the wait is recorded" 2 "$(q "${file}" '.waited_s')"
contains "own command clears: one waiting line was logged" "waiting for the pane" "$(<"${T}/last.err")"
check "own command clears: the waiting line is logged once" 1 "$(grep -c 'waiting for the pane' "${T}/last.err")"
check "own command clears: the command is typed once in the record" 7 "$(q "${file}" '.typed | length')"
contains "own command clears: the header says how long it waited" "; waited 2s for machine=personal|ID=%18|pane=3.1;" "$(zsh "${BRIEF}" --json "${file}" --header)"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 FAKE_RC_TIMES=1 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running bd, not a shell" "FAKE_TAIL=${own_tail}" FRONTIER_RETRY_S=1 -- "${common[@]}")"
check "own read running (the marker recipe on the prompt line): waited through" null "$(q "${file}" '.cut_off')"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 FAKE_RC_TIMES=1 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running bd, not a shell" "FAKE_TAIL=${lane_tail}" FRONTIER_RETRY_S=1 -- "${common[@]}")"
check "a lane's bd write running: waited through" null "$(q "${file}" '.cut_off')"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 FAKE_RC_TIMES=1 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=${lane_tail}"$'\nsome output still scrolling' FRONTIER_RETRY_S=1 -- "${common[@]}")"
check "a lane between commands, output still scrolling: waited through, not holds_text" null "$(q "${file}" '.cut_off')"
fork_tail="at 01:00:00 UTC ❯ run_log '( . ~/homelab/.env; curl -s http://127.0.0.1:8096/Items -H \"\$A\" | jq .TotalRecordCount )'"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 FAKE_RC_TIMES=1 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running curl, not a shell" "FAKE_TAIL=${fork_tail}" FRONTIER_RETRY_S=1 -- "${common[@]}")"
check "a fork's run_log-wrapped command running (not bd, not git): waited through, not busy" null "$(q "${file}" '.cut_off')"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 FAKE_RC_TIMES=1 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running curl, not a shell" "FAKE_TAIL=at 01:00:00 UTC ❯ curl -s http://127.0.0.1:8096/Items" FRONTIER_RETRY_S=1 -- "${common[@]}")"
check "the same command typed bare is Ari's: busy" busy "$(q "${file}" '.cut_off.reason')"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 FAKE_RC_TIMES=1 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running git, not a shell" "FAKE_TAIL=at 01:00:00 UTC ❯ git -C ~/homelab rebase -i main" FRONTIER_RETRY_S=1 -- "${common[@]}")"
check "a bare git command is Ari's, not an agent's: busy" busy "$(q "${file}" '.cut_off.reason')"
rm -f "${T}/canned/refusals.count"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 another caller is typing into it" FRONTIER_RETRY_S=1 -- "${common[@]}" --timeout 5 --previous /dev/null)"
check "own command never clears: own_command" own_command "$(q "${file}" '.cut_off.reason')"
check "own command never clears: exit 0" 0 "${LAST_RC}"
check "own command never clears: the sections are unread" 7 "$(q "${file}" '.cut_off.unread | length')"
check "own command never clears: what held the pane" "another caller is typing into it" "$(q "${file}" '.cut_off.prompt_holds')"
check "own command never clears: the whole budget was spent, not one read's" 1 "$(( $(q "${file}" '.waited_s') >= 30 ))"
own_text="$(zsh "${BRIEF}" --json "${file}" --cut-off)"; rc=$?
check "own command: brief prints the waiting line, exit 3" 3 "${rc}"
check "own command: the waiting line names the pane, what holds it, and asks" 'Waiting on `machine=personal|ID=%18|pane=3.1|nickname=homelab`, busy with `another caller is typing into it`; an agent'"'"'s command, nothing of yours to clear. Read again?' "${own_text}"
check "own command: what held the pane is kept for the next capture" "another caller is typing into it" "$(q "${file}" '.cut_off.busy_cmd')"
lacks "own command: never called his P0" "P0" "${own_text}"
check "own command: the header is the same line" "${own_text}" "$(zsh "${BRIEF}" --json "${file}" --header)"
prev_own="${file}"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 another caller is typing into it" FRONTIER_RETRY_S=1 -- "${common[@]}" --timeout 5)"
check "the newest capture by this session on this pane is the default --previous: the same busy pane is own_command_persists, never his" own_command_persists "$(q "${file}" '.cut_off.reason')"
contains "the persisting wait says since when" "since 20" "$(q "${file}" '.cut_off.prompt_holds')"
check "the persisting wait waits for nothing" 0 "$(q "${file}" '.waited_s')"
persist_text="$(zsh "${BRIEF}" --json "${file}" --cut-off)"; rc=$?
check "persisting wait: brief prints a waiting line, exit 3" 3 "${rc}"
contains "persisting wait: still an agent's, nothing of his" "Still waiting on \`machine=personal|ID=%18|pane=3.1|nickname=homelab\`" "${persist_text}"
lacks "persisting wait: never his P0" "P0" "${persist_text}"
check "persisting wait: one question mark" 1 "$(print -rn -- "${persist_text}" | tr -cd '?' | wc -c | tr -d ' ')"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 another caller is typing into it" FRONTIER_RETRY_S=1 -- "${common[@]}" --timeout 5 --previous "${prev_own}")"
check "--previous names the capture to compare with" own_command_persists "$(q "${file}" '.cut_off.reason')"
file="$(capture CLAUDE_CODE_SESSION_ID=other-session FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 another caller is typing into it" FRONTIER_RETRY_S=1 -- "${common[@]}" --timeout 5)"
check "another session's capture is never the default --previous: this one waits its own budget" own_command "$(q "${file}" '.cut_off.reason')"
row="run_log 'cd ~/homelab && git pull -q --ff-only && bin/doctor.sh --fix --only torrent-logs'"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ ${row}" -- "${common[@]}" --pending "${row}")"
check "his row un-entered on the prompt: row_pending" row_pending "$(q "${file}" '.cut_off.reason')"
check "his row un-entered: the pending text is recorded" "${row}" "$(q "${file}" '.pending')"
check "his row un-entered: no waiting" 0 "$(q "${file}" '.waited_s')"
check "his row un-entered: the line" 'Your row is on your prompt in `machine=personal|ID=%18|pane=3.1|nickname=homelab`, not entered: press Enter there, or clear it, then tell me?' "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ ${row}" -- "${common[@]}")"
check "the same line without --pending is holds_text" holds_text "$(q "${file}" '.cut_off.reason')"
# 3c. his row wrapped by tmux over three tail lines at a pane width of 70: two full-width lines, then the rest
long_row="run_log 'cd ~/homelab && git pull -q --ff-only && bin/doctor.sh --fix --only torrent-logs,torrent-queue,media && bin/lab up apps/torrent'"
wrap_head="at 01:00:00 UTC ❯ ${long_row[1,52]}"
wrap_mid="${long_row[53,122]}"
wrap_tail_rest="${long_row[123,-1]}"
check "wrapped fixture: the first two lines are the pane width" "70 70" "${#wrap_head} ${#wrap_mid}"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=${wrap_head}"$'\n'"${wrap_mid}"$'\n'"${wrap_tail_rest}" -- "${common[@]}" --pending "${long_row}")"
check "his row wrapped over three lines: still row_pending" row_pending "$(q "${file}" '.cut_off.reason')"
check "his row wrapped: the joined line is recorded" "${wrap_head}${wrap_mid}${wrap_tail_rest}" "$(q "${file}" '.cut_off.prompt_holds')"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=${wrap_head}"$'\n'"${wrap_mid}"$'\n'"${wrap_tail_rest}" -- "${common[@]}")"
check "a wrapped un-entered agent line without --pending: holds_text, not a wait" holds_text "$(q "${file}" '.cut_off.reason')"
check "a wrapped un-entered line waits for nothing" 0 "$(q "${file}" '.waited_s')"
# 3d. the pending row lives on disk: pending.zsh set is frontier.zsh's default --pending
check "pending: nothing recorded, exit 3" 3 "$(zsh "${SKILL}/bin/pending.zsh" show --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
check "pending: set records the text" "pending=${row}" "$(zsh "${SKILL}/bin/pending.zsh" set --text "${row}" --session test-session --root "${T}/root" 2>/dev/null)"
check "pending: the TYPED: prefix is refused" 1 "$(zsh "${SKILL}/bin/pending.zsh" set --text "TYPED: ${row}" --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ ${row}" -- "${common[@]}")"
check "pending from the marker: his row on the prompt is row_pending without --pending" row_pending "$(q "${file}" '.cut_off.reason')"
check "pending from the marker: recorded in the capture" "${row}" "$(q "${file}" '.pending')"
file="$(capture CLAUDE_CODE_SESSION_ID=other-session FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ ${row}" -- "${common[@]}")"
check "pending from the marker: another session's marker is not read" holds_text "$(q "${file}" '.cut_off.reason')"
check "pending: clear" "pending=" "$(zsh "${SKILL}/bin/pending.zsh" clear --session test-session --root "${T}/root" 2>/dev/null)"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ ${row}" -- "${common[@]}")"
check "pending cleared: the same line is holds_text again" holds_text "$(q "${file}" '.cut_off.reason')"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running grep, not a shell" "FAKE_TAIL=at 01:00:00 UTC ❯ grep -c closed ${row}" -- "${common[@]}" --pending "${row}")"
check "pending: a bare command of his that contains the row is not his row" busy "$(q "${file}" '.cut_off.reason')"
file="$(capture -- "${common[@]}" --pending "${row}")"
check "pending: the reads went through, so the row is gone: pending_seen false" false "$(q "${file}" '.pending_seen')"
check "no pending: pending_seen null" null "$(q "${full}" '.pending_seen')"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 running doctor.sh, not a shell" "FAKE_TAIL=at 01:00:00 UTC ❯ ${row}"$'\nPASS torrent' -- "${common[@]}" --pending "${row}")"
check "his row running: row_running" row_running "$(q "${file}" '.cut_off.reason')"
check "his row running: pending_seen true" true "$(q "${file}" '.pending_seen')"
contains "his row running: the line names his command" 'Your row is running in `machine=personal|ID=%18|pane=3.1|nickname=homelab` (`run_log' "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
check "his row running: one question mark" 1 "$(zsh "${BRIEF}" --json "${file}" --cut-off | tr -cd '?' | wc -c | tr -d ' ')"
check "FRONTIER_RETRY_S must be a positive integer" 1 "$(FRONTIER_RETRY_S=0 zsh "${FRONTIER}" "${common[@]}" >/dev/null 2>&1; print $?)"
check "--previous must be readable" 1 "$(zsh "${FRONTIER}" "${common[@]}" --previous "${T}/nowhere.json" >/dev/null 2>&1; print $?)"
a="$(capture -- "${common[@]}")"; b="$(capture -- "${common[@]}")"
check "two captures never share a folder" 1 "$([[ "${a}" != "${b}" ]] && print 1 || print 0)"

# 4. the host command's own failure is an error, never a clean section
file="$(capture "FAKE_HOST_RC=git -C:128" -- "${common[@]}")"
check "host rc: cut_off stays null" null "$(q "${file}" '.cut_off')"
contains "host rc: git failure is an error, not an empty clean checkout" "git failed (rc 128)" "$(q "${file}" '.host_git.error')"
contains "header: a failed host checkout says so, never this Mac's head in its place" "; laptop checkout failed; read " "$(zsh "${BRIEF}" --json "${file}" --header)"
file="$(capture "FAKE_HOST_RC=deferred:127" -- "${common[@]}")"
contains "host rc: a failed deferred read is an error, not a count" "command failed (rc 127)" "$(q "${file}" '.deferred.error')"
check "host rc: deferred has no count" null "$(q "${file}" '.deferred.count')"
file="$(capture "FAKE_HOST_RC=ready:127" -- "${common[@]}")"
check "bd missing on the host (rc 127 on ready): the other bd reads are not typed" 2 "$(q "${file}" '.typed | length')"
check "bd missing: every bd section carries the one precondition" true "$(q "${file}" '[.ready, .in_progress, .human, .blocked, .stale, .deferred] | all(.precondition == true)')"
contains "bd missing: the error names the cause" "bd is not on the host" "$(q "${file}" '.human.error')"
check "bd missing: host_git is still read" abc1234 "$(q "${file}" '.host_git.log[0].hash')"
file="$(capture "FAKE_HOST_RC=human list:1" -- "${common[@]}")"
contains "host rc: a failed text read is an error" "rc 1" "$(q "${file}" '.human.error')"
check "host rc: the other sections still fill" beads-abc "$(q "${file}" '.ready[0].id')"

# 5. empty, truncated and unfinished reads
file="$(capture "FAKE_EMPTY=ready" -- "${common[@]}")"
check "empty bd output lands as []" "[]" "$(q "${file}" '.ready | tojson')"
check "empty bd output: the capture still landed" 0 "${LAST_RC}"
file="$(capture "FAKE_EMPTY=deferred" -- "${common[@]}")"
check "empty deferred is a count of 0" 0 "$(q "${file}" '.deferred.count')"
file="$(capture "FAKE_TRUNCATE=in_progress" -- "${common[@]}")"
contains "an unfinished read says so, with the timeout" "read did not finish in 45s" "$(q "${file}" '.in_progress.error')"
check "an unfinished read is not a cut-off" null "$(q "${file}" '.cut_off')"
file="$(capture "FAKE_SHORT=ready" -- "${common[@]}")"
contains "a truncated capture is caught by the byte count" "truncated capture" "$(q "${file}" '.ready.error')"

# 6. stderr noise never clobbers the captured stdout
file="$(capture FAKE_STDERR_NOISE=40 -- "${common[@]}")"
check "noisy stderr: every section read" "beads-abc beads-ip1 beads-h1 2 abc1234" "$(q "${file}" '"\(.ready[0].id) \(.in_progress[0].id) \(.human.ids[0]) \(.deferred.count) \(.host_git.log[0].hash)"')"

# 7. --local with a fake bd on PATH
file="$(PATH="${T}/fakebin:${PATH}" capture -- --local --beads "${T}/beads" --repo "${T}/repo" --local-repo "${T}/repo" --root "${T}/root")"
check "local: exit 0" 0 "${LAST_RC}"
check "local: pane is local, no nickname" "local null" "$(q "${file}" '"\(.pane) \(.nickname)"')"
check "local: ready read through bd -C" beads-abc "$(q "${file}" '.ready[0].id')"
check "local: stale read" beads-ip1 "$(q "${file}" '.stale.ids[0]')"
check "local: host_git from --repo" "local subject" "$(q "${file}" '.host_git.log[0].subject')"
check "local: health null when not given" "null false" "$(q "${file}" '"\(.health.command) \(.health.ran)"')"
check "local: no session needed" 0 "$(env -u CLAUDE_CODE_SESSION_ID PATH="${T}/fakebin:${PATH}" zsh "${FRONTIER}" --local --beads "${T}/beads" --local-repo "${T}/repo" --root "${T}/root" >/dev/null 2>&1; print $?)"
file="$(capture -- "${common[@]}" --local-repo "${T}/nowhere")"
contains "local_git on a non-repo is an error" "git failed" "$(q "${file}" '.local_git.error')"

# 8. the preconditions
check "host mode needs both flags" 1 "$(zsh "${FRONTIER}" --target %18 --run-zsh "${FAKE}" --root "${T}/root" >/dev/null 2>&1; print $?)"
check "host mode needs the session id" 1 "$(env -u CLAUDE_CODE_SESSION_ID zsh "${FRONTIER}" "${common[@]}" >/dev/null 2>&1; print $?)"
contains "host mode names the missing session id" "CLAUDE_CODE_SESSION_ID is unset" "$(env -u CLAUDE_CODE_SESSION_ID zsh "${FRONTIER}" "${common[@]}" 2>&1 >/dev/null)"
check "a timeout under 5 is refused" 1 "$(zsh "${FRONTIER}" "${common[@]}" --timeout 2 >/dev/null 2>&1; print $?)"

# 9. brief.zsh: the header
dir_full="${full%/frontier.json}"
hdr="$(zsh "${BRIEF}" --dir "${dir_full}" --header)"
contains "header: counts" "Ready 2, in progress 1, human 1, blocked 2, stale 1" "${hdr}"
contains "header: the host checkout, labelled and dirty" "laptop abc1234 dirty 1" "${hdr}"
contains "header: the capture time" "; read " "${hdr}"
contains "header: the phase" "; fresh read" "${hdr}"
contains "header: a given phase" "; after row 1" "$(zsh "${BRIEF}" --dir "${dir_full}" --header --phase 'after row 1')"
mkdir -p "${T}/cannedts"
cp "${T}"/canned/{ready.json,human.txt,blocked.txt,deferred.json,hostgit.txt} "${T}/cannedts/"
print -r -- '[{"id":"beads-ip1","title":"Half done","priority":2,"issue_type":"task","assignee":"claude","updated_at":"2026-10-29T00:00:00.123456789-07:00"}]' > "${T}/cannedts/in_progress.json"
print -r -- '' > "${T}/cannedts/stale.txt"
file="$(capture "FAKE_DIR=${T}/cannedts" -- "${common[@]}")"
contains "header: stale is the stale section's count, not a date heuristic; an offset timestamp never crashes it" ", stale 0;" "$(zsh "${BRIEF}" --json "${file}" --header)"
holds_file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ cd ~/homelab && bin/lab up apps/torrent" -- "${common[@]}")"
contains "header: cut off" "Cut off: machine=personal|ID=%18|pane=3.1|nickname=homelab (holds_text); tracker unread" "$(zsh "${BRIEF}" --json "${holds_file}" --header)"
file="$(capture "FAKE_HOST_RC=ready:1" -- "${common[@]}")"
contains "header: an errored section reads failed, not ?" "Ready failed, in progress 1" "$(zsh "${BRIEF}" --json "${file}" --header)"
file="$(capture -- --host-definition laptop --target %18 --beads '~/beads' --local-repo "${T}/repo" --run-zsh "${FAKE}" --root "${T}/root")"
check "header: skipped host_git falls through to this Mac" "this Mac" "$(zsh "${BRIEF}" --json "${file}" --header | awk -F'; ' '{ print $2 }' | awk '{ print $1, $2 }')"
check "header: host_git skipped is recorded" "no --repo" "$(q "${file}" '.host_git.skipped')"
lacks "header: never the doubled word" "checkout checkout" "$(zsh "${BRIEF}" --json "${file}" --header)"
print -r -- '{"ready": []}' > "${T}/foreign.json"
check "brief: a foreign JSON is refused" 1 "$(zsh "${BRIEF}" --json "${T}/foreign.json" --header >/dev/null 2>&1; print $?)"
check "brief: a mode is required" 1 "$(zsh "${BRIEF}" --dir "${dir_full}" >/dev/null 2>&1; print $?)"

# 10. brief.zsh: the cut-off paragraph
out_text="$(zsh "${BRIEF}" --dir "${dir_full}" --cut-off)"; rc=$?
check "cut-off on a full read: exit 0, prints nothing" "0 " "${rc} ${out_text}"
out_text="$(zsh "${BRIEF}" --json "${holds_file}" --cut-off)"; rc=$?
check "cut-off paragraph: exit 3" 3 "${rc}"
contains "cut-off paragraph: the pane label" 'machine=personal|ID=%18|pane=3.1' "${out_text}"
contains "cut-off paragraph: the reason and the move" "holds un-entered text on its prompt; clear it or run it, then tell me" "${out_text}"
contains "cut-off paragraph: the prompt text verbatim" 'cd ~/homelab && bin/lab up apps/torrent' "${out_text}"
contains "cut-off paragraph: the unread sections" "ready, in_progress, human, blocked, stale, deferred, host_git" "${out_text}"
contains "cut-off paragraph: the P0 sentence" "This is yours to clear; I do nothing else until it is." "${out_text}"
contains "cut-off paragraph: the alternatives, as statements" 'Name another pane by its `ID=%N`, or say `stop operator mode`. Tell me when it is clear, or name another pane?' "${out_text}"
check "cut-off paragraph: one paragraph, one question mark" "1 1" "$(print -r -- "${out_text}" | awk 'NF' | wc -l | tr -d ' ') $(print -rn -- "${out_text}" | tr -cd '?' | wc -c | tr -d ' ')"
check "cut-off paragraph: P0 said once" 1 "$(print -rn -- "${out_text}" | awk '{ n += gsub(/P0/, "") } END { print n + 0 }')"
file="$(capture -- "${common[@]}" --target %99)"
contains "cut-off paragraph: no_pane lists the panes" "machine=personal|ID=%3|pane=1.1" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
file="$(capture "FAKE_RC_FOR=blocked:124" -- "${common[@]}")"
timed_text="$(zsh "${BRIEF}" --json "${file}" --cut-off)"
contains "cut-off paragraph: a timed-out read says never resend" "I never resend" "${timed_text}"
contains "cut-off paragraph: a timed-out read asks for the prompt, not to clear" "Tell me when its prompt is back?" "${timed_text}"
lacks "cut-off paragraph: a timed-out read is not his to clear" "yours to clear" "${timed_text}"
file="$(capture FAKE_RC=1 "FAKE_REFUSED=" -- "${common[@]}")"
refused_text_out="$(zsh "${BRIEF}" --json "${file}" --cut-off)"
contains "cut-off paragraph: refused text asks to retry once" "Shall I rewrite the read on one line and try once?" "${refused_text_out}"
lacks "cut-off paragraph: refused text never says it is his to clear" "This is yours to clear" "${refused_text_out}"
contains "cut-off paragraph: the pane carries its nickname" '`machine=personal|ID=%18|pane=3.1|nickname=homelab`' "${out_text}"
contains "header: the cut-off line carries the nickname too" "Cut off: machine=personal|ID=%18|pane=3.1|nickname=homelab (holds_text)" "$(zsh "${BRIEF}" --json "${holds_file}" --header)"

# 10b. an announced absence: with away set, host_unreachable and read_timed_out are the away line, never his P0
check "a full read records no absence" null "$(q "${full}" '.away')"
check "a full read: away_ended false" false "$(q "${full}" '.away_ended')"
away_file="$(capture FAKE_LIST_RC=255 -- "${common[@]}" --away 'going to work, back tonight')"
check "away: recorded in the capture" "going to work, back tonight" "$(q "${away_file}" '.away')"
check "away: the reason is still host_unreachable" host_unreachable "$(q "${away_file}" '.cut_off.reason')"
check "away: the host did not answer, so the absence did not end" false "$(q "${away_file}" '.away_ended')"
away_text="$(zsh "${BRIEF}" --json "${away_file}" --cut-off)"; rc=$?
check "away: brief prints the away line, exit 3" 3 "${rc}"
check "away: the line names the host, not a pane; nothing continues by default" 'Away: the host `laptop` is unreachable, as you said (going to work, back tonight); the tracker is unread, read tried at '"$(q "${away_file}" '.captured_at' | awk '{ sub(/^[0-9-]+T/, ""); sub(/:[0-9][0-9]Z$/, "Z"); print }')"'; nothing of mine runs on from this Mac meanwhile; I read again when you say you are back. Back?' "${away_text}"
lacks "away: never his P0" "P0" "${away_text}"
lacks "away: never tells him to open ssh" "ssh" "${away_text}"
lacks "away: never a bare pane target" '`%18`' "${away_text}"
check "away: one question mark" 1 "$(print -rn -- "${away_text}" | tr -cd '?' | wc -c | tr -d ' ')"
contains "away: the header says Away and names the host" "Away: laptop (host_unreachable); tracker unread; read " "$(zsh "${BRIEF}" --json "${away_file}" --header)"
contains "away: --continuing names the work that runs on here" "; running on from this Mac: lane beads-he0 (PR open); lane beads-9pb; I read again when you say you are back. Back?" "$(zsh "${BRIEF}" --json "${away_file}" --cut-off --continuing 'lane beads-he0 (PR open); lane beads-9pb')"
contains "away: --continuing '' is the default line" "; nothing of mine runs on from this Mac meanwhile;" "$(zsh "${BRIEF}" --json "${away_file}" --cut-off --continuing '')"
check "away: --continuing with a question mark is refused" 1 "$(zsh "${BRIEF}" --json "${away_file}" --cut-off --continuing 'is it done?' >/dev/null 2>&1; print $?)"
check "away: --continuing with a newline is refused" 1 "$(zsh "${BRIEF}" --json "${away_file}" --cut-off --continuing $'lane a\nlane b' >/dev/null 2>&1; print $?)"
check "away: --away with a question mark is refused" 1 "$(zsh "${FRONTIER}" "${common[@]}" --away 'back tonight?' >/dev/null 2>&1; print $?)"
check "away: --away with a newline is refused" 1 "$(zsh "${FRONTIER}" "${common[@]}" --away $'going\nto work' >/dev/null 2>&1; print $?)"
check "away: --away '' is refused with a message, not zsh's" "needs his words" "$(zsh "${FRONTIER}" "${common[@]}" --away '' 2>&1 >/dev/null | awk '!f && /needs his words/ { print "needs his words"; f=1 }')"
check "away: --away with --local is refused" 1 "$(zsh "${FRONTIER}" --local --local-repo "${T}/repo" --root "${T}/root" --away 'going to work' >/dev/null 2>&1; print $?)"
file="$(capture FAKE_RC_FOR=blocked:124 -- "${common[@]}" --away 'going to work')"
timed_away="$(zsh "${BRIEF}" --json "${file}" --cut-off)"
contains "away: a timed-out read is the absence too, and names the pane it resolved" 'Away: the host `laptop` did not answer a read of mine in `machine=personal|ID=%18|pane=3.1|nickname=homelab`, as you said it would not (going to work); I never resend it;' "${timed_away}"
check "away: a timed-out read keeps one question mark" 1 "$(print -rn -- "${timed_away}" | tr -cd '?' | wc -c | tr -d ' ')"
file="$(capture FAKE_RC=75 "FAKE_REFUSED=REFUSED: machine=personal|ID=%18|pane=3.1 ${GATE_TEXT}" "FAKE_TAIL=at 01:00:00 UTC ❯ cd ~/homelab && bin/lab up apps/torrent" -- "${common[@]}" --away 'going to work')"
contains "away: a pane that answered is not the absence; holds_text stays his P0" "**P0, cut off from the tracker.**" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
check "away: a pane that answered ends the absence" true "$(q "${file}" '.away_ended')"
file="$(capture FAKE_LIST_RC=255 -- "${common[@]}")"
contains "no away: host_unreachable stays his P0" "**P0, cut off from the tracker.**" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
file="$(capture FAKE_LIST_RC=1 -- "${common[@]}" --away 'going to work')"
lacks "away: a bad definition is never the absence" "Away:" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
contains "away: a bad definition is the reader's paragraph" "mine to fix, not yours" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
file="$(capture FAKE_LIST_RC=255 -- "${common[@]}" --away 'going to work' --pending "${row}")"
contains "away: his typed row is named from the capture, not retyped" "; your row \`${row}\` sits on that prompt, not entered;" "$(zsh "${BRIEF}" --json "${file}" --cut-off)"

# 10c. the away marker: away.zsh set is frontier.zsh's default --away; a capture that reaches the host clears it
check "away marker: nothing recorded, exit 3" 3 "$(zsh "${AWAY}" show --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
check "away marker: set records his words" "away=going to work, laptop with me" "$(zsh "${AWAY}" set --text 'going to work, laptop with me' --session test-session --root "${T}/root" 2>/dev/null)"
check "away marker: a question mark is refused" 1 "$(zsh "${AWAY}" set --text 'back tonight?' --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
check "away marker: a whole message is refused" 1 "$(zsh "${AWAY}" set --text 'going to work so I will be gone for a bit and you will lose connectivity and the laptop' --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
check "away marker: an empty text is refused" 1 "$(zsh "${AWAY}" set --text '' --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
file="$(capture FAKE_LIST_RC=255 -- "${common[@]}")"
check "away from the marker: recorded without --away" "going to work, laptop with me" "$(q "${file}" '.away')"
contains "away from the marker: the away line" 'Away: the host `laptop` is unreachable, as you said (going to work, laptop with me)' "$(zsh "${BRIEF}" --json "${file}" --cut-off)"
check "away from the marker: the host did not answer, the marker stays" 0 "$(zsh "${AWAY}" show --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
file="$(capture CLAUDE_CODE_SESSION_ID=other-session FAKE_LIST_RC=255 -- "${common[@]}")"
check "away from the marker: another session's marker is not read" null "$(q "${file}" '.away')"
file="$(capture -- "${common[@]}")"
check "away marker: the host answered, away_ended true" true "$(q "${file}" '.away_ended')"
contains "away marker: the header says the host answered" "; host answered; fresh read" "$(zsh "${BRIEF}" --json "${file}" --header)"
check "away marker: the host answered, the marker is cleared" 3 "$(zsh "${AWAY}" show --session test-session --root "${T}/root" >/dev/null 2>&1; print $?)"
file="$(capture -- "${common[@]}")"
check "away marker: cleared, the next capture records no absence" "null false" "$(q "${file}" '"\(.away) \(.away_ended)"')"
check "away marker: clear" "away=" "$(zsh "${AWAY}" clear --session test-session --root "${T}/root" 2>/dev/null)"

# 11. mode.zsh
check "mode: off at first" "mode=off" "$(zsh "${MODE}" status --session s1 --root "${T}/root" 2>/dev/null)"
check "mode: off at first, exit 3" 3 "$(zsh "${MODE}" status --session s1 --root "${T}/root" >/dev/null 2>&1; print $?)"
check "mode: on" "mode=on" "$(zsh "${MODE}" on --session s1 --root "${T}/root" 2>/dev/null | awk 'NR == 1')"
check "mode: status on" "mode=on" "$(zsh "${MODE}" status --session s1 --root "${T}/root" 2>/dev/null | awk 'NR == 1')"
check "mode: status on, exit 0" 0 "$(zsh "${MODE}" status --session s1 --root "${T}/root" >/dev/null 2>&1; print $?)"
since1="$(zsh "${MODE}" status --session s1 --root "${T}/root" 2>/dev/null | awk -F= '/^since=/ { print $2 }')"
check "mode: a second on keeps the first since" "${since1}" "$(zsh "${MODE}" on --session s1 --root "${T}/root" 2>/dev/null | awk -F= '/^since=/ { print $2 }')"
check "mode: another session is off" "mode=off" "$(zsh "${MODE}" status --session s2 --root "${T}/root" 2>/dev/null)"
check "mode: off" "mode=off" "$(zsh "${MODE}" off --session s1 --root "${T}/root" 2>/dev/null)"
check "mode: off again is a no-op" "mode=off" "$(zsh "${MODE}" off --session s1 --root "${T}/root" 2>/dev/null)"
check "mode: status after off, exit 3" 3 "$(zsh "${MODE}" status --session s1 --root "${T}/root" >/dev/null 2>&1; print $?)"
check "mode: an action is required" 1 "$(zsh "${MODE}" --session s1 --root "${T}/root" >/dev/null 2>&1; print $?)"
check "mode: a session is required" 1 "$(env -u CLAUDE_CODE_SESSION_ID zsh "${MODE}" status --root "${T}/root" >/dev/null 2>&1; print $?)"

# 12. the example capture matches a fresh one, key for key
check "example: is JSON" true "$(jq -e . "${EXAMPLE}" >/dev/null 2>&1 && print true || print false)"
check "example: same top-level keys as a fresh capture" "$(q "${full}" 'keys_unsorted | join(",")')" "$(q "${EXAMPLE}" 'keys_unsorted | join(",")')"
for sec in ready in_progress human blocked stale deferred host_git local_git health; do
  check "example: ${sec} has the same shape" "$(q "${full}" ".${sec} | if type == \"array\" then (.[0] // {} | keys | join(\",\")) else (keys | join(\",\")) end")" "$(q "${EXAMPLE}" ".${sec} | if type == \"array\" then (.[0] // {} | keys | join(\",\")) else (keys | join(\",\")) end")"
done
check "example: cut_off keys match the real shape" "$(q "${holds_file}" '.cut_off | keys | join(",")')" "busy_cmd,candidates,pane,prompt_holds,reason,unread"
readonly EXAMPLE_MD="${SKILL}/templates/briefing.example.md"
readonly SPEC_MD="${SKILL}/templates/briefing.md"
check "example: the header renders from it" "Ready 3, in progress 1, human 1, blocked 2, stale 1; laptop abc1234 dirty 1; read 09:07Z; fresh read" "$(zsh "${BRIEF}" --json "${EXAMPLE}" --header)"
check "example: the rendered header is the one in the example markdown" "$(zsh "${BRIEF}" --json "${EXAMPLE}" --header)" "$(awk 'NR > 1 && /^Ready / { print; exit }' "${EXAMPLE_MD}")"
check "example: the first-principles paragraph is ninety words or fewer" 1 "$(( $(awk '/^\*\*First principles\.\*\*/ { print }' "${EXAMPLE_MD}" | wc -w) <= 90 ))"
for form in 'typed into `' 'not typed: ' 'another agent is using this pane; typed when it is free' 'not typed yet' 'destroys'; do
  contains "example: the key form is shown: ${form}" "${form}" "$(<"${EXAMPLE_MD}")"
  contains "spec: the key form is named: ${form}" "${form}" "$(<"${SPEC_MD}")"
done
check "example: the cut-off paragraph is brief.zsh's own output" "$(zsh "${BRIEF}" --json "${holds_file}" --cut-off)" "$(awk '/^\*\*P0, cut off from the tracker/ { print; exit }' "${EXAMPLE_MD}")"
for id in $({ grep -oE 'beads-[a-z0-9]+(\.[0-9]+)?' "${EXAMPLE_MD}" || true; } | sort -u); do
  check "example: ${id} in the markdown is in the JSON" true "$(jq -e --arg id "${id}" 'tostring | contains($id)' "${EXAMPLE}" >/dev/null 2>&1 && print true || print false)"
done

print -- "${pass} passed, ${fail} failed"
(( fail == 0 ))
