# run-log: run_log (a command's stdout and stderr captured byte for byte, each on its own pty,
# into a capture dir an agent reads back), its capture engine run_log-capture.py, irun (a
# command in an interactive zsh) and strip-ansi (with the strip_ansi plugin it wraps). Built
# from the commit the shared flake reads; ari-bins.nix places the bins at ~/.config/bin, where
# /ari-driving and remote hosts expect run_log. An edit in the clone reaches them at the next
# `dotfiles switch`; run the clone's file directly to try it first.
{ lib, stdenvNoCC, zsh, python3, ari_zshlib, src }:
stdenvNoCC.mkDerivation {
  pname = "run-log";
  version = "0";
  # .config is a dot directory, which the unpacker skips: read it in place instead.
  dontUnpack = true;
  buildInputs = [ zsh python3 ];
  installPhase = ''
    runHook preInstall
    cd ${src}/.config
    install -Dm755 -t $out/bin bin/run_log bin/run_log-capture.py bin/irun bin/strip-ansi
    install -Dm644 -t $out/share/zsh/plugins zsh/plugins/strip_ansi.zsh
    install -Dm644 -t $out/share/run-log claude/lib/tmux-pane.sh
    patchShebangs $out/bin
    ${ari_zshlib.pin [ "$out/bin/run_log" ]}
    substituteInPlace $out/bin/run_log \
      --replace-fail '"''${XDG_CONFIG_HOME:-$HOME/.config}/claude/lib/tmux-pane.sh"' "$out/share/run-log/tmux-pane.sh" \
      --replace-fail 'python3 -I "''${CAPTURE_HELPER}"' '${python3}/bin/python3 -I "''${CAPTURE_HELPER}"'
    ${ari_zshlib.pinPlugins [ "$out/bin/strip-ansi" ]}
    runHook postInstall
  '';

  # A capture of a plain command lands, holds its output and its exit code.
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME=$TMPDIR ZDOTDIR=$TMPDIR
    $out/bin/run_log --dir $TMPDIR/caps --no-copy -- echo hello >/dev/null
    grep -qx hello $TMPDIR/caps/*/stdout.plain
    grep -qx exit=0 $TMPDIR/caps/*/metadata
    [[ "$(printf '\033[31mred\033[0m' | $out/bin/strip-ansi)" == red ]]
  '';

  meta.mainProgram = "run_log";
}
