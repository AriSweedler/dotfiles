# The weekly Desktop report: fingerprint, render, decide, write. Requires common.zsh to be
# sourced first (the CLI, every step subprocess and the test harness's zfn all do) for the
# ARI_DOTFILES_* contract, log::*, note and plural. Side-effect-free at source time.
#
# Public contract:
#   report::fingerprint <summary.json> [fail|error]
#       16 hex chars identifying WHAT failed (step + sorted kind/name/problem tuples), "" when
#       nothing did. kind=error hashes step:reason of the errored steps instead.
#   report::render <summary.json> <log.txt> [-k fail|error] [-s FIRST_SEEN] [-w WEEKS]
#                  [-p PREVIOUS_DATE] [-o REPORT_PATH]
#       Pure; markdown on stdout. Defaults: kind from .status, first_seen = today, weeks = 1,
#       no previous run, REPORT_PATH = <desktop>/new-machine-FAILED.md. The log argument is only
#       tailed; every path printed in the report is the canonical state-dir location.
#   report::decide <summary.json> [--force-report]
#       Pure; reads last_result.json and the Desktop file, prints one JSON decision:
#       {kind: pass|fail|error, action: write|unchanged|suppress|clear, fingerprint, first_seen,
#        weeks_failing, consecutive_errors, report_path, report_sha256, previous_date,
#        old_reports: [{action: archive|rename_edited|leave_edited|leave_foreign|collision, from, to}],
#        hud: {message, seconds (null = persistent), open (file:// URL or null)},
#        brew_undeclared, undeclared_count, problems, checks, error_reasons, force}
#   report::write <summary.json> <log.txt> <decision.json>
#       Applies a decision: moves the old report aside, renders and writes the new one plus its
#       archive copy, stamps last-ok on a pass, rewrites last_result.json. Prints the decision
#       extended with {report: written|unchanged|archived|left_edited|none, last_result: {…}}.

if (( ! ${+REPORT_BASENAME} )); then
  typeset -gr REPORT_BASENAME='new-machine-FAILED.md'
fi

report::_today() { local d; strftime -s d '%Y-%m-%d' "${ARI_DOTFILES_NOW}"; print -r -- "${d}"; }

# The given path when nothing sits there, else the first free `<stem>.N.md` beside it.
report::_free_path() {
  local want="${1}" n=2
  local candidate="${want}"
  while [[ -e "${candidate}" ]]; do
    candidate="${want%.md}.${n}.md"
    (( n++ ))
  done
  print -r -- "${candidate}"
}

# Where a Desktop report moves when archived. Byte-identical archives may share a name; anything
# else gets a numbered one, so the archive keeps every render (§4.2).
report::_archive_target() {
  local from="${1}" first_seen="${2}" fp8="${3}"
  local to="${ARI_DOTFILES_STATE_DIR}/reports/${first_seen}-${fp8}.md"
  if [[ -e "${to}" ]] && ! cmp -s "${from}" "${to}"; then
    to="$(report::_free_path "${to}")"
  fi
  print -r -- "${to}"
}

report::fingerprint() {
  local summary="${1}" kind="${2:-fail}" lines
  case "${kind}" in
    fail)
      lines="$(jq -r '[.steps[] | select(.status=="fail")
          | .step + ":" + ((.items // []) | map(.kind + "/" + .name + "/" + (.problem // "")) | sort | join(","))]
         | sort | join("\n")' "${summary}")" ;;
    error)
      lines="$(jq -r '[.steps[] | select(.status=="error") | .step + ":" + .reason] | sort | join("\n")' "${summary}")" ;;
    *) print -u2 -r -- "report::fingerprint: bad kind ${kind}"; return 64 ;;
  esac
  if [[ -z "${lines}" ]]; then
    print -r -- ""
    return 0
  fi
  print -r -- "${lines}" | shasum -a 256 | cut -c1-16
}

