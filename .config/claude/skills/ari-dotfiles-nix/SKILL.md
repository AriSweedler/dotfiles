---
name: ari-dotfiles-nix
description: Edit, switch, roll back and commit Ari's dotfiles under the Nix port (nix-darwin + home-manager): how to tell a file the bridge links into the ~/dotfiles clone from a store-placed or an unmanaged one, the shared and local flakes, where a new tool goes (never a bare brew install), `dotfiles switch` (Claude builds with --build, Ari switches), what Nix owns today versus the open phases, and the install, first-switch, uninstall and troubleshooting facts. Use whenever a change touches ~/.config/dotfiles/nix, ~/.local/share/dotfiles/nix, a file linked into /nix/store, dotfiles switch, darwin-rebuild, brew install, or a Nix-managed package. Tiers, commits, review and pushing stay with /ari-dotfiles.
---

# Dotfiles under Nix

Ari's dotfiles run on nix-darwin and home-manager: the local flake takes the shared one from the plain clone `~/dotfiles`, `dotfiles switch` activates the generation they build, and home-manager links the clone's files into `$HOME`. Here: changing a file or a tool, switching, rolling back, what Nix owns today, and installing or removing Nix; `/ari-dotfiles` stays the authority for tiers, commits, review and pushing.

## Rules

