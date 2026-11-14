#!/usr/bin/env bash
# bin/tmux-tooltip: link puts a --copy text in the URL's copy key; open copies it and leads the hint
# with the outcome; a link without one copies nothing; an https --href link keeps its page's query.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

world_new
TT="${ORIG_CONFIG_DIR}/bin/tmux-tooltip"
# tmux-tooltip sources the shared logging lib through the skills farm.
mkdir -p "${HOME}/.claude/skills"
ln -s "${ORIG_CONFIG_DIR}/claude/skills/ari-skill-shellscripts" "${HOME}/.claude/skills/ari-skill-shellscripts"

# A tmux whose one client is c: it lists c, answers the width and logs each display-menu. A pbcopy
# that keeps what it got.
CLIP="${FIX}/clipboard"
cat > "${FIX}/shims/tmux" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == list-clients ]]; then
  printf 'c\n'
  exit 0
fi
if [[ "\${1:-}" == display-message ]]; then
  case "\$*" in *client_name*) printf '%s\n' "\${4:-c}" ;; *) printf '80\n' ;; esac
  exit 0
fi
printf '%s\n' "\$*" >> "${FIX}/menu.log"
EOF
cat > "${FIX}/shims/pbcopy" <<EOF
#!/usr/bin/env bash
cat > "${CLIP}"
EOF
chmod +x "${FIX}/shims/tmux" "${FIX}/shims/pbcopy"

open_url() { : > "${FIX}/menu.log"; zsh "${TT}" open --url "$1" --client c 2> "${FIX}/err"; }

# ── link --copy: the copy key rides the URL, and printing it copies nothing ──
link="$(zsh "${TT}" link --label beads-o27 --title beads-o27 --text 'Graph view' --copy 'beads-o27 | Graph view' 2>/dev/null)"
assert_contains "link: the copy text is in the copy key" "${link}" "&copy=beads-o27%20%7C%20Graph%20view)"
assert_no_file "link: printing the link copies nothing" "${CLIP}"

# ── open: the click copies the text and the hint says so ──
url="${link#*](}"; url="${url%)}"
open_url "${url}"
assert_eq "open: the clipboard holds the copy text" "beads-o27 | Graph view" "$(cat "${CLIP}" 2>/dev/null)"
assert_contains "open: the card still shows" "$(cat "${FIX}/menu.log")" "display-menu -c c"
assert_contains "open: the hint leads with copied" "$(cat "${FIX}/menu.log")" "copied · click or Esc closes"

# ── an https --href link with --copy: the page's own query stays first, the click copies ──
rm -f "${CLIP}"
link="$(zsh "${TT}" link --label beads-o27 --href 'https://scotty.example.com/p/beads?bead=beads-o27' --title beads-o27 --copy 'beads-o27 | Graph view' 2>/dev/null)"
assert_contains "href: the page and its bead query come first" "${link}" "(https://scotty.example.com/p/beads?bead=beads-o27&tmux-tooltip=show&"
url="${link#*](}"; url="${url%)}"
open_url "${url}"
assert_eq "href: the click copies the text" "beads-o27 | Graph view" "$(cat "${CLIP}" 2>/dev/null)"

# ── a link without --copy: the click copies nothing, the hint is the default ──
rm -f "${CLIP}"
open_url "tmux-tooltip://show?title=beads-o27&text=Graph%20view"
assert_no_file "no copy key: nothing is copied" "${CLIP}"
assert_not_contains "no copy key: the hint does not say copied" "$(cat "${FIX}/menu.log")" "copied"

# ── no pbcopy: nothing is copied, and the hint says why ──
rm -f "${FIX}/shims/pbcopy"
open_url "tmux-tooltip://show?title=x&copy=x"
assert_contains "no pbcopy: the hint says not copied" "$(cat "${FIX}/menu.log")" "not copied: no pbcopy · click or Esc closes"

# ── no tmux client: open stops before the copy ──
cat > "${FIX}/shims/pbcopy" <<EOF
#!/usr/bin/env bash
cat > "${CLIP}"
EOF
chmod +x "${FIX}/shims/pbcopy"
rm -f "${CLIP}"
mv "${FIX}/shims/tmux" "${FIX}/tmux.off"
printf '#!/usr/bin/env bash\nexit 1\n' > "${FIX}/shims/tmux"
chmod +x "${FIX}/shims/tmux"
open_url "tmux-tooltip://show?title=x&copy=x"
assert_eq "no tmux client: open exits 1" 1 "$?"
assert_no_file "no tmux client: nothing is copied" "${CLIP}"
mv "${FIX}/tmux.off" "${FIX}/shims/tmux"

# ── bogus client name: tmux lists only c, so open --client d stops before the copy ──
rm -f "${CLIP}"
zsh "${TT}" open --url "tmux-tooltip://show?title=x&copy=x" --client d 2> "${FIX}/err"
assert_eq "bogus client name: open exits 1" 1 "$?"
assert_no_file "bogus client name: nothing is copied" "${CLIP}"

# ── --copy belongs to link ──
zsh "${TT}" show --title x --copy x 2> /dev/null
assert_eq "show refuses --copy" 1 "$?"

report
