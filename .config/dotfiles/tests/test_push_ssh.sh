#!/usr/bin/env bash
# `dotfiles push` follows the remote: a personal repo whose origin is GitHub over ssh pushes to
# origin over ssh, with no credential helper and no gh token, once `ssh -T git@github.com` names
# ARI_DOTFILES_GITHUB_LOGIN; every other personal repo pushes over https by token, which must
# belong to that login. Here ssh is a shim: `-T` answers as GitHub does with the login in
# ${FIX}/ssh-login, and a git transport call is served from a local bare repo. gh is a shim
# whose token and `api user` login come from files. No push reaches the network.
set -u
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PUSH_ZSH="${ORIG_CONFIG_DIR}/dotfiles/cmd/push.zsh"

# pz SCRIPT [ARG…]: the kernel plus cmd/push.zsh in the hermetic environment, then SCRIPT (zsh)
# with ARGs as its positional parameters; captures OUT, ERR, RC.
pz() {
  local script="$1"; shift
  hermetic_env
  RC=0
  env -i "${HERMETIC_ENV[@]}" "${FIX}/tools/zsh" -c 'for f in "$1"/*.zsh(N); do source "${f}"; done; source "$2"; s="$3"; shift 3; eval "${s}"' _ \
    "${ORIG_CONFIG_DIR}/dotfiles/lib" "${PUSH_ZSH}" "${script}" "$@" > "${FIX}/pz.out" 2> "${FIX}/pz.err" || RC=$?
  OUT="$(cat "${FIX}/pz.out")"
  ERR="$(cat "${FIX}/pz.err")"
}
# push_one REPO: push_begin then push_wait, as push_submodules runs them; OUT is the rows, then
# the repo's push log.
push_one() {
  pz 'local -a PUSH_ROWS=(); local rc=0; push_begin "$1" && push_wait "$1" || rc=$?; print -rl -- "${PUSH_ROWS[@]}"; cat "$(log_file "$1")" 2>/dev/null; return ${rc}' "$1"
}

world_new
seed_fake_repos

LOGIN="$(zsh -f -c 'source "$1"; print -r -- "${ARI_DOTFILES_GITHUB_LOGIN}"' _ "${TESTS_DIR}/../lib/env.zsh")"

cat > "${FIX}/shims/ssh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "${BREW_SHIM_LOG_DIR}/ssh.log"
for a in "\$@"; do
  if [ "\$a" = -T ]; then
    if [ -s "${FIX}/ssh-login" ]; then
      printf "Hi %s! You've successfully authenticated, but GitHub does not provide shell access.\n" "\$(cat "${FIX}/ssh-login")" >&2
    else
      printf 'git@github.com: Permission denied (publickey).\n' >&2
      exit 255
    fi
    exit 1
  fi
done
for last in "\$@"; do :; done
verb="\${last%% *}"
repo="\${last#* }"; repo="\${repo#\\'}"; repo="\${repo%\\'}"; repo="\${repo#/}"
exec git "\${verb#git-}" "${FIX}/remotes/\${repo}"
EOF
cat > "${FIX}/shims/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "${BREW_SHIM_LOG_DIR}/gh.log"
case "\$*" in
  *"auth token"*) [ -s "${FIX}/gh-token" ] || exit 1; cat "${FIX}/gh-token" ;;
  *"api user"*)   [ -s "${FIX}/gh-login" ] || exit 1; cat "${FIX}/gh-login" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${FIX}/shims/ssh" "${FIX}/shims/gh"

