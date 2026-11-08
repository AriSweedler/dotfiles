# Claude Code skills: ~/.claude/skills/<name>, one link per skill the shared tier or a submodule
# holds, declared here instead of made by the skill registry's `link`. Each link points at the
# editable directory (~/.config/claude/skills/<name>, ~/.config/<submodule>/skills/<name>), not
# at the store, so Claude edits a skill in place; a new skill needs `git add` and a switch to get
# its link. ~/.claude/skills itself stays Claude Code's directory (it keeps `synced/` there).
# A local flake links its own skills (~/.local/share/claude-skills/<name>) the same way.
{ config, lib, src, ... }:
let
  home = config.home.homeDirectory;
  roots = [
    ".config/claude/skills"
    ".config/chrome-exoskeleton/skills" # submodules: the input must have submodules=1
    ".config/plugged/skills"
  ];
  skillsIn = root:
    let dir = "${src}/${root}";
    in lib.optionals (builtins.pathExists dir)
      (lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)));
  links = lib.concatMap (root: map (name: { inherit root name; }) (skillsIn root)) roots;
in
lib.mkIf (builtins.pathExists "${src}/.config/claude/skills") {
  home.file = lib.listToAttrs (map
    ({ root, name }: lib.nameValuePair ".claude/skills/${name}" {
      source = config.lib.file.mkOutOfStoreSymlink "${home}/${root}/${name}";
    })
    links);

  # The registry's own links sit where these go; home-manager would move each aside as
  # <name>.before-nix, which Claude Code would then load as a second copy of the skill. Remove
  # a link that is not yet home-manager's before the collision check runs.
  home.activation.claudeSkillsAdopt = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    for name in ${lib.escapeShellArgs (map (l: l.name) links)}; do
      link="${home}/.claude/skills/$name"
      if [[ -L "$link" && "$(readlink "$link")" != /nix/store/* ]]; then
        run rm "$link"
      fi
    done
  '';
}
