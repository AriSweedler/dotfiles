#!/usr/bin/env zsh
# Tests for lib/wrap.zsh, bin/link.zsh, bin/focus.zsh and bin/handoff.zsh: how a long command looks in the chat
# code block, in a fenced step (--paste, --capture; one form at a time), and in the pane a click types it into. Golden layouts (SKILL.md's two-purpose
# example, a pipeline with && and a for-loop, a JSON flag value, a jq program, a short command that stays one
# line, JSON-shaped text left alone); the link still carries the one-line command; and on a throwaway tmux
# server (-L, its own zsh with stub programs), a --cmd types the layout and a trailing ;, a --run types it
# with no '\'' quoting, and the capture's output equals the one-line command's output.
# Never touches the live tmux server, Ari's shell config or his clipboard.
# Run: zsh $HOME/.claude/skills/ari-driving-tmux/tests/link.test.zsh
set -uo pipefail
setopt extended_glob

readonly HERE="${0:A:h}"
readonly SKILL="${HERE:h}"
# tmux's homes, Nix's first, as link.zsh and focus.zsh try them: Claude's Bash may lack the Nix profiles.
readonly TMUX_DIRS="/etc/profiles/per-user/${USERNAME}/bin:/run/current-system/sw/bin:/opt/homebrew/bin"
export PATH="${PATH}:${TMUX_DIRS}"
readonly T="${TMPDIR:-/tmp}/ari-driving-link-test-$$"
readonly L="ari-driving-link-test-$$"
mkdir -p "${T}/zdot" "${T}/logs"
export LOG_COLOR=0

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1}"; print -r -- "--- want"; print -r -- "${2}"; print -r -- "--- got"; print -r -- "${3}"; fi
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1}"; print -r -- "--- needle"; print -r -- "${2}"; print -r -- "--- in"; print -r -- "${3}"; fi
}
lacks() {   # <name> <needle> <haystack>
  if [[ "${3}" != *"${2}"* ]]; then (( pass += 1 )); print -- "ok      ${1}"
  else (( fail += 1 )); print -- "FAIL    ${1} | found='${2}'"; fi
}

source "${SKILL}/lib/wrap.zsh"

# --- the cases: one-line command, then its layout; create and token are SKILL.md's two-purpose example ---
typeset -A CMD WANT
CASES=(create token pipeline json jq short)

CMD[create]="op item create --category 'API Credential' --title 'Registry pull token (registry.example.com)' --vault Private \"credential=\$(pbpaste)\""
WANT[create]="op item create \\
    --category 'API Credential' \\
    --title 'Registry pull token (registry.example.com)' \\
    --vault Private \"credential=\$(pbpaste)\""

CMD[token]="op read 'op://Private/Registry pull token (registry.example.com)/credential' | docker login registry.example.com --username robot --password-stdin && docker manifest inspect registry.example.com/team/web:v1"
WANT[token]="op read \\
    'op://Private/Registry pull token (registry.example.com)/credential' \\
  | docker login registry.example.com --username robot --password-stdin \\
  && docker manifest inspect registry.example.com/team/web:v1"

CMD[pipeline]='printf "%s" "$ARI_TOKEN" | docker login registry.example.com --username robot --password-stdin && for image in alpha beta; do docker manifest inspect "registry.example.com/team/$image:v1"; done'
WANT[pipeline]='printf "%s" "$ARI_TOKEN" \
  | docker login registry.example.com --username robot --password-stdin \
  && for image in alpha beta; do docker manifest inspect "registry.example.com/team/$image:v1"; done'

CMD[json]="aws s3api put-bucket-policy --bucket my-bucket --policy '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\"}]}'"
WANT[json]="aws s3api put-bucket-policy \\
    --bucket my-bucket \\
    --policy '{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
          \"Effect\": \"Allow\",
          \"Principal\": \"*\",
          \"Action\": \"s3:GetObject\"
        }]
      }'"

CMD[jq]="printf 'header = \"Authorization: Bearer %s\"\\n' \"\$(op read 'op://Private/<id>/credential')\" | curl -sS -K - https://registry.example.com/access/api/v1/tokens | jq '[.tokens[]? | {token_id, description, subject, scope, issued_at: (.issued_at | todate), expiry: (if .expiry then (.expiry | todate) else \"none\" end)}]'"
WANT[jq]="printf 'header = \"Authorization: Bearer %s\"\\n' \\
    \"\$(op read 'op://Private/<id>/credential')\" \\
  | curl -sS -K - https://registry.example.com/access/api/v1/tokens \\
  | jq '[.tokens[]? | {
      token_id, description, subject, scope,
      issued_at: (.issued_at | todate),
      expiry: (if .expiry then (.expiry | todate) else \"none\" end)
    }]'"

