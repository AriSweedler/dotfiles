---
name: ari-dotfiles
description: Edit and commit Ari's two-tier dotfiles — shared (`git df`, ~/.config, every machine) and local (`git ldf`, ~/.local, this machine only) — and, everywhere but the personal laptop, review every unpushed public commit for employer-identifying content before recommending a push
---

# Dotfiles

Ari's dotfiles are two git repos, one per tier: a plain clone for the shared tier, a bare repo
for the local one. Pick the tier by whether
the content should be identical on every machine or belongs to this one. The
shared tier and its dev repos are public; no push is recommended until each unpushed commit passes **Review before
push**, except on the personal laptop, where a commit is ready to push as soon as it lands.

| Tier | Alias | Repo | Worktree | Holds | Remote |
|---|---|---|---|---|---|
| Shared | `git dotfiles` / `git df` | plain clone `~/dotfiles` (git dir `~/dotfiles/.git`) | `~/dotfiles`; home-manager links its files into `$HOME` (`/ari-dotfiles-nix`) | Generic, every-machine config under `~/.config` | One shared repo; only Ari pushes |
| Local | `git local-dotfiles` / `git ldf` | bare `~/.local/local-dotfiles.git` | `~/.local` | Company- and machine-specific code under `~/.local` | A private repo per machine, or none (the personal laptop); the agent pushes when there is one |

`git df` is `~/.config/git/bin/git-dotfiles` (the alias is the `dotfiles` block of
`~/.config/dotfiles/nix/git.nix`). It runs git on the clone and turns a `$HOME` path that
resolves into the clone (a linked file, or a file under a linked directory) into its clone path, so
`git df add ~/.config/bin/foo` works for a file that is already tracked. A real directory in
`$HOME`, one that holds per-file links such as `~/.config/zsh/plugins`, does not resolve into the
clone. git refuses it as `outside repository`, so name it by its clone path. A relative path is
relative to the caller's directory. A machine without `~/dotfiles/.git` falls back to the bare repo
`~/dotfiles.git` with `$HOME` as its work tree. There, read every `~/dotfiles/<path>` in this skill
as `~/<path>`. `dotfiles --dir` prints which layout the
machine has. On the personal laptop the bare repo was retired to `~/dotfiles.git.retired`.

The local tier pushes to its `origin` when it has one: `git ldf remote get-url origin` succeeds.
On the personal laptop it has none, by Ari's choice: after an ldf commit there is nothing to push,
`dotfiles push` prints `local tier has no remote; nothing to push`, and that is NEVER a problem to
flag or fix. State (`~/.local/state`) and cache (`~/.cache`) are never versioned.

## Workflow

1. Edit the file. Pick its tier with **Placement rules**. An existing shared file can be edited
   through `$HOME` or the clone, and the change is live at once. **A packaged bin
   (**Placement rules**) is the exception: edit the clone's file and run that file to try it;
   `$HOME`'s copy changes only at the next `dotfiles switch`.**
   - **Create a new shared file at its clone path, `~/dotfiles/<path>`, NEVER at `~/<path>`.** A
     file created at `~/<path>` is not in the repo, and git cannot see it. A new clone file appears
     in `$HOME` only after it is committed and the next `dotfiles switch` runs, because the bridge
     links only what git tracks. Ari runs the switch; Claude may run `dotfiles switch --build`
     (`/ari-dotfiles-nix`).
   - The exception is a directory linked whole, where either path works and the new file is live at
     once. Test it with `[[ -L ~/<dir> ]]`. Today these are `.config/nvim`, `.config/claude` and
     the dev repos.
2. `git df add <abs path>` or `git ldf add <abs path>`. Give a new shared file its clone path:
   its `$HOME` path does not exist yet. Commit with a descriptive
   message and the same paths after `--` (`git df commit -m "…" -- <abs paths>`),
   since tools like `bake` stage files of their own. A path inside a dev repo
   (`~/.config/chrome-exoskeleton/…`) is ignored by the shared repo, and `git df add` refuses it:
   follow **Dev repos** instead.
3. Print `git df log --oneline -1` / `git ldf log --oneline -1` to confirm the tier.
4. Shared: run **Review before push** (its first step skips it on the
   personal laptop). Local: `git ldf push` now, when the tier has an `origin`. Start the
   **Post-change sweep** alongside.
