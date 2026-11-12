#!/usr/bin/env zsh
#
# Explains terminal-notifier's macOS alert style on this machine: what it is now, what Ari
# wants, and how to get there. The dotfiles healthcheck (step claude_notifications) names this
# script in its detail; an agent setting a machine up runs it and follows what it prints.
# Reads only, unless --open.
#
# Usage:
#   notification-style.sh          the state, Ari's preference and the steps
#   notification-style.sh --open   also open System Settings at the Notifications pane

set -u

readonly BUNDLE='fr.julienxx.oss.terminal-notifier'
# The seam and the flag bits are the same as steps/claude_notifications.zsh's reader
# (step::claude_notifications::allowed); change them together.
readonly PLIST="${ARI_DOTFILES_USERNOTED_PLIST:-${HOME}/Library/Group Containers/group.com.apple.usernoted/Library/Preferences/group.com.apple.usernoted.plist}"
readonly PANE_URL="x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=${BUNDLE}"
readonly SELF="${0:A}"

#######################################
# Prints "<allowed> <style>": allowed is on, off, unregistered (macOS has no entry for the
# bundle yet) or unknown (the prefs file is absent or unreadable); style is persistent,
# temporary, none, or - when there is no entry to read.
#######################################
read_state() {
  [[ -r "${PLIST}" ]] || { print -r -- "unknown -"; return 0; }
  python3 -I - "${PLIST}" "${BUNDLE}" 2>/dev/null <<'PY' || print -r -- "unknown -"
import plistlib, sys
apps = plistlib.load(open(sys.argv[1], "rb")).get("apps", [])
hit = [a for a in apps if a.get("bundle-id") == sys.argv[2]]
if not hit:
    print("unregistered -")
else:
    flags = hit[0].get("flags", 0)
    style = "persistent" if flags >> 4 & 1 else "temporary" if flags >> 3 & 1 else "none"
    print("on" if flags >> 25 & 1 else "off", style)
PY
}

main() {
  local open_pane=false
  case "${1:-}" in
    --open) open_pane=true ;;
    "") ;;
    *) print -u2 -r -- "usage: ${SELF:t} [--open]"; return 64 ;;
  esac

  local allowed style
  read -r allowed style < <(read_state)

  print -r -- "terminal-notifier (${BUNDLE}) on this machine"
  print -r -- "  notifications allowed: ${allowed}"
  print -r -- "  alert style:           ${style}"
  print -r -- "  Ari wants:             allowed on, alert style persistent"
  print

  local verdict
  if [[ "${allowed}" == on && "${style}" == persistent ]]; then
    verdict="Nothing to do: this machine is set the way Ari wants."
  elif [[ "${allowed}" == unregistered ]]; then
    verdict="macOS has not seen terminal-notifier yet. Post one banner first, then set the style:
  ~/.config/claude/bin/notification-fire.sh 'style setup test'
  When macOS asks, Ari allows notifications. Then follow the steps below."
  elif [[ "${allowed}" == unknown ]]; then
    verdict="The state could not be read (${PLIST}). Ask Ari to look at the setting; the steps are below."
  else
    verdict="This machine differs from what Ari wants. Ask Ari to change it; the steps are below."
  fi
  print -r -- "${verdict}"
  print

  cat <<EOF
What the style does
  persistent  a Claude Code banner (a permission prompt, the end of a turn) stays on screen
              until Ari clicks or dismisses it. Older macOS calls this style "Alerts".
  temporary   the banner leaves after a few seconds; it is easy to miss. Older macOS: "Banners".
  none        no banner at all; the notification goes straight to Notification Center.

How to change it (only Ari can; it is a click in System Settings)
  1. Open the pane:  ${SELF} --open
     or by hand: System Settings > Notifications > terminal-notifier.
  2. Turn "Allow notifications" on.
  3. Set the alert style to Persistent.
  4. Check:  ${SELF}      (expect: allowed on, alert style persistent)
             dotfiles healthcheck --only claude_notifications

Why an agent cannot do this
  - macOS does not support writing the notification prefs file; the notification daemon owns it.
  - nix-darwin has no option for a per-app alert style.
  - The one supported declarative route is an MDM profile (payload com.apple.notificationsettings),
    which needs a Mac enrolled in an MDM server. Ari decided on 2026-11-12 not to self-host one
    for this: the style stays a manual toggle per machine, and the healthcheck reports it.
  So: NEVER edit the prefs file, NEVER add a Nix option for it. Hand Ari the steps above as one
  action item and re-run this script after Ari says it is done.
EOF

  if [[ "${open_pane}" == true ]]; then
    /usr/bin/open "${PANE_URL}"
  fi
}

main "$@"
