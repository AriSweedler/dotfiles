---
name: ari-dotfiles-skill-registry
description: Claude skills are versioned in Ari's dotfiles. Link tier-held skills into ~/.claude/skills, adopt a local skill into a tier, and report which skills are unlinked, missing, or dangling. Replaces a copy-based sync to a separate skills repo.
---

# Dotfiles Skill Registry

The dotfiles are the registry. Each skill is one real directory in the tier that
owns it, and `~/.claude/skills/<name>` is a symlink to it (on a Nix machine,
home-manager's link through the store). Editing through either path edits the
same files; committing through the tier publishes. There is no copy step, no
drift check against a remote, and no push here (pushing follows `/ari-dotfiles`).

| Tier | Root | Holds |
|---|---|---|
| Shared (`git df`) | `~/.config/claude/skills/` (real dir `~/dotfiles/.config/claude/skills/` on a Nix machine) | Skills correct on every machine |
| Local (`git ldf`) | `~/local-dotfiles/local/<machine>/share/claude-skills/` (clone machine); `~/.local/share/claude-skills/` (bare-repo machine) | Work- or machine-specific skills |
| Either, via a dev repo | `<repo>/skills/` for every `path` in the shared tier's dev-repos manifest (`~/dotfiles/.config/dotfiles/dev-repos`), and in a tier worktree's `.gitmodules` where one remains (e.g. `~/.config/chrome-exoskeleton/skills/`) | Skills that travel with that repo; committed there, not with `git df`/`git ldf` |

- **Farm link**: `~/.claude/skills/<name>`.
- **Clone machine**: the local tier is the `~/local-dotfiles` clone (`~/local-dotfiles/.git` exists); a *bare-repo machine* has `~/.local/local-dotfiles.git`, with `~/.local` as its worktree. The rule is the dotfiles CLI's (`lib/env.zsh`); `ARI_DOTFILES_LDF_GIT_DIR` and `ARI_DOTFILES_LDF_WORK_TREE` override it.
- **`<machine>`**: as ldf-link reads it: `ARI_DOTFILES_MACHINE`, else the first word of `~/.local/share/dotfiles/machine-name`, else the short hostname. It must be listed in `~/local-dotfiles/machines`, or `adopt --tier ldf` refuses.
- **On a clone machine `~/.local/share/claude-skills/<name>` is ldf-link's directory of per-file links, never a tier root.** A new file made through it lands in `~/.local`, untracked. `link` and `adopt` link the clone's directory; `status` marks a farm link into ldf-link's links `via=ldf-link`, and `link --execute` retargets it.
- `~/.local/share/claude/` is Claude Code's own install dir: the bare-repo local root is its sibling, not its child.

## Rules

- **Pick the tier with `/ari-dotfiles` Placement rules.** Generic → df, company-specific → ldf.
- **`adopt` stages; you commit.** One skill per commit, message says why it moved.
  A rename (`--as`) also fixes the `name:` frontmatter and every caller
  (`rg -L -n '<old>' $HOME/.claude/skills`: `-L`, since each skill there is a link) in that same commit.
- **Never move a skill between tiers with `adopt`.** Follow `/ari-dotfiles` § Moving
  a file between tiers, then run `link`.
- **Shared libraries resolve through `$HOME/.claude/skills/`**, never through a
  relative hop from the script's own directory: skills sit in different tiers.
- **Dev-repo skills are committed in the dev repo.** `status` marks them
  `source=submodule:<path>` ("submodule" is the output's word for a dev repo);
  `link` symlinks them like any tier skill. `adopt` never targets a dev repo:
  create the skill under `<repo>/skills/<name>/`, commit it there and finish per
  `/ari-dotfiles` § Dev repos, then link it (**Link on a machine**).
- **Third-party skills stay put.** `~/.claude/skills/.gitignore` lists them; `status`
  reports them as `ignored`. Naming one explicitly to `adopt` is the override. A directory
  with no `SKILL.md` (Claude Code's `synced/` bucket) is not a skill: `status` reports it
  `ignored` with `reason=no-skill-md` on every machine, and `adopt` refuses it.

## Workflow

### See where things stand

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status
```

Prints one `state=… tier=… name=…` line per actionable skill (`--all` includes
healthy rows; `ignored` rows add `reason=gitignore|no-skill-md`; `linked` and
`missing` rows held by a dev repo add `source=submodule:<path>`, `<path>` relative to
the tier's worktree, e.g. `.config/plugged` for `~/dotfiles/.config/plugged` on a
Nix machine). Act per state:

| State | Meaning | Fix |
|---|---|---|
| `unlinked` | real dir, no tier holds it | `adopt` |
| `linked … via=ldf-link` | clone machine: the farm link names ldf-link's per-file links, not the clone's directory | `link --execute` (retargets it) |
| `missing` | tier holds it, no symlink | `link`, or on a Nix machine `dotfiles switch` (**Link on a machine**) |
| `dangling` | symlink target gone, or (clone machine) names ldf-link's links with no clone directory behind them | `link --prune` |
| `shadowed` | real dir hides a tier copy | diff them, keep one, `link` |
| `conflict` | two roots hold it (`tier=df,ldf`; `tier=df,df` is the tier root and a dev repo) | remove one copy through the git that holds it (tier or dev repo), `link` |
| `foreign` | symlink outside every tier | inspect; `rm` the link or adopt its target |

### Adopt a skill

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/adopt --skill <name> --tier df
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/adopt --skill <name> --tier df --execute
```

Preview, then act. `adopt` and `link` mutate: each is a dry run unless `--execute` is on its command line, and `--execute` runs unattended (no wait for a user `yes`); `--dry-run` wins over `--execute`. Convention: `/ari-skill-shellscripts` § Dry run. `status` is read-only and takes neither flag.

Then commit through the tier with a message that says why it belongs there:

```zsh
git df commit -m "claude: adopt the <name> skill into the shared tier"
```

- **Local tier**: `--tier ldf`, then `git ldf commit`.
- **Clone machine**: `adopt --tier ldf` then runs ldf-link, which updates every local-tier link on the machine; its dry run shows ldf-link's preview. Read that preview before `--execute`.
- **`ldf-link not found` or `ldf-link did not link the skill`** (a warning; the skill is adopted, linked to the clone's directory, and staged): commit anyway, run `ldf-link` (a dry run) to see what it refused, settle that per `/ari-dotfiles`, then `ldf-link --execute`.
- **`tier ignores the skills root`**: on a bare-repo machine, add `!/share/claude-skills/` to `~/.local/local-dotfiles.git/info/exclude` and to `~/.config/new-machine/local-dotfiles-exclude`; on a clone machine, change the rule the hint names so the skills root is tracked (git cannot re-include a path under an ignored directory).
- **`machine not in the clone's machines file`**: set the name with `dotfiles machine-name`, or add the machine to `~/local-dotfiles/machines`.

### Link on a machine

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link --execute
```

Preview, then act (dry-run convention above). Idempotent. Creates a symlink for every `missing` skill, and on a clone machine retargets every `via=ldf-link` one to the clone's directory; it touches nothing else.
`--prune` also removes `dangling` links. `dotfiles init` runs it as the
`claude_skills` step (`new-machine check --only claude_skills` reports; `apply` links),
so on a new machine it happens with the rest of the bootstrap.

Who makes which link:

- **A Nix machine (`~/dotfiles/.git` exists): home-manager owns every shared-tier
  and dev-repo link** (`nix/claude-skills.nix`). A `missing` one is fixed by
  `git add` (in the tier, or the dev repo) and `dotfiles switch` (`/ari-dotfiles-nix`),
  never by `link`: the switch's `claudeSkillsAdopt` removes a link `link` made.
- **`link` makes the rest:** local-tier links on every machine, and every link on a
  machine without the Nix port. Run it there after pulling dotfiles that added a skill.

## File storage

- `bin/status` — read-only classification
- `bin/link` — (dry run unless `--execute`) create missing symlinks, retarget `via=ldf-link` ones, prune dangling ones
- `bin/adopt` — (dry run unless `--execute`) check every skill, then move + link + stage each into a tier (+ ldf-link on a clone machine)
- `lib/registry.zsh` — tier roots and worktrees, dev-repo `skills/` roots (dev-repos manifest, any `.gitmodules`) and `skill_state`; sourced by the three scripts
- `tests/registry.test.zsh` — dev-repo roots and the local tier's clone and bare layouts in throwaway HOMEs: `zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/tests/registry.test.zsh`
- `tests/adopt.test.zsh` — `adopt` in throwaway HOMEs, the clone layout included: `zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/tests/adopt.test.zsh`