CMD[short]='kubectl get pods -o wide -n kube-system'
WANT[short]='kubectl get pods -o wide -n kube-system'

# --- layout (what the chat code block shows) ---
for c in "${CASES[@]}"; do
  check "layout: ${c}" "${WANT[$c]}" "$(wrap_command "${CMD[$c]}")"
done
check "layout: a short pipeline stays one line" 'kubectl get pods | grep web && echo done' "$(wrap_command 'kubectl get pods | grep web && echo done')"   # lint: ok
check "layout: a short JSON argument stays inline" "curl -d '{\"a\":1}' https://example.com" "$(wrap_command "curl -d '{\"a\":1}' https://example.com")"
DQ_JSON='"{\"home\":\"$HOME\",\"list\":[1,2,3],\"more\":\"padding padding padding padding\"}"'
contains "layout: a double-quoted JSON argument (its \$HOME expands) is kept as written" \
  "    ${DQ_JSON} \\" "$(wrap_command "jq -n --argjson v ${DQ_JSON} --arg name some-long-name-for-the-width '\$v'")"
JQ_COMMENT="jq '{name: .metadata.name, ns: .metadata.namespace} # pick the name and namespace'"
check "layout: a jq program with a comment is left as written" "${JQ_COMMENT}" "$(wrap_command "${JQ_COMMENT}")"
# JSON-shaped text whose bytes are its meaning: a fixed-string grep pattern, a jq --arg string.
GREP_JSON="grep -cF '{\"level\":\"error\",\"service\":\"web\",\"message\":\"timeout talking to the db\"}' app.jsonl"
check "layout: a JSON-shaped grep pattern is left as written" "${GREP_JSON}" "$(wrap_command "${GREP_JSON}")"
JQ_ARG="jq -n --arg tmpl '{\"level\":\"error\",\"service\":\"web\",\"message\":\"timeout\"}' '\$tmpl | length'"
check "layout: a JSON-shaped jq --arg string is left as written" "${JQ_ARG}" "$(wrap_command "${JQ_ARG}")"
check "layout: jq behind env is still jq" "env FOO=1 jq -c '{
    name: .metadata.name,
    namespace: .metadata.namespace,
    labels: .metadata.labels
  }' pods.json" "$(wrap_command "env FOO=1 jq -c '{name: .metadata.name, namespace: .metadata.namespace, labels: .metadata.labels}' pods.json")"
HASH_WORD="kubectl get pods -o wide -n kube-system --selector app=web # a comment long enough to pass the width"
check "layout: a command with a # word stays one line" "${HASH_WORD}" "$(wrap_command "${HASH_WORD}")"

# --- the run_log text a click types, and the fenced step handoff.zsh renders ---
check "typed: short, no quotes: single-quoted" "run_log --deliver-to %9 'kubectl get pods -o wide -n kube-system'" "$(wrap_run_log_text '--deliver-to %9 ' "${CMD[short]}")"
check "typed: short with quotes: double-quoted, no '\\''" "run_log \"rg 'foo' src\"" "$(wrap_run_log_text '' "rg 'foo' src")"
check "typed: laid out: a quoted heredoc holding the layout" "run_log --deliver-to %9 \"\$(command cat <<'RUN_LOG'
${WANT[create]}
RUN_LOG
)\"" "$(wrap_run_log_text '--deliver-to %9 ' "${CMD[create]}")"
check "fenced step: --capture lays out the jq case in the same heredoc" "\`\`\`zsh
$(wrap_run_log_text '' "${CMD[jq]}")
\`\`\`
Expected: one token" "$(zsh "${SKILL}/bin/handoff.zsh" --print --cmd "${CMD[jq]}" --expect 'one token' --capture 2>/dev/null)"
check "fenced step: --paste shows the bare layout, no run_log" "\`\`\`zsh
${WANT[jq]}
\`\`\`
Expected: one token" "$(zsh "${SKILL}/bin/handoff.zsh" --print --cmd "${CMD[jq]}" --expect 'one token' --paste 2>/dev/null)"
zsh "${SKILL}/bin/handoff.zsh" --print --cmd "${CMD[jq]}" --expect 'one token' >/dev/null 2>&1
check "fenced step: no form flag is refused" 1 "$?"
zsh "${SKILL}/bin/handoff.zsh" --print --cmd "${CMD[short]}" --expect x --paste --capture >/dev/null 2>&1
check "fenced step: --paste with --capture is refused" 1 "$?"
zsh "${SKILL}/bin/handoff.zsh" --print --cmd "${CMD[short]}" --expect x --paste --capture-dir "${T}" >/dev/null 2>&1
check "fenced step: --capture-dir without --capture is refused" 1 "$?"
check "fenced step: a command holding \`\`\` widens the fence" '````zsh
echo "```"
````
Expected: x' "$(zsh "${SKILL}/bin/handoff.zsh" --print --cmd 'echo "```"' --expect x --paste 2>/dev/null)"
check "fenced step: a short command keeps run_log --" "run_log -- kubectl get pods -o wide -n kube-system" \
  "$(zsh "${SKILL}/bin/handoff.zsh" --print --cmd "${CMD[short]}" --expect x --capture 2>/dev/null | awk 'NR == 2')"
