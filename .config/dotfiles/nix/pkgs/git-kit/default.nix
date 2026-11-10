# git-kit: Ari's git bins. git-dotfiles (git's `dotfiles`/`df` alias runs it by path),
# git-health, git-ready, git-delete-if-merged-{all,one}, git-dedupe-case-refs and repo (with the
# double_cd plugin it sources). Built from the commit the shared flake reads; ari-bins.nix places
# each where the clone's copy was linked. The hooks (git/dotfiles-hooks, git/template) stay
# linked files: git runs them by path and they are edited in place.
{ stdenvNoCC, zsh, bash, ari_zshlib, src }:
stdenvNoCC.mkDerivation {
  pname = "git-kit";
  version = "0";
  # .config is a dot directory, which the unpacker skips: read it in place instead.
  dontUnpack = true;
  buildInputs = [ zsh bash ];
  installPhase = ''
    runHook preInstall
    cd ${src}/.config
    install -Dm755 -t $out/bin git/bin/git-dotfiles \
      bin/{git-health,git-ready,git-delete-if-merged-all,git-delete-if-merged-one,git-dedupe-case-refs,repo}
    install -Dm644 -t $out/share/zsh/plugins zsh/plugins/double_cd.zsh
    # git-health reads its notification icon beside itself, and tries atn there first: atn is
    # not in this package, so that lookup goes back to ~/.config/bin.
    install -Dm644 -t $out/bin/assets bin/assets/git-health.png
    patchShebangs $out/bin
    ${ari_zshlib.pin [ "$out/bin/git-health" "$out/bin/git-ready" "$out/bin/git-dedupe-case-refs" "$out/bin/repo" ]}
    ${ari_zshlib.pinPlugins [ "$out/bin/repo" ]}
    substituteInPlace $out/bin/git-health --replace-fail '"''${0:A:h}/atn"' '"''${HOME}/.config/bin/atn"'
    runHook postInstall
  '';

  # Each zsh bin with a --help loads its libraries and answers it (git-ready has none: it acts).
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME=$TMPDIR
    for b in git-health git-dedupe-case-refs repo; do
      $out/bin/$b --help >/dev/null 2>&1 || { echo "$b --help failed"; $out/bin/$b --help; exit 1; }
    done
    ! grep -l '\.config/zsh/plugins/log\.zsh' $out/bin/*
  '';
}
