# macOS defaults every machine gets (was ~/.config/macos.sh). nix-darwin's system.defaults
# writes every key and restarts the Dock on every switch; this writes a key only when its value
# differs and restarts the Dock or Finder only when one of its keys changed, in one script run
# as the user.
{ lib, pkgs, user, ... }:
let
  prefs = {
    "com.apple.finder" = {
      FXEnableExtensionChangeWarning = false; # no warning when changing a file extension
      ShowPathbar = true;
      _FXShowPosixPathInTitle = true; # full POSIX path as the window title
    };
    "com.apple.dock" = {
      mineffect = "suck";
      minimize-to-application = true; # minimize windows into their application's icon
      show-process-indicators = true; # indicator lights for open applications
      showhidden = true; # hidden applications' icons translucent
      mru-spaces = false; # don't rearrange Spaces by most recent use
      orientation = "left";
      no-bouncing = true; # stop Dock icons bouncing
    };
  };
  # The process that reads each domain's keys only at its start.
  restart = {
    "com.apple.finder" = "Finder";
    "com.apple.dock" = "Dock";
  };

  # What `defaults read` prints for the value, and the `defaults write` arguments that set it.
  shown = v: if v == true then "1" else if v == false then "0" else toString v;
  written = v:
    if builtins.isBool v then "-bool ${lib.boolToString v}"
    else if builtins.isInt v then "-int ${toString v}"
    else "-string ${lib.escapeShellArg v}";

  domain = name: keys: ''
    changed=
    ${lib.concatStrings (lib.mapAttrsToList (key: v: ''
      if [ "$(defaults read ${name} ${key} 2>/dev/null)" != ${lib.escapeShellArg (shown v)} ]; then
        defaults write ${name} ${key} ${written v}
        changed=1
      fi
    '') keys)}
    if [ -n "$changed" ]; then
      echo >&2 "restarting ${restart.${name}}..."
      killall -q ${restart.${name}} || true
    fi
  '';

  script = pkgs.writeShellScript "macos-defaults"
    (lib.concatStrings (lib.mapAttrsToList domain prefs));
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo >&2 "macOS defaults..."
    launchctl asuser "$(id -u -- ${user})" sudo --user=${user} -- ${script}
  '';
}
