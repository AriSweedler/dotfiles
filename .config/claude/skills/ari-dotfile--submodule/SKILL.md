---
name: ari-dotfile--submodule
description: Create and work in a dotfiles dev repo ("submodule" is the old word) — one of Ari's public repos, a plain git clone at ~/dotfiles/.config/<name> that the shared repo ignores, linked to ~/.config/<name>, listed in the dev-repos manifest and read by the shared Nix flake as an input locked in flake.lock, with its own hooks, driver, check and skills. The layout every dev repo follows, the recipe for a new one, how commits, the build, pushes and flake.lock bumps flow, and what refuses when. Per-repo specifics live in ari-dotfile--submodule-<name>.
---

# Dotfiles dev repos

A *dev repo* is one of Ari's own public repos living inside the shared-tier
clone `~/dotfiles` (`git df`, `/ari-dotfiles`) as a plain git clone of its own:
`~/dotfiles/.config/<name>`, its `.git` a directory. The shared repo ignores
it; the shared Nix flake reads it as an input, and that flake's `flake.lock`
pins the commit every other machine builds. `~/.config/<name>` resolves
(through `/nix/store`) to the checkout, placed by home-manager's bridge
(`/ari-dotfiles-nix`). "Submodule" is the old word for a dev repo: the skill
names, the `dotfiles_repo` verdicts and `dotfiles push --submodules` keep it,
but there is no `.gitmodules`, no gitlink and no `git df submodule …`.

**A machine still on the old layout** (`~/dotfiles/.gitmodules` exists, or
`~/dotfiles/.config/<name>/.git` is a file) is the one exception: there the user
runs `dotfiles pull`, then `dotfiles apply dotfiles_repo`, which converts each
checkout in place; nothing else here applies until then.

**Before any edit, commit or check in `~/.config/<name>`, invoke
`/ari-dotfile--submodule-<name>`**: it names the repo's check command and its
own failures. This skill has what every dev repo shares.

**Warranted when** all hold: the code has its own toolchain, tests and release
cadence, stands as a public repo on its own, and would drown the dotfiles log
(a framework, an extension, a compiled CLI). **Not warranted** for a script, a
zsh plugin, a skill or config: those are files of a tier (`/ari-dotfiles`
Placement rules). When unsure, ask Ari before step 1. **Company-specific code
and wording NEVER enter a dev repo**; they plug in from the local tier at the
repo's local root (`/ari-dotfiles` Cutpoints).

## Layout contract

Every shared-tier path is written, `git df add`ed and committed by its
`~/dotfiles/…` path: `~/.config/dotfiles` is a directory of per-file links, so a
new file created there is outside the repo. `<input>` is `<name>`; `<step>` is
`<name>` with `-` → `_`. `nix/` below is `~/dotfiles/.config/dotfiles/nix/`.