check "typed: a line equal to the delimiter moves it" "RUN_LOG_1" "$(wrap_heredoc_delimiter $'a\nRUN_LOG\nb')"

# --- the throwaway server: a zsh pane at a ❯ prompt with stub programs, and a return pane ---
cat > "${T}/zdot/.zshrc" <<'EOF'
PROMPT='❯ '
op() { if [[ "${1}" == read ]]; then print -r -- tok-123; else print -rl -- op "$@"; fi; }
pbpaste() { print -r -- pasted-token; }
docker() { print -rl -- docker "$@"; }
aws() { print -rl -- aws "${@[1,-2]}"; print -r -- "${@[-1]}" | jq -cS .; }
kubectl() { print -rl -- kubectl "$@"; }
curl() { cat >/dev/null; print -r -- '{"tokens":[{"token_id":"t1","description":"pull","subject":"robot","scope":"repo:pull","issued_at":1700000000,"expiry":null,"extra":1}]}'; }
EOF
readonly PANE_PATH="${HOME}/.config/bin:${TMUX_DIRS}:/usr/local/bin:/usr/bin:/bin"
# The pane's own PATH: nix-darwin's /etc/zshenv resets the one -e PATH passes, and run_log is then not found.
print -r -- "PATH=${(q)PANE_PATH}" >> "${T}/zdot/.zshrc"
tm() { tmux -L "${L}" -f /dev/null "$@"; }
tm new-session -d -s t -x 250 -y 80 -e "ZDOTDIR=${T}/zdot" -e "LOG_DIR=${T}/logs" -e RUN_LOG_COPY=0 \
  -e ARI_TOKEN=secret-token -e "PATH=${PANE_PATH}" zsh || { print -u2 "cannot start a test tmux server"; exit 1; }
# The attached client focus.zsh switches. script's stdin is a pipe this test holds open (fd 3), so it never
# reads EOF and sends ^D into the pane; nothing in the background holds this test's stdout.
exec 3> >(script -q /dev/null tmux -L "${L}" attach -t t >/dev/null 2>&1)
trap 'tm kill-server 2>/dev/null; exec 3>&-; rm -rf "${T}"' EXIT
export TMUX="$(tm display-message -p '#{socket_path}'),0,0"
P="$(tm list-panes -t t -F '#{pane_id}')"
# A tall pane: zsh shows a buffer taller than its pane cut off (>....), which the capture would read.
tm set-option -g window-size manual; tm resize-window -t t: -x 250 -y 80
R="$(tm new-window -d -P -F '#{pane_id}' -t t: /bin/sh)"
tm set-option -p -t "${P}" @ari_driving on
wait_for() {   # <seconds> <command…>: poll until the command succeeds
  local -i tries=$(( ${1} * 10 )); shift
  while ! "$@" 2>/dev/null; do (( tries -= 1 )); (( tries > 0 )) || return 1; sleep 0.1; done
}
at_prompt() { [[ "$(tm capture-pane -p -t "${P}" | awk 'NF { l = $0 } END { print l }')" == *❯ ]]; }
has_client() { [[ -n "$(tm list-clients)" ]]; }
wait_for 10 at_prompt || { print -u2 "the test pane never showed its prompt"; exit 1; }
wait_for 10 has_client || { print -u2 "no client attached to the test server"; exit 1; }

