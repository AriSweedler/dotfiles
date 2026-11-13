# bd (beads), the tracker Ari and his Claude sessions file work in. nixpkgs has `beads`, but at
# 1.0.3, and the workflow is written against 1.3.4, so this takes upstream's own release instead of
# the package: one asset per system, each hash from the release's checksums.txt. Bumping the
# version means four hashes, which is the price of not waiting for nixpkgs.
# The binaries are generic builds, so off a Mac autoPatchelfHook supplies the glibc they ask for;
# a Mac's needs no such fix. The trackers are state in Ari's home, never in a package.
{ lib, stdenv, fetchurl, autoPatchelfHook }:
let
  version = "1.3.4";
  assets = {
    x86_64-linux = { platform = "linux_amd64"; hash = "sha256-F1wmkEveP/kWjSKC/2tW8XsX9gwi+lrLPazJ+zRlMDo="; };
    aarch64-linux = { platform = "linux_arm64"; hash = "sha256-9O5us+x5uy1+udcXxz77y2+nY8xw9ya00FW3Kv3WitU="; };
    x86_64-darwin = { platform = "darwin_amd64"; hash = "sha256-BecTotqO6rpAuSQYRzXZo00tqGaeTTrFDMcWYFuhBkA="; };
    aarch64-darwin = { platform = "darwin_arm64"; hash = "sha256-sIqcFb/4DEIjXzKUb5SmVmp9kJRP6K/kXz/S81BZbNs="; };
  };
  asset =
    assets.${stdenv.hostPlatform.system}
      or (throw "beads: upstream publishes no asset for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "beads";
  inherit version;

  src = fetchurl {
    url = "https://github.com/gastownhall/beads/releases/download/v${version}/beads_${version}_${asset.platform}.tar.gz";
    inherit (asset) hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  # The tarball is flat: bd beside its README, LICENSE and CHANGELOG.
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 bd $out/bin/bd
    runHook postInstall
  '';

  meta = {
    description = "Dependency-aware issue tracker for AI coding agents";
    homepage = "https://github.com/gastownhall/beads";
    platforms = builtins.attrNames assets;
    mainProgram = "bd";
  };
}
