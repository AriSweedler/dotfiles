#!/usr/bin/env bash
# The personal tier's Claude Code settings serve macOS and NixOS from one file, so no hook command
# may name a home directory: each says $HOME. Claude Code expands $HOME when it rewrites the file,
# and accepting that rewrite breaks every hook on a machine whose home differs.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SETTINGS="${ORIG_CONFIG_DIR}/dotfiles/nix/personal/claude-settings.json"

# Every hook command in the settings on stdin that names an absolute home directory, one per line.
home_paths() {
  jq -r '[.hooks[]?[]?.hooks[]?.command] | .[] | select(test("/Users/|/home/"))'
}

assert_file "the settings file exists" "${SETTINGS}"
assert_eq "the settings file is JSON" 0 "$(jq -e . "${SETTINGS}" > /dev/null; echo $?)"
assert_eq "no hook command names a home directory" "" "$(home_paths < "${SETTINGS}")"
# shellcheck disable=SC2016  # the literal $HOME, as the settings file spells it
assert_contains "the guard hook says \$HOME" \
  "$(jq -r '.hooks.PreToolUse[].hooks[].command' "${SETTINGS}")" \
  '$HOME/.config/claude/bin/pretooluse-headless-chrome-guard.sh'

# The $HOME commands work under any home: a stand-in home laid out as home-manager lays out a real
# one (~/.config/claude linked whole to the clone, ~/.claude/skills/* linked to the tier's skills),
# and each command run through /bin/sh, as Claude Code runs a hook.
CLONE="$(cd "${ORIG_CONFIG_DIR}/.." && pwd)"
FAKE_HOME="$(mktemp -d "${TMPDIR:-/tmp}/claude-settings-home.XXXXXX")" || abort "mktemp failed"
trap 'rm -rf "${FAKE_HOME}"' EXIT
mkdir -p "${FAKE_HOME}/.config" "${FAKE_HOME}/.claude"
ln -s "${CLONE}/.config/claude" "${FAKE_HOME}/.config/claude"
ln -s "${CLONE}/.config/claude/skills" "${FAKE_HOME}/.claude/skills"

# The script a hook command runs once /bin/sh expands it: its first absolute word.
hook_script() {
  # shellcheck disable=SC2016  # expanded by the inner sh, under the stand-in HOME
  HOME="${FAKE_HOME}" /bin/sh -c 'set -- '"$1"'; for w; do case "$w" in /*) printf "%s\n" "$w"; exit;; esac; done'
}

while IFS= read -r cmd; do
  script="$(hook_script "${cmd}")"
  assert_contains "${cmd%% --*} expands into the stand-in home" "${script}" "${FAKE_HOME}/"
  assert_file "${cmd%% --*} resolves to a file" "${script}"
done < <(jq -r '.hooks[][].hooks[].command' "${SETTINGS}")

guard="$(jq -r '.hooks.PreToolUse[].hooks[].command' "${SETTINGS}")"
run_guard() {
  jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | HOME="${FAKE_HOME}" /bin/sh -c "${guard}" 2> /dev/null
  echo $?
}
assert_eq "the guard, run as a hook, blocks headless Chrome.app" 2 \
  "$(run_guard 'open -a "Google Chrome" --args --headless')"
assert_eq "the guard, run as a hook, allows everything else" 0 "$(run_guard 'ls --headless')"

# The check itself catches the rewrite Claude Code makes. No world: this suite reads one file and
# runs on any OS.
expanded="$(jq '.hooks.Stop[0].hooks[0].command = "/Users/someone/.config/claude/bin/stop-fire.sh"' "${SETTINGS}")"
assert_eq "an expanded home path is caught" \
  "/Users/someone/.config/claude/bin/stop-fire.sh" "$(home_paths <<< "${expanded}")"

report
