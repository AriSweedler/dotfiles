#!/usr/bin/env zsh
# Automated tests for bin/adopt, each case in a throwaway HOME whose two tiers are real git repos reached
# through `git df` and `git ldf` aliases, so the moves and the staging are the real ones.
# Cases: a dry run moves nothing; an adoption moves the directory into the tier, links it back and stages
# it, uncommitted; adopting again is a no-op; --as renames; and every refusal (not a skill, the destination
# taken, the new name taken, --as with two skills, a tier that ignores the skills root, a skill linked to
# the other tier) leaves the skill exactly where it was. A skill the .gitignore names is adopted when named.
# A refusal in a batch moves none of it; an unreachable tier repo is refused. On a clone machine a local
# adoption lands in local/<machine>/ and ldf-link gives ~/.local its per-file links (its preview in a dry
# run); a machine the machines file lacks is refused; a farm link into those links reads linked with
# via=ldf-link and `link --execute` retargets it; one with no clone directory behind it reads dangling.
# Run: zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/tests/adopt.test.zsh
set -uo pipefail

readonly SKILL_DIR="${0:A:h:h}"
readonly ADOPT="${SKILL_DIR}/bin/adopt"
readonly STATUS_BIN="${SKILL_DIR}/bin/status"
readonly LINK_BIN="${SKILL_DIR}/bin/link"
readonly LDF_LINK="${HOME}/.config/bin/ldf-link"
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
    -u ARI_DOTFILES_LDF_GIT_DIR -u ARI_DOTFILES_LDF_WORK_TREE -u ARI_DOTFILES_MACHINE -u ARI_DOTFILES_MACHINE_NAME_FILE \
    -u LDF_REPO -u LDF_TARGET HOME="${H}" GIT_CONFIG_GLOBAL="${H}/gitconfig" GIT_CONFIG_NOSYSTEM=1 zsh "${ADOPT}" "$@" 2>"${T}/err")" || rc=$?
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
contains "dry run: the rerun keeps the arguments" "--skill my-skill --tier df --execute" "${err}"
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

mk_skill "${H}/.claude/skills/fine"
adopt --skill fine --skill not-a-skill --tier df --execute
check "a batch with one refusal: refused" 1 "${rc}"
contains "a batch with one refusal: says nothing moved" "nothing moved | refused='1'" "${err}"
untouched "a batch with one refusal" "${H}/.claude/skills/fine"

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

new_home no-alias
mk_skill "${H}/.claude/skills/stranded"
sed -i.bak '/ldf = /d' "${H}/gitconfig"
adopt --skill stranded --tier ldf --execute
check "an unreachable tier repo: refused" 1 "${rc}"
contains "an unreachable tier repo: says so" "tier repo unreachable | tier='ldf'" "${err}"
untouched "an unreachable tier repo" "${H}/.claude/skills/stranded"

# 4. Naming a skill the .gitignore lists is the override.
new_home ignored
mk_skill "${H}/.claude/skills/downloaded"; print -r -- 'downloaded' > "${H}/.claude/skills/.gitignore"
adopt --skill downloaded --tier df --execute
check "a .gitignore'd skill named on the command line is adopted" 0 "${rc}"
check "it is in the shared tier" "yes" "$(is "-f ${H}/dotfiles/.config/claude/skills/downloaded/SKILL.md")"

# 5. The local-dotfiles clone layout: the local tier is ~/local-dotfiles/local/<machine>/, which
# ldf-link assembles into ~/.local as per-file links.
new_home clone
rm -rf "${H}/.local/.git"
git init -q "${H}/local-dotfiles"
print -r -- "testbox mac" > "${H}/local-dotfiles/machines"
mkdir -p "${H}/.local/share/dotfiles" "${H}/.config/bin"; print -r -- "testbox" > "${H}/.local/share/dotfiles/machine-name"
sed -i.bak "s|ldf = !git -C ${H}/.local|ldf = !git -C ${H}/local-dotfiles|" "${H}/gitconfig"
if [[ -x "${LDF_LINK}" ]]; then
  ln -s "${LDF_LINK}" "${H}/.config/bin/ldf-link"
else
  print -r -- "skip    clone: no ldf-link at ${LDF_LINK}; the assembly checks run without it"
fi
readonly CLONE_ROOT="${H}/local-dotfiles/local/testbox/share/claude-skills"
mk_skill "${H}/.claude/skills/clone-skill"
if [[ -x "${LDF_LINK}" ]]; then
  adopt --skill clone-skill --tier ldf
  check "clone dry run: exit 0" 0 "${rc}"
  contains "clone dry run: shows ldf-link's preview" "ldf-link preview" "${err}"
  untouched "clone dry run" "${H}/.claude/skills/clone-skill"
fi
adopt --skill clone-skill --tier ldf --execute
check "clone: exit 0" 0 "${rc}"
check "clone: moved into local/<machine>/ in the clone" "yes" "$(is "-f ${CLONE_ROOT}/clone-skill/notes.md")"
check "clone: the farm links the clone's directory" "${CLONE_ROOT}/clone-skill" "$(readlink "${H}/.claude/skills/clone-skill")"
check "clone: staged in the clone" "local/testbox/share/claude-skills/clone-skill/SKILL.md local/testbox/share/claude-skills/clone-skill/notes.md " "$(staged "${H}/local-dotfiles")"
contains "clone: the row names the clone path" "path=${CLONE_ROOT}/clone-skill" "${out}"
if [[ -x "${LDF_LINK}" ]]; then
  check "clone: ldf-link linked each file into ~/.local" "${CLONE_ROOT}/clone-skill/SKILL.md" "$(readlink "${H}/.local/share/claude-skills/clone-skill/SKILL.md")"
