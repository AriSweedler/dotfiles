# plugged, the Rust CLI and dashboard, built from the shared flake's plugged input: the checkout's
# HEAD at a `dotfiles switch` (it overrides the input with ~/dotfiles/.config/plugged), the locked
# commit otherwise. bin/plugged-dev keeps the edit-and-run loop. The crates are the ones the
# repo's Cargo.lock pins, fetched by their checksums.
{ rustPlatform, src }:
rustPlatform.buildRustPackage {
  pname = "plugged";
  version = "0";
  inherit src;
  cargoLock.lockFile = "${src}/Cargo.lock";
}
