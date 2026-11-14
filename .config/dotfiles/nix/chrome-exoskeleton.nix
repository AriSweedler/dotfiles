# Chrome's manifest for the Chrome Exoskeleton's native messaging host, which writes
# ~/.local/state/chrome-exoskeleton/installed-version each time the extension starts. The host
# and the manifest's shape are the dev repo's (native-host/package.nix); this module supplies the
# extension IDs the manifest allows.
#
# The extension is loaded unpacked and carries no key, so Chrome derives its ID from the path it
# was loaded from: the first 32 hex digits of the path's SHA-256, each mapped 0-f to a-p. Both
# builds the chrome_exoskeleton step accepts are allowed. A card loaded from the resolved
# ~/dotfiles path has another ID, and Chrome refuses it the host. An input locked before the
# repo had the host places nothing.
{ config, lib, pkgs, src, devInputs, ... }:
let
  hasHost = builtins.pathExists "${devInputs.chrome-exoskeleton}/native-host/package.nix";
  host = (import ./pkgs { inherit pkgs src devInputs; }).chrome-exoskeleton-native-host;
  fw = "${config.home.homeDirectory}/.config/chrome-exoskeleton";
  hex = lib.stringToCharacters "0123456789abcdef";
  idOf = path: builtins.replaceStrings hex (lib.stringToCharacters "abcdefghijklmnop")
    (builtins.substring 0 32 (builtins.hashString "sha256" path));
  origins = map (dist: "chrome-extension://${idOf "${fw}/${dist}"}/") [ "dist" "dist-personal" ];
in
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  home.file = lib.optionalAttrs hasHost {
    "Library/Application Support/Google/Chrome/NativeMessagingHosts/${host.hostName}.json".text =
      builtins.toJSON (host.manifest origins);
  };
}
