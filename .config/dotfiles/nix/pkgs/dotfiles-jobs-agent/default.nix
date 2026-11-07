# The dotfiles jobs agent (agent.c), built for nix-darwin's launchd.user.agents.dotfiles-jobs.
{ stdenv }:
stdenv.mkDerivation {
  pname = "dotfiles-jobs-agent";
  version = "1";
  src = ./agent.c;
  dontUnpack = true;
  buildPhase = ''
    $CC -O2 -Wall -Wextra -Werror -framework CoreFoundation -o dotfiles-jobs-agent $src
  '';
  installPhase = ''
    install -Dm755 dotfiles-jobs-agent $out/bin/dotfiles-jobs-agent
  '';
}
