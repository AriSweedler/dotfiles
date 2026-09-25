# step ssh_key — the GitHub ssh key is in the agent. The local tier names it: a 1Password item
# holding the key's "Absolute path" and "password" fields, and the path spelled out, exported as
# ARI_DOTFILES_SSH_KEY_{OP_ITEM,OP_VAULT,PATH} by ~/.local/share/zsh/plugins/dotfiles.zsh. A
# machine without them skips. The check never calls 1Password: with the path known, "loaded" is
# one ssh-add -l. The apply feeds the passphrase to ssh-add through an askpass helper that runs
# op: never argv, never the clipboard.
step::declare ssh_key --group repo \
  --desc "the GitHub ssh key the local tier names is in the agent (passphrase from 1Password)"

ssh_key::path() { print -r -- "${ARI_DOTFILES_SSH_KEY_PATH/#\~/${HOME}}"; }

# ssh-add -l exits 2 when no agent answers (1 = an agent with no identities).
ssh_key::is_agent_reachable() {
  local rc=0
  ssh-add -l >/dev/null 2>&1 || rc=$?
  (( rc != 2 ))
}

# True (0) when the agent holds the key at the given path, by fingerprint.
ssh_key::is_loaded() {
  local fingerprint
  fingerprint="$(ssh-keygen -lf "${1}" 2>/dev/null | awk '{print $2}')"
  [[ -n "${fingerprint}" ]] && ssh-add -l 2>/dev/null | awk '{print $2}' | grep -qxF "${fingerprint}"
}

check::ssh_key() {
  local item="${ARI_DOTFILES_SSH_KEY_OP_ITEM}" key
  if [[ -z "${item}" ]]; then
    verdict skip not_configured -d "ARI_DOTFILES_SSH_KEY_OP_ITEM unset; the local tier exports it when this machine has a key to load"
    return 0
  fi
  key="$(ssh_key::path)"
  if [[ -z "${key}" ]]; then
    verdict warn path_unknown -m -d "ARI_DOTFILES_SSH_KEY_PATH unset: telling whether the key is loaded would take a 1Password call | item='${item}'" \
      -f "export ARI_DOTFILES_SSH_KEY_PATH beside ARI_DOTFILES_SSH_KEY_OP_ITEM in the local tier"
    return 0
  fi
  if [[ ! -f "${key}" ]]; then
    verdict fail key_file_missing -m -d "key file missing | path='${key}' item='${item}'" -f "put the key at ${key}, or fix ARI_DOTFILES_SSH_KEY_PATH"
    return 0
  fi
  if ! ssh_key::is_agent_reachable; then
    verdict error agent_unreachable -d "no ssh-agent answers | SSH_AUTH_SOCK='${SSH_AUTH_SOCK:-}'"
    return 0
  fi
  if ssh_key::is_loaded "${key}"; then
    verdict ok loaded -d "path='${key}'"
    return 0
  fi
  if ! command -v op >/dev/null 2>&1; then
    verdict fail op_missing -m -d "key not in the agent and the 1Password CLI is missing | path='${key}'" -f "brew install 1password-cli, then ${CLI_NAME} apply ssh_key"
    return 0
  fi
  verdict fail not_loaded -d "key not in the agent | path='${key}' item='${item}'" -f "${CLI_NAME} apply ssh_key"
}

apply::ssh_key() {
  local item="${ARI_DOTFILES_SSH_KEY_OP_ITEM}" key askpass
  local -a vault_flag=()
  [[ -n "${ARI_DOTFILES_SSH_KEY_OP_VAULT}" ]] && vault_flag=(--vault "${ARI_DOTFILES_SSH_KEY_OP_VAULT}")
  key="$(ssh_key::path)"
  if [[ -z "${key}" ]]; then log::err "ARI_DOTFILES_SSH_KEY_PATH unset; the local tier exports it | item='${item}'"; return 1; fi
  if [[ ! -f "${key}" ]]; then log::err "ssh key file missing | path='${key}' item='${item}'"; return 1; fi
  if ssh_key::is_loaded "${key}"; then log::info "ssh key already in the agent | path='${key}'"; return 0; fi
  if is_dry_run; then log::info "dry-run, would ssh-add with the passphrase from 1Password | path='${key}' item='${item}'"; return 0; fi
  askpass="$(mktemp)"
  trap 'rm -f "${askpass}"' EXIT
  {
    print -r -- '#!/usr/bin/env zsh'
    print -r -- "exec op item get ${(q)item} ${(q)vault_flag[@]} --fields password --reveal"
  } > "${askpass}"
  chmod 700 "${askpass}"
  DISPLAY=1 SSH_ASKPASS="${askpass}" SSH_ASKPASS_REQUIRE=force ssh-add "${key}" </dev/null
  log::info "ssh key loaded | path='${key}'"
}