- **Ari runs anything that needs sudo**: `dotfiles switch` (it runs `sudo darwin-rebuild switch` and prompts for his password), `darwin-rebuild --rollback` and `--list-generations`, the installer, the uninstaller, and every edit or move in `/etc`, `/var/db` or fstab. Hand each over per `/ari-driving`. **NEVER run one yourself, even when it fails or is not found**; hand Ari the full path `/run/current-system/sw/bin/darwin-rebuild` instead.
  ```
  BAD:  Ari's pane says `darwin-rebuild: command not found` → Claude runs `sudo /run/current-system/sw/bin/darwin-rebuild switch …`
  GOOD: Claude hands Ari `sudo /run/current-system/sw/bin/darwin-rebuild switch --flake ~/.local/share/dotfiles/nix#personal` per /ari-driving
  ```
- **Claude's**: `dotfiles switch --build`, `nix build`, `nix eval`, `nvd diff` and read-only checks. `--build` is not read-only: it commits **and pushes** a moved `flake.lock` in ldf; `--build --no-commit` leaves the tiers untouched, for a trial build.
- **Prefix every Bash call that runs `nix`, `nvd`, `dotfiles` or `env bash` with the Nix PATH**: shell state does not carry between calls, and a Claude session started before the last switch lacks it. The Nix dirs must come before `/usr/bin`, or `env bash` finds `/bin/bash` 3.2:
  ```zsh
  [[ "$(command -v bash)" == /etc/profiles/* ]] || export PATH=/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:$PATH; command -v nix >/dev/null || echo 'nix not installed: see Install and first switch'
  ```
- **Nix sees only what git committed in the clone.** `dotfiles switch` locks the shared input at the clone's HEAD, so an uncommitted change under `.config/dotfiles/nix`, or an uncommitted new file anywhere in the clone, is not in the switch.
- **NEVER run `nix flake update`, `nix flake lock --update-input`, or edit `flake.lock` by hand.** To pick up a new shared commit, run `dotfiles switch --build`. Re-pin nixpkgs, nix-darwin or home-manager only when Ari asks. The header comment of `~/.local/share/dotfiles/nix/flake.nix` that says otherwise predates `dotfiles switch`.
- **When an edit fails read-only, NEVER `chmod`, `sudo`, `rm` or replace the link**: the file is store-placed. Find its source with `grep -rn '<path relative to $HOME>' ~/.config/dotfiles/nix ~/.local/share/dotfiles/nix` (a `home.file` entry), edit that, commit, then **Switch**.
- **NEVER `brew install`, `brew uninstall` or `nix profile install` alone**: a switch uninstalls every undeclared formula and cask. Declare the tool (**Add a tool**).
- **NEVER delete or edit a harness step that Nix also covers** (`dotfiles steps`) until Ari decides between deleting them and keeping them as skip-on-nix (`beads-2ly.7.6`); a change that needs one asks him.
- **Keep this skill current, through `/ari-skill-update`, in the same session** when a switch adds or removes a `home.packages`, `brews`, `casks` or `home.file` entry, a `programs.*` module replaces a bridge link, or a `beads-2ly.7.*` bead closes: **What Nix owns**, the Phase plan, the frontmatter description, and any step that changed. **When What Nix owns and `readlink -f` disagree, tell Ari and propose the fix the same way.**
- **NEVER put a flake or module in `~/.config/nix` or `~/.local/share/nix`.** Nix owns them (user `nix.conf`; repl history and trusted settings). Shared code goes in `~/.config/dotfiles/nix`, machine-only code in `~/.local/share/dotfiles/nix`.

## Layout

### Flakes

| Flake | Path | Tier | Holds |
|---|---|---|---|
| Shared | `~/.config/dotfiles/nix` (the clone's `~/dotfiles/.config/dotfiles/nix`) | df | `darwin.nix` (imports `macos.nix`) as `darwinModules.default`, `home.nix` as `homeModules.default`, `bridge.nix`, `lib.darwinSystem { user; modules; homeModules; }`; its `flake.lock` pins nixpkgs (nixpkgs-unstable), nix-darwin, home-manager |
| Local | `~/.local/share/dotfiles/nix` | ldf | `darwinConfigurations.personal`, built by the shared `lib.darwinSystem` from the local `darwin.nix` (this machine's brews, casks, system packages) and `home.nix` (this machine's packages); takes the shared flake as the `git+file:` input `dotfiles`. `dotfiles switch` reads it as a `path:` flake, so its own uncommitted edits build |

`personal` is this machine's configuration (`nix flake show ~/.local/share/dotfiles/nix` names it elsewhere). `~/dotfiles.git` is retired (`~/dotfiles.git.retired`): `$HOME` is not a work tree, and `git df` runs on the clone.

### The bridge

`bridge.nix` links every file the clone tracks into `$HOME` with `mkOutOfStoreSymlink`, except `README.md`, `.gitmodules` and `.gitignore`. It links `.config/nvim`, `.config/karabiner`, `.config/claude`, `.config/chrome-exoskeleton` and `.config/plugged` as whole directories (`wholeDirs`): a new file inside one is live at once, with no switch.

### Kinds of file

Decide by `readlink -f <file>` alone:

| `readlink -f` ends in | Kind | Example |
|---|---|---|
| `~/dotfiles/…` | Linked: the clone's file | `~/.zshenv -> /nix/store/…-home-manager-files/.zshenv -> ~/dotfiles/.zshenv`; `~/.config/nvim/init.lua` (no link itself; its directory is one) |
| `/nix/store/…` | Store-placed: a read-only copy | `~/.local/state/dotfiles/nix-managed`, from `home.file` in the shared `home.nix` |
| anything else | Not managed | every other file under `~/.local` (the local tier) |

### Backup suffixes

| Suffix | Made by | Where | What to do |
|---|---|---|---|
| `.before-nix` | home-manager, when a file stood where a link goes | `$HOME` | **Troubleshooting** |
| `.before-nix-darwin` | Ari, at the first switch | `/etc` | restore only on **Uninstall** |
| `.backup-before-nix` | the Nix installer | `/etc` | a leftover: **Install and first switch** step 1 |

## What Nix owns

Phases 1–3 and 5 landed (2026-11-07).

- **Packages**: CLI tools from nixpkgs, in `home.packages` of the shared `home.nix` (git, starship, jq, bash 5, zsh, nvd, poppler-utils, …) or the local `home.nix` (machine-only: gh, go, kubectl, …). `environment.systemPackages` in the local `darwin.nix` is for a tool root or launchd needs.
- **Homebrew**: nix-darwin's `homebrew` module; shared `brews` and `casks` in the shared `darwin.nix`, this machine's taps, brews and casks in the local `darwin.nix`, applied from `/etc/dotfiles/Brewfile`. `cleanup = "uninstall"`: **a switch uninstalls every formula and cask not declared.** A switch skips `brew bundle` when the bundle command and the mtimes of Homebrew's `Cellar`, `Caskroom` and `Library/Taps` match `/var/db/dotfiles-brew-bundle.stamp`.
- **Fonts, neovim, the jobs agent**: `fonts.packages`, neovim pinned in the flake, and the `dotfiles-jobs` launchd agent, in the shared `darwin.nix`.
- **macOS defaults**: `macos.nix`, one user script in `postActivation`; it writes a default only when it differs, and restarts the Dock or Finder only when one of its keys changed.
- **System files**: `/etc/zshenv` runs set-environment, which replaces PATH, only in interactive or login shells; a non-interactive script (a launchd job, the test world) keeps the PATH it was given. `/etc/nix/machines` is empty, so a switch does not reload nix-daemon.
- **Files**: every file the clone tracks, linked by the bridge; store-placed, only the marker `~/.local/state/dotfiles/nix-managed`.
- **Planned modules** (`beads-2ly.7.12`): `programs.git`, `programs.starship`, `programs.tmux` and gh replace their bridge links one tool at a time; tmux and terminal-notifier leave brew once nothing hardcodes their brew path.

### Phase plan

Epic `beads-2ly.7` in Ari's beads workspace `~/beads` holds the decisions and the plan; each phase is a child bead and lands when it closes. Read them per `/ari-bead-driven-development` (`bd show beads-2ly.7`).

- **4** (`beads-2ly.7.4`, every config file placed by home-manager): the bridge meets it; it waits only on `beads-2ly.7.11`, the clone and the bridge.
- **6** (`beads-2ly.7.6`): `dotfiles switch` landed and the bare repo is retired; retiring the harness steps Nix covers waits on Ari (Rules).

## Workflow

### Change a file

Take the first bullet that matches:

1. **Under `.config/dotfiles/nix`**, or a store-placed file's source (linked too, but read only at a switch): edit, commit in df per `/ari-dotfiles`, then **Switch**.
2. **A new file**: create it at `~/dotfiles/<path>`, NEVER at `$HOME/<path>` (a switch moves that aside to `.before-nix`). Inside a whole directory (**The bridge**) it is live at once: commit, no switch. Elsewhere: commit, then **Switch**.
3. **Linked**: edit it through `$HOME` or the clone; it is live at once, with no generation to roll back to. After editing a shell startup file, test a clean login (`env -i HOME=$HOME TERM=xterm-256color USER=$USER /bin/zsh -lic true`); on failure, `git df checkout -- <file>`. Commit per `/ari-dotfiles`.
4. **The local flake** (`~/.local/share/dotfiles/nix`): edit, then **Switch**; commit in ldf per `/ari-dotfiles`.
5. **Not managed**: edit in place and commit per `/ari-dotfiles`.

### Add a tool

Pick its place in this order, then edit, commit, **Switch**:

1. A GUI app, a service, or a tap's formula → `casks` or `brews` (a browser: a cask).
2. `grep -rn '/opt/homebrew/bin/<tool>' ~/dotfiles` finds a hardcoded brew path → `brews`, with a comment saying why (terminal-notifier).
3. `nix search nixpkgs#<tool>` finds it at the version Ari needs → `home.packages` (ripgrep). Older than he needs → `brews`, with the version gap in a comment (tree-sitter).

Every machine wants it → the shared module; else the local one. Ari decides when unclear.

### Switch

1. **Check the clone**: `git -C ~/dotfiles status --porcelain`. An untracked (`??`) or staged new file is not linked by this switch: commit it per `/ari-dotfiles`, or tell Ari it stays out. A modified tracked file outside `.config/dotfiles/nix` does not matter: it is live already.
2. **Always build before handing Ari a switch**: `dotfiles switch --build`. It prints one `/nix/store/…-darwin-system-…` path; record it and `git -C ~/dotfiles rev-parse HEAD`.
   - **It warns `uncommitted under the nix directory`** → stop: commit those paths, rebuild. NEVER hand over a switch built with that warning.
   - **Exit 64** → a precondition: no clone, no local flake, or not one host. `0 hosts` can hide an evaluation error: `nix eval path:$HOME/.local/share/dotfiles/nix#darwinConfigurations --apply builtins.attrNames` shows it. Several hosts → ask Ari which is this machine, and set `ARI_DOTFILES_NIX_HOST`.
   - **`unrelated staged changes`** in ldf → commit or unstage them per `/ari-dotfiles`.
   - **A fetch or substitute error** → say the machine is offline, and stop.
   - **An evaluation or build error** → show the first error with its file:line, fix the source, commit, rebuild. After two failed fixes, stop and show Ari the error and what you tried.
   - **The path equals `readlink /run/current-system`** → nothing changed: say so, and skip steps 3 and 4.
3. **Preview**, then hand over, all in one message:
   - `nvd diff /run/current-system <path>`.
   - The source diff: the df commits after the running system's lock rev, the newest `nix: lock the shared flake at <rev>` in `git ldf log --format=%s -- ~/.local/share/dotfiles/nix/flake.lock` older than this build's, plus local-flake edits.
   - **Brew removals, which a rollback does not undo**: `export HOMEBREW_NO_AUTO_UPDATE=1; B=<path>/etc/dotfiles/Brewfile; comm -23 <(brew leaves --installed-on-request | sort) <(brew bundle list --formula --file=$B | sed 's|.*/||' | sort); comm -23 <(brew list --cask -1 | sort) <(brew bundle list --cask --file=$B | sed 's|.*/||' | sort)`. Each name printed is uninstalled by the switch: ask Ari, per name, to declare it (**Add a tool**, then rebuild) or let it go. None → say `no brew removals`.
   - **A tool leaving brew** (a `brews` entry removed, the package added to `home.packages`): `grep -rn '<tool>' ~/dotfiles/.config/zsh ~/dotfiles/.zshenv | grep -E 'init|eval|/opt/homebrew'`; name each match. Tell Ari to `exec zsh` in every open pane afterwards (or re-run that init, e.g. `eval "$(starship init zsh)"`), and to restart a Claude session started before it with `claude --continue`: each keeps the old `/opt/homebrew/bin` path.
4. **Ari**: `dotfiles switch`, handed per `/ari-driving`. Read the result back:
   - Exit 0 and `readlink /run/current-system` equals the built path → done. Tell Ari: shell config changed → a new shell; an app's config → reload that app, by name.
   - Exit 0, another path → HEAD moved since the build: show `nvd diff <built path> /run/current-system` and `git -C ~/dotfiles log --oneline <recorded rev>..HEAD`, the part he did not preview.
   - Non-zero → show the first error, then route it: **Troubleshooting**, or offer **Roll back**. NEVER re-hand the same switch unchanged.
   - Sudo cancelled → nothing activated; say so.

### Roll back

**A rollback reverts the system** (packages, `/etc`, defaults, launchd), **never a linked file**: a broken linked file is fixed in the clone (`git df checkout`, or edit and commit). Claude reads the generations with no sudo: `readlink /nix/var/nix/profiles/system` names the current one (`system-9-link`), `ls -d /nix/var/nix/profiles/system-*-link` lists them, and `nvd diff /nix/var/nix/profiles/system-8-link /nix/var/nix/profiles/system-9-link` shows what the current one changed. Show that diff, then ask Ari to pick; do not pick for him:

- **Roll back** (Ari): `sudo /run/current-system/sw/bin/darwin-rebuild switch --rollback`. Then fix or revert the source and commit it before the next **Switch**, or the next build rebuilds the broken system.
- **Debug first**: Claude reads the source and the diff; Ari runs `sudo darwin-rebuild --list-generations` only when dates matter.

One generation only → nothing to roll back to: offer to fix forward, or **Uninstall**.

## Install and first switch

Claude runs step 1; each later step is Ari's, handed per `/ari-driving`.

1. **Check for leftovers**, only when `/run/current-system` does not exist (else Nix is installed: **Switch**): `grep -s -n -i nix /etc/bashrc /etc/zshrc /etc/zshenv; print -l /etc/*.backup-before-nix(N); grep -s nix /etc/fstab`. Nothing printed is clean. Hand Ari a command per hit: a Nix block in a shell file, a `*.backup-before-nix` file to restore, a `/nix` fstab line (`sudo vifs`). Leave the `nixbld` users and group (UID 351+, GID 350): the installer reuses them.
2. **Install (Ari)** upstream Nix with NixOS's installer, not Determinate's (it installs Determinate Nix): `curl -sSfL -o /tmp/nix-installer https://artifacts.nixos.org/nix-installer && sh /tmp/nix-installer install --enable-flakes`. Check with `/bin/zsh -lic 'nix --version'`.
3. **First switch (Ari)**. It needs the clone at `~/dotfiles` and the local flake at `~/.local/share/dotfiles/nix`, whose `flake.nix` names `$USER` in `user` and the clone's URL. `dotfiles switch` works from the second switch on; the first is `sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin/master#darwin-rebuild -- switch --flake ~/.local/share/dotfiles/nix#personal`. nix-darwin refuses unknown `/etc` files: hand Ari `sudo mv /etc/<name> /etc/<name>.before-nix-darwin` for each it names, then the switch again. On this laptop they were `/etc/bashrc`, `/etc/zshrc`, `/etc/zshenv`, `/etc/zprofile`, `/etc/nix/nix.conf` and `/etc/nix/nix.custom.conf`.

### Uninstall

Ari, in order: restore each `/etc/*.before-nix-darwin`; `sudo nix --extra-experimental-features 'nix-command flakes' run nix-darwin#darwin-uninstaller`; then `sudo /nix/nix-installer uninstall`, which refuses while nix-darwin is installed. List what each step removes before handing it over.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Editing a file fails: read-only | It is store-placed | Rules: find the source; commit; **Switch** |
| A shared edit or a new clone file has no effect after a switch | Not committed when the switch locked HEAD | Commit per `/ari-dotfiles`, then **Switch** |
| A `<file>.before-nix` appears in `$HOME` | A file stood where the bridge links; home-manager moved it aside | Show Ari `diff <file>.before-nix ~/dotfiles/<path>`; move into the clone only what he approves, and delete the backup only after he says so |
| A switch fails: a file would be clobbered by backing it up | `<file>.before-nix` already exists | Resolve the old backup as above, then **Switch** |
| A switch prints `Homebrew bundle: nothing changed since the last bundle; skipped`, yet a declared formula or cask is missing | The stamp matched | Ari: `sudo rm /var/db/dotfiles-brew-bundle.stamp`, then `dotfiles switch` |
| `nix` not found, or `env bash` is 3.2, in a Claude session started before the switch | Its env predates the switch, and `__NIX_DARWIN_SET_ENVIRONMENT_DONE=1` makes `/etc/zshenv` skip Nix setup | The PATH prefix (Rules); test a clean login with `env -i HOME=$HOME TERM=xterm-256color USER=$USER /bin/zsh -lic 'command -v nix'`; Ari restarts the session with `claude --continue` |
| `zsh: no such file or directory: /opt/homebrew/bin/starship` on every prompt | A switch moved starship out of brew; `starship init zsh` baked brew's path into the shell's hooks | `exec zsh` in that pane, or `eval "$(starship init zsh)"` |
| `--list-generations`: `opening lock file "/nix/var/nix/profiles/system.lock": Permission denied` | It needs root | Ari runs it with sudo, or Claude reads the profile links (**Roll back**) |
