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

The harness spells the same two things without the aliases: `dotfiles git <args…>` is
`git df …`, `dotfiles --local git <args…>` is `git ldf …`, and `dotfiles [--local] --dir`
prints the tier's bare repo path.

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
  commits the shared tier's pointer bump for each published one (that path
  alone; `<name>: bump to <sha> (<subject>)`), then pushes the shared repo, all
  as the personal account by token (no key swap), and the local tier alongside
  to its own remote with the ssh agent's key (its pre-push hook included); a
  repo already at its `origin/main` is skipped silently (the submodule count
  line says how many were checked, pushed and bumped); a failed submodule or
  a refused bump blocks the shared push, nothing else blocks anything.
  Each repo's output lands in `~/.local/state/dotfiles/push/<repo>.log`
  (`shared`, `local`, or the submodule path; `.log.bak.1` … `.log.bak.5` = the five runs before).
  After committing, end with: "Run `dotfiles push` when ready."
- **Local: push after every ldf commit.** No confirmation needed; `dotfiles
  push` also picks up a local commit left unpushed.

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
| `slow step` | a step took longer than `DOTFILES_SLOW_STEP` (0.5s; pull's own fetch is allowed 5s) | read the step name; `dotfiles --timing <cmd>` times every step |
| `submodule not checked out` | never initialized here | `dotfiles init` |
| `No such remote`, `Remote is not on github.com` | a rewired or broken checkout | `dotfiles status`, then **Submodules** |
| DNS, timeout, TLS | network | retry; nothing was lost |
| a hook's own `[ERROR]` lines | the repo's pre-push hook refused | fix what it names; NEVER `--no-verify` |
| local log: `[EXO-PREPUSH] failed` | the local tier's pre-push hook ran the exoskeleton suite and it failed; the commit stands | `/ari-dotfile--submodule-chrome-exoskeleton` § When it fails, then push again |

## Placement rules

- **Generic → `~/.config` (df).** Anything correct on every machine: shell
  plugins, PATH policy (`prepend_to_path` for `~/.local/bin` and
  `$XDG_DATA_HOME/bin` is policy, not local), git config, nvim, `~/.config/bin`.
- **Company or machine-specific → `~/.local` (ldf).** Airtable env vars, aws/tsh/
  cloud-dev helpers, per-machine data for fzfdb selectors, `~/.local/bin`
  wrappers. Never a framework, never a launchd job, never a script that stands
  alone: an ldf component plugs into a df framework at one of the **Cutpoints**.
  Something that should run on a schedule or on screen unlock is a job plugin
  under `~/.local/share/dotfiles/jobs/`.
- **Claude skills follow the same split.** The real directory lives in the tier
  that owns it, `~/.config/claude/skills/<name>/` (df) or
  `~/.local/share/claude-skills/<name>/` (ldf), and `~/.claude/skills/<name>` is a
  symlink to it. Edit through either path; commit through the tier. Linking,
  adopting, and drift are `/ari-dotfiles-skill-registry`'s job.
- **Chrome Exoskeleton plugins follow the same split.** A plugin for a site you
  use only as an employee is ldf (`~/.local/share/chrome-exoskeleton/plugins/`);
  everything else is a file of the framework repo at `~/.config/chrome-exoskeleton/`,
  a submodule (see **Submodules**). Building, testing and the framework's own
  push are `/ari-dotfile--submodule-chrome-exoskeleton`'s job.
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

## Cutpoints

Every framework lives in the shared tier; the local tier only plugs into one. The
framework knows the local root by convention (`$XDG_DATA_HOME/<framework>/…`, i.e.
`~/.local/share/<framework>/…`), discovers what is there at run time, reports each
plugin's tier, and installs whatever needs installing from `dotfiles init` or
`new-machine`. The local tier therefore never installs anything, never owns a launchd
job and never ships a framework or a stand-alone script of its own. The Chrome
Exoskeleton is the model.

| Framework (df) | ldf plugs in at | How the framework finds it |
|---|---|---|
| zsh startup, `source_zsh_dir` in `~/.config/zsh/plugins/` | `~/.local/share/zsh/plugins/*.zsh` (secrets in `*.secret.zsh`, untracked) | sourced after the shared plugins |
| `dotfiles jobs` (`~/.config/dotfiles/lib/jobs.zsh`; shared plugins `~/.config/dotfiles/jobs/`) | `~/.local/share/dotfiles/jobs/<name>` | one launchd job runs both roots' plugins on unlock, login and a 5-minute tick; `dotfiles jobs list` |
| Chrome Exoskeleton, `exo` (`~/.config/chrome-exoskeleton/`) | `~/.local/share/chrome-exoskeleton/plugins/<name>/` | `exo link` mounts both roots; `/ari-dotfile--submodule-chrome-exoskeleton` |
| Claude skills, `/ari-dotfiles-skill-registry` (`~/.config/claude/skills/`) | `~/.local/share/claude-skills/<name>/` | symlinked into `~/.claude/skills` |
| `new-machine` Brewfile (`~/.config/new-machine/Brewfile`) | `~/.local/share/new-machine/Brewfile` | merged for `brew bundle` |
| `open-any` (`~/.config/zsh/plugins/open_any.zsh`) | `~/.local/bin/open-*` | discovered by name across both bin tiers |
| fzfdb selectors (functions in `~/.config/zsh/plugins/`) | `~/.local/share/{go_aws,kuber,aws_profile}/` | data read by the shared functions |
| `PATH` (`prepend_to_path` in `ari.zsh`) | `~/.local/bin/`, `~/.local/share/bin/` | on `PATH` on every machine |

**Adding a cutpoint**: build the framework in df with a local root under
`~/.local/share/<framework>/`, admit that root in both copies of the ldf allowlist
(`~/.local/local-dotfiles.git/info/exclude` and
`~/.config/new-machine/local-dotfiles-exclude`), give the framework a `list`/`status` that
names each plugin's tier, wire its install into `dotfiles init` (a step) or `new-machine`
(a step with a check), and add its row here. A plugin needing something outside its
tier (a launchd job, a compiled helper) is the sign that the framework is missing a
piece, not that the plugin should install it.

## Submodules

Some `~/.config` directories are git submodules of the shared repo: their files
belong to another repo, and the shared tier records only a commit hash for the
directory, the **pointer**, which is what every other machine checks out.
`cd ~ && git df submodule status` lists them. Today: `.config/chrome-exoskeleton`
(upstream `github.com/AriSweedler/chrome-exoskeleton`, public;
`/ari-dotfile--submodule-chrome-exoskeleton`) and `.config/plugged` (upstream
`github.com/AriSweedler/plugged`, public; `/ari-dotfile--submodule-plugged`).
The layout every submodule follows and the recipe for a new one:
`/ari-dotfile--submodule`.

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
3. **Its push, and the bump, are the user's**: end with "Run `dotfiles push`
   when ready." That pushes the submodule, commits the shared tier's pointer
   bump (`<name>: bump to <sha> (<subject>)`, that path alone) and pushes the
   shared tier with it; `dotfiles push --submodules` alone still commits the
   bump (`--shared`, `--local` and `--no-<part>` narrow the scope the same
   way). Claude is denied the command. Afterwards, **Verify**.
4. **Bump by hand only when the submodule was pushed some other way** and no
   `dotfiles push` is coming (`git df status --short -- ~/<path>` shows ` M`):
   ```zsh
   git df add ~/<path> && git df commit -m "<name>: bump to $(git -C ~/<path> rev-parse --short HEAD) (<what it carries>)"
   ```
   The df pre-commit hook refuses a pointer not on the submodule's
   `origin/main` (checked locally, fetched only on a miss): push first, re-run
   the commit, nothing to re-stage.

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
  (with `~/.config/bin/exo`) and `~/.config/plugged/` (with `~/.config/bin/plugged`) — see
  **Submodules**, `/ari-dotfile--submodule` (layout, creating one),
  `/ari-dotfile--submodule-chrome-exoskeleton` and `/ari-dotfile--submodule-plugged`
- **Jobs framework**: `~/.config/dotfiles/lib/jobs.zsh`; shared plugins in `~/.config/dotfiles/jobs/`
  (README = the plugin contract) — see **Cutpoints**
- **Harness**: `~/.config/bin/dotfiles` (init, pull, push, status, logs, git, jobs) — see **Pushing**
  and **Bootstrapping a machine**; the push is token-pinned to `DOTFILES_GITHUB_LOGIN`.
  The file in `bin` is only the entrypoint; the program is `~/.config/dotfiles/lib/*.zsh`,
  one module per concern, each independent at source time (its README has the rules and
  the check)

### Local (ldf)
- **Zsh plugins**: `~/.local/share/zsh/plugins/`, sourced after the shared dir
  via `source_zsh_dir --optional "${XDG_DATA_HOME}/zsh/plugins"`
- **Scripts**: `~/.local/bin/` and `~/.local/share/bin/`
- **Job plugins**: `~/.local/share/dotfiles/jobs/<name>` — see **Cutpoints**
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

`dotfiles init` also owns two things `new-machine` does not:

- **Migration from the pre-harness layout.** Its first step renames a shared bare repo still
  at `~/dotfiles` to `~/dotfiles.git`, then moves on; the rest of init gives the renamed repo
  its tracking config, hooks and checkout. A directory at the old name that is not a bare repo
  is left alone with a warning; both names present is an error to settle by hand. The local
  tier is per machine and is not migrated.
- **Jobs.** Its last step, `dotfiles jobs install`, installs the one launchd job
  (`com.<user>.dotfiles-jobs`: screen unlock, login, every 5 minutes) that runs the job
  plugins of both tiers, and boots out the per-plugin jobs it replaced (git-health's,
  aws-sso-autologin's, new-machine's weekly verify). `new-machine`'s `dotfiles_jobs` step checks it is loaded. The
  plugin contract is `~/.config/dotfiles/jobs/README.md`; see **Cutpoints**.

Hook setup for both tiers is documented in `~/.config/git/dotfiles-hooks/README.md`
and `~/.config/git/local-dotfiles-hooks/README.md`; those are the versioned source.