5. Close with one message: what landed, the review verdicts (if it ran),
   the sweep's plan, and any history rewrite the review calls for, ending in one
   question that covers them all (none when nothing is pending). When the change touched a
   Nix module, a packaged bin or `plugged`, or added a shared file outside a directory linked whole, say it
   is live only after Ari runs `dotfiles switch`. End with "Run
   `dotfiles push` when ready." once every unpushed shared commit, including any
   the `yes` just made, has passed the review. On the personal laptop
   (`dotfiles machine-name` prints `personal`), end with it as soon as the commit lands.

**Always pass absolute paths to `git df` and `git ldf`.** Relative pathspecs
resolve against the cwd, and from inside `~/.local` a `share/...` path silently
matches nothing.

```zsh
git df status
git df add ~/dotfiles/.config/bin/my-script && git df commit -m "Add my-script" -- ~/dotfiles/.config/bin/my-script
git df add ~/.config/zsh/plugins/fzf.zsh && git df commit -m "fzf: preview files with bat" -- ~/.config/zsh/plugins/fzf.zsh   # tracked: mapped

git ldf status
git ldf add ~/.local/share/zsh/plugins/foo.zsh && git ldf commit -m "Add foo plugin" -- ~/.local/share/zsh/plugins/foo.zsh
git ldf add -A        # safe: info/exclude is an allowlist of hand-written dirs
git ldf push          # only when the tier has an origin
```

The harness spells the same two things without the aliases: `dotfiles git <args…>` runs git on
the shared tier, `dotfiles --local git <args…>` is `git ldf …`, and `dotfiles [--local] --dir`
prints the tier's git dir (`ARI_DOTFILES_DF_GIT_DIR`; `~/dotfiles/.git` on a clone). `dotfiles git`
passes its arguments untouched, so it needs clone paths. Only `git df` maps `$HOME` paths.

`~/.local/local-dotfiles.git/info/exclude` is the allowlist. Read it; do not
restate it. `git ldf add -A` is safe because of it.