| Piece | Path | Tier | Notes |
|---|---|---|---|
| Repo | `~/dotfiles/.config/<name>/`, upstream `github.com/AriSweedler/<name>`, public | its own | a plain clone on `main` |
| Ignore | `.config/<name>/` in `~/dotfiles/.gitignore` | df | the shared repo never tracks a file of it |
| Manifest | `~/dotfiles/.config/dotfiles/dev-repos`: `[repo ".config/<name>"]`, then `path`, `url` (https), `input`, in that order, all three | df | what `dotfiles push`, `status`, `switch`, the `dotfiles_repo` step and the df pre-commit hook enumerate; the hook pairs each `input` with the `path` above it |
| Flake input | `nix/flake.nix`: in `inputs`, in the `outputs` arguments and in `devInputs`; locked in `nix/flake.lock` | df | the locked rev (the *pointer* in log lines) is the commit a machine builds when it has no checkout |
| Link | `~/.config/<name>` → (through `/nix/store`) `~/dotfiles/.config/<name>` | df | `".config/<name>"` in `wholeDirs` of `nix/bridge.nix`; exists only after a switch that includes it |
| Skills root | `roots` of `nix/claude-skills.nix` | df | links each committed `skills/<skill>` into `~/.claude/skills` at the switch |
| Driver | a script run in place: `~/dotfiles/.config/bin/<name> -> ../<name>/bin/<name>` (exo); a compiled program: a package `nix/pkgs/<name>` built from `devInputs.<input>`, listed in `nix/pkgs/default.nix` (plugged) | df | one entry point with subcommands, on `PATH` |
| Check, build | named by `/ari-dotfile--submodule-<name>` (`exo check`; `bin/plugged-dev check`) | repo | the *repo check*; it ends in one `[OK]` line; anything else is a failure |
| Hooks | `.githooks/pre-commit` runs the repo check; `.githooks/commit-msg` greps the message against the denylist | repo | `core.hooksPath=.githooks` is local config: a fresh clone has no hooks until `dotfiles apply <step>` wires it |
| Denylist | `~/.local/share/<name>/denylist.txt`: one regex per line, `#` comments | ldf | what the public repo must never contain; absent → both hooks pass everything |
| Skills | `~/.config/<name>/skills/<skill>/SKILL.md` | repo | committed in the repo only |
| Local plug-in root (optional) | `~/.local/share/<name>/…` | ldf | only when the repo loads company code at run time; admitted in both ldf allowlists; the repo never requires it |
| Bootstrap | `~/dotfiles/.config/dotfiles/steps/<step>.zsh` | df | `step::declare <step> --group tools --needs dotfiles_repo`, `step::watches <step> '.config/dotfiles/nix/flake.lock'`; `check::<step>` skips when the checkout is missing (fix `dotfiles apply dotfiles_repo`) and fails when the identity or `core.hooksPath` is off (fix `dotfiles apply <step>`) or the repo's built artifact is missing; `apply::<step>` runs `tier::submodule_identity_apply`, wires the hooks and runs whatever build the repo needs, every mutation through `run_mut`. Model: `steps/plugged.zsh` |
| Skill | `/ari-dotfile--submodule-<name>` | repo | the repo's commands, hooks, workflow, failures; the `dotfiles_repo` step checks for it by this name. Model: `~/.config/plugged/skills/ari-dotfile--submodule-plugged/SKILL.md` |

The df lines for plugged, as committed:

```
dev-repos         [repo ".config/plugged"]
                  	path = .config/plugged
                  	url = https://github.com/AriSweedler/plugged.git
                  	input = plugged
.gitignore        .config/plugged/
flake.nix         plugged = { url = "github:AriSweedler/plugged"; flake = false; };      # inputs
                  outputs = { self, nixpkgs, nix-darwin, home-manager, plugged, chrome-exoskeleton }:
                  let devInputs = { inherit plugged chrome-exoskeleton; };
bridge.nix        ".config/plugged"                                                         # wholeDirs
claude-skills.nix { dir = "${devInputs.plugged}/skills"; root = ".config/plugged/skills"; }  # roots
pkgs/default.nix  plugged = pkgs.callPackage ./plugged { src = devInputs.plugged; };
```

**Commits carry the personal identity only**: `user.name "Ari Sweedler"`,
`user.email ari@sweedler.com`, in the repo's `--local` config, never inherited
from the global or work config. Local config is not cloned: on each machine,
`dotfiles apply <step>` pins it (`tier::submodule_identity_apply` in
`~/.config/dotfiles/lib/tiers.zsh`) and `check::<step>` fails on drift.

## How the build and the lock follow the checkout

- **`dotfiles switch`** adds `--override-input dotfiles/<input> git+file://<checkout>?rev=<HEAD>`
  for every dev repo checked out, so a committed but unpushed change builds here;
  an uncommitted one does not. A repo not checked out builds from the lock.
- **`dotfiles push`** pushes each dev repo that is ahead, then bumps the lock:
  `nix flake update <input>` in the shared flake and a commit of `flake.lock`
  alone, `<name>: bump to <sha> (<subject>)`, which the shared push carries.
- **The df pre-commit hook** refuses a staged `flake.lock` whose locked rev for a
  dev repo is not on that repo's `origin/main`.
- **`dotfiles pull`** moves the lock, never a checkout:
  `git -C ~/.config/<name> pull --ff-only origin main` fast-forwards it.
- **NEVER run `nix flake update` for a dev-repo input, and NEVER stage
  `nix/flake.lock` yourself**: only `dotfiles push` bumps it. A modified
  `flake.lock` you did not mean: `git df restore --staged --worktree -- ~/dotfiles/.config/dotfiles/nix/flake.lock`.

The locked rev, to compare with the checkout's HEAD:
`jq -r '.nodes["<input>"].locked.rev' ~/dotfiles/.config/dotfiles/nix/flake.lock`.

## Creating one

