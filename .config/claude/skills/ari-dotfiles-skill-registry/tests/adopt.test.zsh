#!/usr/bin/env zsh
# Automated tests for bin/adopt, each case in a throwaway HOME whose two tiers are real git repos reached
# through `git df` and `git ldf` aliases, so the moves and the staging are the real ones.
# Cases: a dry run moves nothing; an adoption moves the directory into the tier, links it back and stages
# it, uncommitted; adopting again is a no-op; --as renames; and every refusal (not a skill, the destination
# taken, the new name taken, --as with two skills, a tier that ignores the skills root, a skill linked to
# the other tier) leaves the skill exactly where it was. A skill the .gitignore names is adopted when named.
# Run: zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/tests/adopt.test.zsh
set -uo pipefail

readonly SKILL_DIR="${0:A:h:h}"
readonly ADOPT="${SKILL_DIR}/bin/adopt"
readonly T="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/adopt-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "${T}"' EXIT

typeset -i pass=0 fail=0
check() {   # <name> <want> <got>
  if [[ "${2}" == "${3}" ]]; then pass=$(( pass + 1 )); print -r -- "ok      ${1}"; return 0; fi
  fail=$(( fail + 1 )); print -r -- "FAIL    ${1} | want='${2}' got='${3}'"
}
contains() {   # <name> <needle> <haystack>
  if [[ "${3}" == *"${2}"* ]]; then pass=$(( pass + 1 )); print -r -- "ok      ${1}"; return 0; fi
  fail=$(( fail + 1 )); print -r -- "FAIL    ${1} | needle='${2}' in='${3}'"
}
is() { eval "[[ ${1} ]]" && print yes || print no; }

#######################################
# A fresh HOME: ~/dotfiles (the shared tier, a clone) and ~/.local (the local tier) as git repos, the
# skill farm with the shared logging libs linked in, and df/ldf aliases into the two repos.
# Globals: H (the new HOME)
#######################################
new_home() {
  H="${T}/${1}"
  mkdir -p "${H}/.claude/skills" "${H}/dotfiles/.config/claude/skills" "${H}/.local/share/claude-skills"
  git init -q "${H}/dotfiles"; git init -q "${H}/.local"
  ln -s "${SKILL_DIR:h}/ari-skill-shellscripts" "${H}/.claude/skills/ari-skill-shellscripts"
  {
    print -r -- "[alias]"
    print -r -- "	df = !git -C ${H}/dotfiles"
    print -r -- "	ldf = !git -C ${H}/.local"
    print -r -- "[user]"
    print -r -- "	name = t"
    print -r -- "	email = t@example.com"
  } > "${H}/gitconfig"
}
mk_skill() { mkdir -p "${1}"; print -r -- "---" > "${1}/SKILL.md"; print -r -- "body" > "${1}/notes.md"; }

typeset -g out="" err="" rc=0
adopt() {
  rc=0
  out="$(env -u DRY_RUN -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DF_GIT_DIR -u ARI_DOTFILES_DEV_REPOS \
    HOME="${H}" GIT_CONFIG_GLOBAL="${H}/gitconfig" GIT_CONFIG_NOSYSTEM=1 zsh "${ADOPT}" "$@" 2>"${T}/err")" || rc=$?
  err="$(<"${T}/err")"
}
staged() { git -C "${1}" diff --cached --name-only | tr '\n' ' '; }
untouched() {   # <case name> <skill dir>: the real directory is still there, with its files
  check "${1}: the skill is left where it was" "yes yes" "$(is "-d ${2} && ! -L ${2}") $(is "-f ${2}/notes.md")"
}

# 1. Dry run, then the adoption, then a second adoption.
new_home adopt
mk_skill "${H}/.claude/skills/my-skill"
adopt --skill my-skill --tier df
check "dry run: exit 0" 0 "${rc}"
contains "dry run: the row says so" "skill=my-skill tier=df" "${out}"
contains "dry run: dry_run=1" "dry_run=1" "${out}"
untouched "dry run" "${H}/.claude/skills/my-skill"
check "dry run: nothing staged" "" "$(staged "${H}/dotfiles")"

