---
name: ari-dotfiles-skill-registry
description: Claude skills are versioned in Ari's dotfiles. Link tier-held skills into ~/.claude/skills, adopt a local skill into a tier, and report which skills are unlinked, missing, or dangling. Replaces the copy-based sync to the Airtable experimental repo.
---

# Dotfiles Skill Registry

The dotfiles are the registry. Each skill is one real directory in the tier that
owns it, and `~/.claude/skills/<name>` is a symlink to it. Editing through either
path edits the same files; committing through the tier publishes. There is no
copy step, no drift check against a remote, and no push here (pushing follows
`/ari-dotfiles`).

| Tier | Root | Holds |
|---|---|---|
| Shared (`git df`) | `~/.config/claude/skills/` | Skills correct on every machine |
| Local (`git ldf`) | `~/.local/share/claude-skills/` | Airtable- or machine-specific skills |

`~/.local/share/claude/` is Claude Code's own install dir, which is why the local
root is a sibling, not a child, of it.

## Rules

- **Pick the tier with `/ari-dotfiles` Placement rules.** Generic → df, company-specific → ldf.
- **`adopt` stages; you commit.** One skill per commit, message says why it moved.
  A rename (`--as`) also fixes the `name:` frontmatter and every caller
  (`rg -n '<old>' $HOME/.claude/skills`) in that same commit.
- **Never move a skill between tiers with `adopt`.** Follow the Moving-between-tiers
  recipe in `/ari-dotfiles`, then run `link`.
- **Shared libraries resolve through `$HOME/.claude/skills/`**, never through a
  relative hop from the script's own directory: skills sit in different tiers.
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
healthy rows; `ignored` rows add `reason=gitignore|no-skill-md`). Act per state:

| State | Meaning | Fix |
|---|---|---|
| `unlinked` | real dir, no tier holds it | `adopt` |
| `missing` | tier holds it, no symlink | `link` |
| `dangling` | symlink target gone | `link --prune` |
| `shadowed` | real dir hides a tier copy | diff them, keep one, `link` |
| `conflict` | both tiers hold it | remove one via its tier's git, `link` |
| `foreign` | symlink outside every tier | inspect; `rm` the link or adopt its target |

### Adopt a skill

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/adopt --skill <name> --tier df --dry-run
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/adopt --skill <name> --tier df
```

Then commit through the tier with a message that says why it belongs there:

```zsh
git df commit -m "claude: adopt the <name> skill into the shared tier"
```

Local tier: `--tier ldf`, `git ldf commit`. `adopt` refuses when the ldf allowlist
does not cover `share/claude-skills/`; add `!/share/claude-skills/` to
`~/.local/local-dotfiles.git/info/exclude` and to
`~/.config/new-machine/local-dotfiles-exclude`.

### Link on a machine

```zsh
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link --dry-run
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link
```

Idempotent. Creates a symlink for every `missing` skill and touches nothing else;
`--prune` also removes `dangling` links. `new-machine setup` runs it as the
`claude_skills` step (`new-machine check --only claude_skills` reports; `apply` links),
so on a new machine it happens with the rest of the bootstrap. Run it by hand after
pulling shared dotfiles that added a skill.

## File storage

- `bin/status` — read-only classification
- `bin/link` — create missing symlinks, prune dangling ones
- `bin/adopt` — move + link + stage one or more skills into a tier
- `lib/registry.zsh` — tier roots and `skill_state`, shared by the three scripts