**When `git ldf status` fails:**
- `git: 'ldf' is not a git command` → `~/.config/git/config` lacks the alias, which
  `~/.config/dotfiles/nix/git.nix` writes there at a `dotfiles switch`. The fix is the switch
  (Ari's), never an alias added elsewhere.
- `fatal: not a git repository` (or `.../local-dotfiles.git` does not exist) → no
  local repo yet. Say the edit is untracked and point at **Bootstrapping a machine**.

**When the ldf pre-commit hook rejects** (exit 1, one `[ERROR]` line), fix the
cause. NEVER `--no-verify`. NEVER `git ldf add -f` a `.secret.` path.
- `bash 5 required; this is macOS /bin/bash without mapfile` → bash 5 comes from Nix
  (`/ari-dotfiles-nix`). Ari runs `dotfiles switch`, then retry. NEVER `brew install bash`.
- `refusing to commit a secret file | path='...'` → `git ldf rm --cached <abs path>`; the file stays untracked.
- `staged content looks like a credential | path='...'` → move the literal to the
  plugin's `*.secret.zsh` sibling (recipe under **Secrets**), leave a pointer
  comment, re-stage.

## Pushing

- **Shared: NEVER `git df push` and NEVER run `dotfiles push`.** Ari runs it
  (denied to Claude in settings). It pushes every dev repo first, in parallel;
  for each published one it runs `nix flake update <input>` and commits the
  shared tier's `flake.lock` alone (`<name>: bump to <sha> (<subject>)`); then
  it pushes the shared repo, all as the personal account by token (no key
  swap), and the local tier alongside to its own remote, when it has one, with
  the ssh agent's key (its pre-push hook included). A repo already at its
  `origin/main` is skipped silently (the `submodules done` line counts the dev
  repos checked, pushed and bumped). A failed dev repo or a refused bump
  blocks the shared push; nothing else blocks anything.
  Each repo's output lands in `~/.local/state/dotfiles/push/<repo>.log`
  (`shared`, `local`, or the dev repo's path; `.log.bak.1` … `.log.bak.5` = the five runs before).
  After committing, run **Review before push** and end with "Run `dotfiles push`
  when ready." only when it passes; on the personal laptop skip the review and end
  with that line as soon as the commit lands.
- **Local: push after every ldf commit, on a machine whose local tier has an `origin`.** No
  confirmation needed and no review (the repo is private); `dotfiles push` also picks up a local
  commit left unpushed. Without an `origin` (the personal laptop) the commit is the last step.

### Review before push

Runs on every machine but the personal laptop, so a new or unnamed machine is reviewed.
Check first:

```zsh
[[ "$(dotfiles machine-name)" == personal ]] && echo skip || echo review
```

`skip` → dispatch no reviewer: the commit is ready, so end with "Run `dotfiles
push` when ready." as soon as it lands. `review` → each unpushed shared-tier or
dev repo commit becomes public on Ari's push, so review every one for content
that identifies the employer, using the identifying-content list in
`/ari-skill-update` § Rules:

```zsh
git df log --reverse --format=%h origin/main..main            # shared tier
git -C ~/<path> log --reverse --format=%h origin/main..main   # each dev repo `dotfiles status` lists
```

For each commit, dispatch a fresh reviewer with the Agent tool, one per commit.
Give it `git df show <sha>` (or `git -C ~/<path> show <sha>`), the full text of
every file the commit touches as of that commit (`git df show <sha>:<path>`),
and that list. It reports `<file>:<line> — <what identifies the employer> —
<neutral rewrite | move to ldf>`, or `none`, and edits nothing. **Commits made
through `/ari-skill-update` are reviewed here too**: its own review does not replace this one.

Recommend the push only when every unpushed commit's latest pass returned `none`.
A fix in a later commit does not help: the earlier commit would still publish
the content. Fold each fix into the commit that introduced it, then review every
rewritten commit again. Rewriting unpushed history is Ari's call: propose the
exact rewrite and what each rewritten commit will hold, and ask once.

### When `dotfiles push` fails

It stops at the first failing repo, names it, and pushes nothing after it.
Read the log, then act; you may run these two (read-only) yourself:

```zsh
dotfiles status                                   # tiers, dev repos against the lock, each repo's last push line
dotfiles logs --repo shared                       # or --repo .config/chrome-exoskeleton; --previous = the run before
```

| log says | cause | do |
|---|---|---|
| `Personal account is not logged into gh` | this machine's gh has no personal login | the user runs `env -u GITHUB_TOKEN gh auth login` (HTTPS) |
| `Token identity mismatch` | the stored personal token is not the personal account | `env -u GITHUB_TOKEN gh auth status`; re-login |
| `Detached HEAD: nothing to push` | commits made in a dev repo checked out detached (a dev repo is on `main` unless someone detached it; detached with nothing new is skipped silently) | **Dev repos** step 1, which the log's `§ Submodules step 1` hint means (`git -C ~/<path> branch -f main HEAD` if `main` is an ancestor, else ask), push again |
| `! [rejected]` (fetch first / non-fast-forward), or `Remote ref does not match after push` | the remote moved | shared: `dotfiles pull`; dev repo: `git -C ~/<path> pull --rebase origin main`, re-run its checks, push again |
| `lock update failed`, `lock update did not land on the pushed HEAD`, `pointer bump refused` | the `flake.lock` bump after a dev repo's push failed | the nix or hook output above the line; for the second, `dotfiles pull`, then push again |
| `pointer not bumped: checkout is not ahead of the lock` (a warning; the push goes on) | the dev repo's checkout is behind or off the locked commit | `git -C ~/<path> pull --ff-only origin main` (`/ari-dotfile--submodule` § When it fails), or **Dev repos** step 1 if it is detached; the next push bumps it |
| `slow step` | a step took longer than `ARI_DOTFILES_SLOW_STEP` (0.5s; pull's own fetch is allowed 5s) | read the step name; `dotfiles --timing <cmd>` times every step |
| `submodule not checked out` | a dev repo was never cloned here | `dotfiles apply dotfiles_repo` clones it (the log's `dotfiles init` does too) |
| `No such remote`, `Remote is not on github.com` | a rewired or broken checkout | `dotfiles status`, then **Dev repos** |
| DNS, timeout, TLS | network | retry; nothing was lost |
| a hook's own `[ERROR]` lines | the repo's pre-push hook refused | fix what it names; NEVER `--no-verify` |
| local log: `[EXO-PREPUSH] failed` | the local tier's pre-push hook ran the exoskeleton suite and it failed; the commit stands | `/ari-dotfile--submodule-chrome-exoskeleton` § When it fails, then push again |

## Placement rules

- **Generic → `~/.config` (df).** Anything correct on every machine: shell
  plugins, PATH policy (`prepend_to_path` for `~/.local/bin` and
  `$XDG_DATA_HOME/bin` is policy, not local), git config, nvim, `~/.config/bin`.
- **Company or machine-specific → `~/.local` (ldf).** Work env vars, cloud and
  remote-shell helpers, per-machine data for fzfdb selectors, `~/.local/bin`
  wrappers. Never a framework, never a launchd job, never a script that stands
  alone: an ldf component plugs into a df framework at one of the **Cutpoints**.
  Something that should run on a schedule or on screen unlock is a job plugin
  under `~/.local/share/dotfiles/jobs/`.
- **Some files are placed by Nix.** The dotfiles are being ported to nix-darwin
  and home-manager, and the port keeps the split (**Cutpoints**). A file
  home-manager places is a read-only symlink into `/nix/store`, among them git's config and
  ignore, tmux, Starship and gh's `config.yml`. **NEVER run `git config --global` or `gh config
  set`, or edit `~/.config/starship.toml` or `~/.config/tmux/tmux.conf`: edit the module, commit it
  (a switch builds only committed files), then `dotfiles switch --build`; Ari switches.** **NEVER `brew install`:** a new tool goes in a flake.
  Which module writes what, and how to edit, verify, build and switch: `/ari-dotfiles-nix`
  (§ Modules, § What Nix owns).
- **A packaged bin is placed from the store at its old path, so an edit to the clone's file
  reaches `$HOME` only after a commit and a `dotfiles switch`.** `~/.config/dotfiles/nix/ari-bins.nix`
  lists them: the `dotfiles` CLI (its `lib/`, `cmd/` and `steps/` too, though their `$HOME` links
  resolve into the clone), `run_log` and its helpers, the git helpers (`git-dotfiles`
  included), `notes` and the Mac utilities. Test: `readlink -f` of its `$HOME` path (e.g.
  `~/.config/bin/<name>`) ends in `/nix/store`. To try an edit before the switch, run the clone's
  file by path: `~/dotfiles/.config/bin/<name>`. The package recipes are `/ari-dotfiles-nix`'s.
- **Every other shared file in `$HOME` is an out-of-store link into `~/dotfiles`,** made by the
  bridge (`~/.config/dotfiles/nix/bridge.nix`): `readlink -f` ends in the clone. Edit it in
  place, as below.
- **Claude skills follow the same split.** The real directory lives in the tier
  that owns it, `~/dotfiles/.config/claude/skills/<name>/` (df, also at
  `~/.config/claude/skills/<name>/` through the directory link) or
  `~/.local/share/claude-skills/<name>/` (ldf), and `~/.claude/skills/<name>` is a
  symlink to it. Edit through either path; commit through the tier. Linking,
  adopting, and drift are `/ari-dotfiles-skill-registry`'s job.
- **Chrome Exoskeleton plugins follow the same split.** A plugin for a site you
  use only as an employee is ldf (`~/.local/share/chrome-exoskeleton/plugins/`);
  everything else is a file of the framework repo at `~/.config/chrome-exoskeleton/`,
  a dev repo (see **Dev repos**). Building, testing and the framework's own
  push are `/ari-dotfile--submodule-chrome-exoskeleton`'s job.
- **Starship and tmux follow the same split.** Generic config goes in `starship.nix`, `tmux.nix`
  and `nix/tmux/*.conf` (df); a work-only Starship table or tmux line goes in the local flake
  (ldf), at the plug-in points their **Cutpoints** rows name.
- **Split mixed files.** Keep the generic mechanism in config and parameterize
  the company detail from local:
  ```zsh
  # ~/.config/bin/chrome_work_open (df)
  domain="${WORK_EMAIL_DOMAIN:?set in the local tier}"
  # ~/.local/share/zsh/plugins/work.zsh (ldf)
  export WORK_EMAIL_DOMAIN=example.com
  ```
  fzfdb selectors: function in config, work aliases and bookmark data in local.

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

Run the `rg` line first. Show Ari its hits and the block, and run the block only after his `yes`.

```zsh
rg -n 'plugins/work.zsh' ~/dotfiles/.config ~/.local/share   # edit every hit; re-run until empty
git df rm --cached ~/dotfiles/.config/zsh/plugins/work.zsh
mv ~/dotfiles/.config/zsh/plugins/work.zsh ~/.local/share/zsh/plugins/work.zsh
git df commit -m "Move work.zsh to local tier" -- ~/dotfiles/.config/zsh/plugins/work.zsh
git ldf add ~/.local/share/zsh/plugins/work.zsh && git ldf commit -m "Add work.zsh from shared tier" -- ~/.local/share/zsh/plugins/work.zsh
```

Move the clone's file, never the `$HOME` link. The link to it dangles until the next `dotfiles switch` removes it.

## Cutpoints

Every framework lives in the shared tier; the local tier only plugs into one. The
framework knows the local root by convention (`$XDG_DATA_HOME/<framework>/…`, i.e.
`~/.local/share/<framework>/…`), discovers what is there at run time, reports each
plugin's tier, and installs whatever needs installing from a `dotfiles init` step.
The local tier therefore never installs anything, never owns a launchd
job and never ships a framework or a stand-alone script of its own. The Chrome
Exoskeleton is the model.

| Framework (df) | ldf plugs in at | How the framework finds it |
|---|---|---|
| zsh startup, `source_zsh_dir` in `~/.config/zsh/plugins/` | `~/.local/share/zsh/plugins/*.zsh` (secrets in `*.secret.zsh`, untracked) | sourced after the shared plugins |
| `dotfiles jobs` (`~/.config/dotfiles/cmd/jobs.zsh`; shared plugins `~/.config/dotfiles/jobs/`, shared deps `~/.config/dotfiles/deps/`) | `~/.local/share/dotfiles/jobs/<name>`, `~/.local/share/dotfiles/deps/<name>` | one launchd job runs both roots' plugins on unlock, login and a 5-minute tick; a plugin's `# deps:` line names deps run as its setup first (local wins); `dotfiles jobs list` |
| Chrome Exoskeleton, `exo` (`~/.config/chrome-exoskeleton/`) | `~/.local/share/chrome-exoskeleton/plugins/<name>/` | `exo link` mounts both roots; `/ari-dotfile--submodule-chrome-exoskeleton` |
| Claude skills, `/ari-dotfiles-skill-registry` (`~/.config/claude/skills/`) | `~/.local/share/claude-skills/<name>/` | symlinked into `~/.claude/skills` |
| Nix flake (`~/.config/dotfiles/nix/`: exports the nix-darwin and home-manager modules, never switched alone) | `~/.local/share/dotfiles/nix/`, this machine's flake | inverted: the local flake takes the shared one as an input and is the one switched (`darwinConfigurations.personal`); `/ari-dotfiles-nix` |
| `open-any` (`~/.config/zsh/plugins/open_any.zsh`) | `~/.local/bin/open-*` | discovered by name across both bin tiers |
| Starship prompt (`~/.config/dotfiles/nix/starship.nix`) | the local flake's `programs.starship.settings` tables | merged by the module system at a `dotfiles switch`; a key set in both tiers fails the build |
| tmux (`~/.config/dotfiles/nix/tmux.nix`, `nix/tmux/*.conf`) | the local flake's `programs.tmux.extraConfig`; a typhon working copy at `~/.local/share/tmux/local-plugins/tmux-typhon` | the module system appends the local lines at a `dotfiles switch`; the working copy loads instead of the pinned typhon |
| tmuxinator (`~/.config/tmuxinator/*.yml`) | `~/.local/share/tmuxinator/*.yml` | `TMUXINATOR_CONFIG`, set by `~/.config/zsh/plugins/tmux.zsh` when the dir exists; searched before the shared dir |
| Neovim (`~/.config/nvim/`) | `~/.local/share/nvim/site/plugin/*.lua` | nvim's own data-dir runtimepath (kept by lazy.nvim's rtp reset) |
| `/ari-gsw-calendar-add` event types | `~/.local/share/gsw-calendar-add/event-types.md` | the skill reads it beside its own **Event types** sections |
| `/ari-diagram-mermaid` and `/ari-diagram-gh-todo` palette | `~/.local/share/ari-diagram-mermaid/palette.mmd` | its `classDef` lines replace the skills' own, same class names |
| fzfdb selectors (functions in `~/.config/zsh/plugins/`) | `~/.local/share/{go_aws,kuber,aws_profile}/` | data read by the shared functions |
| `PATH` (`prepend_to_path` in `ari.zsh`) | `~/.local/bin/`, `~/.local/share/bin/` | on `PATH` on every machine |

**Adding a cutpoint**: build the framework in df with a local root under
`~/.local/share/<framework>/`, admit that root in both copies of the ldf allowlist
(`~/.local/local-dotfiles.git/info/exclude` and
`~/.config/new-machine/local-dotfiles-exclude`), give the framework a `list`/`status` that
names each plugin's tier, wire its install into a step (`~/.config/dotfiles/steps/<name>.zsh`:
a check and an apply), and add its row here. A plugin needing something outside its
tier (a launchd job, a compiled helper) is the sign that the framework is missing a
piece, not that the plugin should install it.

**Karabiner has no cutpoint, on purpose.** `bake` compiles `~/.config/karabiner/karabiner.ts/`
into `karabiner.json` and `src/raycast_bindings.json`, and both are committed so that a
binding change shows up as a readable diff. A local tier would have to be baked into those
same public files, so every Karabiner binding, Raycast deeplink and baked path is public.
A hotkey for a work-only command (an employer's Raycast extension, an internal URL) goes in
Raycast's own hotkey settings, not in the tables. Before you commit a re-baked
`karabiner.json`, read the staged diff that `bake` prints. It should change only what the
table edit changed.

## Dev repos

Some `~/.config` directories are *dev repos*: Ari's own public repos, each a plain git clone at
`~/dotfiles/.config/<name>`, linked whole to `~/.config/<name>` and ignored by the shared repo.
`~/dotfiles/.config/dotfiles/dev-repos` lists them. Today: `.config/chrome-exoskeleton`
(upstream `github.com/AriSweedler/chrome-exoskeleton`; `/ari-dotfile--submodule-chrome-exoskeleton`)
and `.config/plugged` (upstream `github.com/AriSweedler/plugged`; `/ari-dotfile--submodule-plugged`).
The shared flake takes each as a github input (`flake = false`), and
`~/dotfiles/.config/dotfiles/nix/flake.lock` locks the commit every other machine builds;
`dotfiles switch` builds each from its checkout's `HEAD` here. There is no `.gitmodules` and no
`git df submodule …`. Flags, log lines and healthcheck codes still say *submodule* and mean a dev
repo. The layout, a new one, `dotfiles pull` and every refusal: `/ari-dotfile--submodule`.

### Changing something inside a dev repo

One dotfiles change; never stop after the first commit.

1. **Be on its `main`.** `git -C ~/<path> branch --show-current` must print `main`, and it does
   unless someone detached the checkout. Nothing committed yet → `git -C ~/<path> switch main`.
   Committed while detached → `git -C ~/<path> branch -f main HEAD`, only if
   `git -C ~/<path> merge-base --is-ancestor main HEAD` succeeds; else show
   `git -C ~/<path> log --oneline --graph main...HEAD` and ask which history to keep.
2. **Commit in the dev repo** on `main`, explicit paths:
   `git -C ~/<path> add <files> && git -C ~/<path> commit -m "…"`. Its hooks
   and commit conventions apply, not the tier's.
3. **Its push, and the lock bump, are Ari's**: run **Review before push** on the
   dev repo's unpushed commits and end with "Run `dotfiles push` when ready."
   only when it passes (on the personal laptop, as soon as the commit lands). That pushes the
   dev repo, commits the `flake.lock` bump (**Pushing**) and pushes the shared tier with it.
   `dotfiles push --submodules` pushes the dev repos alone and still
   commits the bump; `--shared`, `--local` and `--no-<part>` narrow the scope the same way.
   Claude is denied the command. Afterwards, **Verify**.

No bump is made by hand: a dev repo pushed some other way gets its bump from the next
`dotfiles push`. The df pre-commit hook refuses a staged `flake.lock` that locks a dev repo at a
commit not on its `origin/main`: Ari pushes the dev repo first (`dotfiles push --submodules`),
then re-run the commit.

### Verify

```
git -C ~/<path> status -sb     → ## main...origin/main
dotfiles status                →  <sha> <path> (heads/main)    leading space, not +
git df status --short -- ~/dotfiles/.config/dotfiles/nix/flake.lock   → (empty)
```

Prefixes: space = the checkout is at the locked commit; `+` = it is elsewhere (a bump is due at
the next `dotfiles push`, or the checkout is behind a pulled lock); `-` = not cloned.

## Key locations

### Ignore files
- `~/.config/git/ignore` — global `core.excludesFile`, every repo on the machine, written by
  the git module (`/ari-dotfiles-nix` § Modules). Its
  `dotfiles.git` and `.local` lines matter only to the bare-repo fallback, whose work tree is `$HOME`.
- `~/dotfiles/.gitignore` — the shared repo's own ignore list. It also keeps out files that tools
  write into linked directories, such as `.config/nvim/lazy-lock.json`.
- `~/.local/local-dotfiles.git/info/exclude` — the local repo's allowlist.

### Shared (df)
- **Scripts**: `~/.config/bin/` on `$PATH`; the packaged ones are placed from the store (**Placement rules**)
- **Git, tmux, Starship and gh config**: home-manager modules in `~/.config/dotfiles/nix/`; where
  each lives and what a switch writes: `/ari-dotfiles-nix` § Modules
- **Git hooks**: `~/.config/git/dotfiles-hooks/` (df), `~/.config/git/local-dotfiles-hooks/` (ldf; needs bash 5)
- **Zsh plugins**: `~/.config/zsh/plugins/`, sourced first
- **Nvim**: `~/.config/nvim/`, lazy.nvim specs in `lua/plugins/`, `lazy = true` by default
- **Claude skills**: `~/.config/claude/skills/<name>/`, symlinked from `~/.claude/skills/<name>`
- **Dev repos**: listed in `~/dotfiles/.config/dotfiles/dev-repos`; today `~/.config/chrome-exoskeleton/`
  (with `~/.config/bin/exo`) and `~/.config/plugged/` (its `plugged` binary is a Nix package) — see
  **Dev repos**, `/ari-dotfile--submodule` (layout, creating one),
  `/ari-dotfile--submodule-chrome-exoskeleton` and `/ari-dotfile--submodule-plugged`
- **Jobs framework**: `~/.config/dotfiles/lib/jobs.zsh`; shared plugins in `~/.config/dotfiles/jobs/`
  (README = the plugin contract) — see **Cutpoints**
- **Nix flake**: `~/.config/dotfiles/nix/` (`flake.nix`, `darwin.nix`, `home.nix`), the shared
  modules — see `/ari-dotfiles-nix`
- **Harness**: `~/.config/bin/dotfiles` (init, pull, push, status, logs, git, jobs; `dotfiles help`) — see **Pushing**
  and **Bootstrapping a machine**; the push is token-pinned to `ARI_DOTFILES_GITHUB_LOGIN`.
  The file in `bin` is only the entrypoint; the program is `~/.config/dotfiles/lib/*.zsh`,
  one module per concern, each independent at source time (its README has the rules and
  the check). The `dotfiles` on `PATH` is the packaged copy, program included, so an edit to
  `lib/`, `cmd/` or `steps/` runs only as `zsh ~/dotfiles/.config/bin/dotfiles <verb>` until
  the next `dotfiles switch`

### Local (ldf)
- **Zsh plugins**: `~/.local/share/zsh/plugins/`, sourced after the shared dir
  via `source_zsh_dir --optional "${XDG_DATA_HOME}/zsh/plugins"`
- **Scripts**: `~/.local/bin/` and `~/.local/share/bin/`
- **Job plugins**: `~/.local/share/dotfiles/jobs/<name>` — see **Cutpoints**
- **Nix flake**: `~/.local/share/dotfiles/nix/`, this machine's flake, the one switched — see `/ari-dotfiles-nix`
- **Machine name**: one word in `~/.local/share/dotfiles/machine-name`. Read it with
  `dotfiles machine-name`, never the path; `dotfiles machine-name NAME` renames and commits
  it. `dotfiles init` writes a random one. `personal` turns off **Review before push**.
- **Data**: `~/.local/share/{go_aws,kuber,aws_profile,tmux_oneshot}/`
- **Claude skills**: `~/.local/share/claude-skills/<name>/`, symlinked from `~/.claude/skills/<name>`
  (`~/.local/share/claude/` is Claude Code's own install dir; hands off)

## Post-change sweep

As soon as a dotfiles change is committed, start the sweep without asking, in
parallel with **Review before push** when it runs. A subagent (this agent, when it is one)
runs `git df status`, `git ldf status` and `dotfiles status` (the dev repos),
reads each change (`diff` for modified, `cat` for untracked), and drafts one line
per commit, grouping tightly related files (a new config plus its include). It
edits and commits nothing:

    Shared (df): 1 modified
    Local (ldf): clean
      df: ~/.config/foo/bar.zsh → "foo: retry once on timeout" — the retry the last session left uncommitted

The plan goes into Workflow step 5's closing message; its one `yes` commits every
planned line, pushes local when it has an `origin`, and runs **Review before push** on anything shared (skipped on the personal laptop).
Both tiers clean → the two status lines, nothing to ask. A change the subagent
cannot explain is listed but left out of the plan.

## Bootstrapping a machine

`dotfiles init` (idempotent, `--dry-run`; what `bootstrap.sh` ends in) converges the whole machine but Nix,
whose installer and first switch are `/ari-dotfiles-nix`'s: every step checks, applies only where it finds
drift, and re-checks, then `dotfiles status` prints; a converged machine changes nothing.
`dotfiles steps` lists the steps and their groups (`repo`, `brew`, `tools`); `init --group repo` or
`init --only a,b` (= `dotfiles apply a b`) narrows it. Every verb answers `--help`, and so
does `dotfiles help <verb>`; a bare `dotfiles` lists the verbs.

The `repo` group is the dotfiles themselves:

- `dotfiles_repo`: the shared repo tracking `origin/main` with an ssh push url
  (`ARI_DOTFILES_PUSH_URL`), hooks wired, every dev repo cloned, `origin/main` fetched. That is
  the plain clone `~/dotfiles` when `~/dotfiles/.git` exists. Without it, the step clones the bare
  repo `~/dotfiles.git` and checks it out into `$HOME`. A pre-harness bare repo at `~/dotfiles` is
  renamed to `~/dotfiles.git` first, and having both is a manual conflict.
- `local_dotfiles_repo`: the local bare repo with the allowlist from
  `~/.config/new-machine/local-dotfiles-exclude` and its hooks. A remote is optional: without
  one the step is `ok`, the local tier stays on this machine and `dotfiles push` skips it.
- `claude_skills`: every tier-held skill linked into `~/.claude/skills`
  (`/ari-dotfiles-skill-registry`'s `link --prune`).
- `ssh_key`: the GitHub ssh key in the agent, its passphrase read from 1Password through an
  askpass helper (`op`; the item, vault and key path come from the local tier's
  `~/.local/share/zsh/plugins/dotfiles.zsh`, so a machine without them skips the step, and
  the check itself never calls 1Password).
- `dotfiles_jobs`: the one launchd job (`com.<user>.dotfiles-jobs`: screen unlock, login,
  every 5 minutes) that runs the job plugins of both tiers, booting out the per-plugin jobs
  it replaced. The plugin contract is `~/.config/dotfiles/jobs/README.md`; see **Cutpoints**.

`brew` is Homebrew itself; the flakes declare the brews, casks and packages (machine-only ones
in the local flake), and a `dotfiles switch` installs them (`/ari-dotfiles-nix`). `tools` is the rest (`raycast_sync`, `chrome_exoskeleton`: `exo deps ci`, `exo build`,
`plugged`, `karabiner`, …).

To back the local tier up, give it a remote. On the personal laptop Ari chose not to, so never propose it there:

```zsh
git ldf remote add origin <this machine's private repo>
git ldf add -A && git ldf commit -m "local dotfiles: initial snapshot" && git ldf push -u origin main
```

Keep `local-dotfiles-exclude` in sync with `~/.local/local-dotfiles.git/info/exclude` when the
allowlist changes.

`dotfiles pull` runs `git df pull --rebase --autostash`: a fast-forward when nothing is local,
otherwise local commits are replayed onto origin. A replay that conflicts is aborted, the tier is
left as it was, and the conflicting files are named; resolve by hand (`git df pull --rebase`,
fix, `git df rebase --continue`), then `dotfiles pull` again. It runs no init and no check:
it maps the pulled paths to the steps that watch them (`step::watches` in each step file),
warns with each affected step and the paths behind it, and prints the one command to run,
`dotfiles apply a b c`; a changed harness (`lib/`, `cmd/`, `steps/`) is live after the next `dotfiles switch`. `pull --dry-run`
fetches and reports the same for what the pull would bring. `dotfiles
status` shows both tiers, the dev repos against the lock and each repo's last push; `dotfiles push`
and `dotfiles logs` are under **Pushing**.

Hook setup for both tiers is documented in `~/.config/git/dotfiles-hooks/README.md`
and `~/.config/git/local-dotfiles-hooks/README.md`; those are the versioned source.
