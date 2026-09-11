# Tests for open_link.zsh. Only --check and url_from are exercised: nothing is opened.
# Only runs when OTTO_TEST__ZSH_PLUGINS_OPEN_LINK=true
[[ "$OTTO_TEST__ZSH_PLUGINS_OPEN_LINK" == "true" ]] || return 0

local _pass=0 _fail=0
source "${HOME}/.config/zsh/plugins/log.zsh"
source "${HOME}/.config/zsh/plugins/open_link.zsh"

function _t() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    log::info "PASS: ${name}"
    ((_pass++))
  else
    log::err "FAIL: ${name}"
    print "  expected: $(print -r -- "$expected" | cat -v)"
    print "  actual:   $(print -r -- "$actual" | cat -v)"
    ((_fail++))
  fi
}

_t "bare URL" "https://example.com/a?b=1" "$(open_link::url_from 'https://example.com/a?b=1')"
_t "URL inside text" "http://x.io/p" "$(open_link::url_from 'see http://x.io/p today')"
_t "mermaid URL split across Claude Code tool lines is joined" "https://mermaid.ink/img/abcdef" \
  "$(open_link::url_from $'● Bash(open https://mermaid.ink/img/abc\n  ⎿  def')"
_t "wrap continues over several indented lines" "https://m.ink/abc" \
  "$(open_link::url_from $'  ⎿  https://m.ink/a\n     b\n     c')"
_t "decorated text still finds a URL that is not wrapped" "https://x.io/one" \
  "$(open_link::url_from $'● Read(file)\n  ⎿  see https://x.io/one now')"
_t "a prose line after the URL is not a continuation" "https://x.io/one" \
  "$(open_link::url_from $'● Bash(echo https://x.io/one\n  ⎿  No content')"
_t "undecorated multi-line text is never joined" "https://a.b" \
  "$(open_link::url_from $'https://a.b\nhello')"
_t "no URL declines" "1" "$(open_link::url_from 'nothing here'; print -- $?)"
_t "empty declines" "1" "$(open_link::url_from ''; print -- $?)"

# ${commands} is writable, so the presence of open-pr can be faked either way.
local _saved_pr="${commands[open-pr]:-}"
commands[open-pr]=/usr/bin/true
_t "github pull URL is ceded when open-pr exists" "1" "$(open_link::url_from 'https://github.com/o/r/pull/12'; print -- $?)"
_t "github non-pull URL is still a link" "https://github.com/o/r/issues/12" "$(open_link::url_from 'https://github.com/o/r/issues/12')"
unset 'commands[open-pr]'
_t "github pull URL is a link when no open-pr exists" "https://github.com/o/r/pull/12" "$(open_link::url_from 'https://github.com/o/r/pull/12')"
[[ -n "${_saved_pr}" ]] && commands[open-pr]="${_saved_pr}"

_t "--check accepts a URL silently" "0:" "$(open_link --check 'https://a.b'; print -n -- "$?:")"
_t "--check declines junk silently" "1:" "$(open_link --check 'junk' 2>/dev/null; print -n -- "$?:")"
_t "--check declines with nothing on stderr" "" "$(open_link --check 'junk' 2>&1)"
_t "open without a URL logs what it saw" "1" "$(open_link 'junk text' 2>&1 | grep -c "No URL found | text='junk text'")"

if (( _fail == 0 )); then
  log::info "open_link: all ${_pass} passed"
else
  log::err "open_link: ${_pass} passed, ${_fail} failed"
  return 1
fi
