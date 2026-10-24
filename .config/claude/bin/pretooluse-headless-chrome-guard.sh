#!/usr/bin/env zsh
#
# Claude Code PreToolUse hook (matcher: Bash). Refuses a headless launch of the
# installed Chrome.app, which steals the user's focus twice per launch: opening
# a page activates the running Chrome, and about 6 s in the instance asks
# LaunchServices to set the https handler, which CoreServicesUIAgent answers by
# ordering its windows front (measured 2026-09-23). Points at
# ~/.config/bin/chrome-headless, whose header has the details.
#
# Exit 2 blocks the tool call and feeds stderr back to Claude; exit 0 lets it
# through. The hook's JSON arrives on stdin and is matched as raw text, so no
# process is spawned; settings.json also gates it with `if` so it only runs
# when the command mentions --headless at all.

set -u

main() {
  local input=""
  IFS= read -r -d '' input || true
  [[ "${input}" == *--headless* ]] || return 0

  # The JSON doubles backslashes, so a shell-escaped "Google\ Chrome" arrives as
  # "Google\\ Chrome"; (\\\\)? in these single-quoted regexes matches that.
  # Only the installed channels count (Chrome, Canary, Beta, Dev): Playwright's
  # "Google Chrome for Testing.app" is a separate bundle and is the fix, not the
  # problem. Both the bare binary and `open -a "Google Chrome" … --args --headless`
  # are refused.
  local chrome_bin='Google(\\\\)? Chrome((\\\\)? (Canary|Beta|Dev))?\.app/Contents/MacOS/Google(\\\\)? Chrome'
  local open_chrome='open [^;&|]*-a [^;&|]*Google(\\\\)? Chrome'
  local for_testing='Google(\\\\)? Chrome(\\\\)? for(\\\\)? Testing'
  local blocked=0
  if [[ "${input}" =~ ${chrome_bin} ]]; then
    blocked=1
  elif [[ "${input}" =~ ${open_chrome} ]] && ! [[ "${input}" =~ ${for_testing} ]]; then
    blocked=1
  fi
  if (( blocked )); then
    cat >&2 <<'MSG'
Blocked: launching /Applications/Google Chrome.app headless steals the user's focus (opening a page activates the running Chrome; ~6 s later CoreServicesUIAgent comes to the front), and its --dump-dom hangs. Use the wrapper with the same Chromium flags:
  chrome-headless --dump-dom <url>            # chrome-headless-shell (default): DOM dumps, screenshots; exits cleanly
  chrome-headless --full <flags>              # Google Chrome for Testing: whole browser, CDP, extensions
  chrome-headless --which                     # print the binary it would use
Both are Playwright's browsers under ~/Library/Caches/ms-playwright and never touch the running Chrome. `open -a "Google Chrome"` headless is refused for the same reason.
MSG
    return 2
  fi
  return 0
}

main "$@"
