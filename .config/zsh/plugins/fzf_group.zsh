# fzf_group.zsh — the fzf options every group picker shares.
#
# A group picker lists one group's leaves under a "<group>/ " prompt: tmux-oneshot's
# second level, go-link's go/ list. Every such picker has the same contract, and its
# header states it, so the picker documents itself and no picker spells it out:
#   esc        back one level. fzf exits FZF_GROUP_BACK_RC; the caller reopens whatever
#              opened it, and a command that exits the same code is treated alike.
#   alt-enter  the typed name verbatim. fzf's print-query exits with only the query
#              line, so the caller acts on what was typed, never on the highlighted row.
# Enter keeps fzf's default (the highlighted row) and needs no explaining.
#
# Usage:
#   fzf_group::args go
#   out="$(fzf "${reply[@]}" ...)"
# reply carries --prompt, --header, --print-query and the alt-enter bind. The first
# output line is the query; a one-line output means no row was picked.

typeset -g FZF_GROUP_BACK_RC=130

function fzf_group::args() {
  local group="${1:?group name}"
  reply=(
    "--prompt=${group}/ "
    "--header=${group}/   esc: back   alt-enter: typed name verbatim"
    --print-query
    --bind=alt-enter:print-query
  )
}
