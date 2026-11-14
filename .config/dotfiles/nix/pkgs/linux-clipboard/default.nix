# pbcopy, pbpaste, clip-hist and xclip for Linux (clipboard.sh has the design). Installed only
# off a Mac (home.nix): there the real pbcopy and Raycast do this.
{ writeShellApplication, symlinkJoin, coreutils, diffutils, findutils, fzf }:
let
  command = name: writeShellApplication {
    inherit name;
    # tmux comes from the caller's PATH: clip-hist must talk to the server it was run from.
    runtimeInputs = [ coreutils diffutils findutils fzf ];
    text = builtins.readFile ./clipboard.sh;
  };
in
symlinkJoin {
  name = "linux-clipboard-0";
  paths = map command [ "pbcopy" "pbpaste" "clip-hist" "xclip" ];
  nativeBuildInputs = [ diffutils ];
  # The install check: the OSC 52 bytes for a short copy, plain and wrapped for tmux, and xclip
  # reading back what it copied.
  postBuild = ''
    export CLIPBOARD_DIR=$TMPDIR/clip CLIPBOARD_TTY=$TMPDIR/tty
    unset TMUX

    printf 'hi' | $out/bin/pbcopy
    printf '\e]52;c;aGk=\a' > $TMPDIR/want
    cmp $TMPDIR/want $CLIPBOARD_TTY
    [[ "$($out/bin/pbpaste)" == hi ]]

    printf 'hi' | TMUX=/tmp/tmux-1/default,1,0 $out/bin/pbcopy
    printf '\ePtmux;\e\e]52;c;aGk=\a\e\\' > $TMPDIR/want
    cmp $TMPDIR/want $CLIPBOARD_TTY

    printf 'from gh\n' | $out/bin/xclip -selection clipboard
    [[ "$($out/bin/xclip -o -selection clipboard)" == 'from gh' ]]
    printf 'a\n' | $out/bin/xclip -r -in -sel clipboard
    [[ "$($out/bin/pbpaste | od -An -c | tr -d ' ')" == a ]]

    # Past the cap the copy reaches only the files.
    : > $CLIPBOARD_TTY
    head -c 90000 /dev/zero | tr '\0' x | $out/bin/pbcopy
    [[ ! -s $CLIPBOARD_TTY ]]
    [[ "$($out/bin/pbpaste | wc -c)" -eq 90000 ]]
  '';
}