# --- the chat block link.zsh prints, and the one line its link carries ---
for c in "${CASES[@]}"; do
  out="$(zsh "${SKILL}/bin/link.zsh" --pane "${P}" --run "${CMD[$c]}" 2>/dev/null)"
  block="> \`\`\`zsh"$'\n'"${(F)${(@)${(@f)WANT[$c]}/#/> }}"$'\n'"> \`\`\`"
  contains "link block: ${c}" "${block}" "${out}"
  encoded="${${out%%$'\n'*}#*\?run=}"; encoded="${encoded%%[\&\)]*}"
  check "link payload: ${c} is the one-line command" "${CMD[$c]}" "${(g::)${encoded//\%/\\x}}"
  # The paired paste round: link.zsh --cmd's code block, its `> ` stripped, is handoff.zsh --paste's block.
  cmd_out="$(zsh "${SKILL}/bin/link.zsh" --pane "${P}" --cmd "${CMD[$c]}" 2>/dev/null)"
  paste_out="$(zsh "${SKILL}/bin/handoff.zsh" --print --cmd "${CMD[$c]}" --expect x --paste 2>/dev/null)"
  check "paired round: ${c}: the --cmd block equals the --paste step" "${paste_out%$'\n'Expected: x}" "${(F)${(@)${(@f)cmd_out}[2,-1]#> }}"
done

# --- tmux off PATH (a Claude Bash without the Nix profiles): link.zsh and focus.zsh still find it ---
readonly BARE_PATH=/usr/bin:/bin
if [[ -n "$(PATH="${BARE_PATH}" command -v tmux)" ]]; then
  print -- "skip    tmux off PATH: ${BARE_PATH} holds a tmux"
else
  out="$(PATH="${BARE_PATH}" /bin/zsh "${SKILL}/bin/link.zsh" --pane "${P}" 2>"${T}/link.err")"
  check "tmux off PATH: link.zsh rc 0" 0 "$?"
  contains "tmux off PATH: link.zsh prints the focus link" "(tmux-pane://${P#%})" "${out}"
  PATH="${BARE_PATH}" /bin/zsh "${SKILL}/bin/focus.zsh" --no-activate --pane "${P}" >/dev/null 2>"${T}/focus.err"
  check "tmux off PATH: focus.zsh rc 0" 0 "$?"
fi

# --- a --cmd types the layout, no Enter; a trailing ; survives (tmux's own parser would eat it) ---
typed_line() {   # <cmd>: click --cmd, read back the pane's last lines, then cancel the line
  wait_for 10 at_prompt
  zsh "${SKILL}/bin/focus.zsh" --no-activate --pane "${P}" --cmd "${1}" >/dev/null 2>"${T}/focus.err"
  sleep 0.5
  print -r -- "${(F)${(@)${(@f)$(tm capture-pane -p -J -t "${P}")}%%[[:space:]]#}}"
  tm send-keys -t "${P}" C-c
}
contains "cmd: a trailing ; is typed" "❯ find . -name x -exec echo {} \\;" "$(typed_line 'find . -name x -exec echo {} \;')"
contains "cmd: a laid-out command is typed laid out" "❯ ${WANT[jq]}" "$(typed_line "${CMD[jq]}")"

# --- a --run types the layout into the pane; its capture matches the one-line command's output ---
for c in "${CASES[@]}"; do
  wait_for 10 at_prompt
  before=(${T}/logs/*(N/))
  zsh "${SKILL}/bin/focus.zsh" --no-activate --pane "${P}" --run "${CMD[$c]}" --return-pane "${R}" >/dev/null 2>"${T}/focus.err"
  check "run ${c}: focus.zsh rc 0" 0 "$?"
  new_capture() { local -a now=(${T}/logs/*(N/)); (( ${#now} > ${#before} )); }
  wait_for 15 new_capture
  dir=(${T}/logs/*(N/om[1]))
  has_exit() { grep -q '^exit=' "${dir[1]}/metadata"; }
  wait_for 15 has_exit
  screen="$(tm capture-pane -p -J -S - -t "${P}")"
  screen="${(F)${(@)${(@f)screen}%%[[:space:]]#}}"   # cells zsh redrew keep trailing blanks
  typed="$(wrap_run_log_text "--deliver-to ${R} " "${CMD[$c]}")"
  contains "run ${c}: the pane shows the layout as typed" "❯ ${typed}" "${screen}"
  lacks "run ${c}: no '\\'' quoting in the pane" "'\\''" "${screen}"
  want_out="$(cd "${T}" && env -i HOME="${HOME}" ZDOTDIR="${T}/zdot" ARI_TOKEN=secret-token PATH="${PANE_PATH}" zsh -ic "${CMD[$c]}" 2>/dev/null)"
  check "run ${c}: output equals the one-line command's" "${want_out}" "$(<"${dir[1]}/stdout.plain")"
  check "run ${c}: exit 0" "exit=0" "$(grep '^exit=' "${dir[1]}/metadata")"
done

print -- "${pass} passed, ${fail} failed"
(( fail == 0 ))