Claude does 1–5, 7, 9 and 10; the user does 6 and 8. **Claude pushes nothing.**
Until step 9's switch, `~/.config/<name>` does not exist, so steps 1–8 address
the new repo as `~/dotfiles/.config/<name>`. First, a read-only preflight:
`~/dotfiles/.config/<name>` and `~/.local/share/<name>` absent, no
`.config/<name>` in `dev-repos`, and `gh repo view AriSweedler/<name>` failing
or showing an empty repo; a step whose result already exists is done: skip it.

1. **Repo.** `git init -b main ~/dotfiles/.config/<name>`;
   `git -C ~/dotfiles/.config/<name> config user.name "Ari Sweedler"`;
   `git -C ~/dotfiles/.config/<name> config user.email ari@sweedler.com`;
   `git -C ~/dotfiles/.config/<name> remote add origin https://github.com/AriSweedler/<name>.git`.
   Write `bin/<name>`, its check and build, `README.md`
   (`/ari-hemingway--structure-repo-quickstart`), `.gitignore`.
2. **Hooks.** `.githooks/pre-commit` (`exec` the repo check) and `.githooks/commit-msg`
   (denylist grep; `exit 0` when `~/.local/share/<name>/denylist.txt` is
   unreadable), both `chmod +x`; then
   `git -C ~/dotfiles/.config/<name> config core.hooksPath .githooks`.
   Model: `~/.config/chrome-exoskeleton/.githooks/`.
3. **Local tier.** `~/.local/share/<name>/denylist.txt` (copy
   `~/.local/share/chrome-exoskeleton/denylist.txt`). A local plug-in root also
   needs `!/share/<name>/` in `~/.local/local-dotfiles.git/info/exclude` and in
   `~/.config/new-machine/local-dotfiles-exclude`. `git ldf add <abs paths>`,
   then commit; the user's `dotfiles push` pushes it.
4. **Declare it in the shared tier**, one commit holding every df row of
   **Layout contract** but the lock: `dev-repos`, `.gitignore`, `nix/flake.nix`,
   `nix/bridge.nix`, `nix/claude-skills.nix`, the driver and the bootstrap step.
   `git df add <abs paths> && git df commit -m "<name>: declare the dev repo (<what it is>)"`.
   **No `dotfiles switch` or `--build` until step 5 has committed** (before then
   the switch fails: `locking the shared input failed`, no checkout HEAD to
   override with); after it, `--build` works.
5. **Skill and first commit.** `~/dotfiles/.config/<name>/skills/ari-dotfile--submodule-<name>/SKILL.md`;
   `git -C ~/dotfiles/.config/<name> add <files> && git -C ~/dotfiles/.config/<name> commit -m "feat: …"`.
   The hooks run; the repo check must end `[OK]`.
6. **User: the remote.** An empty public `github.com/AriSweedler/<name>`:
   github.com/new (no README, no license), or
   `GH_TOKEN="$(env -u GITHUB_TOKEN gh auth token -u AriSweedler)" gh repo create AriSweedler/<name> --public`.
   Then Claude checks `gh repo view AriSweedler/<name> --json visibility,isEmpty`
   → `"PUBLIC"`, `true`.
7. **Review**: `/ari-dotfiles` **Review before push** on the repo's commits and
   step 4's, then "Run `dotfiles push` when ready." **Plain `dotfiles push`, never
   `--shared` or `--no-submodules`**: those publish step 4 with no lock entry,
   and every other machine's clone and switch fail. **STOP until the user says
   it ran.**
8. **User: `dotfiles push`.** It pushes the repo as the personal account, sets
   its `origin/main`, commits the first lock (`<name>: bump to <sha> (…)`) and
   pushes the shared tier.
9. **Switch**, only once the locked rev equals the repo's HEAD and
   `git -C ~/dotfiles status -sb` shows nothing ahead: `/ari-dotfiles-nix`
   **Switch** (Claude builds with `--build`, then switches). Only then do
   `~/.config/<name>`, its driver and its skill links exist.
10. **Wire and record.** `dotfiles apply <step>`; then **Verify**, every line. Add
    a row to **Known dev repos** below and to `/ari-dotfiles` § Dev repos, both
    through `/ari-skill-update`.

Until step 9, `dotfiles healthcheck` may report `submodule_undocumented` and
`dotfiles status` a `+` for the new repo; both clear at the switch.

## Working in one

