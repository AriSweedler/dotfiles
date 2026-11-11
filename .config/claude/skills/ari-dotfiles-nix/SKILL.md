---
name: ari-dotfiles-nix
description: Edit, switch, roll back and commit Ari's dotfiles under the Nix port (nix-darwin + home-manager): how to tell a file the bridge links into the ~/dotfiles clone from a store-placed or an unmanaged one, the shared and local flakes, Ari's own packages (`pkgs/`) and the packaged bins placed from the store, how to package another bin, the dev repos the shared flake takes as inputs, where a new tool goes (never a bare brew install), `dotfiles switch` (Claude builds with --build, then switches; every other sudo command is Ari's), what Nix owns (packages, Homebrew, the jobs agent, and the git, tmux, starship and gh configs home-manager writes), how to edit and verify a module-written config, how to build a worktree, and the install, first-switch, uninstall and troubleshooting facts. Use whenever a change touches ~/.config/dotfiles/nix, ~/.local/share/dotfiles/nix, a file linked into /nix/store, dotfiles switch, darwin-rebuild, brew install, or a Nix-managed package. Tiers, commits, review and pushing stay with /ari-dotfiles.
---

# Dotfiles under Nix

Ari's dotfiles run on nix-darwin and home-manager: the local flake takes the shared one from the plain clone `~/dotfiles`, `dotfiles switch` activates the generation they build, and home-manager links the clone's files into `$HOME`, except the bins Ari runs everywhere, which it places from packages built at the clone's HEAD (package what you run, link what you edit). Here: changing a file, a module-written config, a packaged bin or a tool, packaging another bin, verifying and switching, rolling back, what Nix owns, and installing or removing Nix; `/ari-dotfiles` stays the authority for tiers, commits, review and pushing.

## Rules

- **Claude runs `dotfiles switch` itself** (**Switch**); **Ari runs every other command that needs sudo**: a raw `sudo darwin-rebuild …`, `darwin-rebuild --rollback` and `--list-generations`, the installer, the uninstaller, and every edit or move in `/etc`, `/var/db` or fstab. Hand each over per `/ari-driving`. **NEVER run one yourself, even when `dotfiles switch` fails or `darwin-rebuild` is not found**; hand Ari the full path `/run/current-system/sw/bin/darwin-rebuild` instead.
  ```
  BAD:  `dotfiles switch` prints `darwin-rebuild: command not found` → Claude runs `sudo /run/current-system/sw/bin/darwin-rebuild switch …`
  GOOD: Claude hands Ari `sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/.local/share/dotfiles/nix#<host>` per /ari-driving
  ```
- **Claude's**: `dotfiles switch` (**Switch** step 4), `dotfiles switch --build`, `nix build`, `nix eval`, `nvd diff` and read-only checks. `--build` is not read-only: it commits **and pushes** a moved `flake.lock` in ldf; `--build --no-commit` moves the lock but leaves it uncommitted (undo: `git ldf checkout -- ~/.local/share/dotfiles/nix/flake.lock`). A trial build that writes nothing is **Verify a module change**'s or **Build a worktree**'s `nix build`.
- **Prefix every Bash call that runs `nix`, `nvd`, `dotfiles`, `env bash`, or the Nix-provided `git` or `tmux`, with the Nix PATH**: shell state does not carry between calls, and a Claude session started before the last switch lacks it. The Nix dirs must come before `/usr/bin`, or `env bash` finds `/bin/bash` 3.2:
  ```zsh
  [[ "$(command -v bash)" == /etc/profiles/* ]] || export PATH=/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH; command -v nix >/dev/null || echo 'nix not installed: see Install and first switch'
  ```
- **Nix sees only what git committed in the clone.** `dotfiles switch` locks the shared input at the clone's HEAD, so an uncommitted change under `.config/dotfiles/nix` or in a path **The bridge** skips, or an uncommitted new file anywhere in the clone, is not in the switch; a dev repo (**Dev repos**) builds from its checkout's HEAD the same way. A trial `nix build --override-input dotfiles git+file://…` sees uncommitted edits to tracked files; the switch never does.
- **NEVER run `nix flake update`, `nix flake lock --update-input`, or edit `flake.lock` by hand, in the shared or local flake** (a public repo's own flake: **Troubleshooting**). To pick up a new shared commit, run `dotfiles switch --build`. Re-pin nixpkgs, nix-darwin or home-manager only when Ari asks. The header comment of `~/.local/share/dotfiles/nix/flake.nix` that says otherwise predates `dotfiles switch`.
- **When an edit fails read-only, NEVER `chmod`, `sudo`, `rm` or replace the link**: the file is store-placed; edit its source per **Change a file**.
- **NEVER run `git config --global` or `gh config set`** (nor `gh alias set`): a module writes those files into the store, and the write fails. Set the value where **Change a file** says.
  ```
  BAD:  git config --global pull.rebase true   → error: could not lock config file …/.config/git/config
  GOOD: every machine → the `base` block of git.nix, Verify, commit, Switch
  GOOD: one machine only → git config --file ~/.local/share/git/config pull.rebase true
  ```
- **NEVER `brew install`, `brew uninstall` or `nix profile install` alone**: a switch uninstalls every undeclared formula and cask. Declare the tool (**Add a tool**).
- **NEVER set `ARI_ZSHLIB` or `ARI_PLUGINS` beyond one command**: not in a shell startup file, a module, a skill, or a package (`wrapProgram --set`, `makeWrapper --set`). A script run from the clone, skill bins included, would read the store's library and stop seeing live edits. A package pins its library with `ari_zshlib.pin` and `pinPlugins` only (**Ari's packages**).
  ```
  BAD:  export ARI_ZSHLIB=/nix/store/…-ari-zshlib-0/lib   in ~/.zshenv
  GOOD: ARI_ZSHLIB=$TMPDIR/fixture-lib $out/bin/<bin> --help   (one command, in a test)
  GOOD: a packaged bin runs a stale library → commit, then Switch (Change a file, item 3)
  ```
- **Keep this skill current, through `/ari-skill-update`, in the same session.**
  - When: a switch adds or removes a `home.packages`, `brews`, `casks`, `home.file` or `xdg.configFile` entry in the shared flake; a `programs.*` module or an import of `home.nix` comes or goes; a package in `pkgs/default.nix`, a `placed` path in `ari-bins.nix`, a file a package copies, or a flake input changes; a harness step shrinks because Nix covers it; a phase bead of the Nix port epic closes.
  - Update: **What Nix owns** (**Ari's packages**, **Dev repos** and **Modules** included), **Open work**, the Flakes table, the frontmatter description, and any step that changed.
  - **When What Nix owns and `readlink -f` disagree, tell Ari and propose the fix the same way.**
- **This skill holds nothing true of one machine only**: no configuration name (write `<host>`), no machine's own packages, brews, casks or `/etc` files. A step that needs one reads it from the local tier at run time.
- **NEVER put a flake or module in `~/.config/nix` or `~/.local/share/nix`.** Nix owns them (user `nix.conf`; repl history and trusted settings). Shared code goes in `~/.config/dotfiles/nix`, machine-only code in `~/.local/share/dotfiles/nix`.

## Layout

### Flakes

| Flake | Path | Tier | Holds |
|---|---|---|---|
| Shared | `~/.config/dotfiles/nix` (the clone's `~/dotfiles/.config/dotfiles/nix`) | df | `darwin.nix` (imports `macos.nix`) as `darwinModules.default`, `home.nix` (imports `ari-bins.nix`, `claude-skills.nix`, `git.nix`, `tmux.nix`, `starship.nix`, `gh.nix`, `karabiner.nix`, `nvim.nix`, …) as `homeModules.default`, `bridge.nix`, `pkgs/default.nix` as `packages.aarch64-darwin.<name>` (**Ari's packages**), `lib.darwinSystem { user; modules; homeModules; }`; its `flake.lock` pins nixpkgs (nixpkgs-unstable), nix-darwin, home-manager and the dev repos `plugged`, `chrome-exoskeleton` and `run-log` (**Dev repos**) |
| Local | `~/.local/share/dotfiles/nix` | ldf | `darwinConfigurations.<host>`, built by the shared `lib.darwinSystem` from the local `darwin.nix` (the machine's own taps, brews, casks, system packages) and `home.nix` (its own packages: where a machine adds its own tools); takes the shared flake as the `git+file:` input `dotfiles`. `dotfiles switch` reads it as a `path:` flake, so its own uncommitted edits build |

`<host>` is the local flake's configuration, named per machine: `$ARI_DOTFILES_NIX_HOST` when set, else the one name `nix eval path:$HOME/.local/share/dotfiles/nix#darwinConfigurations --apply builtins.attrNames` prints. Fill it in before running a command that names it. `~/dotfiles.git` is retired (`~/dotfiles.git.retired`): `$HOME` is not a work tree, and `git df` runs on the clone.

### The bridge

`bridge.nix` links every file the clone tracks into `$HOME` with `mkOutOfStoreSymlink`, except `README.md`, `.gitignore` and each path a module places from the store: the option `dotfiles.bridge.skip`, which `ari-bins.nix` sets to every packaged bin's path, and its own `skipped` list:

- `.config/nvim` (`nvim.nix`): plugins are start packages pinned in `nvim-pack-lock.json`; `zg` writes to `~/.local/share/nvim/site/spell`.
- `.config/karabiner/karabiner.json` (`karabiner.nix`), `.config/tmux_oneshot` (`tmux-oneshot.nix`), `.config/tmuxinator` (`tmuxinator.nix`).

It links `.config/claude` and the dev-repo checkouts `.config/chrome-exoskeleton`, `.config/plugged` and `.config/run-log` as whole directories (`wholeDirs`): a new file inside one is live at once, with no switch, except a new skill directory, whose `~/.claude/skills/<name>` link `claude-skills.nix` makes at a switch.

**Work on Karabiner in `~/dotfiles/.config/karabiner`, never `~/.config/karabiner`**: that directory is linked file by file, so an untracked file there (`node_modules`, a new source) stays in `$HOME`, while `bin/bake` and `dotfiles raycast link` read the clone.

### Kinds of file

Run `readlink -f` on the `$HOME` path, never the `~/dotfiles/…` one. A Linked file may also be copied into a package (**Ari's packages** › Copied sources): it is then live for scripts run from the clone and stale in the packaged bins until a **Switch**.

| `readlink -f` ends in | Kind | Example |
|---|---|---|
| `~/dotfiles/…` | Linked: the clone's file | `~/.zshenv -> /nix/store/…-home-manager-files/.zshenv -> ~/dotfiles/.zshenv`; `~/.config/plugged/README.md` (no link itself; its directory is one) |
| `/nix/store/…` | Store-placed: a read-only copy | `~/.config/git/config -> /nix/store/…-hm_gitconfig`, from `git.nix` (**Modules**); `~/.config/nvim -> /nix/store/…-source/.config/nvim`, from `nvim.nix`; `~/.config/bin/run_log -> /nix/store/…-run-log-0/bin/run_log`, a packaged bin (**Ari's packages**); `~/.local/state/dotfiles/nix-managed`, from `home.file` in the shared `home.nix` |
| anything else | Not managed | every other file under `~/.local` (the local tier) |

### Backup suffixes

| Suffix | Made by | Where | What to do |
|---|---|---|---|
| `.before-nix` | home-manager, when a file stood where a link goes | `$HOME` | **Troubleshooting** |
| `.before-nix-darwin` | Ari, at the first switch | `/etc` | restore only on **Uninstall** |
| `.backup-before-nix` | the Nix installer | `/etc` | a leftover: **Install and first switch** step 1 |

## What Nix owns

- **Packages**: CLI tools from nixpkgs, in `home.packages` of the shared `home.nix` (jq, delta, terminal-notifier, bash 5, zsh, nvd, poppler-utils, …) or the local `home.nix` (a machine's own); git, tmux, starship and gh come from their modules (**Modules**), Ari's own tools from `pkgs/` (**Ari's packages**). `environment.systemPackages` in the local `darwin.nix` is for a tool root or launchd needs.
- **PATH order**: a login shell puts `/opt/homebrew/bin` and `/opt/homebrew/sbin` before `~/.nix-profile/bin` and `/etc/profiles/per-user/$USER/bin` (`~/.config/zsh/plugins/brew.zsh` runs `brew shellenv`). A tool that is both a brew and a Nix package runs the brew copy until the brew goes.
- **Homebrew**: nix-darwin's `homebrew` module; shared `brews` and `casks` in the shared `darwin.nix`, a machine's own taps, brews and casks in the local `darwin.nix`, applied from the Brewfile nix-darwin writes to `/etc/dotfiles/Brewfile` (no tier holds a Brewfile). `cleanup = "uninstall"`: **a switch uninstalls every formula and cask not declared.** A switch skips `brew bundle` when the bundle command and the mtimes of Homebrew's `Cellar`, `Caskroom` and `Library/Taps` match `/var/db/dotfiles-brew-bundle.stamp`.
- **Fonts, neovim**: `fonts.packages` in the shared `darwin.nix`; neovim pinned in the shared `home.nix`.
- **The jobs agent**: `launchd.user.agents.dotfiles-jobs` in the shared `darwin.nix` is the only installer of the dotfiles jobs launchd job. `dotfiles jobs install` only removes the legacy per-plugin jobs; a missing or unloaded job is fixed by **Switch**.
- **macOS defaults**: `macos.nix`, one user script in `postActivation`; it writes a default only when it differs, and restarts the Dock or Finder only when one of its keys changed.
- **System files**: `/etc/zshenv` runs set-environment, which replaces PATH, only in interactive or login shells; a non-interactive script (a launchd job, the test world) keeps the PATH it was given. `/etc/nix/machines` is empty, so a switch does not reload nix-daemon.
- **Files**:
  - Linked by the bridge: every file the clone tracks, less what **The bridge** skips.
  - Store-placed: the configs in **Modules**; the packaged bins (**Ari's packages**); what **The bridge** skips (`karabiner.nix` parses `karabiner.json` at evaluation, so invalid JSON fails the switch); `~/.config/tmux/typhon.d` and `~/.config/tmux/typhon-help` (`xdg.configFile` in `tmux.nix`); `~/.local/share/zsh-vi-mode` and the marker `~/.local/state/dotfiles/nix-managed` (`home.file` in the shared `home.nix`).
  - Skill links: `~/.config/claude/skills/<name>` and each dev repo's `skills/<name>` get one `~/.claude/skills/<name>` link, pointing at the editable directory, from `claude-skills.nix`. A new skill gets its link at the first **Switch** after its commit, not from the registry's `link`; adoption and status stay with `/ari-dotfiles-skill-registry`.
- **Harness steps** (`dotfiles steps`): a step Nix covers keeps only what Nix does not do. `dotfiles_jobs` checks the job and names `dotfiles switch` as the fix; `plugged` sets the checkout's hooks and identity, and the binary on PATH is Nix's; `karabiner` runs only Karabiner's own healthcheck. When Nix takes over more of a step, delete that half in the same change.

### Ari's packages

`pkgs/default.nix` is the package set `{ pkgs, src, devInputs }`, one attribute per package; `home.nix` and `ari-bins.nix` import the same set. **Package what you run, link what you edit.** Names: `<pkg>` is the attribute (the `nix build …#<pkg>` target and the `placed` key); its directory under `pkgs/` and its `pname` match it, except `ari_zshlib` (`pkgs/ari-zshlib`, `pname = "ari-zshlib"`) and `run-log` (no directory: `pkgs/default.nix` calls the run-log input's own `package.nix`, given `zshlib = self.ari_zshlib`). A placed bin resolves to `/nix/store/…-<pname>-<version>/bin/<bin>`. The shared flake exports each package as `packages.aarch64-darwin.<pkg>`; build one alone, uncommitted edits to tracked files included:

```zsh
nix build "git+file://$HOME/dotfiles?dir=.config/dotfiles/nix#<pkg>" --no-link --print-out-paths   # → /nix/store/…-notes-0
```

| Package | Holds |
|---|---|
| `ari_zshlib` | The shared shell library in one store `lib/`: `log.zsh` and its icon, `strip_ansi.zsh`, `log_rotate.zsh`, `tmux-pane.sh`, copies of `/ari-skill-shellscripts`'s `lib/` (`logging`, `dry_run`, `await`, `run_with_timeout`, `investigation_folder`; edit them there; the build points `logging.zsh` at the `log.zsh` beside it), bash `log` and `arg`. That `lib/` is byte for byte the public mirror `github.com/AriSweedler/ari-zshlib` (**Dev repos**); the dotfiles stay its source |
| `run-log` | `run_log`, `run_log-capture.py`, `irun`, `strip-ansi`, built from the `run-log` input (**Dev repos**; edit them per `/ari-dotfile--submodule-run-log`) |
| `git-kit` | `git-dotfiles` (at `~/.config/git/bin`), `git-health`, `git-ready`, `git-delete-if-merged-all`, `git-delete-if-merged-one`, `git-dedupe-case-refs`, `repo` |
| `notes` | `notes` |
| `mac-utils` | The small macOS bins (`open-link`, `applelink`, `json-sort`, …: the full list is its `placed` entry in `ari-bins.nix`); Swift compiled at build time |
| `dotfiles-cli` | `dotfiles`, with a mirror of the `.config` slice the CLI loads |
| `plugged` | The `plugged` binary, built from the `plugged` input (**Dev repos**); in `home.packages`, not placed |

- **Placement.** `ari-bins.nix` places each packaged bin from the store at the repo path its clone copy was linked at (`placed = { <pkg> = [ repo paths ]; }`, e.g. `.config/bin/run_log`), and puts those paths in `dotfiles.bridge.skip`, so every caller that names the old path keeps working. Editing one: **Change a file**, item 3.
- **Copied sources.** A package also copies linked files into the store, so its bins see an edit to one only after a commit and a **Switch**: `ari_zshlib` copies `zsh/plugins/{log,strip_ansi,log_rotate}.zsh`, `claude/lib/tmux-pane.sh`, `claude/skills/ari-skill-shellscripts/lib/*.zsh` and `bash/plugins/{log,arg}.bash`; `dotfiles-cli` copies `dotfiles/{cmd,lib,steps,assets}`, every `zsh/plugins/*.zsh` and `new-machine`; `git-kit` and `mac-utils` copy their own plugins; `run-log` copies no clone file, only its checkout's `bin/` and `ari_zshlib`. The test for any file: `grep -rn '<path under .config>' ~/dotfiles/.config/dotfiles/nix/pkgs`.
- **Libraries.** A bin sources the shared library as `"${ARI_ZSHLIB:-<live path>}/<file>"` and its own plugin as `"${ARI_PLUGINS:-${HOME}/.config/zsh/plugins}/<plugin>.zsh"`. `<live path>` is one of the three strings `liveDefaults` in `pkgs/ari-zshlib/default.nix` lists, spelled exactly: `${HOME}/.config/zsh/plugins`, `${HOME}/.claude/skills/ari-skill-shellscripts/lib`, `${HOME}/.config/bash/plugins`. The package's build rewrites those defaults to store paths with `ari_zshlib.pin [ "$out/bin/<bin>" … ]` and `ari_zshlib.pinPlugins [ "$out/bin/<bin>" … ]` (the plugin copies go in `$out/share/zsh/plugins`). **Any other spelling (`~/…`, `$HOME/…`, `${SKILLS_DIR}/…`, `${XDG_CONFIG_HOME:-…}`) is not rewritten, and the build does not fail**: the packaged bin keeps reading the live files.
- **`dotfiles-cli`.** `ARI_DOTFILES_SRC` names the editable sources (the edit verbs' targets and the tests); run from the store it defaults to `~/dotfiles/.config/dotfiles`. The job plugins (`dotfiles/jobs`) stay linked files. An edit to the CLI (`cmd/switch.zsh` included) runs from the store only after a **Switch**; try it first with `~/dotfiles/.config/bin/dotfiles <verb>`, and use that clone copy for the switch when the edit changes the switch.

### Dev repos

`plugged`, `chrome-exoskeleton` and `run-log` are inputs of the shared flake (`github:AriSweedler/<name>`, `flake = false`), passed to its modules and to `pkgs/` as `devInputs`; they are not git submodules, and no flake URL carries `submodules=1`. `~/dotfiles/.config/dotfiles/dev-repos` lists each checkout, which the clone ignores. The `ari-zshlib` mirror (checkout `~/dotfiles/.config/ari-zshlib`, also ignored) is not a dev repo and not an input: Ari's public repos take it as theirs (run-log's own flake does), and the shared flake builds `ari_zshlib` from the clone. Which repos, their layout, commits, pushes and the `flake.lock` bump `dotfiles push` makes: `/ari-dotfile--submodule` (the name predates the flake inputs); this skill never runs `dotfiles push`.

- **`dotfiles switch`** runs `nix flake lock --override-input dotfiles 'git+file://<clone>?dir=.config/dotfiles/nix&rev=<HEAD>'` plus `--override-input dotfiles/<input> 'git+file://<checkout>?rev=<HEAD>'` per checkout present: each dev repo builds from its checkout's HEAD commit, unpushed commits included; one not checked out builds from the shared `flake.lock`.
- **A trial build** (**Verify a module change**, **Build a worktree**) overrides only `dotfiles`, so it builds the dev repos at the shared lock's commits. **When the change touches `pkgs/plugged`, the `run-log` package, or a module that reads `devInputs`, add the override the switch makes, for each checkout present**: `--override-input dotfiles/<input> "git+file://$HOME/dotfiles/.config/<input>?rev=$(git -C ~/dotfiles/.config/<input> rev-parse HEAD)"`. The `?rev=` keeps uncommitted checkout edits out, as the switch does.

### Modules

These `programs.*` modules in the shared flake write their configs into the store. The local flake adds to one through the same option, e.g. `programs.starship.settings.kubernetes.disabled = false;` or `programs.tmux.extraConfig = "set -g status-position top";` in its `home.nix`. **Set each `settings` key in one tier only**: a key both tiers set fails evaluation (`conflicting definition values`); ask Ari which tier keeps it, and use `lib.mkForce` only when he says so. `extraConfig` does not conflict: the local lines come after the shared ones, so a repeated `set` there silently wins.

| Module | Writes | After a switch | Notes |
|---|---|---|---|
| `git.nix` | `~/.config/git/config`, `~/.config/git/ignore` | nothing: read on each run | Includes `~/.local/share/git/config` last, for repos under `$HOME` only (`gitdir:~/`), so that file wins. It is not managed. delta is a plain package with `core.pager = delta`, not `programs.delta`, whose integration pages only diff, log, show and blame. `~/.config/git/bin` (less `git-dotfiles`, a packaged bin), the hooks and `git/template` stay linked. |
| `tmux.nix` | `~/.config/tmux/tmux.conf` | `<Prefix>C-s` in each running server | Typed options, then `~/.config/dotfiles/nix/tmux/*.conf` in the order `tmux.nix` lists them, concatenated into `extraConfig`. typhon is pinned from GitHub (`AriSweedler/tmux-typhon`, `mkTmuxPlugin`) and runs last; no TPM. A working copy at `~/.local/share/tmux/local-plugins/tmux-typhon` loads instead of the pin. |
| `starship.nix` | `~/.config/starship.toml` | nothing: the next prompt reads it | `~/.config/zsh/plugins/starship.zsh` runs `starship init`. |
| `gh.nix` | `~/.config/gh/config.yml` | nothing | `hosts.yml` stays gh's. `gitCredentialHelper` is off: git keeps osxkeychain. |

### Open work

Phases 1–5 landed (2026-11-07). The plan and its decisions are the Nix port epic in Ari's beads workspace `~/beads` (title "Mac feels like NixOS without replacing macOS …"); read it per `/ari-bead-driven-development`, and ask Ari when `~/beads` is missing.

- **Phase 6**: `dotfiles switch` landed, the bare repo is retired, and the steps Nix covers shrank (2026-11-10; **What Nix owns** › Harness steps).
- **Packages** (epic "Dotfiles as Nix packages: package what you run, link what you edit", same workspace): the packages, `dotfiles-cli`, the dev-repo inputs, `run-log`'s move to its own repo and the `ari-zshlib` mirror landed (2026-11-10). Open: `tmux-oneshot` moves to its own public repo. Decided against: moving bins out of skills.

## Workflow

### Change a file

Take the first item that matches:

1. **A git setting for one machine only**: `git config --file ~/.local/share/git/config <key> <value>`. Live at once, no switch, repos under `$HOME` only; the file is not managed.
2. **A config a module writes** (**Modules**), or a file it reads (`~/dotfiles/.config/dotfiles/nix/tmux/*`): edit the module or that file, **Verify a module change**, commit in df per `/ari-dotfiles`, then **Switch**. A gh setting for one machine only goes in the local `home.nix` (`programs.gh.settings`).
3. **A packaged bin** (`readlink -f` ends in `/nix/store/…-<pname>-<version>/bin/<bin>`), **or a file a package copies** (**Ari's packages** › Copied sources; its `grep` finds it): edit the clone's copy, `~/dotfiles/<repo path>` (a bin's repo path is its `placed` entry in `ari-bins.nix`: `.config/bin/<bin>`, or `.config/git/bin/git-dotfiles`); a `run-log` bin's source is the run-log checkout's `bin/`, edited and committed per `/ari-dotfile--submodule-run-log`. Try it by running that clone copy directly, so its shebang picks the interpreter; a Swift bin runs only once built (the package `nix build`). Commit in df, then **Switch**. **NEVER report the edit live in the packaged bins before that Switch.** An edit to an `ari_zshlib` file reaches every packaged bin: name them to Ari before the commit. A build or `installCheckPhase` failure → handle it as **Switch** step 2's build errors. A new bin stays linked (item 5) unless Ari asks to package it (**Package a bin**).
4. **Anything else under `.config/dotfiles/nix`**, or a store-placed file's source (linked too, but read only at a switch): find the source with `readlink -f <file>`, then `grep -rn '<path>' ~/dotfiles/.config/dotfiles/nix ~/.local/share/dotfiles/nix` (grep the clone: `grep -r` skips the bridge's symlinks under `~/.config`). A `home.file` path is relative to `$HOME`, an `xdg.configFile` path to `~/.config`: `~/.config/tmux/typhon.d` → `grep -rn 'tmux/typhon.d'` → `tmux.nix: xdg.configFile."tmux/typhon.d".source = ./tmux/typhon.d;`. Edit, commit in df, **Switch**.
5. **A new file**: create it at `~/dotfiles/<path>`, NEVER at `$HOME/<path>` (a switch moves that aside to `.before-nix`). Inside a whole directory (**The bridge**) it is live at once: commit, no switch; except a new skill directory, whose `~/.claude/skills/<name>` link comes at the next **Switch** (**What Nix owns** › Files). Elsewhere: commit, then **Switch**.
6. **Linked**, and not a file a package copies (item 3): edit it through `$HOME` or the clone; it is live at once, with no generation to roll back to. After editing a shell startup file, test a clean login (`env -i HOME=$HOME TERM=xterm-256color USER=$USER /bin/zsh -lic true`); on failure, `git df checkout -- <file>`. Commit per `/ari-dotfiles`.
7. **The local flake** (`~/.local/share/dotfiles/nix`): edit, then **Switch**; commit in ldf per `/ari-dotfiles`.
8. **Not managed**: edit in place and commit per `/ari-dotfiles`.

### Add a tool

Pick its place in this order, then edit, commit, **Switch**:

1. A GUI app, a service, or a tap's formula → `casks` or `brews` (a browser: a cask).
2. `grep -rn '/opt/homebrew/bin/<tool>' ~/dotfiles` finds a brew path the code needs → `brews`, with a comment saying why. A hit is not a need when the code first tries a Nix path or `command -v`: `for p in /etc/profiles/per-user/$USER/bin/tmux … /opt/homebrew/bin/tmux` is a fallback list, and the tool goes in `home.packages`.
3. `nix search nixpkgs#<tool>` finds it at the version Ari needs → `home.packages` (ripgrep). Older than he needs → `brews`, with the version gap in a comment (tree-sitter). A home-manager `programs.<tool>` option exists → still `home.packages`; moving its config from the bridge into a module is Ari's call.

Every machine wants it → the shared module; else the local one (the personal laptop's `home.nix` has `cf`, Cloudflare's CLI, from nixpkgs). Ari decides when unclear. One of Ari's own scripts is not a tool to declare: it is a linked file (**Change a file**, item 5), packaged only when Ari asks (**Package a bin**).

### Package a bin

**Only when Ari names the bin and asks for it to be packaged**: afterwards an edit to it is live only after a commit and a **Switch**. Otherwise it stays linked. NEVER package a skill's `bin/`. `readlink -f ~/<repo path>` already ends in `/nix/store` → it is packaged: **Change a file**, item 3.

1. **Convert its source lines** to the forms in **Ari's packages** › Libraries, with `<live path>` spelled exactly:
   ```
   BEFORE: source "${ZDOTDIR:-${HOME}/.config/zsh}/plugins/open_link.zsh"
   AFTER:  source "${ARI_PLUGINS:-${HOME}/.config/zsh/plugins}/open_link.zsh"
   AFTER:  readonly LOG_LIB="${ARI_ZSHLIB:-${HOME}/.config/zsh/plugins}/log.zsh"
   BAD:    "${ARI_ZSHLIB:-${SKILLS_DIR}/ari-skill-shellscripts/lib}/logging.zsh"   ← never pinned
   ```
2. **Pick its package**: a `git-*` helper or `repo` → `git-kit`; a `run_log` helper → the run-log repo (`/ari-dotfile--submodule-run-log`), not `pkgs/`; any other small macOS utility → `mac-utils`; otherwise a new `pkgs/<pkg>/default.nix`, copied from `pkgs/notes/default.nix` (the smallest; no plugin) or `pkgs/git-kit/default.nix` (a bin with its own plugin):
   - `dontUnpack = true`, and read `${src}/.config/…` in place: the unpacker skips dot directories.
   - `install -Dm755 -t $out/bin`, then `patchShebangs $out/bin`.
   - `${ari_zshlib.pin [ "$out/bin/<bin>" ]}`, and `${ari_zshlib.pinPlugins [ "$out/bin/<bin>" ]}` with the plugin installed to `$out/share/zsh/plugins`.
   - A `doInstallCheck` whose `installCheckPhase` runs the bin with `HOME=$TMPDIR`, and fails on a live path the pin missed, as `pkgs/mac-utils` does: `if grep -lE '\.config/(zsh|bash)/plugins/|ari-skill-shellscripts/lib' $out/bin/<bin>; then exit 1; fi`.
   - Swift: compile at build time with `swiftc` (`pkgs/mac-utils`); `swiftc` reads a file without the `.swift` suffix as an object file, so `cp` it to `<bin>.swift` first.
3. **Add it** to `pkgs/default.nix` (a new package) and to `placed` in `ari-bins.nix` (repo paths, no `~/`), never to `home.packages`:
   ```nix
   foo = pkgs.callPackage ./foo { inherit src; inherit (self) ari_zshlib; };   # pkgs/default.nix
   foo = [ ".config/bin/foo" ];                                               # ari-bins.nix, placed
   ```
4. **`git -C ~/dotfiles add`** the new files (Rules), then build the package alone with the `nix build` in **Ari's packages**. Then build `$H` as **Verify a module change** does and check `readlink $H/<repo path>` names `…-<pname>-<version>/bin/<bin>`; **do not commit until it does**. A build or `installCheckPhase` failure → handle it as **Switch** step 2's build errors.
5. Commit in df per `/ari-dotfiles`, then **Switch**; `readlink -f ~/<repo path>` then ends in the package's store path. Then `/ari-skill-update ari-dotfiles-nix` adds the bin to **Ari's packages** (Rules).

### Verify a module change

**Run it on every edit under item 2 of Change a file, before the commit.** It builds the clone's working tree (tracked files, uncommitted edits included) with `--override-input`, because the local `flake.lock` still pins the old shared commit until `dotfiles switch --build` moves it; a build without the override compares the running config with itself. Run it as one Bash call, so `$H` survives, from `~` so git's `gitdir:~/` include resolves:

```zsh
[[ "$(command -v bash)" == /etc/profiles/* ]] || export PATH=/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH; cd ~
H=$(nix build --no-link --print-out-paths --no-write-lock-file --override-input dotfiles "git+file://$HOME/dotfiles?dir=.config/dotfiles/nix" "path:$HOME/.local/share/dotfiles/nix#darwinConfigurations.<host>.config.home-manager.users.$USER.home-files") && [[ -d $H ]] || exit 1
diff <(git config --global --list --includes) <(GIT_CONFIG_GLOBAL=$H/.config/git/config git config --global --list --includes)
diff ~/.config/git/ignore $H/.config/git/ignore
tmux -L nixold kill-server 2>/dev/null; tmux -L nixtest kill-server 2>/dev/null
tmux -L nixold -f ~/.config/tmux/tmux.conf new-session -d; tmux -L nixtest -f $H/.config/tmux/tmux.conf new-session -d
diff <(tmux -L nixold show -g; tmux -L nixold show -gw) <(tmux -L nixtest show -g; tmux -L nixtest show -gw)
tmux -L nixold kill-server; tmux -L nixtest kill-server
diff ~/.config/starship.toml $H/.config/starship.toml; diff ~/.config/gh/config.yml $H/.config/gh/config.yml
```

- The two test servers keep a running server's runtime `set`s out of the tmux diff. tmux 3.8 made the `display-panes-*` options window options: they show in `show -gw`, not `show -g`.
- For starship and gh, a change in quoting, key order or indentation is formatting; ignore it.
- **The build fails** → handle it as Switch step 2's errors do.
- **Every diff is empty, but the change was meant to alter the config** → `$H` is not your edit (a file not `git add`ed, the wrong flake): stop; do not report it verified.
- **A difference the change did not intend** → NEVER switch: fix the source and verify again. After two failed fixes, show Ari the diff.
- **Only intended differences** → carry them, one line each, into Switch step 3's preview.

### Switch

1. **Check the clone and each dev-repo checkout** (`dotfiles switch` warns only about the nix directory; the clone's status never shows the checkouts):
   ```zsh
   git -C ~/dotfiles status --porcelain
   for d in ${(f)"$(git config -f ~/dotfiles/.config/dotfiles/dev-repos --get-regexp '^repo\..*\.path$' | cut -d' ' -f2)"}; do [[ -d ~/dotfiles/$d/.git ]] && git -C ~/dotfiles/$d status --porcelain | sed "s|^|$d: |"; done
   ```
   - An untracked (`??`) or staged new file is not linked by this switch: commit it per `/ari-dotfiles`, or tell Ari it stays out.
   - **A packaged bin, a file a package copies (Change a file, item 3), or any edit in a dev-repo checkout MUST be committed before the build** (a checkout per `/ari-dotfile--submodule`), or named to Ari as left out.
   - A modified tracked file under `.config/dotfiles/nix` or in a path **The bridge** skips is not in this switch either: commit it, or tell Ari it stays out.
   - Any other modified tracked file is live already.
2. **Always build before switching**: `dotfiles switch --build`. It prints one `/nix/store/…-darwin-system-…` path; record it and `git -C ~/dotfiles rev-parse HEAD`.
   - **It warns `uncommitted under the nix directory`** → stop: commit those paths, rebuild. NEVER switch a build made with that warning.
   - **Exit 64** → a precondition: no clone, no local flake, or not one host. `0 hosts` can hide an evaluation error: the listing in **Flakes** shows it. Several hosts → ask Ari which one to build, and prefix every later `dotfiles` call with `ARI_DOTFILES_NIX_HOST=<host>`.
   - **`unrelated staged changes`** in ldf → commit or unstage them per `/ari-dotfiles`.
   - **A fetch or substitute error** → say the machine is offline, and stop.
   - **An evaluation or build error** → show the first error with its file:line, fix the source, commit, rebuild. After two failed fixes, stop and show Ari the error and what you tried.
   - **The path equals `readlink /run/current-system`** → nothing changed: say so, and skip steps 3 and 4.
3. **Preview**, in one message, then go on to step 4 unless it asks Ari something:
   - `nvd diff /run/current-system <path>`.
   - **Module configs**, when the build changes a module (**Modules**): the intended differences **Verify a module change** found, one line each; not yet run → run it now. No module changed → omit the line.
   - The source diff: the df commits after the running system's lock rev, the newest `nix: lock the shared flake at <rev>` in `git ldf log --format=%s -- ~/.local/share/dotfiles/nix/flake.lock` older than this build's, plus local-flake edits, plus each checkout's `git -C ~/dotfiles/<path> log --oneline <its rev in the running lock>..HEAD`, marking commits not yet on its upstream; none → `no dev-repo changes`.
   - **Brew removals, which a rollback does not undo**: `export HOMEBREW_NO_AUTO_UPDATE=1; B=<path>/etc/dotfiles/Brewfile; comm -23 <(brew leaves --installed-on-request | sed 's|.*/||' | sort) <(brew bundle list --formula --file=$B | sed 's|.*/||' | sort); comm -23 <(brew list --cask -1 | sort) <(brew bundle list --cask --file=$B | sed 's|.*/||' | sort)`; both sides strip the tap prefix, which `brew leaves` prints (`owner/tap/name`). Each name printed is uninstalled by the switch: ask Ari, per name, to declare it (**Add a tool**, then rebuild) or let it go. None → say `no brew removals`.
   - **A tool leaving brew** (a `brews` entry removed, the tool now from `home.packages` or a `programs.*` module): `grep -rn '<tool>' ~/dotfiles/.config/zsh ~/dotfiles/.zshenv | grep -E 'init|eval|/opt/homebrew'`; name each match. Tell Ari to `exec zsh` in every open pane afterwards (or re-run that init, e.g. `eval "$(starship init zsh)"`), and to restart a Claude session started before it with `claude --continue`: each keeps the old `/opt/homebrew/bin` path.
4. **Claude**: `dotfiles switch`, with the Nix PATH prefix (Rules), never a raw `sudo darwin-rebuild`. The harness refuses it, or sudo asks for a password → hand Ari the same `dotfiles switch` per `/ari-driving` and read his result the same way; the permission rule that allows it is Ari's to add, NEVER edit Claude's settings for it. Read the result:
   - Exit 0 and `readlink /run/current-system` equals the built path → done. Tell Ari: shell config changed → a new shell; a module's config → its **After a switch** cell in **Modules**; another app's config → reload that app, by name.
   - Exit 0, another path → HEAD moved since the build: show `nvd diff <built path> /run/current-system` and `git -C ~/dotfiles log --oneline <recorded rev>..HEAD`, the part he did not preview.
   - Non-zero → show the first error, then route it: **Troubleshooting**, or offer **Roll back**. NEVER re-run the same switch unchanged.
   - Sudo refused or cancelled → nothing activated; say so.

### Roll back

**A rollback reverts the system** (packages, `/etc`, defaults, launchd), **never a linked file**: a broken linked file is fixed in the clone (`git df checkout`, or edit and commit). Claude reads the generations with no sudo: `readlink /nix/var/nix/profiles/system` names the current one (`system-9-link`), `ls -d /nix/var/nix/profiles/system-*-link` lists them, and `nvd diff /nix/var/nix/profiles/system-8-link /nix/var/nix/profiles/system-9-link` shows what the current one changed. Show that diff, then ask Ari to pick; do not pick for him:

- **Roll back** (Ari): `sudo /run/current-system/sw/bin/darwin-rebuild switch --rollback`. Then fix or revert the source and commit it before the next **Switch**, or the next build rebuilds the broken system.
- **Debug first**: Claude reads the source and the diff; Ari runs `sudo darwin-rebuild --list-generations` only when dates matter.

One generation only → nothing to roll back to: offer to fix forward, or **Uninstall**.

### Build a worktree

A trial build of shared changes in a git worktree of the clone, without committing them on `main`. **NEVER switch from it**: a switch builds the clone's HEAD, so merge to `main`, then **Switch**.

1. `git -C <worktree> add` every new file: a `git+file:` input sees only tracked files (uncommitted edits to them included).
2. Build:
   ```zsh
   nix build "path:$HOME/.local/share/dotfiles/nix#darwinConfigurations.<host>.system" --override-input dotfiles 'git+file://<worktree>?dir=.config/dotfiles/nix' --no-write-lock-file --no-link --print-out-paths
   ```
   For **Verify a module change** on the worktree, use its build with `$HOME/dotfiles` replaced by `<worktree>`. Nix rejects the worktree URL → stop and show the error; do not commit to `main` to get around it.

## Install and first switch

Claude runs step 1; each later step is Ari's, handed per `/ari-driving`.

1. **Check for leftovers**, only when `/run/current-system` does not exist (else Nix is installed: **Switch**): `grep -s -n -i nix /etc/bashrc /etc/zshrc /etc/zshenv; print -l /etc/*.backup-before-nix(N); grep -s nix /etc/fstab`. Nothing printed is clean. Hand Ari a command per hit: a Nix block in a shell file, a `*.backup-before-nix` file to restore, a `/nix` fstab line (`sudo vifs`). Leave the `nixbld` users and group (UID 351+, GID 350): the installer reuses them.
2. **Install (Ari)** upstream Nix with NixOS's installer, not Determinate's (it installs Determinate Nix): `curl -sSfL -o /tmp/nix-installer https://artifacts.nixos.org/nix-installer && sh /tmp/nix-installer install --enable-flakes`. Check with `/bin/zsh -lic 'nix --version'`.
3. **First switch (Ari)**. It needs the clone at `~/dotfiles` and the local flake at `~/.local/share/dotfiles/nix`, whose `flake.nix` names `$USER` in `user` and the clone's URL. `dotfiles switch` works from the second switch on; the first is `sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin/master#darwin-rebuild -- switch --flake ~/.local/share/dotfiles/nix#<host>` (**Flakes**). nix-darwin refuses unknown `/etc` files: hand Ari `sudo mv /etc/<name> /etc/<name>.before-nix-darwin` for each it names, then the switch again.

### Uninstall

Ari, in order: restore each `/etc/*.before-nix-darwin`; `sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin#darwin-uninstaller`; then `sudo /nix/nix-installer uninstall`, which refuses while nix-darwin is installed. List what each step removes before handing it over.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Editing a file fails: read-only | It is store-placed | **Change a file**, items 2–4 |
| An edit to a bin, or to a library or plugin it reads, has no effect | The bin is packaged, or the file is one a package copies: the bin runs the store copy from the last switch | **Change a file**, item 3 |
| The `dotfiles_jobs` step fails `not_installed` or `not_loaded` | The launchd job is nix-darwin's | **Switch**; `dotfiles jobs install` does not install it |
| A build fails in `karabiner.nix` (a JSON parse error or an assertion) | `karabiner.json` is not a valid JSON object | Re-bake it (`~/dotfiles/.config/karabiner/bin/bake`), commit, rebuild |
| `git config --global` fails (`could not lock config file …/.config/git/config`), or `gh config set` / `gh alias set` fails | A module writes that config into the store | **Change a file**, items 1–2 |
| `git maintenance register` fails to write the config | It writes the global config by default | `git maintenance register --config-file ~/.local/share/git/config` |
| A public repo's flake, updated right after a push to one of its inputs, locks the older commit (run-log's `ari-zshlib` lock did) | Nix caches a GitHub ref for an hour | In that repo, `nix flake update <input> --refresh` |
| A shared edit or a new clone file has no effect after a switch | Not committed when the switch locked HEAD | Commit per `/ari-dotfiles`, then **Switch** |
| A `<file>.before-nix` appears in `$HOME` | A file stood where the bridge links; home-manager moved it aside | Show Ari `diff <file>.before-nix ~/dotfiles/<path>`; move into the clone only what he approves, and delete the backup only after he says so |
| A switch fails: a file would be clobbered by backing it up | `<file>.before-nix` already exists | Resolve the old backup as above, then **Switch** |
| A switch prints `Homebrew bundle: nothing changed since the last bundle; skipped`, yet a declared formula or cask is missing | The stamp matched | Ari: `sudo rm /var/db/dotfiles-brew-bundle.stamp`; then **Switch** |
| `nix` not found, or `env bash` is 3.2, in a Claude session started before the switch | Its env predates the switch, and `__NIX_DARWIN_SET_ENVIRONMENT_DONE=1` makes `/etc/zshenv` skip Nix setup | The PATH prefix (Rules); test a clean login with `env -i HOME=$HOME TERM=xterm-256color USER=$USER /bin/zsh -lic 'command -v nix'`; Ari restarts the session with `claude --continue` |
| `zsh: no such file or directory: /opt/homebrew/bin/starship` on every prompt | A switch moved starship out of brew; `starship init zsh` baked brew's path into the shell's hooks | `exec zsh` in that pane, or `eval "$(starship init zsh)"` |
| `--list-generations`: `opening lock file "/nix/var/nix/profiles/system.lock": Permission denied` | It needs root | Ari runs it with sudo, or Claude reads the profile links (**Roll back**) |
