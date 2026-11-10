# dotfiles-cli: the `dotfiles` CLI from the commit the shared flake reads. $out mirrors the slice
# of .config the CLI loads relative to itself (bin/dotfiles finds dotfiles/lib two levels up,
# and lib/env.zsh reads the zsh plugins and new-machine beside it), so the store copy runs as the
# clone's does. ari-bins.nix places bin/dotfiles at ~/.config/bin/dotfiles.
#
# The editable sources stay in the clone: ARI_DOTFILES_SRC (the edit verbs' targets, the tests)
# defaults to ~/dotfiles/.config/dotfiles here. The job plugins (dotfiles/jobs) stay linked files
# the jobs framework discovers. An edit reaches the store copy at the next `dotfiles switch`; run
# ~/dotfiles/.config/bin/dotfiles to try it first.
{ lib, stdenvNoCC, zsh, src }:
let
  srcDefault = "\${ARI_DOTFILES_SRC:-\${ARI_DOTFILES_ROOT}}";
in
stdenvNoCC.mkDerivation {
  pname = "dotfiles-cli";
  version = "0";
  # .config is a dot directory, which the unpacker skips: read it in place instead.
  dontUnpack = true;
  buildInputs = [ zsh ];
  installPhase = ''
    runHook preInstall
    cd ${src}/.config
    install -Dm755 -t $out/bin bin/dotfiles
    mkdir -p $out/dotfiles $out/zsh/plugins
    cp -R dotfiles/cmd dotfiles/lib dotfiles/steps dotfiles/assets $out/dotfiles/
    cp -R new-machine $out/new-machine
    for f in zsh/plugins/*.zsh; do
      [[ $f == *.test.zsh ]] || install -Dm644 $f $out/zsh/plugins/''${f##*/}
    done
    cp -R zsh/plugins/assets $out/zsh/plugins/assets
    chmod -R u+w $out
    patchShebangs $out/bin
    substituteInPlace $out/dotfiles/lib/env.zsh \
      --replace-fail ${lib.escapeShellArg srcDefault} '${"$"}{ARI_DOTFILES_SRC:-${"$"}{HOME}/dotfiles/.config/dotfiles}'
    runHook postInstall
  '';

  # The store copy loads every module and answers help.
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME=$TMPDIR
    $out/bin/dotfiles help >/dev/null
    $out/bin/dotfiles steps >/dev/null
  '';

  meta.mainProgram = "dotfiles";
}
