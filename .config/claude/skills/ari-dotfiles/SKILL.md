---
name: ari-dotfiles
description: Edit and commit Ari's two-tier dotfiles (shared: `git df`, ~/.config, every machine; local: `git ldf`, one private repo cloned at ~/local-dotfiles on every machine, holding each machine's and each tag's files, which ldf-link links into ~/.local), run the `dotfiles switch` a commit needs and check the change is live, and, everywhere but the personal laptop, review every unpushed public commit for employer-identifying content before recommending a push
---

# Dotfiles

Ari's dotfiles are two git repos, one per tier, each a plain clone on every machine: the public
shared repo and the private local one, `ldf`. Pick the tier by whether the content should be
identical on every machine or belongs to one machine, or to the machines that share a tag. Claude
commits, runs the `dotfiles switch` a commit needs (Workflow step 3) and pushes the local tier; Ari
pushes the shared tier, its dev repos and its mirrors. The
shared tier, its dev repos and its mirrors are public; no push is recommended until each unpushed commit passes **Review before
push**, except on the personal laptop, where a commit is ready to push as soon as it lands.

| Tier | Alias | Repo | Worktree | Holds | Remote |
|---|---|---|---|---|---|
| Shared | `git dotfiles` / `git df` | plain clone `~/dotfiles` (git dir `~/dotfiles/.git`) | `~/dotfiles`; home-manager links its files into `$HOME` (`/ari-dotfiles-nix`) | Generic, every-machine config under `~/.config` | One shared repo; only Ari pushes |
| Local | `git local-dotfiles` / `git ldf` | plain clone `~/local-dotfiles` of `ldf` (git dir `~/local-dotfiles/.git`) | `~/local-dotfiles`; `ldf-link` links its files into `~/.local` | Company- and machine-specific code under `~/.local`: one machine's in `local/<machine>/`, a tag's in `<tag>/` | `ldf` on co2's Forgejo, on every machine; the agent pushes |

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