- **Identity and hooks first, on every machine.** Before the first commit here,
  `git -C ~/.config/<name> config --local user.email` must print
  `ari@sweedler.com` and `config core.hooksPath` must print `.githooks`; else
  `dotfiles apply <step>`. After every commit,
  `git -C ~/.config/<name> log -1 --format='%an <%ae> %cn <%ce>'` must print
  `Ari Sweedler <ari@sweedler.com>` twice.
- **Be on `main`.** `git -C ~/.config/<name> branch --show-current` must print
  `main`. If it prints nothing (someone detached it, or the `dotfiles_repo`
  apply left a converted checkout whose `main` had diverged):
  - `merge-base --is-ancestor HEAD main` succeeds (exit 0) → `switch main`.
  - `merge-base --is-ancestor main HEAD` succeeds → `branch -f main HEAD && switch main`.
  - neither → show `log --oneline --graph main...HEAD` and ask Ari which history `main` keeps.
- **Commit on `main` directly. NEVER a branch, a worktree or a PR for a dev
  repo**, whatever the default git guidance says; Ari's push publishes `main`.
- **Explicit paths, in the repo's git.** `git -C ~/.config/<name> add <files>`;
  never `-A` or `.`; never through `git df` (refused: the path is ignored).
- **Run the repo check before every commit; it MUST end in one `[OK]` line.**
  The hook runs it again. A red check means fixing the code: **NEVER
  `--no-verify`, and NEVER edit `denylist.txt` to pass.** No denylist on this
  machine → the hooks pass everything: read the staged diff and the message for
  company content yourself, and tell Ari the denylist is missing.
- **Conventional commits**, `type(scope): subject`, public wording: no company
  hostnames, ids, ticket numbers or colleague names.
- **Skills under `skills/` are files of the repo**, committed by the rules
  above; **NEVER `git df add` or registry-`adopt` them**. A new or renamed skill
  directory gets its `~/.claude/skills` link at the next `dotfiles switch` after
  its commit.
- **One checkout.** `~/.config/<name>` and `~/dotfiles/.config/<name>` are the
  same directory; any other clone of the repo is stale: never edit, commit or
  build in it.

## Pushing

**Claude NEVER pushes a dev repo** (`git push`, `git -C … push`, `gh auth switch`,
`gh repo create --push`) and is denied `dotfiles push`. When to say "Run
`dotfiles push` when ready." and the review before it: `/ari-dotfiles` § Dev
repos, step 3. Before saying it, `git df status --porcelain -- ~/dotfiles/.config/dotfiles/nix`
must print nothing: the bump commits `flake.lock` from the working tree, so a
pending lock edit would ride along. `dotfiles push --submodules` is the dev
repos and their bumps only. A repo pushed some other way gets its bump from the
next `dotfiles push`. The push logs are `dotfiles logs --repo .config/<name>`;
once a failure's cause is fixed, re-running `dotfiles push` recovers it.

## Verify

```
git -C ~/.config/<name> status -sb              → ## main...origin/main
git -C ~/.config/<name> config --local --get-regexp '^user\.'
                                                → user.email ari@sweedler.com / user.name Ari Sweedler
realpath ~/.config/<name>                       → $HOME/dotfiles/.config/<name>
git -C ~/dotfiles check-ignore .config/<name>   → .config/<name>
jq -r '.nodes["<input>"].locked.rev' ~/dotfiles/.config/dotfiles/nix/flake.lock
                                                → the checkout's HEAD
git -C ~/dotfiles status -sb                    → ## main...origin/main   (nothing ahead)
dotfiles status                                 → under submodules:  <sha> .config/<name> (heads/main)   leading space, not + or -
<the repo check>                                → … [OK] …
zsh $HOME/.claude/skills/ari-dotfiles-skill-registry/bin/status --all --skill ari-dotfile--submodule-<name>
                                                → state=linked …
dotfiles healthcheck --only dotfiles_repo,<step> → ok
```

Every line must match; a mismatch is a row of **When it fails**, never a success.

## When it fails

