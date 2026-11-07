# Tests for ~/.config/zsh/functions/astound — the invoice parser, on made-up layout text and on real invoices
# Only runs when OTTO_TEST__ZSH_PLUGINS_ASTOUND=true
[[ "$OTTO_TEST__ZSH_PLUGINS_ASTOUND" == "true" ]] || return 0

# The real invoices hold Ari's address and account, so their goldens live in the local tier
# (ASTOUND_GOLDENS, one '<invoice file>\t<tuple>' line each) and the invoices stay where astound
# files them; without the goldens file that half is skipped. The made-up text below is public.

local _pass=0 _fail=0 _skip=0
source "${0:h}/log.zsh"
ASTOUND_DEFINE_ONLY=1 source "${0:A:h:h}/functions/astound"

function _t() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    log::info "PASS: ${name}"
    ((_pass++))
  else
    log::err "FAIL: ${name} | expected='${expected}' actual='${actual}'"
    ((_fail++))
  fi
}

# A statement as pdftotext -layout lays it out: the lines the parser reads, padded like the real one.
function _layout() {
  local statement="$1" period="$2" charge="$3" credit="$4"
  print -r -- "                                                            CITY, ST 00000          Statement Date:          ${statement}"
  [[ -n "$credit" ]] && print -r -- "                 ${period%%-*}                   Paperless Billing/Autopay Credit          ${credit} CR"
  print -r -- "                 ${period} Internet Service                                         ${charge}"
  print -r -- "                             1.0 Gigabit Internet Service"
}

_t "a month with the autopay credit" "11/02/26,12/01/26,40,-10.00" \
  "$(_layout 11/05/2026 11/02-12/01 50.00 -10.00 | astound::_parse_layout)"
_t "no credit: the full charge, an empty credit" "06/02/26,07/01/26,50," \
  "$(_layout 06/05/2026 06/02-07/01 50.00 '' | astound::_parse_layout)"
_t "the year is the statement's" "03/02/27,04/01/27,40,-10.00" \
  "$(_layout 03/05/2027 03/02-04/01 50.00 -10.00 | astound::_parse_layout)"
_t "a period past December ends next year" "12/02/26,01/01/27,40,-10.00" \
  "$(_layout 12/05/2026 12/02-01/01 50.00 -10.00 | astound::_parse_layout)"
astound::_parse_layout <<< "no statement here" > /dev/null
_t "text with no statement fails" 1 "$?"

local goldens="${ASTOUND_GOLDENS:-${XDG_DATA_HOME:-${HOME}/.local/share}/astound/tests/goldens.tsv}"
if [[ ! -f "$goldens" ]]; then
  log::warn "SKIP: real invoices; no goldens | goldens='${goldens}'"
  ((_skip++))
elif ! (( ${+commands[pdftotext]} )); then
  log::err "FAIL: real invoices need pdftotext (poppler-utils in the shared flake)"
  ((_fail++))
else
  local line file want
  for line in "${(@f)$(grep -v '^#' "$goldens")}"; do
    file="${line%%$'\t'*}" want="${line#*$'\t'}"
    _t "invoice ${file}" "$want" "$(astound::_extract_from_pdf "$(astound::dir)/${file}")"
  done
fi

log::info "astound.test.zsh: ${_pass} passed, ${_fail} failed, ${_skip} skipped"
(( _fail == 0 ))
