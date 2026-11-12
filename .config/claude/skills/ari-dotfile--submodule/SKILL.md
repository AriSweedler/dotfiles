---
name: ari-dotfile--submodule
description: Create and work in a dotfiles dev repo ("submodule" is the old word) — one of Ari's public repos, a plain git clone at ~/dotfiles/.config/<name> that the shared repo ignores, linked to ~/.config/<name>, listed in the dev-repos manifest and read by the shared Nix flake as an input locked in flake.lock, with its own check and skills, and hooks unless it ships as a package. The layout every dev repo follows, the recipe for a new one, how commits, the build, pushes and flake.lock bumps flow, and what refuses when. Also the mirrors (ari-zshlib): public repos whose files `dotfiles push` exports from a shared-flake package, whose copied files are edited only at their dotfiles source. Per-repo specifics live in ari-dotfile--submodule-<name>.
---

# Dotfiles dev repos

A *dev repo* is one of Ari's own public repos living inside the shared-tier
clone `~/dotfiles` (`git df`, `/ari-dotfiles`) as a plain git clone of its own:
`~/dotfiles/.config/<name>`, its `.git` a directory. The shared repo ignores
it; the shared Nix flake reads it as an input, and that flake's `flake.lock`
pins the commit every other machine builds, a NixOS host through a lock of its
own (**How the build…**). `~/.config/<name>` resolves
(through `/nix/store`) to the checkout, placed by home-manager's bridge
(`/ari-dotfiles-nix`). "Submodule" is the old word for a dev repo: the skill
names, the `dotfiles_repo` verdicts and `dotfiles push --submodules` keep it,
but there is no `.gitmodules`, no gitlink and no `git df submodule …`.

**A machine still on the old layout** (`~/dotfiles/.gitmodules` exists, or
`~/dotfiles/.config/<name>/.git` is a file) is the one exception: there the user
runs `dotfiles pull`, then `dotfiles apply dotfiles_repo`, which converts each
checkout in place; nothing else here applies until then.

