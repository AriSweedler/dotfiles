---
name: ari-dotfiles
description: Edit and commit Ari's two-tier dotfiles — shared (`git df`, ~/.config, every machine) and local (`git ldf`, ~/.local, this machine only)
---

# Dotfiles

Ari's dotfiles are two bare git repos, one per tier. Pick the tier by whether
the content should be identical on every machine or belongs to this one.

| Tier | Alias | Bare repo | Worktree | Holds | Remote |
|---|---|---|---|---|---|
| Shared | `git dotfiles` / `git df` | `~/dotfiles.git` | `$HOME` | Generic, every-machine config under `~/.config` | One shared repo; only Ari pushes |
| Local | `git local-dotfiles` / `git ldf` | `~/.local/local-dotfiles.git` | `~/.local` | Company- and machine-specific code under `~/.local` | One private repo per machine; the agent pushes |

On this laptop the local `origin` is `git@github.com:AriSweedler-at/dotfiles.git`
(work account). State (`~/.local/state`) and cache (`~/.cache`) are never versioned.

## Workflow

1. Edit the file. Pick its tier with **Placement rules**.
2. `git df add <abs path>` or `git ldf add <abs path>`; commit with a descriptive message.
3. Print `git df log --oneline -1` / `git ldf log --oneline -1` to confirm the tier.
4. Shared: end with "Run `git_df_push` when ready." Local: `git ldf push` now.
5. Offer the **Post-change sweep**.

**Always pass absolute paths to `git df` and `git ldf`.** Relative pathspecs
resolve against the cwd, and from inside `~/.local` a `share/...` path silently
matches nothing.

```zsh
git df status
git df add ~/.config/bin/my-script && git df commit -m "Add my-script"

git ldf status
git ldf add ~/.local/share/zsh/plugins/foo.zsh && git ldf commit -m "Add foo plugin"
git ldf add -A        # safe: info/exclude is an allowlist of hand-written dirs
git ldf push
```

`~/.local/local-dotfiles.git/info/exclude` is the allowlist. Read it; do not
restate it. `git ldf add -A` is safe because of it.

**When `git ldf status` fails:**
- `git: 'ldf' is not a git command` → the alias is missing: `~/.gitconfig` does not
  `[include] path = ~/.config/git/plugin/dotfiles.gitconfig`. Fix the include, do not add the alias elsewhere.
- `fatal: not a git repository` (or `.../local-dotfiles.git` does not exist) → no
  local repo yet. Say the edit is untracked and point at **Bootstrapping a machine**.

**When the ldf pre-commit hook rejects** (exit 1, one `[ERROR]` line), fix the
cause. NEVER `--no-verify`. NEVER `git ldf add -f` a `.secret.` path.
- `bash 5 required; this is macOS /bin/bash without mapfile` → `brew install bash`, retry.
- `refusing to commit a secret file | path='...'` → `git ldf rm --cached <abs path>`; the file stays untracked.
- `staged content looks like a credential | path='...'` → move the literal to the
  plugin's `*.secret.zsh` sibling (recipe under **Secrets**), leave a pointer
  comment, re-stage.

## Pushing

- **Shared: NEVER `git df push` and NEVER run `git_df_push`.** It is Ari's
  function. After committing, end with: "Run `git_df_push` when ready."
- **Local: push after every ldf commit.** No confirmation needed.

## Placement rules

- **Generic → `~/.config` (df).** Anything correct on every machine: shell
  plugins, PATH policy (`prepend_to_path` for `~/.local/bin` and
  `$XDG_DATA_HOME/bin` is policy, not local), git config, nvim, `~/.config/bin`.
- **Company or machine-specific → `~/.local` (ldf).** Airtable env vars, aws/tsh/
  cloud-dev helpers, per-machine data for fzfdb selectors, `~/.local/bin`
  wrappers.
- **Claude skills follow the same split.** The real directory lives in the tier
  that owns it, `~/.config/claude/skills/<name>/` (df) or
  `~/.local/share/claude-skills/<name>/` (ldf), and `~/.claude/skills/<name>` is a
  symlink to it. Edit through either path; commit through the tier. Linking,
  adopting, and drift are `/ari-dotfiles-skill-registry`'s job.
- **Split mixed files.** Keep the generic mechanism in config and parameterize
  the company detail from local:
  ```zsh
  # ~/.config/bin/chrome_work_open (df)
  domain="${WORK_EMAIL_DOMAIN:?set in the local tier}"
  # ~/.local/share/zsh/plugins/airtable.zsh (ldf)
  export WORK_EMAIL_DOMAIN=airtable.com
  ```
  fzfdb selectors: function in config, Airtable aliases and bookmark data in local.