# Shared jq prelude for the row renderers. Table cells must stay on one line and must not
# contain an unescaped pipe.
if (( ! ${+REPORT_JQ_PRELUDE} )); then
typeset -gr REPORT_JQ_PRELUDE='
  def kind_rank: {"formula":0,"cask":1,"tap":2,"vscode":3}[.] // 9;
  def cell: tostring | gsub("\n"; " ⏎ ") | gsub("\\|"; "\\|");
  def code: if . == null or . == "" then "—" else "`" + . + "`" end;
  def nm: if type == "string" then . else (((.kind // "") + " " + (.name // "")) | ltrimstr(" ")) end;
  def fixsfx: if (. // "") == "" then "" else " (`" + . + "`)" end;
'
fi

report::_rows_failed() {
  jq -r --arg prev "${2}" "${REPORT_JQ_PRELUDE}"'
    (.brew.undeclared // []) as $und
    | def new_suffix($k; $n):
        if any($und[]; .kind == $k and .name == $n and .new == true)
        then (if $prev == "" then " (new)" else " (new since " + $prev + ")" end) else "" end;
      [ .steps[] | select(.status == "fail") | . as $st
        | if ((.items // []) | length) == 0 then
            { step: .step, item: "—", k: 9, n: "",
              problem: (.reason + (if (.detail // "") == "" then "" else " — " + .detail end)),
              tier: "—", fix: (.fix | code) }
          else .items[]
            | { step: $st.step, item: (.kind + " " + .name), k: (.kind | kind_rank), n: .name,
                problem: ((.problem // "") + (if (.hint // "") == "" then "" else ": " + .hint end)
                          + new_suffix(.kind; .name)),
                tier: (.tier // "—"),
                fix: (if .problem == "orphaned" then "see below" else ($st.fix | code) end) }
          end ]
    | sort_by([.step, .k, .n])[]
    | "| \(.step | cell) | \(.item | cell) | \(.problem | cell) | \(.tier | cell) | \(.fix | cell) |"' "${1}"
}

report::_rows_errors() {
  jq -r "${REPORT_JQ_PRELUDE}"'
    [ .steps[] | select(.status == "error") ] | sort_by(.step)[]
    | "| \(.step) | \(.reason | cell) | \((.detail // "") | if . == "" then "—" else . end | cell) |"' "${1}"
}

report::_rows_undeclared() {
  jq -r --arg cli "${CLI_NAME}" "${REPORT_JQ_PRELUDE}"'
    (.brew.undeclared // []) | sort_by([(.kind | kind_rank), .name])[]
    | "| \(.kind) | \(.name | cell) | \((.tap // "—") | cell)"
      + " | `\($cli) brew decree \(.kind):\(.name) --global`"
      + " | `\($cli) brew decree \(.kind):\(.name) --local`"
      + " | `\($cli) brew decree \(.kind):\(.name) --ignore-local --reason \"…\"` |"' "${1}"
}

report::_line_new_since() {
  jq -r --arg prev "${2}" "${REPORT_JQ_PRELUDE}"'
    [ (.brew.undeclared // []) | sort_by([(.kind | kind_rank), .name])[] | select(.new == true) | .kind + " " + .name ]
    | if length == 0 then empty
      else (if $prev == "" then "New since the last run: " else "New since the last run (" + $prev + "): " end) + join(", ") + "."
      end' "${1}"
}

report::_bullets_human() {
  jq -r --arg cli "${CLI_NAME}" "${REPORT_JQ_PRELUDE}"'
    def keg: split("/") | last;
    def tap: split("/") | if length >= 3 then (.[0:2] | join("/")) else "" end;
    def tiers: (.tiers // (if (.tier // "") == "" then [] else [.tier] end));
    [ (.brew.orphan_keg // [])[]
      | .name as $n | ($n | keg) as $keg | ($n | tap) as $tap | (.hint // "") as $h
      | if ($h | startswith("the tap now ships cask")) then
          "- `\($n)` is an orphaned keg: the tap converted the formula to a cask. Run\n  `brew uninstall \($keg) && brew tap \($tap) && brew install --cask \($n)`,\n  then `\($cli) brew decree cask:\($n) --local`."
        elif $h == "tap not tapped" then
          "- `\($n)` is an orphaned keg: its tap \($tap) is not tapped. Run `brew tap \($tap)` to restore it, or\n  `brew uninstall \($keg)` if it is no longer wanted."
        else
          "- `\($n)` is an orphaned keg (\(if $h == "" then "formula removed from tap" else $h end)): a fresh machine cannot install it. Run\n  `brew uninstall \($keg)` if it is no longer wanted; otherwise find where the formula moved and declare that."
        end ]
    + [ (.brew.declared_orphan // [])[]
        | "- \(.kind) `\(.name)` is declared\(if (tiers | length) > 0 then " in " + (tiers | join(", ")) else "" end) but its keg is orphaned (see above): a fresh machine cannot install it. Repair the keg, then\n  `\($cli) brew undecree \(.kind):\(.name)` and decree the replacement." ]
    + [ (.brew.duplicate // [])[]
        | "- \(.kind) `\(.name)` is declared twice (\(tiers | join(", "))): remove one line by hand, or `\($cli) brew undecree \(.kind):\(.name)` if decree wrote it." ]
    | .[]' "${1}"
}

report::_bullets_noted() {
  jq -r --arg cli "${CLI_NAME}" "${REPORT_JQ_PRELUDE}"'
    def oneline: gsub("\n"; "; ");
    def amb: nm + (if (type == "object" and (.candidates // []) != []) then " → " + (.candidates | join(", ")) else "" end);
    [ .steps[] | select(.status == "warn" and .reason != "manual_font") | . as $st
      | if ((.items // []) | length) == 0 then
          "- \(.step): \((if (.detail // "") == "" then .reason else .detail end) | oneline)\($st.fix | fixsfx)"
        else .items[]
          | if .kind == "tap" and .problem == "needs to be tapped" then
              "- \($st.step): tap \(.name) needs to be tapped (`\($cli) setup` taps it; or delete the line)"
            else "- \($st.step): \(.kind) \(.name) \(.problem // "")\($st.fix | fixsfx)" end
        end ]
    + [ (.brew.untrusted_taps // [])[] | "- brew_drift: declared tap \(nm) lacks `trusted: true`" ]
    + [ (.brew.unresolvable_ignore // [])[] | "- brew_drift: ignore entry \(nm) matches nothing installed" ]
    + [ (.brew.include_declared_missing // [])[]
        | "- brew_drift: include-declared Brewfile missing, its items are not ignored: \(if type == "string" then . else (.path // tostring) end)" ]
    + [ (.brew.ambiguous_alias // [])[] | "- brew_drift: ambiguous alias \(amb)" ]
    + [ (.brew.inventory_note // empty) | select(. != null and . != "") | "- brew_drift: \(.)" ]
    + (if .brew.vscode_skipped == true then ["- brew_drift: VS Code inventory skipped (`code` not found)"] else [] end)
    | .[]' "${1}"
}

report::render() {
  local summary="${1}" log="${2}"
  shift 2
  local kind="" first_seen="" weeks=1 previous="" report_path=""
  while (( $# )); do
    case "${1}" in
      -k) kind="${2}"; shift 2 ;;
      -s) first_seen="${2}"; shift 2 ;;
      -w) weeks="${2}"; shift 2 ;;
      -p) previous="${2}"; shift 2 ;;
      -o) report_path="${2}"; shift 2 ;;
      *) print -u2 -r -- "report::render: bad flag ${1}"; return 64 ;;
    esac
  done
  local state_dir="${ARI_DOTFILES_STATE_DIR}" desktop_dir="${ARI_DOTFILES_DESKTOP_DIR}" local_dir="${ARI_DOTFILES_LOCAL_DIR}"
  local now="${ARI_DOTFILES_NOW}" host="${ARI_DOTFILES_HOST}" run_id run_status stamp fp
  run_id="$(jq -r '.run_id // "unknown"' "${summary}")"
  run_status="$(jq -r '.status // "error"' "${summary}")"
  if [[ -z "${kind}" ]]; then
    if [[ "${run_status}" == error ]]; then kind=error; else kind=fail; fi
  fi
  if [[ -z "${first_seen}" ]]; then first_seen="$(report::_today)"; fi
  if [[ -z "${report_path}" ]]; then report_path="${desktop_dir}/${REPORT_BASENAME}"; fi
  fp="$(report::fingerprint "${summary}" "${kind}")"
  strftime -s stamp '%Y-%m-%d %H:%M' "${now}"

  local -a counts
  counts=("${(@f)$(jq -r '[(.steps | length),
      ([.steps[] | select(.status == "fail")] | length),
      ([.steps[] | select(.status == "warn")] | length),
      ([.steps[] | select(.status == "error")] | length),
      ((.brew.undeclared // []) | length),
      (((.brew.orphan_keg // []) + (.brew.declared_orphan // []) + (.brew.duplicate // [])) | length)] | .[]' "${summary}")}")
  local total="${counts[1]}" fails="${counts[2]}" warns="${counts[3]}" errors="${counts[4]}"
  local undeclared="${counts[5]}" human="${counts[6]}"
  local log_path="${state_dir}/verify/log.txt"

  local lead
  if [[ "${kind}" == error ]]; then
    lead="${errors} of ${total} checks could not run"
    if (( fails > 0 )); then lead+=", ${fails} failed"; fi
  else
    lead="${fails} of ${total} checks failed"
  fi
  lead+=", $(plural "${warns}" warning warnings)."

  print -r -- "<!-- new-machine-report v1 fingerprint=${fp} run_id=${run_id} first_seen=${first_seen} kind=${kind} -->"
  if [[ "${kind}" == error ]]; then
    print -r -- "# new-machine weekly check COULD NOT RUN — ${host}, ${stamp}"
  else
    print -r -- "# new-machine weekly check FAILED — ${host}, ${stamp}"
  fi
  print -r -- ""
  print -r -- "${lead} First seen ${first_seen} ($(plural "${weeks}" week weeks)). This file is rewritten only when the set of"
  print -r -- 'problems changes; the same failure gets a banner, not a new file. Deleting it means "acknowledged".'
  print -r -- "State lives in ${state_dir}/ · machine-readable: last-check.json"
  print -r -- ""

  if [[ "${kind}" == error ]]; then
    print -r -- "## The check itself could not run"
    print -r -- ""
    print -r -- "| step | reason | detail |"
    print -r -- "|---|---|---|"
    report::_rows_errors "${summary}"
    print -r -- ""
  fi

  if (( fails > 0 )); then
    print -r -- "## What failed"
    print -r -- ""
    print -r -- "| step | item | problem | tier | fix |"
    print -r -- "|---|---|---|---|---|"
    report::_rows_failed "${summary}" "${previous}"
    print -r -- ""
  fi

  if (( undeclared > 0 )); then
    print -r -- "## Undeclared brew items (decree each one; I decide the tier)"
    print -r -- ""
    print -r -- "| kind | name | from | every machine | this machine | never declare |"
    print -r -- "|---|---|---|---|---|---|"
    report::_rows_undeclared "${summary}"
    print -r -- ""
    local new_since
    new_since="$(report::_line_new_since "${summary}" "${previous}")"
    if [[ -n "${new_since}" ]]; then
      print -r -- "${new_since}"
      print -r -- ""
    fi
  fi

  if (( human > 0 )); then
    print -r -- "## Needs a human (the tool never uninstalls or reinstalls)"
    print -r -- ""
    report::_bullets_human "${summary}"
    print -r -- ""
  fi

  local noted
  noted="$(report::_bullets_noted "${summary}")"
  if [[ -n "${noted}" ]]; then
    print -r -- "## Also noted (warnings, no report on their own)"
    print -r -- ""
    print -r -- "${noted}"
    print -r -- ""
  fi

  print -r -- "## Raw log (last 40 lines)"
  print -r -- ""
  print -r -- '```'
  if [[ -f "${log}" ]]; then
    tail -n 40 "${log}"
  else
    print -r -- "(no log at ${log})"
  fi
  print -r -- '```'
  print -r -- "Full log: ${log_path}"
  print -r -- "Run dir:  ${state_dir}/runs/${run_id}/  (summary.json, Brewfile.merged, bundle_check.out, drift.json)"
  print -r -- "Trail:    ${state_dir}/verify.log"
  print -r -- ""

  local task
  if [[ "${kind}" == error ]]; then
    task="Diagnose why '${CLI_NAME} healthcheck' cannot run on this machine and fix it; do not silence the check."
  else
    task="Fix every row under 'What failed', following the rules below it (check prior fixes with git df log first; commit with the fix(new-machine/<step>) header). For brew items run '${CLI_NAME} brew triage' and propose one '${CLI_NAME} brew decree ...' per item; I decide the tier."
  fi
  cat <<EOF
## How to feed this to Claude

1. In a terminal: \`cd ~\` and paste this one line:

    claude "Read ${report_path} and ${log_path}. Load the /ari-dotfiles skill first and follow its two-tier rules: shared tier (~/.config, git df) commit and NEVER push, end with 'Run dotfiles push when ready'; local tier (~/.local, git ldf) commit and then git ldf push. ${task} Finish with '${CLI_NAME} healthcheck --json' and show me the output."

2. Rules for the fix (the /ari-dotfiles skill is canonical):
   - Declared brew state is the two Brewfiles: ${HOME}/.config/new-machine/Brewfile (global, df) and
     ${local_dir}/Brewfile (local, ldf), plus \`Brewfile.ignore\` beside each.
     Undeclared items are settled with \`${CLI_NAME} brew decree …\`, never by editing brew's state and never with
     \`brew bundle cleanup\`, \`brew upgrade\`, or \`brew bundle add\`.
   - Do not install anything to make the check pass except \`${CLI_NAME} apply <step>\`, which installs only what
     the Brewfiles declare. Orphaned kegs need a human: propose the command, do not run it.
   - Never \`--no-verify\`; never commit a \`*.secret.zsh\`.
   - If a finding is a false alarm, fix the checker in ${HOME}/.config/dotfiles/steps/<step>.zsh and add a
     tests/test_*.sh case that reproduces it; \`${CLI_NAME} test\` must pass.
   - Before fixing a row, read the prior fixes for that step; a repeat usually means the last fix's
     assumption broke (a tool renamed a binary, launchd's PATH changed):
       git df log --oneline --grep='fix(new-machine/<step>)'
   - Commit each fix with the header \`fix(new-machine/<step>): <what was wrong, one line>\`, so the grep
     above finds it. The body states the reason code from the report (e.g. \`claude_missing\`), whether
     the checker or the machine was wrong, the root cause, and the test that reproduces it. Use the same
     header when the checker lives elsewhere, like ${HOME}/.config/karabiner/bin/healthcheck.

## What "fixed" looks like

\`${CLI_NAME} healthcheck\` exits 0 and prints \`status: ok\`. The next weekly run (or \`${CLI_NAME} verify\` now) moves this
file to ${state_dir}/reports/ and posts "verified OK".
EOF
}

# Describe a file at a would-be report path: our marker (first line) and whether its sha256 is the
# one recorded at write time. Prints JSON, `null` when the file is absent.
report::_inspect() {
  local file="${1}" expected_sha="${2}"
  if [[ ! -f "${file}" ]]; then
    print -r -- 'null'
    return 0
  fi
  local first sha marker=false fp="" run_id="" first_seen="" kind="" sha_matches=false
  first="$(head -n 1 "${file}")"
  # first_seen and run_id become path components, so the marker admits only their exact shapes.
  if [[ "${first}" =~ '^<!-- new-machine-report v1 fingerprint=([0-9a-f]*) run_id=([0-9]{8}T[0-9]{6}) first_seen=([0-9]{4}-[0-9]{2}-[0-9]{2}) kind=([a-z]+) -->$' ]]; then
    marker=true
    fp="${match[1]}"; run_id="${match[2]}"; first_seen="${match[3]}"; kind="${match[4]}"
  fi
  sha="$(shasum -a 256 "${file}" | cut -d' ' -f1)"
  if [[ -n "${expected_sha}" && "${sha}" == "${expected_sha}" ]]; then sha_matches=true; fi
  jq -cn --arg path "${file}" --argjson marker "${marker}" --arg sha "${sha}" --argjson sha_matches "${sha_matches}" \
         --arg fp "${fp}" --arg run_id "${run_id}" --arg first_seen "${first_seen}" --arg kind "${kind}" \
    '{path: $path, marker: $marker, sha: $sha, sha_matches: $sha_matches, fingerprint: $fp, fp8: ($fp | .[0:8]),
      run_id: $run_id, first_seen: $first_seen, kind: $kind}'
}

# What to do with a file already sitting at a report path, before this run writes (mode=write)
# or after a pass (mode=pass). Our unedited report is archived; an edited one is never clobbered;
# a foreign file is left alone. Prints one JSON action, or nothing when there is no file.
report::_old_report_action() {
  local existing="${1}" mode="${2}" canonical="${3}" fp8="${4}"
  if [[ "${existing}" == null ]]; then return 0; fi
  local file marker sha_matches first_seen efp8 desktop_dir="${ARI_DOTFILES_DESKTOP_DIR}"
  file="$(jq -r .path <<< "${existing}")"
  marker="$(jq -r .marker <<< "${existing}")"
  sha_matches="$(jq -r .sha_matches <<< "${existing}")"
  first_seen="$(jq -r .first_seen <<< "${existing}")"
  efp8="$(jq -r .fp8 <<< "${existing}")"
  local action to=""
  if [[ "${marker}" == false ]]; then
    if [[ "${mode}" == write && "${canonical}" == true ]]; then
      action=collision
      to="${desktop_dir}/new-machine-FAILED.${fp8}.md"
    else
      action=leave_foreign
    fi
  elif [[ "${sha_matches}" == true ]]; then
    action=archive
    to="$(report::_archive_target "${file}" "${first_seen}" "${efp8}")"
  elif [[ "${mode}" == write ]]; then
    action=rename_edited
    to="${desktop_dir}/new-machine-FAILED.${first_seen}-${efp8}.edited.md"
    local n=2
    while [[ -e "${to}" ]]; do
      to="${desktop_dir}/new-machine-FAILED.${first_seen}-${efp8}.edited.${n}.md"
      (( n++ ))
    done
  else
    action=leave_edited
  fi
  jq -cn --arg action "${action}" --arg from "${file}" --arg to "${to}" \
    '{action: $action, from: $from, to: (if $to == "" then null else $to end)}'
}

report::decide() {
  local summary="${1}"
  shift
  local force=false
  while (( $# )); do
    case "${1}" in
      --force-report) force=true; shift ;;
      *) print -u2 -r -- "report::decide: bad flag ${1}"; return 64 ;;
    esac
  done
  local state_dir="${ARI_DOTFILES_STATE_DIR}" desktop_dir="${ARI_DOTFILES_DESKTOP_DIR}" report today
  report="${desktop_dir}/${REPORT_BASENAME}"
  today="$(report::_today)"

  local run_status kind
  run_status="$(jq -r '.status // ""' "${summary}")"
  case "${run_status}" in
    ok|warn) kind=pass ;;
    fail)    kind=fail ;;
    error)   kind=error ;;
    *) print -u2 -r -- "report::decide: unknown summary status '${run_status}'"; return 1 ;;
  esac

  local last='null' last_file="${state_dir}/last_result.json"
  if [[ -f "${last_file}" ]]; then
    if ! last="$(jq -c . "${last_file}" 2>/dev/null)"; then
      log::warn "last_result.json unreadable, treating as absent | path='${last_file}'"
      last='null'
    fi
  fi
  local last_fp last_sha last_first_seen last_weeks last_errors last_report_path last_ts last_undeclared
  last_fp="$(jq -r '.fingerprint // ""' <<< "${last}")"
  last_sha="$(jq -r '.report_sha256 // ""' <<< "${last}")"
  last_first_seen="$(jq -r '.first_seen // ""' <<< "${last}")"
  last_weeks="$(jq -r '.weeks_failing // 0' <<< "${last}")"
  last_errors="$(jq -r '.consecutive_errors // 0' <<< "${last}")"
  last_report_path="$(jq -r '.report_path // ""' <<< "${last}")"
  last_ts="$(jq -r '.ts // ""' <<< "${last}")"
  last_undeclared="$(jq -c '.brew_undeclared // []' <<< "${last}")"
  local previous_date=""
  if [[ "${last_ts}" =~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' ]]; then previous_date="${last_ts[1,10]}"; fi

  local fp=""
  case "${kind}" in
    fail)  fp="$(report::fingerprint "${summary}" fail)" ;;
    error) fp="$(report::fingerprint "${summary}" error)" ;;
  esac
  local fp8="${fp[1,8]}"

  local -a stats
  stats=("${(@f)$(jq -r '[(.steps | length),
      ([.steps[] | select(.status == "fail") | ((.items // []) | length) | if . == 0 then 1 else . end] | add // 0),
      ([.steps[] | select(.status == "error")] | length),
      ((.brew.undeclared // []) | length)] | .[]' "${summary}")}")
  local checks="${stats[1]}" problems=$(( stats[2] + stats[3] )) undeclared_count="${stats[4]}"
  local error_reasons transient run_undeclared
  error_reasons="$(jq -c '[.steps[] | select(.status == "error") | .reason] | unique' "${summary}")"
  transient="$(jq -r 'all(.[]; . == "brew_busy" or . == "timed_out")' <<< "${error_reasons}")"
  run_undeclared="$(jq -c '[(.brew.undeclared // [])[] | .kind + "/" + .name]' "${summary}")"

  local action first_seen="" weeks=0 consecutive_errors=0 report_path="" report_sha="" undeclared="${run_undeclared}"
  local hud_message hud_seconds=null hud_open=""
  local -a old_actions=()
  local -a candidates=("${report}")
  if [[ -n "${last_report_path}" && "${last_report_path}" != "${report}" ]]; then candidates+=("${last_report_path}"); fi
  local candidate existing canonical act

  if [[ "${kind}" == error ]]; then consecutive_errors=$(( last_errors + 1 )); fi

  if [[ "${kind}" == pass ]]; then
    action=clear
    hud_message="${CLI_NAME}: verified OK (${checks} checks)"
    hud_seconds=2
    for candidate in "${candidates[@]}"; do
      existing="$(report::_inspect "${candidate}" "${last_sha}")"
      act="$(report::_old_report_action "${existing}" pass true "${fp8}")"
      if [[ -n "${act}" ]]; then old_actions+=("${act}"); fi
    done
  elif [[ "${kind}" == error && "${transient}" == true && "${force}" == false ]] && (( consecutive_errors < 2 )); then
    # A transient error is not a verdict: carry the previous fingerprint and undeclared set untouched.
    action=suppress
    fp="${last_fp}"
    undeclared="${last_undeclared}"
    first_seen="${last_first_seen}"
    weeks="${last_weeks}"
    report_path="${last_report_path}"
    report_sha="${last_sha}"
    hud_message="${CLI_NAME}: check could not run ($(jq -r 'join(", ")' <<< "${error_reasons}")); retrying next week"
    hud_seconds=8
  elif [[ "${fp}" == "${last_fp}" && "${force}" == false ]]; then
    action=unchanged
    first_seen="${last_first_seen:-${today}}"
    weeks=$(( last_weeks + 1 ))
    report_path="${last_report_path}"
    report_sha="${last_sha}"
    hud_message="${CLI_NAME}: still failing since ${first_seen} (${weeks} wk) — Desktop report, or: ${CLI_NAME} verify --force-report"
  else
    action=write
    if [[ "${fp}" == "${last_fp}" ]]; then
      first_seen="${last_first_seen:-${today}}"
      weeks=$(( last_weeks + 1 ))
    else
      first_seen="${today}"
      weeks=1
    fi
    report_path="${report}"
    local collision=false
    for candidate in "${candidates[@]}"; do
      canonical=false
      if [[ "${candidate}" == "${report}" ]]; then canonical=true; fi
      existing="$(report::_inspect "${candidate}" "${last_sha}")"
      act="$(report::_old_report_action "${existing}" write "${canonical}" "${fp8}")"
      if [[ -z "${act}" ]]; then continue; fi
      old_actions+=("${act}")
      if [[ "$(jq -r .action <<< "${act}")" == collision ]]; then collision=true; fi
    done
    if [[ "${collision}" == true ]]; then
      # The collision name gets the same protection as the canonical path: our unedited copy is
      # archived, an edited one renamed aside, anything else left alone and a numbered name used.
      local target="${desktop_dir}/new-machine-FAILED.${fp8}.md" n=2 moved
      while true; do
        moved="$(print -rl -- "${old_actions[@]}" | jq -rs --arg from "${target}" \
                   'any(.[]; .from == $from and (.action == "archive" or .action == "rename_edited"))')"
        if [[ "${moved}" == true ]]; then break; fi
        existing="$(report::_inspect "${target}" "${last_sha}")"
        if [[ "${existing}" == null ]]; then break; fi
        act="$(report::_old_report_action "${existing}" write false "${fp8}")"
        if [[ "$(jq -r .action <<< "${act}")" == leave_foreign ]]; then
          target="${desktop_dir}/new-machine-FAILED.${fp8}.${n}.md"
          (( n++ ))
          continue
        fi
        old_actions+=("${act}")
        break
      done
      report_path="${target}"
    fi
    hud_message="${CLI_NAME}: ${problems} problems — report on Desktop"
    hud_open="file://${report_path}"
  fi

  local old_json='[]'
  if (( ${#old_actions[@]} > 0 )); then old_json="$(print -rl -- "${old_actions[@]}" | jq -cs .)"; fi
  jq -cn --arg kind "${kind}" --arg action "${action}" --arg fp "${fp}" --arg first_seen "${first_seen}" \
         --argjson weeks "${weeks}" --argjson errors "${consecutive_errors}" --arg report_path "${report_path}" \
         --arg report_sha "${report_sha}" --arg previous_date "${previous_date}" --argjson old "${old_json}" \
         --arg hud_message "${hud_message}" --argjson hud_seconds "${hud_seconds}" --arg hud_open "${hud_open}" \
         --argjson undeclared "${undeclared}" --argjson undeclared_count "${undeclared_count}" \
         --argjson problems "${problems}" --argjson checks "${checks}" --argjson error_reasons "${error_reasons}" \
         --argjson force "${force}" --arg status "${run_status}" '
    def nullable: if . == "" then null else . end;
    {kind: $kind, action: $action, status: $status, fingerprint: $fp, first_seen: ($first_seen | nullable),
     weeks_failing: $weeks, consecutive_errors: $errors, report_path: ($report_path | nullable),
     report_sha256: ($report_sha | nullable), previous_date: ($previous_date | nullable), old_reports: $old,
     hud: {message: $hud_message, seconds: $hud_seconds, open: ($hud_open | nullable)},
     brew_undeclared: $undeclared, undeclared_count: $undeclared_count, problems: $problems, checks: $checks,
     error_reasons: $error_reasons, force: $force}'
}

report::write() {
  local summary="${1}" log="${2}" decision="${3}"
  if [[ ! -f "${decision}" ]]; then
    print -u2 -r -- "report::write: decision file missing | path='${decision}'"
    return 64
  fi
  local state_dir="${ARI_DOTFILES_STATE_DIR}"
  mkdir -p "${state_dir}/reports"

  local action kind fp first_seen weeks report_path report_sha previous run_id ts run_status errors undeclared
  action="$(jq -r .action "${decision}")"
  kind="$(jq -r .kind "${decision}")"
  fp="$(jq -r .fingerprint "${decision}")"
  first_seen="$(jq -r '.first_seen // ""' "${decision}")"
  weeks="$(jq -r .weeks_failing "${decision}")"
  report_path="$(jq -r '.report_path // ""' "${decision}")"
  report_sha="$(jq -r '.report_sha256 // ""' "${decision}")"
  previous="$(jq -r '.previous_date // ""' "${decision}")"
  errors="$(jq -r .consecutive_errors "${decision}")"
  undeclared="$(jq -c .brew_undeclared "${decision}")"
  run_id="$(jq -r '.run_id // "unknown"' "${summary}")"
  ts="$(jq -r '.ts // ""' "${summary}")"
  run_status="$(jq -r '.status // ""' "${summary}")"

  local report_result=none old_action from to
  local -a olds
  olds=("${(@f)$(jq -c '.old_reports[]' "${decision}")}")
  local old
  for old in "${olds[@]}"; do
    if [[ -z "${old}" ]]; then continue; fi
    old_action="$(jq -r .action <<< "${old}")"
    from="$(jq -r .from <<< "${old}")"
    to="$(jq -r '.to // ""' <<< "${old}")"
    case "${old_action}" in
      archive)
        mkdir -p "${to:h}"
        mv -f "${from}" "${to}"
        note "archived report | from='${from}' to='${to}'"
        if [[ "${action}" == clear ]]; then report_result=archived; fi ;;
      rename_edited)
        mv -f "${from}" "${to}"
        note "moved edited report aside | from='${from}' to='${to}'" ;;
      leave_edited)
        note "left edited report | path='${from}'"
        if [[ "${action}" == clear ]]; then report_result=left_edited; fi ;;
      leave_foreign)
        note "left foreign file at report path | path='${from}'" ;;
      collision)
        note "foreign file at report path, writing beside it | path='${from}' report='${to}'" ;;
    esac
  done

  case "${action}" in
    write)
      local archive
      archive="$(report::_free_path "${state_dir}/reports/$(report::_today)-${fp[1,8]}.md")"
      local -a render_args=(-k "${kind}" -s "${first_seen}" -w "${weeks}" -o "${report_path}")
      if [[ -n "${previous}" ]]; then render_args+=(-p "${previous}"); fi
      report::render "${summary}" "${log}" "${render_args[@]}" > "${archive}.tmp"
      mv -f "${archive}.tmp" "${archive}"
      mkdir -p "${report_path:h}"
      if [[ -e "${report_path}" ]]; then
        # decide moved everything it found at this path aside; whatever appeared since is not ours to overwrite.
        local beside
        beside="$(report::_free_path "${report_path}")"
        note "file appeared at the report path since the decision; writing beside it | path='${report_path}' report='${beside}'"
        report_path="${beside}"
      fi
      cp "${archive}" "${report_path}"
      report_sha="$(shasum -a 256 "${report_path}" | cut -d' ' -f1)"
      note "report written | path='${report_path}' archive='${archive}'"
      report_result=written ;;
    unchanged) report_result=unchanged ;;
    clear) print -r -- "run_id='${run_id}' ts='${ts}'" > "${state_dir}/last-ok" ;;
    suppress) ;;
    *) print -u2 -r -- "report::write: unknown action '${action}'"; return 1 ;;
  esac

  local last_file="${state_dir}/last_result.json"
  jq -n --arg run_id "${run_id}" --arg ts "${ts}" --arg status "${run_status}" --arg fp "${fp}" \
        --arg first_seen "${first_seen}" --argjson weeks "${weeks}" --arg report_path "${report_path}" \
        --arg sha "${report_sha}" --argjson errors "${errors}" --argjson undeclared "${undeclared}" '
    def nullable: if . == "" then null else . end;
    {schema: 1, run_id: $run_id, ts: $ts, status: $status, fingerprint: $fp, first_seen: ($first_seen | nullable),
     weeks_failing: $weeks, report_path: ($report_path | nullable), report_sha256: ($sha | nullable),
     consecutive_errors: $errors, brew_undeclared: $undeclared}' > "${last_file}.tmp"
  mv -f "${last_file}.tmp" "${last_file}"

  jq -c --arg report "${report_result}" --slurpfile lr "${last_file}" '. + {report: $report, last_result: $lr[0]}' "${decision}"
}
