# Chrome's manifest for the Chrome Exoskeleton's native messaging host, which writes
# ~/.local/state/chrome-exoskeleton/installed-version each time the extension starts. The host
# and the manifest's shape are the dev repo's (native-host/package.nix); this module supplies the
# extension IDs the manifest allows.
#
# The framework's manifest.json carries a `key`, so Chrome derives the extension ID from the key,
# not from the load path: every build (dist, dist-personal, link path or resolved path) has the
# same ID, and Chrome refuses a second card with it. The ID below is that key's. An input locked
# before the repo had the host places nothing.
{ config, lib, pkgs, src, devInputs, ... }:
let
  hasHost = builtins.pathExists "${devInputs.chrome-exoskeleton}/native-host/package.nix";
  host = (import ./pkgs { inherit pkgs src devInputs; }).chrome-exoskeleton-native-host;
  origins = [ "chrome-extension://jlmloooodpmalocmdeaidemlajfljemd/" ];
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  home.file = lib.optionalAttrs hasHost {
    "Library/Application Support/Google/Chrome/NativeMessagingHosts/${host.hostName}.json".text =
      builtins.toJSON (host.manifest origins);
  };
}
