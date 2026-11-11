# ari_zshlib, the shared shell library in one store directory, $out/lib: log.zsh (the one
# logging library, with its notification icon), the skill script libs (logging, dry_run, await,
# run_with_timeout, investigation_folder), strip_ansi.zsh, log_rotate.zsh, the fzf group pickers
# (fzf_group.zsh, fzf_groups.zsh), tmux-pane.sh and the bash pair (log, arg). Built from the commit the shared flake reads. The public mirror,
# github.com/AriSweedler/ari-zshlib (the checkout ~/dotfiles/.config/ari-zshlib), holds this same
# lib/ and is what Ari's public tools take as their input.
#
# Only packaged tools use it. A bin reads "${ARI_ZSHLIB:-<the live path>}/<file>", and its
# package's build rewrites that default to this store path (passthru.pin), so the tool is pinned.
# Nothing exports ARI_ZSHLIB, so everything run from the clone (skills, ~/.config/bin) keeps
# reading the live files, edited without a switch: package what you run, link what you edit.
{ lib, stdenvNoCC, src }:
let
  # The live-path defaults scripts spell, each rewritten by pin.
  liveDefaults = [
    "\${ARI_ZSHLIB:-\${HOME}/.config/zsh/plugins}"
    "\${ARI_ZSHLIB:-\${HOME}/.claude/skills/ari-skill-shellscripts/lib}"
    "\${ARI_ZSHLIB:-\${HOME}/.config/bash/plugins}"
  ];
  pluginsDefault = "\${ARI_PLUGINS:-\${HOME}/.config/zsh/plugins}";
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ari-zshlib";
  version = "0";
  # .config is a dot directory, which the unpacker skips: read it in place instead.
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    cd ${src}/.config
    install -Dm644 -t $out/lib zsh/plugins/{log,strip_ansi,log_rotate,fzf_group,fzf_groups}.zsh claude/lib/tmux-pane.sh
    install -Dm644 -t $out/lib/assets zsh/plugins/assets/robot.png
    install -Dm644 -t $out/lib \
      claude/skills/ari-skill-shellscripts/lib/{logging,dry_run,await,run_with_timeout,investigation_folder}.zsh \
      bash/plugins/{log,arg}.bash
    # logging.zsh is a shim over log.zsh: point it at the copy beside it, not ~/.config (the
    # mirror's form, so the two lib/ directories are the same bytes).
    substituteInPlace $out/lib/logging.zsh \
      --replace-fail '"''${XDG_CONFIG_HOME:-''${HOME}/.config}/zsh/plugins/log.zsh"' '"''${''${(%):-%x}:A:h}/log.zsh"   # the copy beside this file'
    runHook postInstall
  '';

  # pin [ FILE … ]: shell lines for a package's postInstall that rewrite each live-path default
  # in FILE to this store copy. The "${ARI_ZSHLIB:-" stays, so a test can still point a packaged
  # script at a fixture library.
  passthru.pin = files: lib.concatMapStrings
    (f: "substituteInPlace ${f}"
      + lib.concatMapStrings
        (d: " --replace-quiet ${lib.escapeShellArg d} ${lib.escapeShellArg "\${ARI_ZSHLIB:-${finalAttrs.finalPackage}/lib}"}")
        liveDefaults
      + "\n")
    files;

  # pinPlugins [ FILE … ]: the same for a bin's own zsh plugin, "${ARI_PLUGINS:-<the live plugin
  # dir>}", rewritten to the package's $out/share/zsh/plugins, where it installs its copies.
  passthru.pinPlugins = files: lib.concatMapStrings
    (f: "substituteInPlace ${f} --replace-quiet ${lib.escapeShellArg pluginsDefault} \"\\\${ARI_PLUGINS:-$out/share/zsh/plugins}\"\n")
    files;
})
