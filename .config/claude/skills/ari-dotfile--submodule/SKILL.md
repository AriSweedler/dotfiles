---
name: ari-dotfile--submodule
description: Create and work in a dotfiles submodule — one of Ari's public repos checked out at ~/.config/<name>, recorded in the shared tier as a pointer, with its own hooks, driver, check and skills. The layout every submodule follows, the recipe for a new one, how commits, pushes and pointer bumps flow, and what refuses when. Per-repo specifics live in ari-dotfile--submodule-<name>.
---

# Dotfiles submodules

A submodule is a directory under `~/.config` whose files belong to another git
repo. The shared tier (`git df`, `/ari-dotfiles`) records only a commit hash
for it, the **pointer**; every other machine checks that hash out.
`~/.gitmodules` declares them; `cd ~ && git df submodule status` lists them.

**Warranted when** the code has its own toolchain, tests and release cadence,
stands as a public repo on its own, and would drown the dotfiles log: a
framework, an extension, a compiled CLI. **Not warranted** for a script, a zsh
plugin, a skill or config: those are files of a tier (`/ari-dotfiles`
Placement rules). Company-specific code never enters a submodule; it plugs in
from the local tier at the submodule's local root (`/ari-dotfiles` Cutpoints).

## Layout contract

| Piece | Path | Tier | Notes |
|---|---|---|---|
| Repo | `~/.config/<name>/`, upstream `github.com/AriSweedler/<name>`, public | df holds the pointer | on `main`; `.git` is a file after `submodule update`, a directory after an in-place add; both work |
| Declaration | `~/.gitmodules`: `[submodule ".config/<name>"]`, `path`, an https `url` | df | what `dotfiles push`, `dotfiles init`, `dotfiles status` and the skill registry enumerate |
| Driver | `~/.config/bin/<name> -> ../<name>/bin/<name>` | df | one entry point with subcommands; `~/.config/bin` is on `PATH` |
| Check, build | `<name> check`, `<name> build` (or the repo's `bin/<name>-dev …`) | repo | each ends in one `[OK]` line; anything else is a failure |
| Hooks | `.githooks/pre-commit` runs the check; `.githooks/commit-msg` greps the message against the denylist | repo | `core.hooksPath=.githooks` is local config: a fresh checkout has no hooks until the `new-machine` step wires it |
| Denylist | `~/.local/share/<name>/denylist.txt`: one regex per line, `#` comments | ldf | what the public repo must never contain; absent → both hooks are no-ops, review by eye |
| Skills | `~/.config/<name>/skills/<skill>/SKILL.md`, symlinked into `~/.claude/skills` by `/ari-dotfiles-skill-registry` `link` | repo | committed in the repo, never `git df add`ed; `adopt` refuses a submodule |
| Local plug-in root (optional) | `~/.local/share/<name>/…` | ldf | admitted in both ldf allowlists; discovered at run time; the repo never requires it |
| Bootstrap | `new-machine` step `<name>` with `STEP_NEEDS=dotfiles_repo`; a clause in `dotfiles init`'s `init done … next=` line | df | `~/.config/new-machine/lib/steps.zsh`, `~/.config/dotfiles/lib/init.zsh` |
| Skill | `/ari-dotfile--submodule-<name>` | repo | the repo's commands, hooks, workflow, failures; everything else is here |

Commit identity in the repo is the personal address (what
`git -C ~/.config/chrome-exoskeleton config user.email` prints), never the
work one: the repo is public, files and messages alike.

## Creating one

Claude does 1–5 and 8–10; the user does 6, 7 and 11. Nothing here pushes.

1. **Repo.** `git init -b main ~/.config/<name>`;
   `git -C ~/.config/<name> config user.email <personal address>`;
   `git -C ~/.config/<name> remote add origin https://github.com/AriSweedler/<name>.git`.
   Write `bin/<name>`, its `check` and `build`, `README.md`, `.gitignore`.
2. **Hooks.** `.githooks/pre-commit` (`exec` the check) and `.githooks/commit-msg`
   (denylist grep; `exit 0` when `~/.local/share/<name>/denylist.txt` is
   unreadable), both `chmod +x`; then
   `git -C ~/.config/<name> config core.hooksPath .githooks`.
   Model: `~/.config/chrome-exoskeleton/.githooks/`.
3. **Local tier.** `~/.local/share/<name>/denylist.txt` (copy
   `~/.local/share/chrome-exoskeleton/denylist.txt`). A local plug-in root also
   needs `!/share/<name>/` in `~/.local/local-dotfiles.git/info/exclude` and in
   `~/.config/new-machine/local-dotfiles-exclude`. `git ldf add <abs paths>`,
   commit, `git ldf push`.
4. **Driver.** `ln -s ../<name>/bin/<name> ~/.config/bin/<name>`;
   `git df add ~/.config/bin/<name>`, commit.
5. **Skill and first commit.** `~/.config/<name>/skills/ari-dotfile--submodule-<name>/SKILL.md`;
   `git -C ~/.config/<name> add <files> && git -C ~/.config/<name> commit -m "feat: …"`.
   The hooks run; the check must be green.
6. **User: the remote.** An empty public `github.com/AriSweedler/<name>`:
   github.com/new, or
   `GH_TOKEN="$(env -u GITHUB_TOKEN gh auth token -u AriSweedler)" gh repo create AriSweedler/<name> --public`.
7. **Declare, then the user pushes.**
   `cd ~ && git df submodule add https://github.com/AriSweedler/<name>.git .config/<name>`:
   the path is already a repo, so nothing is cloned; `.gitmodules` and the
   pointer are staged. The user runs `dotfiles push --submodules`: it pushes the
   repo as the personal account, sets its `origin/main`, and commits the pointer
   alone (`<name>: bump to <sha> (<subject>)`); `.gitmodules` stays staged.
8. **Declaration commit.**
   `git df commit -m "<name>: declare the submodule (<what it is>)" -- ~/.gitmodules`.
9. **Bootstrap.** In `~/.config/new-machine/lib/steps.zsh`: `<name>` appended
   to `STEPS`, `[<name>]=dotfiles_repo` in `STEP_NEEDS`, a `STEP_DESC` line,
   `check::<name>` (`skip` when `~/.config/<name>/bin/<name>` is missing, fix
   `new-machine apply dotfiles_repo`; `fail` when `core.hooksPath` is not
   `.githooks` or the build output is missing, fix `new-machine apply <name>`;
   else `ok`) and `apply::<name>` (wire the hooks, build). Model:
   `check::chrome_exoskeleton` / `apply::chrome_exoskeleton`. Add the repo's
   setup to the `next=` clause of `cmd_init` in `~/.config/dotfiles/lib/init.zsh`.
   `git df add` both, commit.
10. **Link and record.** `zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link`.
    Add a row to **Known submodules** below and to `/ari-dotfiles` § Submodules.
11. **User: `dotfiles push`.** Then **Verify**.

## Working in one

- **Be on `main`.** `git -C ~/.config/<name> branch --show-current` must print
  `main`; it prints nothing after any `git df pull` or `git df submodule
  update`. Nothing committed yet → `switch main`. Committed while detached →
  `branch -f main HEAD`, only if `merge-base --is-ancestor main HEAD`
  succeeds; else ask.
- **Explicit paths, in the repo's git.** `git -C ~/.config/<name> add <files>`;
  never `-A` or `.`; never through `git df` (refused: `Pathspec '…' is in
  submodule '…'`). Run the check yourself before committing; the hook runs it again.
- **Conventional commits**, `type(scope): subject`, public wording: no company
  hostnames, ids, ticket numbers or colleague names. The commit-msg hook greps
  the message; the check greps the tracked files.
- **No branch, no PR.** Commits land on `main`; the user's push publishes them.
- **Skills under `skills/` are files of the repo**: same steps, then `link`.
- **`git submodule` only from `$HOME`** (`cd ~ && git df submodule …`);
  anywhere else it targets whatever repo the cwd is in.
- **Any other checkout of the repo is history only.** Never edit, commit or
  build there.

## Pushing

The user's, never Claude's. `dotfiles push` (`/ari-dotfiles` § Pushing) pushes
every declared submodule that is ahead, as the personal account by token, sets
its `origin/main`, commits the shared tier's pointer bump (that path alone),
then pushes the shared tier. Claude is denied the command and MUST NOT push a
submodule any other way (`git push`, `git -C … push`, `gh auth switch`,
`gh repo create --push`). After committing, when the user asked to ship, end
with "Run `dotfiles push` when ready." and wait; otherwise stop and say the
commit is local. `dotfiles push --submodules` is the submodules and their bumps
only. Bump by hand only when the repo was pushed some other way
(`/ari-dotfiles` § Submodules step 4).

## Verify

```
git -C ~/.config/<name> status -sb              → ## main...origin/main
cd ~ && git df submodule status                 →  <sha> .config/<name> (heads/main)   leading space, not +
git df status --short -- ~/.config/<name>       → (empty)
<name> check                                    → … [OK] …
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status --all | grep <name>
                                                → state=linked … source=submodule:.config/<name>
new-machine check --only <name>                 → ok
```

## When it fails

Never `--no-verify`, in any repo. Never edit `denylist.txt` to make a check pass.

| symptom | cause | do |
|---|---|---|
| `git df add`: `fatal: Pathspec '…' is in submodule '…'` | staging a repo file through the tier | `git -C ~/.config/<name> add <files>` |
| `branch --show-current` prints nothing | detached after `git df pull` / `submodule update` | **Working in one**, first rule |
| pre-commit: the check is red | code | fix, commit again |
| commit-msg: `denylisted identifier` | the message | reword, commit again |
| hooks did not run | `core.hooksPath` unset on this checkout | `git -C ~/.config/<name> config core.hooksPath .githooks`, or `new-machine apply <name>` |
| df pre-commit: `<name> pointer … is not on origin/main` | bump before the push | the user runs `dotfiles push --submodules`; re-run the commit, nothing to re-stage |
| `dotfiles push` log: `Personal account is not logged into gh` / `Token identity mismatch` | gh login | the user: `env -u GITHUB_TOKEN gh auth login` (HTTPS), or `gh auth status` |
| `dotfiles push` log: `Push rejected` above `remote: Repository not found` | the GitHub repo does not exist | step 6 is the user's |
| `dotfiles push` log: `Push rejected` (non-fast-forward) or `Remote ref does not match after push` | remote `main` moved | `git -C ~/.config/<name> pull --rebase origin main`; re-run the check by hand (a rebase skips the hook); ask for the push again |
| `dotfiles push` log: `Detached HEAD: nothing to push` | committed while detached | **Working in one**, first rule; push again |
| `dotfiles push` log: `submodule not checked out` | never initialized here | `dotfiles init` |
| `dotfiles push` log: `No such remote` | step 1's `remote add` missing | `git -C ~/.config/<name> remote add origin https://github.com/AriSweedler/<name>.git` |
| `submodule status` prefix `+` | checkout ahead of the pointer | a bump is pending: `dotfiles push`; on a machine that only pulled, `cd ~ && git df submodule update` |
| `submodule status` prefix `-` | not initialized | `cd ~ && git df submodule update --init -- .config/<name>` (`dotfiles init` does it) |
| registry `status`: the repo's skill `dangling` or `missing` | skill dir renamed or new | `zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/link --prune` |
| `new-machine check`: `submodule_uninitialized` / `submodule_drift` | pointer vs checkout | the two rows above |

## Known submodules

| Path | Driver | Upstream | Skill | Local root | State |
|---|---|---|---|---|---|
| `~/.config/chrome-exoskeleton/` | `exo` | `github.com/AriSweedler/chrome-exoskeleton` | `/ari-dotfile--submodule-chrome-exoskeleton` | `~/.local/share/chrome-exoskeleton/` (plugins, `env.zsh`, `denylist.txt`) | declared |
| `~/.config/plugged/` | `plugged` | `github.com/AriSweedler/plugged` | `/ari-dotfile--submodule-plugged` | `~/.local/share/plugged/` (`denylist.txt`) | planned; not yet in `~/.gitmodules` |
