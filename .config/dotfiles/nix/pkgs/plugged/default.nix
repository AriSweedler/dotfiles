# plugged, the Swift CLI and TUI in the .config/plugged submodule, built from the commit the
# shared tier's pointer names (the flake input carries submodules). A change lands on PATH once
# the pointer moves and `dotfiles switch` runs; bin/plugged-dev keeps the edit-and-run loop.
{ swiftPackages, swift, swiftpm, src }:
swiftPackages.stdenv.mkDerivation {
  pname = "plugged";
  version = "0";
  src = "${src}/.config/plugged";
  nativeBuildInputs = [ swift swiftpm ];
  installPhase = ''
    runHook preInstall
    install -Dm755 "$(swiftpmBinPath)/plugged" $out/bin/plugged
    runHook postInstall
  '';
}
