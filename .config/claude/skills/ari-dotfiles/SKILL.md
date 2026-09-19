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
   A path inside a submodule (`~/.config/chrome-exoskeleton/…`) is refused by
   `git df add`: follow **Submodules** instead.
3. Print `git df log --oneline -1` / `git ldf log --oneline -1` to confirm the tier.
4. Shared: end with "Run `dotfiles push` when ready." Local: `git ldf push` now.
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

- **Shared: NEVER `git df push` and NEVER run `dotfiles push`.** Ari runs it
  (denied to Claude in settings). It pushes every submodule first, in parallel,
  then the shared repo, all as the personal account by token (no key swap);
  a repo already at its `origin/main` is skipped silently (the submodule count
  line says how many were checked and pushed); a failed submodule blocks the
  shared push. Each repo's output lands in
  `~/.local/state/dotfiles/push/<repo>.log` (`.log.bak.1` = the run before).
  After committing, end with: "Run `dotfiles push` when ready."
- **Local: push after every ldf commit.** No confirmation needed.

### When `dotfiles push` fails

It stops at the first failing repo, names it, and pushes nothing after it.
Read the log, then act; you may run these two (read-only) yourself:

```zsh
dotfiles status                                   # tiers, submodule pointers, each repo's last push line
dotfiles logs --repo shared                       # or --repo .config/chrome-exoskeleton; --previous = the run before
```

| log says | cause | do |
|---|---|---|
| `Personal account is not logged into gh` | this machine's gh has no personal login | the user runs `env -u GITHUB_TOKEN gh auth login` (HTTPS) |
| `Token identity mismatch` | the stored personal token is not the personal account | `env -u GITHUB_TOKEN gh auth status`; re-login |
| `Detached HEAD: nothing to push` | commits made while a pull had left the submodule detached (detached with nothing new is skipped silently) | **Submodules** step 1 (`git -C ~/<path> branch -f main HEAD` if `main` is an ancestor, else ask), push again |
| `! [rejected]` (fetch first / non-fast-forward), or `Remote ref does not match after push` | the remote moved | shared: `dotfiles pull`; submodule: `git -C ~/<path> pull --rebase origin main`, re-run its checks, push again |
| `slow step` | a step took longer than `DOTFILES_SLOW_STEP` (0.5s) | read the step name; `dotfiles --timing <cmd>` times every step |
| `submodule not checked out` | never initialized here | `dotfiles init` |
| `No such remote`, `Remote is not on github.com` | a rewired or broken checkout | `dotfiles status`, then **Submodules** |
| DNS, timeout, TLS | network | retry; nothing was lost |
| a hook's own `[ERROR]` lines | the repo's pre-push hook refused | fix what it names; NEVER `--no-verify` |

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
- **Chrome Exoskeleton plugins follow the same split.** A plugin for a site you
  use only as an employee is ldf (`~/.local/share/chrome-exoskeleton/plugins/`);
  everything else is a file of the framework repo at `~/.config/chrome-exoskeleton/`,
  a submodule (see **Submodules**). Building, testing and the framework's own
  push are `/ari-dotfile-submodule-chrome-exoskeleton`'s job.
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

## Submodules

Some `~/.config` directories are git submodules of the shared repo: their files
belong to another repo, and the shared tier records only a commit hash for the
directory, the **pointer**, which is what every other machine checks out.
`cd ~ && git df submodule status` lists them. Today: `.config/chrome-exoskeleton`
(upstream `github.com/AriSweedler/chrome-exoskeleton`, public; the repo itself
is `/ari-dotfile-submodule-chrome-exoskeleton`'s job).

`git df add` refuses a file inside a submodule (`fatal: Pathspec '…' is in
submodule '…'`); the only path it accepts there is the directory itself, the
pointer. `git submodule` runs only from `$HOME`: plain `git submodule`
elsewhere targets whatever repo the cwd is in.

### Changing something inside a submodule

One dotfiles change; never stop after the first commit.

1. **Be on its `main`.** `git -C ~/<path> branch --show-current` must print
   `main`; it prints nothing after any `git df pull` or `git df submodule
   update` (`submodule.recurse=true` checks the pointer out detached). Nothing
   committed yet → `git -C ~/<path> switch main`. Committed while detached →
   `git -C ~/<path> branch -f main HEAD`, only if
   `git -C ~/<path> merge-base --is-ancestor main HEAD` succeeds; else ask.
2. **Commit in the submodule's repo** on `main`, explicit paths:
   `git -C ~/<path> add <files> && git -C ~/<path> commit -m "…"`. Its hooks
   and commit conventions apply, not the tier's.
3. **Its push is the user's**: `dotfiles push --submodules-only` (every
   submodule, in parallel, one log each, as the personal account); Claude is
   denied it. Ask, wait, then confirm
   `git -C ~/<path> status -sb` → `## main...origin/main`.