# new_repo PATH ORIGIN: a checkout at HOME/PATH on main, one commit ahead of its bare remote
# ${FIX}/remotes/test/<name>.git (where the ssh shim serves test/<name>.git), origin set to ORIGIN.
new_repo() {
  local dir="${HOME}/$1" bare="${FIX}/remotes/test/${1##*/}.git"
  git init -q --initial-branch=main "${dir}"
  printf 'one\n' > "${dir}/a" && git -C "${dir}" add a && git -C "${dir}" commit -q -m one
  git init -q --bare --initial-branch=main "${bare}"
  git -C "${dir}" push -q "${bare}" main
  git -C "${dir}" fetch -q "${bare}" main:refs/remotes/origin/main
  git -C "${dir}" remote add origin "$2"
  printf 'two\n' >> "${dir}/a" && git -C "${dir}" commit -q -am two
}
say() { if [[ -n "$1" ]]; then printf '%s\n' "$1" > "${FIX}/ssh-login"; else : > "${FIX}/ssh-login"; fi; }

# ── An ssh origin, ssh authenticates as the login: pushed over ssh, no token ─

new_repo .config/viassh git@github.com:test/viassh.git
say "${LOGIN}"; : > "${FIX}/gh-token"
shim_logs_reset
push_one .config/viassh
HEAD="$(git -C "${HOME}/.config/viassh" rev-parse HEAD)"
assert_eq "ssh: rc 0" 0 "${RC}"
assert_contains "ssh: the row" "${OUT}" ".config/viassh	pushed	${HEAD}"
assert_eq "ssh: the remote has the commit" "${HEAD}" "$(git --git-dir="${FIX}/remotes/test/viassh.git" rev-parse main)"
assert_contains "ssh: asked ssh whom it authenticates as" "$(shim_log ssh)" "-T"
assert_contains "ssh: the push went to origin over ssh" "$(shim_log ssh)" "git-receive-pack 'test/viassh.git'"
assert_eq "ssh: gh never asked (no token)" "" "$(shim_log gh)"
assert_contains "ssh: says it skips the token" "${ERR}" "ssh origin, no token needed | repo='.config/viassh' login='${LOGIN}'"
assert_contains "ssh: the log names the transport" "${OUT}" "url='git@github.com:test/viassh.git' as='${LOGIN} by ssh'"
assert_not_contains "ssh: no https url" "${OUT}" "https://github.com"
assert_eq "ssh: the tracking ref follows" "${HEAD}" "$(git -C "${HOME}/.config/viassh" rev-parse refs/remotes/origin/main)"

# ── ssh:// form, and a pushurl wins over an https fetch url ──────────────────

new_repo .config/sshform https://github.com/test/sshform.git
git -C "${HOME}/.config/sshform" remote set-url --push origin ssh://git@github.com/test/sshform.git
shim_logs_reset
push_one .config/sshform
assert_eq "ssh:// pushurl: rc 0" 0 "${RC}"
assert_eq "ssh:// pushurl: the remote has the commit" "$(git -C "${HOME}/.config/sshform" rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/test/sshform.git" rev-parse main)"
assert_eq "ssh:// pushurl: gh never asked" "" "$(shim_log gh)"

# An https origin that git's insteadOf sends to ssh (what the local tier sets on co2) is followed.
new_repo .config/rewritten https://github.com/test/rewritten.git
git -C "${HOME}/.config/rewritten" config url.git@github.com:.insteadOf https://github.com/
shim_logs_reset
push_one .config/rewritten
assert_eq "insteadOf to ssh: rc 0" 0 "${RC}"
assert_eq "insteadOf to ssh: the remote has the commit" "$(git -C "${HOME}/.config/rewritten" rev-parse HEAD)" "$(git --git-dir="${FIX}/remotes/test/rewritten.git" rev-parse main)"
assert_eq "insteadOf to ssh: gh never asked" "" "$(shim_log gh)"

# ── ssh authenticates as someone else: the token path, which refuses ────────

new_repo .config/other git@github.com:test/other.git
say someone-else; : > "${FIX}/gh-token"
shim_logs_reset
push_one .config/other
assert_eq "ssh as another login: rc 1" 1 "${RC}"
assert_contains "ssh as another login: says so" "${ERR}" "ssh does not authenticate as the login; ssh origins push by token | login='${LOGIN}' ssh_login='someone-else'"
assert_contains "ssh as another login: falls back to the token" "$(shim_log gh)" "auth token -u ${LOGIN}"
assert_contains "ssh as another login: no token, no push" "${OUT}" ".config/other	failed (token)"
assert_not_contains "ssh as another login: nothing pushed over ssh" "$(shim_log ssh)" "git-receive-pack"