**Before any edit, commit or check in a dev repo, invoke
`/ari-dotfile--submodule-<name>`**: it names the repo's check command and its
own failures. Not in the skill list yet (no switch since its commit) → Read
`~/dotfiles/.config/<name>/skills/ari-dotfile--submodule-<name>/SKILL.md`
directly. This skill has what every dev repo shares. **A mirror (ari-zshlib)
has no per-repo skill: read § Mirrors before touching its checkout.**

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
| Manifest | `~/dotfiles/.config/dotfiles/dev-repos`: `[repo ".config/<name>"]`, then `path`, `url` (https), `input`, in that order, all three | df | what `dotfiles push`, `status`, `switch`, the `dotfiles_repo` step and the df pre-commit hook enumerate; the hook pairs each `input` with the `path` above it; for a `[mirror]` section, see **Mirrors** |
| Flake input | `nix/flake.nix`: in `inputs`, in the `outputs` arguments and in `devInputs`; locked in `nix/flake.lock` | df | the locked rev (the *pointer* in log lines) is the commit a machine builds when it has no checkout |
| Link | `~/.config/<name>` → (through `/nix/store`) `~/dotfiles/.config/<name>` | df | `".config/<name>"` in `wholeDirs` of `nix/bridge.nix`; exists only after a switch that includes it |
| Skills root | `roots` of `nix/claude-skills.nix` | df | links each committed `skills/<skill>` into `~/.claude/skills` at the switch |
| Driver | a script run in place: `~/dotfiles/.config/bin/<name> -> ../<name>/bin/<name>` (exo); a compiled program: a package `nix/pkgs/<name>` built from `devInputs.<input>`, listed in `nix/pkgs/default.nix` (plugged); a *packaged repo*'s own recipe: `<input> = pkgs.callPackage "${devInputs.<input>}/package.nix" { … };` in `nix/pkgs/default.nix`, its bins placed at `~/.config/bin` from the store by `placed` in `nix/ari-bins.nix` (run-log, tmux-oneshot) | df | one entry point with subcommands, on `PATH`; a packaged repo may ship several bins and needs no driver script |
| Check, build | named by `/ari-dotfile--submodule-<name>` (`exo check`; `bin/plugged-dev check`; `nix build` of the repo's own flake) | repo | the *repo check*; it ends in one `[OK]` line, or, for a packaged repo, `nix build` exits 0; anything else is a failure |
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

**A packaged repo** (run-log, tmux-oneshot) carries its own `package.nix` and needs every
df row but the bootstrap step, plus `README.md`, `package.nix` and the skill in
the repo. Its `package.nix` takes a `zshlib` argument and rewrites each bin's
`${ARI_ZSHLIB:-…}` default to that store copy: the shared flake passes the
clone's own `ari_zshlib` (`nix/pkgs/default.nix`), the repo's own flake its
`ari-zshlib` input (**Mirrors**, Consumers). It has no Hooks, Denylist or Bootstrap, so **Creating one** skips
steps 2 and 3 and step 4's step file, and no step pins its identity: on each
machine, once `dotfiles apply dotfiles_repo` has cloned it, Claude runs step 1's
two `config` lines by hand. Its skill says only that `core.hooksPath` prints
nothing, no `dotfiles apply <step>` exists, and the identity and company-content
checks the hooks would run are Claude's at each commit; the identity pin and the
local lock (**How the build…**, `dotfiles switch`) it cites from here.

**Commits carry the personal identity only**: `user.name "Ari Sweedler"`,
`user.email ari@sweedler.com`, in the repo's `--local` config, never inherited
from the global or work config. Local config is not cloned: on each machine,
`dotfiles apply <step>` pins it (`tier::submodule_identity_apply` in
`~/.config/dotfiles/lib/tiers.zsh`) and `check::<step>` fails on drift; a
packaged repo has no step, so Claude pins it (above).

## How the build and the lock follow the checkout

- **`dotfiles switch`** adds `--override-input dotfiles/<input> git+file://<checkout>?rev=<HEAD>`
  for every dev repo checked out, so a committed but unpushed change builds here;
  an uncommitted one does not. A repo not checked out builds from the lock. It
  writes the local flake's lock, `~/.local/share/dotfiles/nix/flake.lock`, and
  commits it in the local tier (`nix: lock the shared flake at <sha7>`;
  `--no-commit` leaves it modified) *before* it builds, `--build` included, so a
  failed build still leaves the local lock moved: a locked rev there equal to
  the checkout's HEAD does not mean the build landed; read the last switch's
  output.
- **`dotfiles push`** first exports each mirror (**Mirrors**), then pushes each
  dev repo and mirror that is ahead, then bumps the lock of each dev repo pushed:
  `nix flake update <input>` in the shared flake and a commit of `flake.lock`
  alone, `<name>: bump to <sha> (<subject>)`, which the shared push carries.
- **A NixOS host** imports the shared flake's `lib.nixosHome` through its own
  flake, which locks the dotfiles as its own input; `dotfiles push` does not
  move that lock. After the push and the bump, a Nix module or packaged-bin
  change reaches the host by `nix flake update dotfiles` in the host's flake
  (not the shared one: the NEVER below does not apply), a commit and push of
  that lock, and a switch; a file linked from the clone is live there after
  `git -C ~/dotfiles pull`. The host builds with its own nixpkgs (the input
  follows it), which can be older than the shared flake's, so a package that
  builds on the Mac can fail there: build for the host (its dry run) before
  calling the change shipped. For the homelab's co2 the steps and their order
  are `/ari-homelab`'s, in `hosts/co2/README.md` § Dotfiles.
- **The df pre-commit hook** refuses a staged `flake.lock` whose locked rev for a
  dev repo is not on that repo's `origin/main`.
- **`dotfiles pull`** fast-forwards each dev repo's checkout to its `origin/main` after it
  pulls the shared tier (`dev repo <path>: <old7>..<new7>`; `--dry-run` says "would move"). A checkout that
  is off `main`, has tracked edits, or is ahead of or diverged from `origin/main` is left as it is with a
  warning naming why (`git -C ~/.config/<name> status -sb`). Mirrors are not pulled.
- **NEVER run `nix flake update` for a dev-repo input of the shared flake, and
  NEVER stage `nix/flake.lock` yourself**: only `dotfiles push` bumps it. A
  repo's own `flake.lock` is the repo's file (**Creating one**, step 1). A modified
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
   (`/ari-hemingway--structure-repo-quickstart`), `.gitignore`. A repo whose
   own `flake.nix` takes another of Ari's repos as an input (run-log and
   tmux-oneshot take `ari-zshlib`) locks it only after that repo is pushed,
   with `--refresh` (**Mirrors**, Consumers).
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
  `dotfiles apply <step>` (a packaged repo: `core.hooksPath` prints nothing, and
  a wrong identity takes **Creating one** step 1's two `config` lines). After every commit,
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
pending lock edit would ride along. When the commits being pushed touch a
mirror's `watch` path or its checkout, the mirror preflight (**Verify a mirror**)
must pass too. `dotfiles push --submodules` is the mirror exports, the dev repos,
the mirrors and the dev repos' bumps; `--shared`, `--local` or `--no-submodules`
export no mirror. A repo pushed some other way gets its bump from the
next `dotfiles push`. The push logs are `dotfiles logs --repo .config/<name>`;
once a failure's cause is fixed, re-running `dotfiles push` recovers it.

## Mirrors

A *mirror* is a public repo whose `<dir>` is a copy of one of the shared flake's
packages, exported by `dotfiles push`. It is the answer when public repos need a
pinned copy of files the tiers source live. It is not a dev repo: no flake
input, so no locked rev and no bump; no `~/.config/<name>` link; no per-repo
skill, hooks, denylist, bootstrap step or repo check; and no step clones it. The
one mirror is `ari-zshlib` (`github.com/AriSweedler/ari-zshlib`), whose `lib/`
is the package `ari_zshlib`, built by `nix/pkgs/ari-zshlib` from the dotfiles'
shell library.

`<path>` is the manifest `path` (`.config/ari-zshlib`), `<dir>` is `dir` (`lib`)
and `<package>` is `package` (`ari_zshlib`). **The checkout is only at
`~/dotfiles/<path>`: address it as `git -C ~/dotfiles/<path>` in every command,
never `~/<path>`**, as the `fix=` hints `dotfiles push` prints for a mirror do.

- **NEVER edit, stage or commit a file under `<dir>` in the checkout**: the next
  export refuses while it is dirty, and overwrites it. Edit its source instead:
  the `installPhase` of `nix/pkgs/<package>` names the source of each file in
  `<dir>`. Commit the source per `/ari-dotfiles`. A new file `<dir>` must ship
  goes into that `installPhase` and, unless an existing `watch` entry already
  contains it, into `watch`, in the same commit.
- **Manifest.** `[mirror "<path>"]` in `dev-repos` (committed by its
  `~/dotfiles/…` path): `path` and `package` are required (a section without
  either is silently ignored), then `url`, `dir` (default `lib`) and `watch`,
  space-separated files or directories relative to `~/dotfiles` (empty: every
  new shared HEAD rebuilds). The shared repo's `.gitignore` lists `<path>/`.
  ```
  [mirror ".config/ari-zshlib"]
  	path = .config/ari-zshlib
  	url = https://github.com/AriSweedler/ari-zshlib.git
  	package = ari_zshlib
  	dir = lib
  	watch = .config/dotfiles/nix/pkgs/ari-zshlib .config/zsh/plugins/log.zsh … .config/bash/plugins
  ```
- **Export.** A `dotfiles push` with the dev repos in scope exports each mirror
  before any push:
  1. It skips the build when no `watch` path changed between the stamp (the
     checkout's local git config `dotfiles.mirroredRev`) and the shared tier's
     committed HEAD; an empty or unknown stamp always builds. Uncommitted source
     edits are never exported.
  2. It refuses when the checkout is off `main` or `<dir>` has uncommitted changes.
  3. It builds `<package>` from that HEAD, replaces `<dir>` with the store's,
     and commits it alone as `<dir>: mirror dotfiles <sha7>`.
  4. It pushes the mirror with the dev repos; no bump follows.

  A failed export blocks nothing; the push reports failure at the end
  (**When it fails**, the `mirror not exported` rows). A machine without the
  checkout skips the export silently: after committing a `watch` change there,
  tell Ari it reaches the mirror at the next `dotfiles push` from a machine that
  has `~/dotfiles/<path>`.
- **The checkout's own files** (`README.md`, `flake.nix`) are edited and
  committed there, on `main` (**Working in one**, Be on `main`), with explicit
  paths and conventional commits. No hooks run, so before every commit check
  that `git -C ~/dotfiles/<path> config --local user.email` prints
  `ari@sweedler.com` (else set `user.name "Ari Sweedler"` and
  `user.email ari@sweedler.com` with `config --local`), and read the staged diff
  and message for company content yourself.
- **A new machine** gets the checkout by hand: `git clone <url> ~/dotfiles/<path>`,
  then the two `config --local` identity lines above.
- **Consumers.** run-log and tmux-oneshot take `ari-zshlib` as an input of their
  *own* flake; the shared build passes them `self.ari_zshlib`, so a stale
  consumer lock affects only that repo's own `nix build`, never a switch. It is
  the repo's flake, not the shared one, so **How the build…**'s NEVER does not
  apply, and `--flake path:…` MUST stay on the command. To move a consumer to
  the exported `lib/`:
  1. Only after Ari says `dotfiles push` ran:
     `git -C ~/dotfiles/<path> fetch origin && git -C ~/dotfiles/<path> status -sb`
     must print `## main...origin/main`.
  2. `nix flake update ari-zshlib --refresh --flake path:$HOME/dotfiles/.config/<name>`.
     Nix caches a GitHub ref for about an hour; without `--refresh` it locks the older commit.
  3. `jq -r '.nodes["ari-zshlib"].locked.rev' ~/dotfiles/.config/<name>/flake.lock`
     must equal `git -C ~/dotfiles/<path> rev-parse origin/main`; else repeat step 2.
  4. The repo check, a commit of `flake.lock` in the consumer (**Working in
     one**), then "Run `dotfiles push` when ready.": that second push publishes
     the consumer and bumps its locked rev.

### Verify a mirror

The *mirror preflight*, run before "Run `dotfiles push` when ready." and after an export:

```
git -C ~/dotfiles/<path> branch --show-current     → main
git -C ~/dotfiles/<path> status --porcelain -- <dir>
                                                   → nothing   (else the uncommitted row)
git -C ~/dotfiles/<path> config --local user.email → ari@sweedler.com
git -C ~/dotfiles/<path> log --oneline origin/main..HEAD
                                                   → hand-made commits: review each per `/ari-dotfiles` Review before push
git -C ~/dotfiles diff --name-only "$(git -C ~/dotfiles/<path> config --local dotfiles.mirroredRev)" HEAD -- <watch…>
                                                   → files: the next push exports; nothing: it only moves the stamp
```

After the push, `git -C ~/dotfiles/<path> log -1 --format=%s` prints
`<dir>: mirror dotfiles <sha7>` when it exported, and `status -sb` prints
`## main...origin/main`.

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
| `dotfiles push` log: `Push rejected` (non-fast-forward) or `Remote ref does not match after push` | remote `main` moved | `git -C ~/.config/<name> pull --rebase origin main`; then the repo check by hand (a rebase skips the hook); only on `[OK]`, "Run `dotfiles push` when ready." A mirror (`~/dotfiles/<path>`) has no repo check: after the rebase, `git -C ~/dotfiles/<path> config --local --unset dotfiles.mirroredRev`, so the next push re-exports `<dir>` |
| `dotfiles push` log: `Detached HEAD: nothing to push` | committed while detached | **Working in one**, Be on `main`; then "Run `dotfiles push` when ready." |
| `dotfiles push` log: `No such remote` | step 1's `remote add` missing | `git -C ~/.config/<name> remote add origin https://github.com/AriSweedler/<name>.git` |
| `dotfiles push`: `lock update failed` / `pointer bump refused` | the `flake.lock` bump after the push | the nix or hook output above the line; a private or missing GitHub repo makes `nix flake update` 404 (step 6) |
| `dotfiles push`: `lock update did not land on the pushed HEAD` | `origin/main` is ahead of the checkout, or Nix's cached GitHub lookup is stale | `git -C ~/.config/<name> fetch origin && git -C ~/.config/<name> status -sb`: behind → `pull --ff-only origin main`, then "Run `dotfiles push` when ready."; else the user re-runs `NIX_CONFIG='tarball-ttl = 0' dotfiles push` |
| `dotfiles push`: `pointer not bumped: checkout is not ahead of the lock` | the checkout is behind or beside the locked rev | the `+` row |
| `dotfiles status` prefix `+`, or healthcheck `submodule_drift` | HEAD is not the locked rev | compare with the locked rev (**How the build…**): locked rev an ancestor of HEAD → a bump is pending: "Run `dotfiles push` when ready."; HEAD an ancestor of it → `git -C ~/.config/<name> pull --ff-only origin main`; neither → **Working in one**, Be on `main`, last case |
| `dotfiles status` prefix `-`, push log `submodule not checked out`, or healthcheck `submodule_uninitialized` | a `[repo]` in the manifest but it is not cloned | `dotfiles apply dotfiles_repo` clones it from the manifest `url`; then `dotfiles apply <step>` |
| healthcheck `submodule_layout` | still a git submodule checkout (`.git` a file into the shared repo's `modules/`) | `dotfiles apply dotfiles_repo`: moves the git dir into `<path>/.git` and switches to `main` when `main` is absent or behind HEAD |
| healthcheck `submodule_undocumented` | the checkout lacks `README.md` or `skills/ari-dotfile--submodule-<name>/SKILL.md`, or the skill is not linked into `~/.claude/skills` | write what the detail names (**Creating one**, steps 1 and 5) and commit it in the repo; then `dotfiles switch`, which places the link (a registry `link` is undone by the next switch) |
| `~/.config/<name>`: `No such file or directory` | `wholeDirs` in `nix/bridge.nix` lacks `.config/<name>`, no switch since it was added, or the repo is not cloned here | **Creating one**, steps 4 and 9; or the `-` row |
| `dotfiles push`: `mirror not exported: its checkout is not on main` | the mirror checkout is detached or on a branch | the printed `fix=` (`git -C ~/dotfiles/<path> switch main`) only when HEAD is an ancestor of `main`; otherwise the other cases of **Working in one**, Be on `main`, with `git -C ~/dotfiles/<path>`; then "Run `dotfiles push` when ready." |
| `dotfiles push`: `mirror not exported: <dir>/ has uncommitted changes` | `<dir>` was edited in the checkout, or an earlier export's copy failed | in order: 1. save it: `git -C ~/dotfiles/<path> diff HEAD -- <dir> > /tmp/<name>-mirror.diff`, and copy out each file `git -C ~/dotfiles/<path> ls-files --others --exclude-standard -- <dir>` lists; 2. apply each change to its source (**Mirrors**, the NEVER rule) and commit it; 3. **only after step 2 is committed**, the printed `fix=` commands: `git -C ~/dotfiles/<path> restore --staged --worktree <dir> && git -C ~/dotfiles/<path> clean -fd <dir>`; 4. "Run `dotfiles push` when ready." A failed copy has nothing to move: start at step 3 |
| `dotfiles push`: `mirror not exported: the package did not build` | the shared tier's HEAD does not build `<package>` | the nix output above the line; fix the source and commit it per `/ari-dotfiles`; then "Run `dotfiles push` when ready." |
| `dotfiles push`: `mirror not exported: the package has no such directory` | `<package>`'s output lacks `<dir>` | fix `dir` in `dev-repos` or the package's `installPhase`; commit; then "Run `dotfiles push` when ready." |
| `dotfiles push`: `mirror not exported: the copy failed` / `the commit was refused` | permissions, or the checkout's git config | the output above the line; fix the cause, then the uncommitted row from step 3; **never commit `<dir>` by hand** |

## Known dev repos

| Path | Input | Driver | Upstream | Skill | Local root |
|---|---|---|---|---|---|
| `~/.config/chrome-exoskeleton/` | `chrome-exoskeleton` | `exo` (`.config/bin` link) | `github.com/AriSweedler/chrome-exoskeleton` | `/ari-dotfile--submodule-chrome-exoskeleton` | `~/.local/share/chrome-exoskeleton/` (plugins, `env.zsh`, `denylist.txt`) |
| `~/.config/plugged/` | `plugged` | `plugged` (`nix/pkgs/plugged`) | `github.com/AriSweedler/plugged` | `/ari-dotfile--submodule-plugged` | `~/.local/share/plugged/` (`denylist.txt`) |
| `~/.config/run-log/` | `run-log` | `run_log`, `run_log-capture.py`, `irun`, `strip-ansi` (its `package.nix`, placed by `nix/ari-bins.nix`) | `github.com/AriSweedler/run-log` | `/ari-dotfile--submodule-run-log` | none (a packaged repo: no hooks, denylist or bootstrap step) |
| `~/.config/tmux-oneshot/` | `tmux-oneshot` | `tmux-oneshot` (its `package.nix`, placed at `~/.config/bin/tmux-oneshot` by `nix/ari-bins.nix`) | `github.com/AriSweedler/tmux-oneshot` | `/ari-dotfile--submodule-tmux-oneshot` | none (a packaged repo: no hooks, denylist or bootstrap step) |