fi
status_rows="$(env -u ARI_DOTFILES_LDF_GIT_DIR -u ARI_DOTFILES_LDF_WORK_TREE -u ARI_DOTFILES_MACHINE -u ARI_DOTFILES_MACHINE_NAME_FILE \
  -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DF_GIT_DIR -u ARI_DOTFILES_DEV_REPOS HOME="${H}" zsh "${STATUS_BIN}" --all 2>/dev/null)"
contains "clone: status reads the adopted skill as linked" "state=linked tier=ldf name=clone-skill" "${status_rows}"

# A skill linked before the move: the farm names ~/.local/share/claude-skills/<name>, a real directory
# of per-file links into the clone.
mk_skill "${CLONE_ROOT}/old-link"
mkdir -p "${H}/.local/share/claude-skills/old-link"
ln -s "${CLONE_ROOT}/old-link/SKILL.md" "${H}/.local/share/claude-skills/old-link/SKILL.md"
ln -s "${H}/.local/share/claude-skills/old-link" "${H}/.claude/skills/old-link"
# ~/.local/share/claude-skills/<name> with nothing in the clone behind it is not a local skill.
mkdir -p "${H}/.local/share/claude-skills/orphan"
ln -s "${H}/.local/share/claude-skills/orphan" "${H}/.claude/skills/orphan"
status_rows="$(env -u ARI_DOTFILES_LDF_GIT_DIR -u ARI_DOTFILES_LDF_WORK_TREE -u ARI_DOTFILES_MACHINE -u ARI_DOTFILES_MACHINE_NAME_FILE \
  -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DF_GIT_DIR -u ARI_DOTFILES_DEV_REPOS HOME="${H}" zsh "${STATUS_BIN}" --all 2>/dev/null)"
contains "clone: a farm link into ldf-link's per-file links is linked, marked" "state=linked tier=ldf name=old-link via=ldf-link" "${status_rows}"
contains "clone: one with no clone directory behind it is dangling" "state=dangling tier=- name=orphan" "${status_rows}"
link_out="$(env -u DRY_RUN -u ARI_DOTFILES_LDF_GIT_DIR -u ARI_DOTFILES_LDF_WORK_TREE -u ARI_DOTFILES_MACHINE -u ARI_DOTFILES_MACHINE_NAME_FILE \
  -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DF_GIT_DIR -u ARI_DOTFILES_DEV_REPOS HOME="${H}" zsh "${LINK_BIN}" --prune --execute 2>/dev/null)"
contains "clone link: retargets the marked link" "retargeted=1" "${link_out}"
check "clone link: it now names the clone's directory" "${CLONE_ROOT}/old-link" "$(readlink "${H}/.claude/skills/old-link")"
check "clone link: prunes the dangling one" "no" "$(is "-L ${H}/.claude/skills/orphan")"
link_out="$(env -u DRY_RUN -u ARI_DOTFILES_LDF_GIT_DIR -u ARI_DOTFILES_LDF_WORK_TREE -u ARI_DOTFILES_MACHINE -u ARI_DOTFILES_MACHINE_NAME_FILE \
  -u ARI_DOTFILES_DF_WORK_TREE -u ARI_DOTFILES_DF_GIT_DIR -u ARI_DOTFILES_DEV_REPOS HOME="${H}" zsh "${LINK_BIN}" --prune --execute 2>/dev/null)"
check "clone link: a second run changes nothing" "linked=0 retargeted=0 pruned=0" "$(print -r -- "${link_out}" | awk -F= '/^(linked|retargeted|pruned)=/{printf "%s%s", (n++ ? " " : ""), $0}')"

# A clone that ignores the skills root: the hint names the rule, not the bare repo's allowlist.
mk_skill "${H}/.claude/skills/ignored-here"
print -r -- "local/" > "${H}/local-dotfiles/.gitignore"
adopt --skill ignored-here --tier ldf --execute
check "clone ignoring: refused" 1 "${rc}"
contains "clone ignoring: names the rule" "make /local/testbox/share/claude-skills/ tracked: the rule .gitignore:1:local/ ignores it" "${err}"
check "clone ignoring: no allowlist hint" "no" "$( [[ "${err}" == *allowlist* ]] && print yes || print no )"
untouched "clone ignoring" "${H}/.claude/skills/ignored-here"

rm "${H}/local-dotfiles/.gitignore"

# A machine name the clone's machines file lacks would stage the skill where no machine links it.
print -r -- "renamed" > "${H}/.local/share/dotfiles/machine-name"
mk_skill "${H}/.claude/skills/phantom"
adopt --skill phantom --tier ldf --execute
check "unknown machine: refused" 1 "${rc}"
contains "unknown machine: names it and the file" "machine not in the clone's machines file | machine='renamed'" "${err}"
untouched "unknown machine" "${H}/.claude/skills/phantom"
check "unknown machine: no local/<name>/ made" "no" "$(is "-e ${H}/local-dotfiles/local/renamed")"

print -r -- "summary  pass=${pass} fail=${fail}"
(( fail == 0 ))