# ── ssh names nobody (no key): the token path too ────────────────────────────

say ""
shim_logs_reset
push_one .config/other
assert_eq "ssh denied: rc 1" 1 "${RC}"
assert_contains "ssh denied: ssh_login is none" "${ERR}" "ssh_login='-'"
assert_contains "ssh denied: falls back to the token" "${ERR}" "Personal account is not logged into gh"

# ── An https origin: by token, never asks ssh; a foreign token is refused ────

new_repo .config/viahttps https://github.com/test/viahttps.git
say "${LOGIN}"
printf 'tok-123\n' > "${FIX}/gh-token"; printf 'work-account\n' > "${FIX}/gh-login"
shim_logs_reset
push_one .config/viahttps
assert_eq "https, foreign token: rc 1" 1 "${RC}"
assert_contains "https, foreign token: refused" "${ERR}" "Token identity mismatch | expected='${LOGIN}' got='work-account'"
assert_eq "https: ssh never asked" "" "$(shim_log ssh)"

# The personal token: push_repo goes to the https url with the one-shot helper. git itself is
# stood in for at the push (repo_git), so nothing leaves the machine.
printf '%s\n' "${LOGIN}" > "${FIX}/gh-login"
shim_logs_reset
pz 'repo_git() {
    if [[ " $* " == *" push "* ]]; then
      print -r -- "$*" >> "'"${FIX}"'/git-push.log"
      print -r -- "To https://github.com/test/viahttps.git"; print -r -- " "$'"'"'\t'"'"'"refs/heads/main:refs/heads/main"$'"'"'\t'"'"'"aaa..bbb"; print -r -- Done; return 0
    fi
    local repo="$1"; shift; git -C "${ARI_DOTFILES_DF_WORK_TREE}/${repo}" "$@"
  }
  local -a PUSH_ROWS=(); local rc=0; push_begin "$1" && push_wait "$1" || rc=$?; print -rl -- "${PUSH_ROWS[@]}"; cat "$(log_file "$1")"; return ${rc}' .config/viahttps
assert_eq "https, personal token: rc 0" 0 "${RC}"
assert_contains "https, personal token: verified" "${ERR}" "pushing as | login='${LOGIN}' identity='verified'"
PUSHED="$(cat "${FIX}/git-push.log")"
assert_contains "https, personal token: to the https url" "${PUSHED}" "push --porcelain https://github.com/test/viahttps.git refs/heads/main:refs/heads/main"
assert_contains "https, personal token: with the one-shot credential helper" "${PUSHED}" "-c credential.helper= -c credential.helper=!f()"
assert_contains "https, personal token: the log names the login" "${OUT}" "url='https://github.com/test/viahttps.git' as='${LOGIN}' "
assert_eq "https, personal token: ssh never asked" "" "$(shim_log ssh)"

# ── A dry run: no network, the transport is named ────────────────────────────

shim_logs_reset
ARI_DOTFILES_DRY_RUN=1 pz 'local -a PUSH_ROWS=(); push_begin .config/viassh; push_begin .config/viahttps'
assert_contains "dry run: an ssh origin keeps its url, transport undecided" "${ERR}" "repo='.config/viassh' branch='main'"
assert_contains "dry run: ssh or token" "${ERR}" "url='git@github.com:test/viassh.git' transport='ssh or token'"
assert_contains "dry run: an https origin is token" "${ERR}" "url='https://github.com/test/viahttps.git' transport='token'"
assert_eq "dry run: ssh not called" "" "$(shim_log ssh)"
assert_eq "dry run: gh not called" "" "$(shim_log gh)"

report