adopt --skill my-skill --tier df --execute
check "adopt: exit 0" 0 "${rc}"
check "adopt: the directory is in the shared tier" "yes" "$(is "-f ${H}/dotfiles/.config/claude/skills/my-skill/notes.md")"
check "adopt: the farm entry is a symlink into it" "${H}/dotfiles/.config/claude/skills/my-skill" "$(readlink "${H}/.claude/skills/my-skill")"
check "adopt: both files staged" ".config/claude/skills/my-skill/SKILL.md .config/claude/skills/my-skill/notes.md " "$(staged "${H}/dotfiles")"
check "adopt: nothing committed" "" "$(git -C "${H}/dotfiles" log --oneline 2>/dev/null)"
contains "adopt: names the commit to make" "git df commit -m" "${err}"

adopt --skill my-skill --tier df --execute
check "again: exit 0" 0 "${rc}"
contains "again: already adopted" "already adopted | skill='my-skill' tier='df'" "${err}"
contains "again: adopted nothing" "adopted='0'" "${err}"

# 2. The local tier, and --as.
mk_skill "${H}/.claude/skills/old-name"
adopt --skill old-name --tier ldf --as new-name --execute
check "--as: exit 0" 0 "${rc}"
check "--as: moved under the new name in the local tier" "yes" "$(is "-f ${H}/.local/share/claude-skills/new-name/SKILL.md")"
check "--as: linked under the new name" "${H}/.local/share/claude-skills/new-name" "$(readlink "${H}/.claude/skills/new-name")"
check "--as: the old name is gone from the farm" "no" "$(is "-e ${H}/.claude/skills/old-name")"
check "--as: staged in the local tier" "share/claude-skills/new-name/SKILL.md share/claude-skills/new-name/notes.md " "$(staged "${H}/.local")"

# 3. Refusals.
mkdir -p "${H}/.claude/skills/not-a-skill"; print -r -- "body" > "${H}/.claude/skills/not-a-skill/notes.md"
adopt --skill not-a-skill --tier df --execute
check "no SKILL.md: refused" 1 "${rc}"
contains "no SKILL.md: says why" "not a skill | skill='not-a-skill'" "${err}"
untouched "no SKILL.md" "${H}/.claude/skills/not-a-skill"

mk_skill "${H}/.claude/skills/taken"; mkdir -p "${H}/dotfiles/.config/claude/skills/taken-elsewhere"
adopt --skill taken --tier df --as taken-elsewhere --execute
check "destination exists: refused" 1 "${rc}"
untouched "destination exists" "${H}/.claude/skills/taken"

mk_skill "${H}/.claude/skills/other"
adopt --skill taken --tier df --as other --execute
check "new name taken in the farm: refused" 1 "${rc}"
contains "new name taken: says so" "new name already taken | dest='other'" "${err}"
untouched "new name taken" "${H}/.claude/skills/taken"

adopt --skill taken --skill other --tier df --as both --execute
check "--as with two skills: refused" 1 "${rc}"

adopt --skill taken --tier attic --execute
check "an unknown tier: refused" 1 "${rc}"
untouched "an unknown tier" "${H}/.claude/skills/taken"

new_home ignoring
mk_skill "${H}/.claude/skills/local-only"
mkdir -p "${H}/.local/.git/info"; print -r -- '*' > "${H}/.local/.git/info/exclude"      # the ldf allowlist without !/share/claude-skills/
adopt --skill local-only --tier ldf --execute
check "a tier that ignores the skills root: refused" 1 "${rc}"
contains "it names the allowlist fix" "add !/share/claude-skills/ to the ldf allowlist" "${err}"
untouched "a tier that ignores the skills root" "${H}/.claude/skills/local-only"

new_home cross
mk_skill "${H}/.local/share/claude-skills/in-ldf"; ln -s "${H}/.local/share/claude-skills/in-ldf" "${H}/.claude/skills/in-ldf"
adopt --skill in-ldf --tier df --execute
check "a skill linked to the other tier: refused" 1 "${rc}"
contains "it names its state" "state='linked' tier='ldf'" "${err}"
check "it stays in the local tier" "yes" "$(is "-f ${H}/.local/share/claude-skills/in-ldf/notes.md")"

# 4. Naming a skill the .gitignore lists is the override.
new_home ignored
mk_skill "${H}/.claude/skills/downloaded"; print -r -- 'downloaded' > "${H}/.claude/skills/.gitignore"
adopt --skill downloaded --tier df --execute
check "a .gitignore'd skill named on the command line is adopted" 0 "${rc}"
check "it is in the shared tier" "yes" "$(is "-f ${H}/dotfiles/.config/claude/skills/downloaded/SKILL.md")"

print -r -- "summary  pass=${pass} fail=${fail}"
(( fail == 0 ))