| symptom | cause | do |
|---|---|---|
| `git df add`: `The following paths are ignored by one of your .gitignore files` | staging a repo file through the tier | `git -C ~/.config/<name> add <files>` |
| `git df add`: `outside repository` | a new shared-tier file written under `~/.config/dotfiles` | move it to its `~/dotfiles/.config/dotfiles/…` path |
| `branch --show-current` prints nothing | detached | **Working in one**, Be on `main` |
| pre-commit: the repo check is red | code | fix, commit again |
| commit-msg: `denylisted identifier` | the message | reword, commit again |
| hooks did not run | `core.hooksPath` unset on this clone | `dotfiles apply <step>` |
| df pre-commit: `<input> is locked at <sha>, which is not on origin/main.` | a staged `flake.lock` ahead of the repo's push | unstage it (**How the build…**, last rule); the user's `dotfiles push` makes the bump |
| `dotfiles push` log: `Personal account is not logged into gh` / `Token identity mismatch` | gh login | the user: `env -u GITHUB_TOKEN gh auth login` (HTTPS), or `gh auth status` |
| `dotfiles push` log: `Push rejected` above `remote: Repository not found` | the GitHub repo does not exist | step 6 is the user's |
| `dotfiles push` log: `Push rejected` (non-fast-forward) or `Remote ref does not match after push` | remote `main` moved | `git -C ~/.config/<name> pull --rebase origin main`; then the repo check by hand (a rebase skips the hook); only on `[OK]`, "Run `dotfiles push` when ready." |
| `dotfiles push` log: `Detached HEAD: nothing to push` | committed while detached | **Working in one**, Be on `main`; push again |
| `dotfiles push` log: `No such remote` | step 1's `remote add` missing | `git -C ~/.config/<name> remote add origin https://github.com/AriSweedler/<name>.git` |
| `dotfiles push`: `lock update failed` / `pointer bump refused` | the `flake.lock` bump after the push | the nix or hook output above the line; a private or missing GitHub repo makes `nix flake update` 404 (step 6) |
| `dotfiles push`: `lock update did not land on the pushed HEAD` | `origin/main` is ahead of the checkout, or Nix's cached GitHub lookup is stale | `git -C ~/.config/<name> fetch origin && git -C ~/.config/<name> status -sb`: behind → `pull --ff-only origin main`, push again; else the user re-runs `NIX_CONFIG='tarball-ttl = 0' dotfiles push` |
| `dotfiles push`: `pointer not bumped: checkout is not ahead of the lock` | the checkout is behind or beside the locked rev | the `+` row |
| `dotfiles status` prefix `+`, or healthcheck `submodule_drift` | HEAD is not the locked rev | compare with the locked rev (**How the build…**): locked rev an ancestor of HEAD → a bump is pending, `dotfiles push`; HEAD an ancestor of it → `git -C ~/.config/<name> pull --ff-only origin main`; neither → **Working in one**, Be on `main`, last case |
| `dotfiles status` prefix `-`, push log `submodule not checked out`, or healthcheck `submodule_uninitialized` | the manifest lists it but it is not cloned | `dotfiles apply dotfiles_repo` clones it from the manifest `url`; then `dotfiles apply <step>` |
| healthcheck `submodule_layout` | still a git submodule checkout (`.git` a file into the shared repo's `modules/`) | `dotfiles apply dotfiles_repo`: moves the git dir into `<path>/.git` and switches to `main` when `main` is absent or behind HEAD |
| healthcheck `submodule_undocumented` | the checkout lacks `README.md` or `skills/ari-dotfile--submodule-<name>/SKILL.md`, or the skill is not linked into `~/.claude/skills` | write what the detail names (**Creating one**, steps 1 and 5) and commit it in the repo; then `dotfiles switch`, which places the link (a registry `link` is undone by the next switch) |
| `~/.config/<name>`: `No such file or directory` | `wholeDirs` in `nix/bridge.nix` lacks `.config/<name>`, no switch since it was added, or the repo is not cloned here | **Creating one**, steps 4 and 9; or the `-` row |

## Known dev repos

| Path | Input | Driver | Upstream | Skill | Local root |
|---|---|---|---|---|---|
| `~/.config/chrome-exoskeleton/` | `chrome-exoskeleton` | `exo` (`.config/bin` link) | `github.com/AriSweedler/chrome-exoskeleton` | `/ari-dotfile--submodule-chrome-exoskeleton` | `~/.local/share/chrome-exoskeleton/` (plugins, `env.zsh`, `denylist.txt`) |
| `~/.config/plugged/` | `plugged` | `plugged` (`nix/pkgs/plugged`) | `github.com/AriSweedler/plugged` | `/ari-dotfile--submodule-plugged` | `~/.local/share/plugged/` (`denylist.txt`) |
