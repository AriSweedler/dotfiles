# mac-utils: Ari's small macOS bins, built from the commit the shared flake reads and placed by
# ari-bins.nix where the clone's copies were linked (~/.config/bin). The Swift ones are compiled
# here, once per build, instead of on first run: applelink was a `#!/usr/bin/env swift` script
# (interpreted on every call) and pbpastelinks compiled its extractor through swift-run.
#
# A bin's own plugin (open_link, open_any, json_sort, colors) ships in share/zsh/plugins with
# log.zsh beside it, since those plugins source log.zsh from their own directory.
{ lib, swiftPackages, swift, makeWrapper, zsh, bash, python3, imagemagick, jq, ari_zshlib, src }:
let
  zshBins = [ "open-link" "open-any" "pbpastelinks" "json-sort" "notif-center" "yubitap" "probe-color" "probe-emoji" "chrome-headless" ];
  otherBins = [ "applepaste" "utc-date" "replace" "favicon-maker" "karabiner-list-keyboards" ];
  plugins = [ "open_link" "open_any" "json_sort" "colors" ];
in
swiftPackages.stdenv.mkDerivation {
  pname = "mac-utils";
  version = "0";
  # .config is a dot directory, which the unpacker skips: read it in place instead.
  dontUnpack = true;
  nativeBuildInputs = [ swift makeWrapper ];
  buildInputs = [ zsh bash python3 ];

  buildPhase = ''
    runHook preBuild
    # swiftc reads a file without the .swift suffix as an object file.
    cp ${src}/.config/bin/applelink applelink.swift
    swiftc -O -o applelink applelink.swift
    swiftc -O -o pbpastelinks-extract ${src}/.config/bin/pbpastelinks-extract.swift
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin applelink
    install -Dm755 -t $out/libexec pbpastelinks-extract
    for b in ${lib.escapeShellArgs (zshBins ++ otherBins)}; do
      install -Dm755 ${src}/.config/bin/$b $out/bin/$b
    done
    for p in ${lib.escapeShellArgs plugins}; do
      install -Dm644 ${src}/.config/zsh/plugins/$p.zsh $out/share/zsh/plugins/$p.zsh
    done
    ln -s ${ari_zshlib}/lib/log.zsh $out/share/zsh/plugins/log.zsh
    patchShebangs $out/bin
    ${ari_zshlib.pin (map (b: "$out/bin/${b}") (zshBins ++ [ "replace" ]))}
    ${ari_zshlib.pinPlugins (map (b: "$out/bin/${b}") zshBins)}
    substituteInPlace $out/bin/pbpastelinks \
      --replace-fail '"''${PBPASTELINKS_EXTRACT_BIN:-}"' "\''${PBPASTELINKS_EXTRACT_BIN:-$out/libexec/pbpastelinks-extract}"
    # favicon-maker shells out to ImageMagick's convert; sips and iconutil are macOS's.
    wrapProgram $out/bin/favicon-maker --suffix PATH : ${lib.makeBinPath [ imagemagick ]}
    # json-sort's plugin runs jq.
    wrapProgram $out/bin/json-sort --suffix PATH : ${lib.makeBinPath [ jq ]}
    runHook postInstall
  '';

  # Every zsh bin loads its store libraries: none names a live path any more, and the ones with
  # a pure mode answer.
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME=$TMPDIR
    if grep -lE '\.config/zsh/plugins/(log|open_link|open_any|json_sort|colors)\.zsh|bash/plugins/' $out/bin/*; then
      echo "a bin still names a live library path"; exit 1
    fi
    [[ "$(echo '{"b":1,"a":2}' | $out/bin/json-sort)" == *'"a"'*'"b"'* ]]
    $out/bin/utc-date >/dev/null
  '';
}
