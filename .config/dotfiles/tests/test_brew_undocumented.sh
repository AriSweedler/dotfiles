#!/usr/bin/env bash
# decree::undocumented, the Brewfile doc rule as a pure line scan: an entry is documented by a
# trailing `# why` or by a heading comment opening its paragraph; a commented-out entry is no
# heading, the decree marker never counts, and an ignore entry needs a non-empty `# reason`.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
MARKER="# ── decreed via 'new-machine brew decree'; move into a section when tidying ──"

# gaps KIND FILE: the scan's reply, one `<line>\t<kind:name>` per gap, as OUT.
gaps() { zfn decree.zsh eval "decree::undocumented '$1' '$2'; print -rl -- \"\${reply[@]}\""; }
T=$'\t'

BREWFILE="${FIX}/Brewfile"
cat > "${BREWFILE}" <<EOF
# Unix essentials
brew "awk"
cask "font", args: { appdir: "~/#Apps" }

# brew "ffmpeg"
brew "fd"
brew "bat"  # cat with wings
cask "quoted", args: { appdir: "~/#Apps" }
cask "quoted-why", args: { appdir: "~/#Apps" }  # why
tap "x/y", trusted: true  # feeds y
tap "x/z", trusted: true
brew "hash" #
brew 'single'  ## two hashes, then text

#
brew "empty-heading"

  # an indented heading
  brew "indented"
${MARKER}
brew "in-block"
brew "in-block-why"  # because

# a heading inside the decree block is re-sorted away by the next decree
brew "in-block-headed"
EOF
gaps Brewfile "${BREWFILE}"
assert_eq "scan exits 0" 0 "${RC}"
assert_eq "every gap by line, and only the gaps" \
"6${T}formula:fd
8${T}cask:quoted
11${T}tap:x/z
12${T}formula:hash
16${T}formula:empty-heading
21${T}formula:in-block
25${T}formula:in-block-headed" "${OUT}"
assert_not_contains "a heading documents its paragraph" "${OUT}" "formula:awk"
assert_not_contains "a '#' inside a quoted string is no comment, but a later one is" "${OUT}" "quoted-why"
assert_not_contains "tap \"x\", trusted: true  # why is documented" "${OUT}" "tap:x/y"
assert_not_contains "single quotes, two hashes" "${OUT}" "formula:single"
assert_not_contains "an indented heading still heads its paragraph" "${OUT}" "formula:indented"

# The marker opens no paragraph of its own: an entry right under it needs its comment.
printf '%s\n' "# header" "" "${MARKER}" 'brew "a"' > "${BREWFILE}"
gaps Brewfile "${BREWFILE}"
assert_eq "the marker is no heading" "4${T}formula:a" "${OUT}"

gaps Brewfile "${FIX}/no-such-Brewfile"
assert_eq "a missing file has no gaps" "" "${OUT}"

IGNORE="${FIX}/Brewfile.ignore"
printf '%s\n' \
  '# Installed here on purpose. One entry per line:' \
  '#   include-declared <abs path>  # a comment line is no entry' \
  'formula libtiff   # library' \
  'cask zoom' \
  'tap a/b  #' \
  'formula wget  #   ' \
  'include-declared /x/Brewfile   # another tool owns these' \
  'include-declared /y/Brewfile' \
  "${MARKER}" \
  'vscode golang.go  # editor' > "${IGNORE}"
gaps Brewfile.ignore "${IGNORE}"
assert_eq "an ignore entry needs a non-empty reason" \
"4${T}cask:zoom
5${T}tap:a/b
6${T}formula:wget
8${T}include-declared:/y/Brewfile" "${OUT}"

report