4. **Commit the bump**, always, as part of the same change:
   ```zsh
   git df add ~/<path> && git df commit -m "<name>: bump to $(git -C ~/<path> rev-parse --short HEAD) (<what it carries>)"
   ```
   The df pre-commit hook fetches the submodule's `origin/main` and refuses a
   pointer not on it (step 3 skipped, a stale `main` pushed, or offline): fix,
   re-run the commit, nothing to re-stage. Pointer already at HEAD → nothing to
   bump; say so.
5. End with "Run `dotfiles push` when ready.", as for any shared-tier commit.

### After `git df pull` on any machine

The pull moves the pointer and detaches the checkout onto it; a never-initialized
submodule stays an empty directory until `cd ~ && git df submodule update --init`.
Then the repo's own refresh (chrome-exoskeleton: `exo link && exo build`), and
step 1 before committing in it again. `new-machine apply dotfiles_repo` runs
the `--init` on a fresh machine; `new-machine check` reports
`submodule_uninitialized` and `submodule_drift`.

### Verify

```
git -C ~/<path> status -sb          → ## main...origin/main
cd ~ && git df submodule status      →  <sha> <path> (heads/main)    leading space, not +
git df status --short -- <path>      → (empty)
```

Prefixes: space = checkout matches the pointer; `+` = checkout ahead of the
pointer (bump needed, or update on another machine); `-` = not initialized.

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
- **Submodules**: declared in `~/.gitmodules`; today `~/.config/chrome-exoskeleton/`
  (with `~/.config/bin/exo`) — see **Submodules** and `/ari-dotfile-submodule-chrome-exoskeleton`
- **Harness**: `~/.config/bin/dotfiles` (init, pull, push, status, logs) — see **Pushing**
  and **Bootstrapping a machine**; the push is token-pinned to `DOTFILES_GITHUB_LOGIN`

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
with "Run `dotfiles push` when ready." if anything landed in the shared repo.

## Bootstrapping a machine

`new-machine setup` (`~/.config/new-machine/bin/new-machine`, idempotent, `--dry-run`) does this:
Homebrew + `~/.config/new-machine/Brewfile` (includes `bash`; the ldf hook needs bash 5),
bare-clone the shared repo to `~/dotfiles.git`, `git init --bare ~/.local/local-dotfiles.git`
with the allowlist from `~/.config/new-machine/local-dotfiles-exclude`, `core.hooksPath`
for both repos, `submodule update --init` (the `dotfiles_repo` step), the `claude_skills`
step, which symlinks every tier-held skill into `~/.claude/skills`
(`/ari-dotfiles-skill-registry`'s `link --prune`), and the `chrome_exoskeleton` step
(`exo deps ci`, `exo build`). It prints the one manual step, since the remote is per machine:

```zsh
git ldf remote add origin <this machine's private repo>
git ldf add -A && git ldf commit -m "local dotfiles: initial snapshot" && git ldf push -u origin main
```

Keep `local-dotfiles-exclude` in sync with `~/.local/local-dotfiles.git/info/exclude` when the
allowlist changes.

`dotfiles init` (`~/.config/bin/dotfiles`) is the canonical setup of the dotfiles themselves,
and both `bootstrap.sh` and new-machine's `dotfiles_repo` step call it: shared repo cloned
and tracking `origin/main`, checked out into `$HOME`, hooks wired for both tiers, submodules
checked out, skills linked, and the GitHub ssh key loaded into the agent with its passphrase
read from 1Password (`op`; the item and vault come from the local tier's
`~/.local/share/zsh/plugins/dotfiles.zsh`, so a machine without them just skips the key).
Idempotent; `--dry-run` prints the plan. `dotfiles pull` fast-forwards the shared tier and
re-runs init; `dotfiles status` shows both tiers, the submodule pointers and each repo's last
push; `dotfiles push` and `dotfiles logs` are under **Pushing**.

Hook setup for both tiers is documented in `~/.config/git/dotfiles-hooks/README.md`
and `~/.config/git/local-dotfiles-hooks/README.md`; those are the versioned source.
