# plugged, the Swift CLI and TUI, built from the shared flake's plugged input: the checkout's HEAD
# at a `dotfiles switch` (it overrides the input with ~/dotfiles/.config/plugged), the locked
# commit otherwise. bin/plugged-dev keeps the edit-and-run loop.
{ swiftPackages, swift, swiftpm, src }:
swiftPackages.stdenv.mkDerivation {
  pname = "plugged";
  version = "0";
  inherit src;
  nativeBuildInputs = [ swift swiftpm ];
  installPhase = ''
    runHook preInstall
    install -Dm755 "$(swiftpmBinPath)/plugged" $out/bin/plugged
    runHook postInstall
  '';
}