The local clone holds `local/<machine>/` (one machine's files, at their paths under `~/.local`),
one directory per tag (`mac/`, `nixos/`, `pi/`: files every machine with that tag shares), and
`machines` (one line per machine with its tags: `ozone mac`, `co2 nixos`, `ganymede nixos pi`).
A new file goes in `local/<machine>/` until a second machine needs it; then it moves to the tag
those machines share, never copied into each `local/<machine>/`. When no tag fits, or which tag is
unclear, ask Ari, naming the machines each choice reaches (`machines`).

`ldf-link` (`~/.config/bin/ldf-link`, a dry run unless `--execute`) links each `~/.local/<path>` to
`local/<machine>/<path>`, else to the one tag that has it: local beats a tag. It prunes links into
the clone whose source is gone, and replaces a real file only when identical. Every home-manager
activation runs it (`~/.config/dotfiles/nix/ldf.nix`), but a switch that changes nothing in the
system does not activate: after a fresh clone, a new file or a pull, run `ldf-link --execute`
yourself. Exit 1 has three causes:
- `conflict <path>: in tags <a> and <b>` (a path in two of this machine's tags, not in
  `local/<machine>/`) → the run links and prunes nothing. Ask Ari which tag keeps it, or put this
  machine's copy in `local/<machine>/`, then run again.
- `refuse <file>: differs from <source>` (a real file where a link goes; the rest of the run still
  applies) → `diff` the two, keep one copy (the clone's, or the real file's content committed into
  the clone), remove the real file, run again.
- `machine '<name>' is not in …/machines` → add the machine's line (**Bootstrapping a machine**).

A machine without `~/local-dotfiles/.git` has not moved yet: `git ldf` falls back to its old bare
repo `~/.local/local-dotfiles.git`, work tree `~/.local`, with an allowlist and an optional `origin`;
read every clone path in this skill as its `~/.local` path there. The moved machines (ozone, co2,
ganymede) kept the bare repo as `~/.local/local-dotfiles.git.retired`. The archived per-machine
repos' history is `local/ozone/`'s and `local/co2/`'s, merged in by git subtree: `git ldf log --
local/ozone` shows only the merge, because the old commits recorded their paths at the root.
State (`~/.local/state`) and cache (`~/.cache`) are never versioned.

## Workflow

1. Edit the file. Pick its tier with **Placement rules**. An existing shared file can be edited
   through `$HOME` or the clone, and the change is live at once. **A packaged bin is the
   exception** (**Placement rules**): **edit the clone's file and run that file to try it;
   `$HOME`'s copy changes only at the next `dotfiles switch`.** A bin built from a dev repo
   (run-log's four, `tmux-oneshot`) is not the clone's file: edit it in that dev repo (**Dev
   repos**). A mirror's files are the reverse: edit them only at their dotfiles source.
   - **Create a new shared file at its clone path, `~/dotfiles/<path>`, NEVER at `~/<path>`.** A
     file created at `~/<path>` is not in the repo, and git cannot see it. A new clone file appears
     in `$HOME` only after it is committed and switched (step 3), because the bridge links only
     what git tracks.
   - The exception is a directory linked whole, where either path works and the new file is live at
     once. Test it with `[[ -L ~/<dir> ]]`. Today these are `.config/claude` and the dev repos.
     Two things in them still wait for the switch (step 3): a new skill directory's
     `~/.claude/skills/<name>` link, and a packaged dev repo's bins.
     `.config/nvim` is not one: `nvim.nix` places the whole directory from the store, so an edit
     to `~/dotfiles/.config/nvim` reaches nvim only after a commit and a `dotfiles switch`.
   - **Edit or create a local file at its clone path, `~/local-dotfiles/local/<machine>/<path>`
     (or `~/local-dotfiles/<tag>/<path>`), NEVER through its `~/.local` link.** An edit is live at
     once through the link. A new file reaches `~/.local` only after it is committed and
     `ldf-link --execute` runs: ldf-link links only tracked files.
2. `git df add <abs path>` or `git ldf add <abs clone path>`. Give a new shared file its clone path:
   its `$HOME` path does not exist yet. Give every local file its clone path: `git ldf` refuses a
   `~/.local` path as outside the work tree. Commit with a descriptive
   message and the same paths after `--` (`git df commit -m "…" -- <abs paths>`).
   **In every repo these dotfiles touch (both tiers and each dev repo's checkout), NEVER
   `git add -A`, `git add .` or `git commit -a`: stage and commit named paths only.** A driver, a
   tool (`bake`) or another session may have files of its own there, staged or untracked, and a
   sweeping add commits them before anyone approved them. A path inside a dev repo
   (`~/.config/run-log/…`) is ignored by the shared repo, and `git df add` refuses it:
   follow **Dev repos** instead.
3. Print `git df log --oneline -1` / `git ldf log --oneline -1` to confirm the tier: it must
   show the subject just committed. Then test every committed path. **You MUST run `dotfiles
   switch` yourself, now, when ANY committed path:**
   - is under either tier's `nix/` directory (`~/dotfiles/.config/dotfiles/nix`,
     `~/.local/share/dotfiles/nix`);
   - is a packaged bin or a file a package copies: `readlink -f` of its `$HOME` path ends in
     `/nix/store`, or it is in run-log, tmux-oneshot or plugged;
   - adds, removes or moves a shared file outside a directory linked whole (step 1), a skill
     directory, or a zsh plugin in either tier.

   Switch per `/ari-dotfiles-nix` § Switch: build, preview, switch, then its check that the change
   itself is live. **NEVER report the change live before that check passes. NEVER tell Ari to run
   the switch**, unless § Switch's own run was refused. A commit that matches none is live at once.
4. Shared: run **Review before push** (its first step skips it on the
   personal laptop). Local: `git ldf pull --rebase && git ldf push` now (**Pushing**), then
   `ldf-link --execute` when the commit or the pull added or removed a file. Start the
   **Post-change sweep** alongside.
5. Close with one message: what landed (the switch's own ldf `flake.lock` commit included), what
   the switch made live and the check that showed it, or how it failed,
   the review verdicts (if it ran), the sweep's plan, and any history rewrite the review calls
   for, ending in one question that covers them all (none when nothing is pending). When the
   change touched a path in a `[mirror]`'s `watch` list, say the next `dotfiles push` also
   exports and publishes that mirror. End with "Run
   `dotfiles push` when ready." once every unpushed shared commit, including any
   the `yes` just made, has passed the review. On the personal laptop
   (`dotfiles machine-name` prints `ozone`), end with it as soon as the commit lands.

**Always pass absolute paths to `git df` and `git ldf`.** Relative pathspecs
resolve against the cwd, so a `share/...` path silently matches nothing.

```zsh
git df status
git df add ~/dotfiles/.config/bin/my-script && git df commit -m "Add my-script" -- ~/dotfiles/.config/bin/my-script
git df add ~/.config/zsh/plugins/fzf.zsh && git df commit -m "fzf: preview files with bat" -- ~/.config/zsh/plugins/fzf.zsh   # tracked: mapped

git ldf status
git ldf add ~/local-dotfiles/local/ozone/share/zsh/plugins/foo.zsh && git ldf commit -m "Add foo plugin" -- ~/local-dotfiles/local/ozone/share/zsh/plugins/foo.zsh   # ozone; elsewhere local/<its machine-name>
git ldf pull --rebase && git ldf push
ldf-link --execute    # a new file: link it into ~/.local

git -C ~/.config/run-log add bin/irun && git -C ~/.config/run-log commit -m "irun: …" -- bin/irun   # a dev repo
```

The harness spells the same two things without the aliases: `dotfiles git <args…>` runs git on
the shared tier, `dotfiles --local git <args…>` is `git ldf …`, and `dotfiles [--local] --dir`
prints the tier's git dir (`ARI_DOTFILES_DF_GIT_DIR`; `~/dotfiles/.git` on a clone). `dotfiles git`
passes its arguments untouched, so it needs clone paths. Only `git df` maps `$HOME` paths.

The clone has no allowlist: it holds only what was put in it, and tool data and caches stay in
`~/.local`, outside it. Only an unmoved machine's bare repo has one,
`~/.local/local-dotfiles.git/info/exclude` (edited with `dotfiles --local git --edit`). Neither
keeps out another session's files: a skill-update driver's unapproved edits sit in
`share/claude-skills/`, so `git ldf add -A` is unsafe too.

**When `git ldf status` fails:**
- `git: 'ldf' is not a git command` → `~/.config/git/config` lacks the alias, which
  `~/.config/dotfiles/nix/git.nix` writes there at a `dotfiles switch`. The fix is that switch,
  which Claude runs (Workflow step 3), never an alias added elsewhere.
- `fatal: not a git repository` (neither `~/local-dotfiles/.git` nor
  `~/.local/local-dotfiles.git` exists) → no local tier yet. Say the edit is untracked and point
  at **Bootstrapping a machine**.
- `fatal: … is outside repository` → a `~/.local` path; give its clone path.

**When the ldf pre-commit hook rejects** (exit 1, one `[ERROR]` line), fix the
cause. NEVER `--no-verify`. NEVER `git ldf add -f` a `.secret.` path.
- `bash 5 required; this is macOS /bin/bash without mapfile` → bash 5 comes from Nix
  (`/ari-dotfiles-nix`): run `dotfiles switch` (Workflow step 3), then retry. NEVER `brew install bash`.
- `refusing to commit a secret file | path='...'` → `git ldf rm --cached <abs clone path>`, then
  move the file out of the clone to its `~/.local` path (**Secrets**).
- `staged content looks like a credential | path='...'` → move the literal to the
  plugin's `*.secret.zsh` sibling (recipe under **Secrets**), leave a pointer
  comment, re-stage.

## Pushing

- **Shared: NEVER `git df push` and NEVER run `dotfiles push`.** Ari runs it
  (denied to Claude in settings). It first exports each mirror (**Dev repos**):
  when a path in the mirror's manifest `watch` list changed since its last
  export, it builds the mirror's package from the shared HEAD and commits it in
  the checkout as `<dir>: mirror dotfiles <sha7>` (`/ari-dotfile--submodule` § Mirrors).
  It then pushes every dev repo and mirror, in parallel; for each published dev
  repo (a mirror has no lock) it runs `nix flake update <input>` and commits the
  shared tier's `flake.lock` alone (`<name>: bump to <sha> (<subject>)`); then
  it pushes the shared repo, all as the personal account by token (no key
  swap), and the local tier alongside to `ldf`, with the ssh agent's key (its
  pre-push hook included). A repo already at its
  `origin/main` is skipped silently (the `submodules done` line counts the dev
  repos checked, pushed and bumped). **A failed dev repo or mirror push, or a
  refused bump, skips the shared push (`skipped (a submodule failed)`); an export
  that fails (any `mirror not exported` line) skips nothing, but the run still
  exits non-zero (`push failed`; after an empty `--edit` plan, with no further line).**
  Each repo's output lands in `~/.local/state/dotfiles/push/<repo>.log`
  (`shared`, `local`, or the dev repo's path; `.log.bak.1` … `.log.bak.5` = the five runs before).
  After committing, run **Review before push** and end with "Run `dotfiles push`
  when ready." only when it passes; on the personal laptop skip the review and end
  with that line as soon as the commit lands.
- **Local: `git ldf pull --rebase && git ldf push` after every ldf commit, on every machine, the
  personal laptop included.** No confirmation needed and no review (`ldf` is private). Every moved
  machine pushes to the one `ldf`, and `dotfiles pull` does not pull it, so pull first; then
  `ldf-link --execute` when the pull brought files in or took them away. `dotfiles push` also
  pushes a local commit left unpushed. NEVER `--force`.
  - The rebase conflicts → `git ldf rebase --abort`, name the files, and ask Ari.
  - co2's Forgejo unreachable → the commit stands; say "committed, not pushed", and the next
    `git ldf push` or `dotfiles push` sends it.
  - Only an unmoved bare repo may lack an `origin`: there `git ldf push` says so and exits 0, and
    the commit is the last step.

### Review before push

Runs on every machine but the personal laptop, so a new or unnamed machine is reviewed.
Check first:

```zsh
[[ "$(dotfiles machine-name)" == ozone ]] && echo skip || echo review
```

`skip` → dispatch no reviewer: the commit is ready, so end with "Run `dotfiles
push` when ready." as soon as it lands. `review` → each unpushed shared-tier,
dev repo or mirror commit becomes public on Ari's push, so review every one for content
that identifies the employer, using the identifying-content list in
`/ari-skill-update` § Rules:

```zsh
git df log --reverse --format=%h origin/main..main                     # shared tier
git -C ~/<path> log --reverse --format=%h origin/main..main            # each dev repo `dotfiles status` lists
git -C ~/dotfiles/<path> log --reverse --format=%h origin/main..main   # each [mirror] in dev-repos (status omits them)
```

A mirror's `<dir>: mirror dotfiles <sha7>` commit, the push's own export included, passes when
the shared commits it copies passed. When the commits touch a mirror's `watch` path or its
checkout, the mirror preflight (`/ari-dotfile--submodule` § Verify a mirror) must pass too.

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

It pushes every repo it can, then ends in `push failed` and, on a terminal, a table of each
repo's result; what skips the shared push is under **Pushing**. Read the log, then act. "Push
again" below means: close per Workflow step 5, through **Review before push** when the fix
committed anything. Both commands are read-only; run them yourself:

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
| `pointer not bumped: checkout is not ahead of the lock` (a warning; the push goes on) | the dev repo's checkout is behind or off the locked commit | `dotfiles pull` (it fast-forwards a clean checkout on `main`), else `git -C ~/<path> pull --ff-only origin main` (`/ari-dotfile--submodule` § When it fails), or **Dev repos** step 1 if it is detached; the next push bumps it |
| `mirror not exported: …`, on Ari's terminal only (no push log holds it) | the export failed: the package did not build, the checkout `~/dotfiles/<path>` is not on `main`, its `<dir>/` has uncommitted changes, or the copy or commit failed | ask Ari for the line; its row in `/ari-dotfile--submodule` § When it fails (never a bare `switch main`; save a `<dir>/` edit before the `restore`/`clean` its `fix=` names), then push again |
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
  wrappers. The file lives in the clone, in `local/<machine>/`, or in a tag's directory when
  every machine with that tag needs it. Never a framework, never a launchd job, never a script that stands
  alone: an ldf component plugs into a df framework at one of the **Cutpoints**.
  Something that should run on a schedule or on screen unlock is a job plugin
  under `~/.local/share/dotfiles/jobs/`.
- **Some files are placed by Nix.** The dotfiles are being ported to nix-darwin
  and home-manager, and the port keeps the split (**Cutpoints**). A file
  home-manager places is a read-only symlink into `/nix/store`, among them git's config and
  ignore, tmux, Starship, gh's `config.yml` and the whole `~/.config/nvim`. **NEVER run
  `git config --global` or `gh config set`, or edit `~/.config/starship.toml` or `~/.config/tmux/tmux.conf`: edit the module, commit it
  (a switch builds only committed files), then switch (Workflow step 3).** **NEVER `brew install`:** a new tool goes in a flake.
  Which module writes what, and how to edit, verify, build and switch: `/ari-dotfiles-nix`
  (§ Modules, § What Nix owns).
- **A packaged bin is placed from the store at its old path, so an edit to the clone's file
  reaches `$HOME` only after a commit and a `dotfiles switch`.** `~/.config/dotfiles/nix/ari-bins.nix`
  lists them: the `dotfiles` CLI (its `lib/`, `cmd/` and `steps/` too, though their `$HOME` links
  resolve into the clone), the git helpers (`git-dotfiles` included), `notes` and the Mac
  utilities. Test: `readlink -f` of its `$HOME` path (e.g.
  `~/.config/bin/<name>`) ends in `/nix/store`. To try an edit before the switch, run the clone's
  file by path: `~/dotfiles/.config/bin/<name>`. The package recipes are `/ari-dotfiles-nix`'s.
  The same list places run-log's four bins and `tmux-oneshot` at `~/.config/bin`, built from
  their dev repos (**Dev repos**); try an edit by running the checkout's file,
  `~/dotfiles/.config/<repo>/bin/<name>`.
- **Every other shared file in `$HOME` is an out-of-store link into `~/dotfiles`,** made by the
  bridge (`~/.config/dotfiles/nix/bridge.nix`): `readlink -f` ends in the clone. Edit it in
  place, as below.
- **Claude skills follow the same split.** The real directory lives in the tier
  that owns it, `~/dotfiles/.config/claude/skills/<name>/` (df, also at
  `~/.config/claude/skills/<name>/` through the directory link) or
  `~/.local/share/claude-skills/<name>/` (ldf, whose files are links into the clone), and
  `~/.claude/skills/<name>` is a symlink to it. Edit through either path; commit through the
  tier, an ldf skill's files by their clone paths. Linking,
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
`<plugin>.secret.zsh` beside the plugin that needs it in `~/.local`, a real file never put in the
clone (an unmoved bare repo's allowlist excludes it); `*.secret.zsh` is excluded from ldf. A
shell sources it only once the local flake declares it under its own `local-` key, like any
local plugin (**Cutpoints**, zsh row), and Workflow step 3 has switched.

```zsh
f=~/.local/share/zsh/plugins/foo.secret.zsh
[[ -e "$f" ]] || install -m 600 /dev/null "$f"   # never truncate an existing one
echo "export FOO_TOKEN='...'" >> "$f"
```

In the tracked plugin leave only a pointer:
`# Token exports: foo.secret.zsh (untracked, mode 600, listed in the local flake)`.
The ldf pre-commit hook rejects `.secret.` paths and token-shaped content. No
shared `get secrets` helper exists yet; do not assume one.

### Moving a file between tiers

Run the `rg` line first. Show Ari its hits and the block, and run the block only after his `yes`.

```zsh
rg -n 'plugins/work.zsh' ~/dotfiles/.config ~/local-dotfiles   # edit every hit; re-run until empty
src=~/dotfiles/.config/zsh/plugins/work.zsh
dst=~/local-dotfiles/local/$(dotfiles machine-name)/share/zsh/plugins/work.zsh   # or ~/local-dotfiles/<tag>/share/…
[[ ! -e $dst ]] && mkdir -p ${dst:h} && git df rm --cached $src && mv $src $dst \
  && git df commit -m "Move work.zsh to local tier" -- $src \
  && git ldf add $dst && git ldf commit -m "Add work.zsh from shared tier" -- $dst
git ldf pull --rebase && git ldf push
ldf-link --execute
```

Move the clone's file, never the `$HOME` link. The old shared link dangles until Workflow step 3's switch removes it: run it after the block. A zsh
plugin moved into ldf loads only once the local flake declares it (**Cutpoints**, zsh row): add
that line before the switch.

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
| zsh startup, the Nix-built `~/.config/zsh/plugins.list.zsh` (`nix/zsh-plugins.nix`) | `~/.local/share/zsh/plugins/*.zsh` (secrets in `*.secret.zsh`, untracked) | sourced only when the local flake declares it, after the shared plugins, under a `local-` key: `dotfiles.zsh.plugins.local-<name> = "<abs path>";`, since a key equal to a shared plugin's name replaces that plugin in its place; its `<name>.secret.zsh` takes a key the same way (`/ari-dotfiles-nix` § Change a file); a new or removed plugin in either tier is live after a switch |
| `dotfiles jobs` (`~/.config/dotfiles/cmd/jobs.zsh`; shared plugins `~/.config/dotfiles/jobs/`, shared deps `~/.config/dotfiles/deps/`) | `~/.local/share/dotfiles/jobs/<name>`, `~/.local/share/dotfiles/deps/<name>` | one launchd job runs both roots' plugins on unlock, login and a 5-minute tick; a plugin's `# deps:` line names deps run as its setup first (local wins); `dotfiles jobs list` |
| Chrome Exoskeleton, `exo` (`~/.config/chrome-exoskeleton/`) | `~/.local/share/chrome-exoskeleton/plugins/<name>/` | `exo link` mounts both roots; `/ari-dotfile--submodule-chrome-exoskeleton` |
| Claude skills, `/ari-dotfiles-skill-registry` (`~/.config/claude/skills/`) | `~/.local/share/claude-skills/<name>/` | symlinked into `~/.claude/skills` |
| Nix flake (`~/.config/dotfiles/nix/`: exports the nix-darwin and home-manager modules, never switched alone) | `~/.local/share/dotfiles/nix/`, this machine's flake | inverted: the local flake takes the shared one as an input and is the one switched (`darwinConfigurations.ozone` on the personal laptop); `/ari-dotfiles-nix` |
| `open-any` (`~/.config/zsh/plugins/open_any.zsh`) | `~/.local/bin/open-*` | discovered by name across both bin tiers |
| Starship prompt (`~/.config/dotfiles/nix/starship.nix`) | the local flake's `programs.starship.settings` tables | merged by the module system at a `dotfiles switch`; which leaves conflict: `/ari-dotfiles-nix` § Modules |
| tmux (`~/.config/dotfiles/nix/tmux.nix`, `nix/tmux/*.conf`) | the local flake's `programs.tmux.extraConfig`; a typhon working copy at `~/.local/share/tmux/local-plugins/tmux-typhon` | the module system appends the local lines at a `dotfiles switch`; the working copy loads instead of the pinned typhon |
| tmuxinator (`~/.config/tmuxinator/*.yml`) | `~/.local/share/tmuxinator/*.yml` | `TMUXINATOR_CONFIG`, set by `~/.config/zsh/plugins/tmux.zsh` when the dir exists; searched before the shared dir |
| Neovim (`~/.config/nvim/`) | `~/.local/share/nvim/site/plugin/*.lua` | nvim's default runtimepath holds `~/.local/share/nvim/site`, so its `plugin/` loads beside the store-placed config |
| `/ari-gsw-calendar-add` event types | `~/.local/share/gsw-calendar-add/event-types.md` | the skill reads it beside its own **Event types** sections |
| `/ari-diagram-mermaid` and `/ari-diagram-gh-todo` palette | `~/.local/share/ari-diagram-mermaid/palette.mmd` | its `classDef` lines replace the skills' own, same class names |
| fzfdb selectors (functions in `~/.config/zsh/plugins/`) | `~/.local/share/{go_aws,kuber,aws_profile}/` | data read by the shared functions |
| `PATH` (`prepend_to_path` in `ari.zsh`) | `~/.local/bin/`, `~/.local/share/bin/` | on `PATH` on every machine |

**Adding a cutpoint**: build the framework in df with a local root under
`~/.local/share/<framework>/` (the clone needs nothing more; for a machine not moved yet, admit
the root in both copies of its bare repo's allowlist, `~/.local/local-dotfiles.git/info/exclude`
and `~/.config/new-machine/local-dotfiles-exclude`), give the framework a `list`/`status` that
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
(upstream `github.com/AriSweedler/chrome-exoskeleton`; `/ari-dotfile--submodule-chrome-exoskeleton`),
`.config/run-log` (upstream `github.com/AriSweedler/run-log`; `/ari-dotfile--submodule-run-log`),
`.config/plugged` (upstream `github.com/AriSweedler/plugged`; `/ari-dotfile--submodule-plugged`)
and `.config/tmux-oneshot` (upstream `github.com/AriSweedler/tmux-oneshot`; `/ari-dotfile--submodule-tmux-oneshot`).
The shared flake takes each as a github input (`flake = false`), and
`~/dotfiles/.config/dotfiles/nix/flake.lock` locks the commit every other machine builds;
`dotfiles switch` builds each from its checkout's `HEAD` here. There is no `.gitmodules` and no
`git df submodule …`. Flags, log lines and healthcheck codes still say *submodule* and mean a dev
repo, and the *submodule* flags and counts cover mirrors too. The layout, a new one, `dotfiles pull`
and every refusal: `/ari-dotfile--submodule`.

The manifest also lists *mirrors* (`[mirror]`; today ari-zshlib): public repos whose `<dir>`
(`lib`) `dotfiles push` exports from a shared-flake package (**Pushing**). A mirror is not
linked into `$HOME`: address its checkout as `~/dotfiles/<path>` (`~/dotfiles/.config/ari-zshlib`),
never `~/<path>`. **NEVER edit a file under its `<dir>` in the checkout; edit its dotfiles source.**
Mirrors: `/ari-dotfile--submodule` § Mirrors.

### Changing something inside a dev repo

One dotfiles change; never stop after the first commit.

1. **Be on its `main`.** `git -C ~/<path> branch --show-current` must print `main`, and it does
   unless someone detached the checkout. Nothing committed yet → `git -C ~/<path> switch main`.
   Committed while detached → `git -C ~/<path> branch -f main HEAD`, only if
   `git -C ~/<path> merge-base --is-ancestor main HEAD` succeeds; else show
   `git -C ~/<path> log --oneline --graph main...HEAD` and ask which history to keep.
2. **Commit in the dev repo** on `main`, named paths only (Workflow step 2's NEVER holds here too):
   `git -C ~/<path> add <paths> && git -C ~/<path> commit -m "…" -- <paths>`. Its hooks
   and commit conventions apply, not the tier's. A commit to a packaged repo (run-log,
   tmux-oneshot, plugged), or one that adds a skill directory, then takes Workflow step 3's switch.
3. **Its push, and the lock bump, are Ari's**: run **Review before push** on the
   dev repo's unpushed commits, **and on every unpushed shared commit, even for
   `--submodules`: a mirror export publishes from the shared HEAD**, and end with "Run `dotfiles push` when ready."
   only when it passes (on the personal laptop, as soon as the commit lands). That pushes the
   dev repo, commits the `flake.lock` bump (**Pushing**) and pushes the shared tier with it.
   `dotfiles push --submodules` exports the mirrors, pushes the dev repos and mirrors alone and still
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
  write under `~/.config`, such as `.config/gh/hosts.yml`.
- `~/.local/local-dotfiles.git/info/exclude` — the allowlist of a machine not moved onto the
  clone yet; the clone has none.

### Shared (df)
- **Scripts**: `~/.config/bin/` on `$PATH`; the packaged ones are placed from the store (**Placement rules**)
- **Git, tmux, Starship and gh config**: home-manager modules in `~/.config/dotfiles/nix/`; where
  each lives and what a switch writes: `/ari-dotfiles-nix` § Modules
- **Git hooks**: `~/.config/git/dotfiles-hooks/` (df), `~/.config/git/local-dotfiles-hooks/` (ldf; needs bash 5)
- **Zsh plugins**: `~/.config/zsh/plugins/`, sourced first
- **Nvim**: `~/.config/nvim/`, placed whole from the store by `~/.config/dotfiles/nix/nvim.nix`; edit
  `~/dotfiles/.config/nvim`. Plugins are start packages each pinned by `nvim-pack-lock.json` (rev and
  hash), placed in `~/.local/share/nvim/site/pack/nix/start`; nothing installs or updates one at run
  time (`/ari-dotfiles-nix` § The bridge)
- **Claude skills**: `~/.config/claude/skills/<name>/`, symlinked from `~/.claude/skills/<name>`
- **Dev repos**: listed in `~/dotfiles/.config/dotfiles/dev-repos`; today `~/.config/chrome-exoskeleton/`
  (with `~/.config/bin/exo`), `~/.config/run-log/` (its four bins are placed at `~/.config/bin`),
  `~/.config/plugged/` (its `plugged` binary is a Nix package) and `~/.config/tmux-oneshot/` (its
  bin is placed at `~/.config/bin/tmux-oneshot`) — see
  **Dev repos**, `/ari-dotfile--submodule` (layout, creating one),
  `/ari-dotfile--submodule-chrome-exoskeleton`, `/ari-dotfile--submodule-run-log`,
  `/ari-dotfile--submodule-plugged` and `/ari-dotfile--submodule-tmux-oneshot`
- **ldf-link**: `~/.config/bin/ldf-link`, run at each activation by
  `~/.config/dotfiles/nix/ldf.nix`; tests `~/.config/dotfiles/tests/test_ldf_link.sh`
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
Each file below is a link into the clone `~/local-dotfiles`, to `local/<machine>/<path>` or
`<tag>/<path>`; edit and commit it there. The clone's `machines` file gives each machine its tags.
- **Zsh plugins**: `~/.local/share/zsh/plugins/`, sourced after the shared ones once the
  local flake declares each under a `local-` key (**Cutpoints**)
- **Scripts**: `~/.local/bin/` and `~/.local/share/bin/`
- **Job plugins**: `~/.local/share/dotfiles/jobs/<name>` — see **Cutpoints**
- **Nix flake**: `~/.local/share/dotfiles/nix/`, this machine's flake, the one switched — see `/ari-dotfiles-nix`
- **Machine name**: one word in `~/.local/share/dotfiles/machine-name`. Read it with
  `dotfiles machine-name`, never the path; `dotfiles machine-name NAME` renames and commits
  it. `dotfiles init` writes a random one. `ozone` (the personal laptop) turns off **Review before push**.
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
planned line, switches when a line needs it (Workflow step 3), pushes local, and runs **Review before push** on anything shared (skipped on the personal laptop).
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
- `local_dotfiles_repo`: with the clone `~/local-dotfiles`, it only wires its hooks
  (`core.hooksPath` = `~/.config/git/local-dotfiles-hooks`), warns on unpushed commits, and
  reports `ok clone`. On a machine not moved yet, it is the old bare repo with the allowlist from
  `~/.config/new-machine/local-dotfiles-exclude` and its hooks, a remote optional.
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

No step clones `ldf`. A new machine joins it by hand. `git ldf remote get-url origin` on a moved
machine gives the URL (co2 itself uses `forgejo@localhost:ari/ldf.git`). Wire the hooks before the
first commit, so the secret check runs on it. Ask Ari for the machine's tags before writing its
`machines` line.

```zsh
[[ -d ~/local-dotfiles/.git ]] || git clone <ldf url> ~/local-dotfiles
dotfiles apply local_dotfiles_repo        # hooks; then it reports ok clone
# add "<machine> <tags>" to ~/local-dotfiles/machines and the machine's files under local/<machine>/
git ldf add ~/local-dotfiles/machines ~/local-dotfiles/local/<machine>/<paths> && git ldf commit -m "local/<machine>: join ldf" -- ~/local-dotfiles/machines ~/local-dotfiles/local/<machine>/<paths>
git ldf pull --rebase && git ldf push
ldf-link --execute
```

On a machine not moved yet, keep `local-dotfiles-exclude` in sync with
`~/.local/local-dotfiles.git/info/exclude` when the allowlist changes.

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