### Secrets

**NEVER put a credential literal in a tracked file.** The `export` goes in
`<plugin>.secret.zsh` beside the plugin that needs it; `*.secret.zsh` is
excluded from ldf and `source_zsh_dir` sources every `*.zsh` under both plugin
dirs, so no wiring is needed.

```zsh
f=~/.local/share/zsh/plugins/foo.secret.zsh
install -m 600 /dev/null "$f"
echo "export FOO_TOKEN='...'" >> "$f"
```

In the tracked plugin leave only a pointer:
`# Token exports: foo.secret.zsh (untracked, mode 600, sourced by source_zsh_dir)`.
The ldf pre-commit hook rejects `.secret.` paths and token-shaped content. No
shared `get secrets` helper exists yet; do not assume one.

### Moving a file between tiers

Show the block and the `rg` hits before running.

```zsh
git df rm --cached ~/.config/zsh/plugins/airtable.zsh
mv ~/.config/zsh/plugins/airtable.zsh ~/.local/share/zsh/plugins/airtable.zsh
git df commit -m "Move airtable.zsh to local tier"
git ldf add ~/.local/share/zsh/plugins/airtable.zsh && git ldf commit -m "Add airtable.zsh from shared tier"
rg -n 'plugins/airtable.zsh' ~/.config ~/.local/share   # edit every hit; re-run until empty
```

## Key locations

### Ignore files
- `~/.config/git/ignore` — global `core.excludesFile`, every repo on the machine;
  this is what hides `dotfiles.git` and `.local` from the shared repo.
- `~/.local/local-dotfiles.git/info/exclude` — the local repo's allowlist.

### Shared (df)
- **Scripts**: `~/.config/bin/` on `$PATH`
- **Git config plugins**: `~/.config/git/plugin/` (aliases live in `dotfiles.gitconfig`)
- **Git hooks**: `~/.config/git/dotfiles-hooks/` (df), `~/.config/git/local-dotfiles-hooks/` (ldf; needs brew bash 5)
- **Zsh plugins**: `~/.config/zsh/plugins/`, sourced first
- **Nvim**: `~/.config/nvim/`, lazy.nvim specs in `lua/plugins/`, `lazy = true` by default
- **Claude skills**: `~/.config/claude/skills/<name>/`, symlinked from `~/.claude/skills/<name>`

### Local (ldf)
- **Zsh plugins**: `~/.local/share/zsh/plugins/`, sourced after the shared dir
  via `source_zsh_dir --optional "${XDG_DATA_HOME}/zsh/plugins"`
- **Scripts**: `~/.local/bin/` and `~/.local/share/bin/`
- **Data**: `~/.local/share/{go_aws,kuber,aws_profile,tmux_oneshot}/`
- **Claude skills**: `~/.local/share/claude-skills/<name>/`, symlinked from `~/.claude/skills/<name>`
  (`~/.local/share/claude/` is Claude Code's own install dir; hands off)

## Post-change sweep

After a dotfiles change lands, ask:

> Want me to go through your other pending dotfiles changes and commit them too?

If yes, run `git df status` and `git ldf status` and report each tier on its
own line before anything else:

    Shared (df): clean
    Local (ldf): 2 modified, 1 untracked

Both clean → those two lines are the whole answer; stop. Otherwise inspect each
change (`diff` for modified, `cat` for untracked), then print the plan as one
line per commit (tier: files → message), grouping tightly related files (a new
config plus its include), before the first commit. Commit, then push local; end
with "Run `git_df_push` when ready." if anything landed in the shared repo.

## Bootstrapping a machine

`new-machine setup` (`~/.config/new-machine/bin/new-machine`, idempotent, `--dry-run`) does this:
Homebrew + `~/.config/new-machine/Brewfile` (includes `bash`; the ldf hook needs bash 5),
bare-clone the shared repo to `~/dotfiles.git`, `git init --bare ~/.local/local-dotfiles.git`
with the allowlist from `~/.config/new-machine/local-dotfiles-exclude`, and `core.hooksPath`
for both repos. It prints the one manual step, since the remote is per machine:

```zsh
git ldf remote add origin <this machine's private repo>
git ldf add -A && git ldf commit -m "local dotfiles: initial snapshot" && git ldf push -u origin main
```

Keep `local-dotfiles-exclude` in sync with `~/.local/local-dotfiles.git/info/exclude` when the
allowlist changes.

Hook setup for both tiers is documented in `~/.config/git/dotfiles-hooks/README.md`
and `~/.config/git/local-dotfiles-hooks/README.md`; those are the versioned source.
