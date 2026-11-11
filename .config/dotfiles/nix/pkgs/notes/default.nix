# notes: open or initialize today's daily note under NOTE_BASE (~/Desktop/notes). Built from the
# commit the shared flake reads; ari-bins.nix places it at ~/.config/bin/notes, where the dotfiles
# CLI, tmuxinator and the skills call it.
{ stdenvNoCC, zsh, git, ari_zshlib, src }:
stdenvNoCC.mkDerivation {
  pname = "notes";
  version = "0";
  # .config is a dot directory, which the unpacker skips: read it in place instead.
  dontUnpack = true;
  buildInputs = [ zsh ];
  installPhase = ''
    runHook preInstall
    install -Dm755 -t $out/bin ${src}/.config/bin/notes
    patchShebangs $out/bin
    ${ari_zshlib.pin [ "$out/bin/notes" ]}
    runHook postInstall
  '';

  # It loads the store library and resolves today's path in a scratch notes dir. git and nvim
  # come from PATH at run time (home.nix installs both); the check stubs nvim.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ git ];
  installCheckPhase = ''
    export HOME=$TMPDIR NOTE_BASE=$TMPDIR/notes
    # notes commits when it initializes the scratch repo; the sandbox has no git identity.
    export GIT_AUTHOR_NAME=check GIT_AUTHOR_EMAIL=check@example.invalid GIT_COMMITTER_NAME=check GIT_COMMITTER_EMAIL=check@example.invalid
    mkdir -p $TMPDIR/stub && printf '#!/bin/sh\n' > $TMPDIR/stub/nvim && chmod +x $TMPDIR/stub/nvim
    export PATH=$TMPDIR/stub:$PATH
    $out/bin/notes --help >/dev/null
    [[ "$($out/bin/notes path)" == $TMPDIR/notes/*/*/*.md ]]
  '';

  meta.mainProgram = "notes";
}
