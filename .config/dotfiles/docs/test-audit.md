# Test audit: what does work, and what tests it

Bead beads-2ly.6. Ari, 2026-11-06: "everything that should be tested ... There are framework
things that nix will fix for me. I don't need to test nix. There are also scripts and stuff that
need to do work."

Audited 2026-11-13 at shared-tier commit 2c45c30. Scope: `~/.config/bin`, the zsh and bash
plugins and the zsh functions, the `dotfiles` harness (`lib`, `cmd`, `steps`, `jobs`), the skills'
`bin/` and `lib/` scripts, the Claude Code hook scripts (`.config/claude/bin`, `.config/claude/lib`),
the git helper and hooks (`.config/git`), the Karabiner, AltTab and new-machine scripts, and the
nvim config's own Lua. Out of scope: the dev repos (chrome-exoskeleton, run-log, plugged,
tmux-oneshot), which carry their own suites, and Nix itself.

`~/.local/bin` is out of this audit: it is the local tier (`git ldf`), which is per machine and
private, and this doc is a file of the public shared repo. The local tier's scripts get their own
audit, kept in the local tier.

## How to read the table

- **Path** is relative to the repo root (`~/dotfiles`). A directory row covers every file in it.
- **Tests today** names each suite that exercises the file, with the count it printed in this
  audit's own run (`passed` or `passed/failed`). Hermetic suites live in
  `.config/dotfiles/tests/`, plugin suites in `.config/zsh/plugins/`, skill suites in the
  skill's `tests/`. A Nix package's `installCheckPhase` is a smoke check run at build time; it is
  named as `install check` and has no count, because this audit did not build the packages.
- **Nix?** says what Nix does with the file: `no`; `placed (<package>)` (a Nix package copies the
  file into the store, and that copy is what runs when the package's command runs: a packaged bin
  at its old path, or a file a packaged bin sources. Nix owns which copy runs; the work is still
  ours); `owns` (the work itself is Nix's: installs, linking, launchd). `dotfiles-cli` copies
  `lib`, `cmd`, `steps`, `new-machine` and every zsh plugin but the `*.test.zsh` files
  (`nix/pkgs/dotfiles-cli/default.nix`), so every row for those carries `placed (dotfiles-cli)`.
- **Verdict** is one of `covered`, `needs a suite`, or `no test needed`, with the reason.

How the counts were produced: every `tests/test_*.sh` with `bash`, every
`zsh/plugins/*.test.zsh` under its `OTTO_TEST__ZSH_PLUGINS_<NAME>=true` gate, every skill
`tests/*.test.zsh` (and `check_mention_matchers.zsh`) with `zsh`, and
`lua .config/nvim/lua/ari/gitsigns/pr_parsers_spec.lua`, all from a worktree of 2c45c30 at its
`/private/tmp/...` path. The path matters: run through `/tmp/...` (a symlink to `/private/tmp`),
`test_test_edit.sh` fails 59/11; from the `/private/tmp` path it passes 70/0.
`ari-bead-driven-development/tests/claim_actor.test.zsh` was not run: it drives the real `bd`.

## Suites that failed in this run

| Suite | Result | Cause |
|---|---|---|
| `raycast.test.zsh` | 75/3 | The three `bin:` cases (help lists `edit`, `--dry-run` on a read-only verb, `--to` on another verb). Not diagnosed. |
| `ari-skill-shellscripts/tests/conventions.test.zsh` | 42/4 | All four findings are in `conventions.test.zsh` itself, read through `~/.claude/skills`. The lint skips its own file by its worktree path, so from a worktree it lints itself. An artifact of where it ran. |

At 2ebdebd two more suites failed, test_help_shape.sh 68/1 and test_help_edit.sh 76/3:
`cmd/push.zsh:40` put `` `ssh -T git@github.com` `` in a `verb::env` description, and the help
expanded it as a command substitution, so `dotfiles push --help` opened an ssh connection. The three
`--no-commit` cases edit `push`'s declaration and render its help, which runs the same substitution.
2c45c30 removed the backticks, and at 2c45c30 both suites pass (69/0, 79/0).

## `~/.config/bin`

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/bin/dotfiles` | entrypoint of the harness | every hermetic suite runs it | placed (dotfiles-cli) | covered: see the harness tables |
| `.config/bin/atn` | logging front for terminal-notifier | `atn.test.zsh` (12) | no | covered |
| `.config/bin/repo` | move among a repo's checkouts, label the tmux window | `repo.test.zsh` (21); install check (`--help`) | placed (git-kit) | covered |
| `.config/bin/json-sort` | wrapper over `json_sort.zsh` | `json_sort.test.zsh` (30); install check | placed (mac-utils) | covered |
| `.config/bin/open-any` | wrapper over `open_any.zsh` | `open_any.test.zsh` (22) | placed (mac-utils) | covered |
| `.config/bin/open-link` | wrapper over `open_link.zsh` | `open_link.test.zsh` (31) | placed (mac-utils) | covered |
| `.config/bin/ari-driving` | link to the ari-driving-tmux skill's bin | `ari-driving.test.zsh` (65) | no | covered: see the skills table |
| `.config/bin/alttab-free-build` | link to `.config/alttab/bin/alttab-free-build`: build AltTab Free from source, patch, install | `test_alttab_edit.sh` (76), `test_alttab_step.sh` (43) | no | covered for the patch workflow the tests drive; the build itself needs Xcode and the network: no test needed beyond that |
| `.config/bin/exo` | link into the chrome-exoskeleton dev repo | the dev repo's own vitest/playwright suites | no | out of scope (dev repo) |
| `.config/bin/karabiner-typing-test` | link to karabiner.ts's script: open a Monkeytype test seeded by `passage`, log a CSV line | none | no | needs a suite: the CSV log and the passage hand-off are logic; the browser part is not |
| `.config/bin/git-health` | maintenance runner and guardrail for git object stores (413 lines) | install check (`--help`) | placed (git-kit) | needs a suite: it rewrites object stores; a temp-repo suite is cheap |
| `.config/bin/git-delete-if-merged-all` | delete every local branch merged into the base | none | placed (git-kit) | needs a suite: deletes branches |
| `.config/bin/git-delete-if-merged-one` | delete one branch if merged | none | placed (git-kit) | needs a suite: deletes a branch |
| `.config/bin/git-dedupe-case-refs` | delete remote-tracking refs that collide by case | install check (`--help`) | placed (git-kit) | needs a suite: deletes refs |
| `.config/bin/git-ready` | switch to the dir-named branch and fetch | none | placed (git-kit) | needs a suite: small, fold into the git-kit suite |
| `.config/bin/notes` | date-indexed git journal of daily notes (308 lines) | install check (`--help`, `notes path`) | placed (notes) | needs a suite: path math and commits on a journal Ari uses daily |
| `.config/bin/notif-center` | read and click macOS notifications through AX (862 lines) | install check (layouts present, `notif-ax` usage) | placed (mac-utils) | needs a suite for its layout parsing against the checked-in `.layout` fixtures; the AX calls need a live session |
| `.config/bin/pbpastelinks` | rewrite the clipboard as text with links inlined (369 lines) | none | placed (mac-utils) | needs a suite: the HTML/RTF-to-text rewrite is pure given an input |
| `.config/bin/pbpastelinks-extract.swift` | read every rich-text flavour off the clipboard | none | placed (mac-utils) | no test needed: a pasteboard read; its output feeds `pbpastelinks`, which the suite above covers from fixtures |
| `.config/bin/passage` | walk typing-practice books one passage at a time (661 lines) | none | no | needs a suite: bookmarks and passage splitting are pure state |
| `.config/bin/replace` | find and replace across source files | none | placed (mac-utils) | needs a suite: rewrites files |
| `.config/bin/tmux-tooltip` | read-only card over tmux (519 lines) | used by `bead_link.test.zsh` (16) for its link form only | no | needs a suite: its block layout is pure text |
| `.config/bin/tmux-restart` | restart the tmux server and restore every window | none | no | needs a suite on a throwaway `-L` server: it kills the server |
| `.config/bin/tmux-edit-window` | open `$EDITOR` on a file in a tmux window | named by `test_jobs_notify.sh` (17), not run | no | no test needed: a one-call wrapper |
| `.config/bin/swift-cache` | inspect and trim the shared Swift build cache | none | no | covered once `swift_cache.zsh` has a suite (its logic lives there) |
| `.config/bin/swift-pkg` | run a SwiftPM package's binary from the cache | none | no | same as `swift-cache` |
| `.config/bin/swift-run` | run a single-file Swift tool from the cache | none | no | same as `swift-cache` |
| `.config/bin/chrome-headless` | headless Chromium that never steals focus | none | placed (mac-utils) | no test needed: launches a browser; nothing to assert without one |
| `.config/bin/claude-pr-from-session` | print the PR bound to a Claude Code session | none | no | needs a suite: parses session files; fixtures make it cheap |
| `.config/bin/favicon-maker` | make favicons from an image | none | placed (mac-utils) | no test needed: a wrapper over image tools |
| `.config/bin/applelink` | put a rich link on the clipboard (Swift) | none | placed (mac-utils) | no test needed: one pasteboard write |
| `.config/bin/applepaste` | type text as keystrokes through Script Editor | none | placed (mac-utils) | no test needed: UI automation |
| `.config/bin/karabiner-list-keyboards` | list keyboards by USB vendor id | none | placed (mac-utils) | no test needed: a lookup table over `ioreg` |
| `.config/bin/probe-color` | report what colours the terminal shows | install check (`colors=8`, `colors=256`) | placed (mac-utils) | covered by the install check; a diagnostic |
| `.config/bin/probe-emoji` | measure glyph widths in the terminal | none | placed (mac-utils) | no test needed: a diagnostic that needs a terminal |
| `.config/bin/utc-date` | print HH:MM in UTC | install check (runs) | placed (mac-utils) | no test needed: one `date` call |
| `.config/bin/yubitap` | check a YubiKey registers a tap | none | placed (mac-utils) | no test needed: needs the hardware |

## zsh plugins

`test_suites` reports 30 plugins with no suite; they are the 30 rows below whose Tests column is
`none`. `run_tests.zsh` is the runner and is not counted.

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/zsh/plugins/brew.zsh` | Homebrew env (no auto-update) | `brew.test.zsh` (3) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/claude.zsh` | reclaude and Claude helpers | `claude.test.zsh` (7) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/claude_parsers.zsh` | version-dispatched parsers for Claude Code's files | `claude_parsers.test.zsh` (21) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/double_cd.zsh` | `c<name>` jumps from JSON | `double_cd.test.zsh` (15) | placed (dotfiles-cli, git-kit) | covered |
| `.config/zsh/plugins/fzf_groups.zsh` | exclusive option groups for tmux-oneshot | `fzf_groups.test.zsh` (34) | placed (dotfiles-cli, ari-zshlib) | covered |
| `.config/zsh/plugins/json_sort.zsh` | canonical JSON | `json_sort.test.zsh` (30) | placed (dotfiles-cli, mac-utils) | covered |
| `.config/zsh/plugins/log_rotate.zsh` | rotate a log, keep N backups | `log_rotate.test.zsh` (19) | placed (dotfiles-cli, ari-zshlib) | covered |
| `.config/zsh/plugins/oneshot_group.zsh` | publish a command family as a oneshot group | `oneshot_group.test.zsh` (15) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/open_any.zsh` | pick the opener whose `--check` accepts the input | `open_any.test.zsh` (22) | placed (dotfiles-cli, mac-utils) | covered |
| `.config/zsh/plugins/open_link.zsh` | open a URL from the clipboard | `open_link.test.zsh` (31) | placed (dotfiles-cli, mac-utils) | covered |
| `.config/zsh/plugins/raycast.zsh` | router behind `dotfiles raycast` | `raycast.test.zsh` (75/3) | placed (dotfiles-cli) | covered; 3 failures above |
| `.config/zsh/plugins/raycast_link.zsh` | the `link` subsystem | `raycast_link.test.zsh` (73) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/raycast_snippets.zsh` | the `snippets` subsystem | `raycast_snippets.test.zsh` (196) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/strip_ansi.zsh` | strip ANSI escapes | `strip_ansi.test.zsh` (14) | placed (dotfiles-cli, ari-zshlib) | covered |
| `.config/zsh/plugins/tmux.zsh` | `tcap`, history slicing | `tmux.test.zsh` (53) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/vi_.zsh` | the `vi_*` editor family | `vi_.test.zsh` (12) | placed (dotfiles-cli) | covered |
| `.config/zsh/plugins/log.zsh` | the one logging library (28 functions; the ari-zshlib mirror's source) | none of its own; every suite loads it | placed (dotfiles-cli, ari-zshlib) | needs a suite: its line format is a contract that bins and tests parse |
| `.config/zsh/plugins/swift_cache.zsh` | one cache tree for Swift builds: keys, toolchain stamp, trim (351 lines) | none | placed (dotfiles-cli) | needs a suite: key and trim logic decide what gets rebuilt or deleted |
| `.config/zsh/plugins/fzfdb_cli.zsh` | fzfdb selector: keys, paths, actions (319 lines) | none | placed (dotfiles-cli) | needs a suite: key validation and paths are pure |
| `.config/zsh/plugins/history.zsh` | history options; `histrm` rewrites the history file | none | placed (dotfiles-cli) | needs a suite: `histrm` deletes history lines |
| `.config/zsh/plugins/colors.zsh` | contrast choice, colourize, xterm index | none | placed (dotfiles-cli, mac-utils) | needs a suite: pure colour math |
| `.config/zsh/plugins/utc.zsh` | `utc`, `timedelta` conversions | none | placed (dotfiles-cli) | needs a suite: pure time math |
| `.config/zsh/plugins/str.zsh` | `str::join`, `str::colorize` | none | placed (dotfiles-cli) | needs a suite: pure, a few cases |
| `.config/zsh/plugins/jq.zsh` | `jq::flatten`, `jq::fzf` | none | placed (dotfiles-cli) | needs a suite for `jq::flatten` (pure); `jq::fzf` is interactive |
| `.config/zsh/plugins/pubkey.zsh` | pick and copy a public key | none | placed (dotfiles-cli) | no test needed: a menu over files and the clipboard |
| `.config/zsh/plugins/scroller.zsh` | ANSI scroll-region drawing | none | placed (dotfiles-cli) | no test needed: terminal drawing, read by eye |
| `.config/zsh/plugins/ssh.zsh` | `ssh-conf`, `machines`, agent load | none | placed (dotfiles-cli) | no test needed: wrappers over ssh and the agent |
| `.config/zsh/plugins/www.zsh` | browse helpers | none | placed (dotfiles-cli) | no test needed: opens a browser |
| `.config/zsh/plugins/keystroke.zsh` | run a command from a keystroke | none | placed (dotfiles-cli) | no test needed: a ZLE binding |
| `.config/zsh/plugins/gif.zsh` | `convert_to_gif` over ffmpeg | none | placed (dotfiles-cli) | no test needed: one ffmpeg call |
| `.config/zsh/plugins/xdg.zsh` | XDG dir exports | none | placed (dotfiles-cli) | no test needed: environment |
| `.config/zsh/plugins/ari.zsh` | editor and machine defaults | none | placed (dotfiles-cli) | no test needed: environment |
| `.config/zsh/plugins/arr.zsh` | `arr::contains` | none | placed (dotfiles-cli) | no test needed: one loop |
| `.config/zsh/plugins/chpwd.zsh` | source a venv on `cd` | none | placed (dotfiles-cli) | no test needed: one hook |
| `.config/zsh/plugins/cronstrue.zsh` | `cronny` wrapper | none | placed (dotfiles-cli) | no test needed: one call |
| `.config/zsh/plugins/dotfiles_cli.zsh` | `df` aliases | none | placed (dotfiles-cli) | no test needed: aliases |
| `.config/zsh/plugins/focus_terminal.zsh` | bring the terminal to the front | none | placed (dotfiles-cli) | no test needed: one osascript |
| `.config/zsh/plugins/fzf.zsh` | fzf defaults | none | placed (dotfiles-cli) | no test needed: configuration |
| `.config/zsh/plugins/fzf_group.zsh` | shared fzf options for group pickers | none (used by `fzf_groups.test.zsh`) | placed (dotfiles-cli, ari-zshlib) | no test needed: options |
| `.config/zsh/plugins/k8s.zsh` | `kwhoami` | none | placed (dotfiles-cli) | no test needed: one kubectl call |
| `.config/zsh/plugins/karabiner.zsh` | `vi_::karabiner_*` editors | none | placed (dotfiles-cli) | no test needed: opens files |
| `.config/zsh/plugins/neovim.zsh` | `vi_::dotfiles` | none | placed (dotfiles-cli) | no test needed: opens nvim |
| `.config/zsh/plugins/rust.zsh` | one line of env | none | placed (dotfiles-cli) | no test needed: environment |
| `.config/zsh/plugins/starship.zsh` | init Starship | none | owns (home-manager writes its config); placed (dotfiles-cli) | no test needed: Nix |
| `.config/zsh/plugins/whitespace.zsh` | `whitespace` one-liner | none | placed (dotfiles-cli) | no test needed: one call |
| `.config/zsh/plugins/zsh-vi-mode.zsh` | load zsh-vi-mode | none | owns (home.nix places it); placed (dotfiles-cli) | no test needed: Nix |

## zsh functions and startup

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/zsh/.zshrc` | `prepend_to_path`, plugin loading | none | no | needs a suite for `prepend_to_path` (PATH policy: move-to-front, no duplicates); the rest is startup |
| `.config/zsh/.zshenv` | ZDOTDIR for child shells | none | no | no test needed: environment |
| `.config/zsh/tab_completion.zsh` | compinit and styles | none | no | no test needed: configuration |
| `.config/zsh/completions` | completion functions (`_dotfiles` is generated) | `test_completion_spec.sh` (39) for `_dotfiles` | no | covered for `_dotfiles`; the others: no test needed (zsh completion glue) |
| `.config/zsh/functions/jq::drill` | interactive jq drill-down (156 lines) | none | no | no test needed: an fzf loop; its path building could move into a pure helper first |
| `.config/zsh/functions/vifxn` | open the file a function, alias or command is defined in | none | no | needs a suite: resolving the definition site is logic |
| `.config/zsh/functions/sonic` | file a Sonic invoice from Downloads | none | no | no test needed: a one-off filing flow over Downloads and a browser |
| `.config/zsh/functions/astound` | pointer to the ari-astound skill | none | no | no test needed: four lines |
| `.config/zsh/functions/read_one_keypress` | read one key with echo off | none | no | no test needed: tty handling |
| `.config/zsh/functions/clipboard` | simple clipboard UI | none | no | no test needed: UI |
| `.config/zsh/functions/pubkey` | copy own public key | none | no | no test needed: one copy |
| `.config/zsh/functions/vimrg` | rg results into vim | none | no | no test needed: one call |
| `.config/zsh/functions/b_echo` | banner echo | none | no | no test needed: output |
| `.config/zsh/functions/bb_echo` | banner echo | none | no | no test needed: output |
| `.config/zsh/functions/log::err` | log alias | none | no | no test needed: one line |
| `.config/zsh/functions/log::info` | log alias | none | no | no test needed: one line |
| `.config/zsh/functions/log::warn` | log alias | none | no | no test needed: one line |
| `.config/zsh/functions/wait_for_keypress` | wait for a key | none | no | no test needed: one line |

## The `dotfiles` harness: `lib`

All of `lib`, `cmd` and `steps` is placed by the dotfiles-cli package, whose install check runs
`dotfiles help` and `dotfiles steps`. The work is ours, so placement does not change a verdict.

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/dotfiles/lib/cache.zsh` | reuse a check's verdict while its inputs are unchanged | `test_check_speed.sh` (21), `test_check_speed_2.sh` (20) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/dispatch.zsh` | flags, verb, help | `test_cli.sh` (95), `test_help_edit.sh` (79) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/edit.zsh` | open in `$EDITOR`, keep only when it checks out | `test_verb_lib.sh` (77), `test_git_edit.sh` (72), `test_steps_edit.sh` (88) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/env.zsh` | constants, seams, defaults | `test_env_hermetic.sh` (47), `test_push_ssh.sh` (41) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/kind.zsh` | the type of a command-line value | `test_completion_spec.sh` (39), `test_verb_lib.sh` (77) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/lock.zsh` | one run at a time | `test_verify_lock.sh` (16) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/logging.zsh` | source the log library | every suite | placed (dotfiles-cli) | no test needed: 12 lines of sourcing |
| `.config/dotfiles/lib/machine_name.zsh` | the machine's name file | `test_machine_name.sh` (22) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/notify.zsh` | verify's trail and the banner | `test_jobs_notify.sh` (17), `test_verify_report.sh` (35) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/plan.zsh` | the `--edit` plan file | `test_verb_lib.sh` (77), `test_apply_edit.sh` (38), `test_init_edit.sh` (54) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/run.zsh` | dry-run gate, timing, watchdogs | `test_step_progress.sh` (54), `test_step_timeout.sh` (12), `test_spin_overhead.sh` (13), `test_step_assist.sh` (12) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/spec.zsh` | the command line as data, and its linter | `test_completion_spec.sh` (39) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/steps.zsh` | the step registry and runner | `test_runner.sh` (20), `test_step_isolation.sh` (10), `test_test_properties.sh` (12), `test_step_dotfiles_docs.sh` (37) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/tiers.zsh` | git for the two tiers and the dev repos | `test_tier_commit_no_remote.sh` (4), `test_step_dotfiles_repo.sh` (79), `test_step_local_dotfiles_repo.sh` (27) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/ui.zsh` | output fanciness and the gum wrapper | `test_ui.sh` (60) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/verb.zsh` | a verb's help and parser from one declaration | `test_verb_lib.sh` (77), `test_help_shape.sh` (69) | placed (dotfiles-cli) | covered; at 2ebdebd this suite caught a bug in `push`'s declaration (see **Suites that failed in this run**) |
| `.config/dotfiles/lib/verdict.zsh` | what a check prints | `test_runner.sh` (20), `test_report_render.sh` (32) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/lib/watch.zsh` | which paths each step reads | `test_pull_changes.sh` (43) | placed (dotfiles-cli) | covered |

## The `dotfiles` harness: `cmd`

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/dotfiles/cmd/alttab.zsh` | `dotfiles alttab` | `test_alttab_step.sh` (43), `test_alttab_edit.sh` (76) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/alttab/edit.zsh` | `alttab edit` | `test_alttab_edit.sh` (76) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/apply.zsh` | `dotfiles apply STEP..` | `test_apply_edit.sh` (38), `test_fix_rollup.sh` (32) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/completion.zsh` | compile `_dotfiles` | `test_completion_spec.sh` (39) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/completion/emit.zsh` | the compiler's back end | `test_completion_spec.sh` (39) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/git.zsh` | `dotfiles git` | `test_local_exclude.sh` (10), `test_git_edit.sh` (72) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/git/edit.zsh` | `--local git edit` | `test_git_edit.sh` (72) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/healthcheck.zsh` | every check, reported | `test_healthcheck_edit.sh` (42), `test_report_render.sh` (32), `test_check_all_ok.sh` (8) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/help.zsh` | `dotfiles help` | `test_help_shape.sh` (69), `test_cli.sh` (95) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/help/edit.zsh` | `help --edit` | `test_help_edit.sh` (79) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/init.zsh` | converge the machine | `test_init.sh` (18), `test_setup_idempotent.sh` (10), `test_setup_fresh_home.sh` (24), `test_bootstrap.sh` (37) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/jobs.zsh` | `dotfiles jobs` | `test_jobs_deps.sh` (30), `test_jobs_notify.sh` (17), `test_jobs_edit.sh` (61) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/jobs/edit.zsh` | `jobs edit` | `test_jobs_edit.sh` (61) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/kinds.zsh` | the kind catalog | `test_completion_spec.sh` (39) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/logs.zsh` | `dotfiles logs` | `test_logs.sh` (19) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/machine-name.zsh` | `dotfiles machine-name` | `test_machine_name.sh` (22) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/pull.zsh` | `dotfiles pull` | `test_pull.sh` (33), `test_pull_changes.sh` (43), `test_pull_edit.sh` (41) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/push.zsh` | `dotfiles push` | `test_push_ssh.sh` (41), `test_push_mirror.sh` (48), `test_push_summary.sh` (49), `test_push_edit.sh` (81) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/raycast.zsh` | `dotfiles raycast` | `test_raycast_local_ok.sh` (13), `test_raycast_undocumented.sh` (20), `raycast.test.zsh` (75/3) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/run/edit.zsh` | the `--edit` plan for init, apply, healthcheck | `test_init_edit.sh` (54), `test_healthcheck_edit.sh` (42), `test_pull_edit.sh` (41) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/status.zsh` | `dotfiles status` | `test_status_cards.sh` (68) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/status/edit.zsh` | `status --edit` | `test_status_edit.sh` (66) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/steps.zsh` | `dotfiles steps` | `test_cli.sh` (95), `test_steps_edit.sh` (88) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/steps/edit.zsh` | `steps edit` | `test_steps_edit.sh` (88) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/switch.zsh` | `dotfiles switch`: lock the shared input, then nix-darwin | `test_cmd_switch.sh` (27) | owns the switch itself; placed (dotfiles-cli) | covered for our part (the lock and the refusals); the switch is Nix |
| `.config/dotfiles/cmd/test.zsh` | `dotfiles test` | `test_test_edit.sh` (70), `test_step_test_suites.sh` (21) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/verify.zsh` | the weekly verify | `test_verify_report.sh` (35), `test_verify_error.sh` (25), `test_verify_dedup.sh` (42), `test_verify_lock.sh` (16), `test_verify_show.sh` (37), `test_verify_edit.sh` (45) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/cmd/verify/report.zsh` | the Desktop report | `test_report_render.sh` (32), `test_verify_edit.sh` (45) | placed (dotfiles-cli) | covered |

## The `dotfiles` harness: `steps` and `jobs`

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/dotfiles/steps/alttab.zsh` | AltTab Free build installed | `test_alttab_step.sh` (43) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/brew.zsh` | Homebrew is installed | `test_check_brew_off_path.sh` (7), `test_runner.sh` (20) | owns (nix-darwin's homebrew module); placed (dotfiles-cli) | covered for the check; installs are Nix |
| `.config/dotfiles/steps/chrome_exoskeleton.zsh` | the extension built and loaded | `test_chrome_exoskeleton_step.sh` (49) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/claude.zsh` | Claude Code installed | `test_step_misc.sh` (119) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/claude_notifications.zsh` | Claude Code hooks wired | `test_step_misc.sh` (119) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/claude_skills.zsh` | every tier-held skill linked | `test_step_claude_skills.sh` (29) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/dotfiles_docs.zsh` | every step and verb documented | `test_step_dotfiles_docs.sh` (37) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/dotfiles_jobs.zsh` | the jobs launchd agent loaded | `test_step_misc.sh` (119), `test_jobs_edit.sh` (61) | owns (the jobs agent); placed (dotfiles-cli) | covered for the check; the agent is Nix |
| `.config/dotfiles/steps/dotfiles_repo.zsh` | the shared repo cloned, tracking, hooks | `test_step_dotfiles_repo.sh` (79) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/home_strays.zsh` | no stray shell files in `$HOME` | `test_step_misc.sh` (119) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/karabiner.zsh` | Karabiner's healthcheck passes | `test_report_render.sh` (32), `test_pull_changes.sh` (43) for its watches only | owns (karabiner.nix places the config); placed (dotfiles-cli) | no test needed beyond the watches: a pass-through of Karabiner's own check |
| `.config/dotfiles/steps/local_dotfiles_repo.zsh` | the local bare repo, allowlist, hooks | `test_step_local_dotfiles_repo.sh` (27) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/machine_name.zsh` | the machine name is set | `test_machine_name.sh` (22) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/neovim.zsh` | nvim from Nix starts headless cleanly | `test_step_misc.sh` (119) | owns the binary; placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/nix_port.zsh` | the machine is on the Nix port (340 lines) | `test_step_misc.sh` (119) | owns; placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/plugged.zsh` | plugged's hooks wired, Nix's plugged on PATH | `test_pull_changes.sh` (43), `test_push_summary.sh` (49) name it only | placed (dotfiles-cli) | needs a suite: its check has no case of its own (S) |
| `.config/dotfiles/steps/raycast_sync.zsh` | Raycast in parity with the dotfiles | `test_raycast_local_ok.sh` (13), `test_raycast_undocumented.sh` (20) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/ssh_key.zsh` | the GitHub key in the agent | `test_step_ssh_key.sh` (33) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/terminal_config.zsh` | Terminal.app Option-as-Meta | `test_step_misc.sh` (119) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/terminal_nerdfont.zsh` | a Nerd Font installed and used | `test_step_misc.sh` (119), `test_check_all_ok.sh` (8) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/test_suites.zsh` | every suite says what it tests | `test_step_test_suites.sh` (21) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/tmux_server.zsh` | the tmux server runs PATH's tmux | `test_step_tmux_server.sh` (17) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/steps/xcode.zsh` | full Xcode selected and licensed | `test_xcode_step.sh` (10) | placed (dotfiles-cli) | covered |
| `.config/dotfiles/jobs/dotfiles-verify` | weekly `dotfiles verify` | the verify suites above | no | no test needed: an `exec` with env |
| `.config/dotfiles/jobs/git-health` | hourly `git-health --all` | none | no | no test needed: an `exec`; the work is `git-health`'s |

## Skill `bin/` scripts

Paths are under `.config/claude/skills/`.

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/claude/skills/ari-bead-driven-development/bin/bead_autolink.py` | MessageDisplay hook: bare bead id to link | `bead_autolink.test.zsh` (11) | no | covered |
| `.config/claude/skills/ari-bead-driven-development/bin/bead_autolink.zsh` | its entrypoint | `bead_autolink.test.zsh` (11) | no | covered |
| `.config/claude/skills/ari-bead-driven-development/bin/bead_link.zsh` | one link per bead | `bead_link.test.zsh` (16) | no | covered |
| `.config/claude/skills/ari-diagram-mermaid/bin/bake` | gate, contrast-check, render and link a diagram (395 lines) | none | no | needs a suite: the directive and contrast gates are pure |
| `.config/claude/skills/ari-diagram-mermaid/bin/init.zsh` | session temp folder | none | no | no test needed: mkdir and print |
| `.config/claude/skills/ari-diagram-onlinegantt/bin/validate` | validate a `.gantt` file against the schema | none | no | needs a suite: pure, fixtures in hand |
| `.config/claude/skills/ari-diagram-onlinegantt/bin/diff` | structural diff of two `.gantt` files | none | no | needs a suite: pure |
| `.config/claude/skills/ari-dotfiles-skill-registry/bin/link` | link tier-held skills into `~/.claude/skills` | `registry.test.zsh` (15) | no | covered |
| `.config/claude/skills/ari-dotfiles-skill-registry/bin/status` | where every skill stands | `registry.test.zsh` (15) | no | covered |
| `.config/claude/skills/ari-dotfiles-skill-registry/bin/adopt` | move a skill into a tier and link it back | none | no | needs a suite: it moves directories |
| `.config/claude/skills/ari-driving-remote/bin/run.zsh` | type one command into a pane, here or over ssh (1343 lines) | `run-help` (19), `run-large-capture` (7), `run-put` (67), `run-refusal-kind` (123), `run-typed-text` (57) | no | covered |
| `.config/claude/skills/ari-driving-tmux/bin/ari-driving` | mark a pane on, off, status | `ari-driving.test.zsh` (65) | no | covered |
| `.config/claude/skills/ari-driving-tmux/bin/focus.zsh` | focus a pane by id | `copy.test.zsh` (38), `link.test.zsh` (88) | no | covered |
| `.config/claude/skills/ari-driving-tmux/bin/handoff.zsh` | render a handoff block | `link.test.zsh` (88) | no | covered |
| `.config/claude/skills/ari-driving-tmux/bin/link.zsh` | click-to-focus or click-to-type link | `link.test.zsh` (88), `copy.test.zsh` (38) | no | covered |
| `.config/claude/skills/ari-driving-tmux/bin/pretooluse_bash_pbcopy_guard.sh` | refuse a Bash command that writes the clipboard | `copy.test.zsh` (38) | no | covered |
| `.config/claude/skills/ari-gsw-calendar-add/bin/cal-add.zsh` | add an event through concert-mcp | none | no | no test needed: a wrapper; concert-mcp holds the logic |
| `.config/claude/skills/ari-gsw-calendar-add/bin/cal-del.zsh` | delete an event through concert-mcp | none | no | no test needed: a wrapper |
| `.config/claude/skills/ari-gsw-doc-to-md/bin/doc_to_md.py` | Google Doc JSON to markdown (521 lines) | none | no | needs a suite: a deterministic converter; golden files from saved Doc JSON |
| `.config/claude/skills/ari-gsw-doc-to-md/bin/doc-to-md.zsh` | its entrypoint | none | no | no test needed: prereqs and a timeout |
| `.config/claude/skills/ari-gsw-read/bin/expand_links.py` | classify a source and expand it to doc links | none | no | needs a suite: URL classification is pure |
| `.config/claude/skills/ari-gsw-read/bin/expand.zsh` | its entrypoint | none | no | no test needed: prereqs and a timeout |
| `.config/claude/skills/ari-hemingway--lib/bin/verify-claims-at-sha` | check `path:line` claims at a SHA | none | no | needs a suite: a temp repo makes it cheap |
| `.config/claude/skills/ari-hemingway--lib/bin/git-permalink-info` | build a permalink from a checkout | none | no | needs a suite: remote-URL parsing is pure |
| `.config/claude/skills/ari-hemingway--lib/bin/detect-transfer` | detect how to get file content to Ari's machine | none | no | needs a suite: small, fold into the hemingway--lib suite |
| `.config/claude/skills/ari-hemingway--lib/bin/make-investigation-folder` | make an investigation folder | none | no | needs a suite: fold into the hemingway--lib suite |
| `.config/claude/skills/ari-hemingway--share-explainer/bin/share.zsh` | card, preview, gates, commit, push, watch Pages (656 lines) | none | no | needs a suite for its dry run (the default): it commits and pushes when run with `--execute` |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_publish.zsh` | create or update a Doc | `gdoc_dry_run.test.zsh` (92) | no | covered |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_finish.zsh` | the fix-up batch | `gdoc_dry_run.test.zsh` (92) | no | covered |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_asides.zsh` | asides as tabs | `gdoc_asides.test.zsh` (65), `gdoc_dry_run.test.zsh` (92) | no | covered |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_asides.py` | its Python | `gdoc_asides.test.zsh` (65) | no | covered |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_image_checks.py` | image findings | none | no | needs a suite: pure over a Doc read |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_image_checks.zsh` | its entrypoint | none | no | no test needed: PYTHONPATH and exec |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_widths.py` | size table columns (338 lines) | none | no | needs a suite: pure layout math |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_widths.zsh` | its entrypoint | none | no | no test needed: PYTHONPATH and exec |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_heights.py` | table heights from a PDF export | none | no | needs a suite: pure over a fixture PDF's text |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_table_heights.zsh` | its entrypoint | none | no | no test needed: PYTHONPATH and exec |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_render_pages.swift` | PDF pages to PNG | none | no | no test needed: one PDFKit call |
| `.config/claude/skills/ari-hemingway--share-gdoc/bin/gdoc_render_pages.zsh` | its entrypoint | none | no | no test needed: a wrapper |
| `.config/claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh` | bookmarks in a published Doc | `gdoc_bookmarks_dry_run.test.zsh` (66) | no | covered |
| `.config/claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.py` | its Python | `gdoc_bookmarks_dry_run.test.zsh` (66) | no | covered |
| `.config/claude/skills/ari-hemingway--structure-bookmark/bin/gas` | the Apps Script half | `gdoc_bookmarks_dry_run.test.zsh` (66) for the push only | no | no test needed: runs only inside Google's runtime |
| `.config/claude/skills/ari-hemingway--structure-ciechanowski/bin` | figure builders, assembler, screenshot (10 files) | none | no | needs a suite for `assemble.py` and `figure_manifest.py` (pure); the `*_fig.py` generators and `shot.zsh` are read by eye |
| `.config/claude/skills/ari-hemingway--structure-repo-quickstart/bin/check_readme.zsh` | the README gate | none | no | needs a suite: a gate should have pass and fail fixtures |
| `.config/claude/skills/ari-hemingway--structure-scaffold/bin/check_definitions_order.zsh` | definitions-order gate | `check_mention_matchers.zsh` (24 cases) for its matcher | no | covered for the matcher; the ordering rule: needs cases (fold in) |
| `.config/claude/skills/ari-hemingway--structure-scaffold/bin/cluster_definitions.py` | cluster a definitions table (696 lines) | `check_mention_matchers.zsh` (24 cases) for its matcher | no | needs a suite for the clustering itself |
| `.config/claude/skills/ari-hemingway--structure-scaffold/bin/cluster_definitions.zsh` | its entrypoint | none | no | no test needed: PYTHONPATH and exec |
| `.config/claude/skills/ari-hemingway--structure-scaffold/bin/drive_subfolder.zsh` | pick the Drive folder | none | no | no test needed: a gws lookup |
| `.config/claude/skills/ari-hemingway--structure-working-doc/bin/asks.zsh` | the asks table of a working doc | none | no | needs a suite: table parsing is pure |
| `.config/claude/skills/ari-operator-mode/bin/frontier.zsh` | operator mode's state reader (1190 lines) | `frontier.test.zsh` (491) | no | covered |
| `.config/claude/skills/ari-operator-mode/bin/brief.zsh` | the deterministic reply parts | `frontier.test.zsh` (491) | no | covered |
| `.config/claude/skills/ari-operator-mode/bin/mode.zsh` | operator mode on/off | `frontier.test.zsh` (491) | no | covered |
| `.config/claude/skills/ari-operator-mode/bin/pending.zsh` | the typed-but-unentered row | `frontier.test.zsh` (491) | no | covered |
| `.config/claude/skills/ari-operator-mode/bin/away.zsh` | the announced absence | `frontier.test.zsh` (491) | no | covered |
| `.config/claude/skills/ari-parallel-play/bin/watch-merge.zsh` | one PR's life to merge | `watch-merge.test.zsh` (12) | no | covered |
| `.config/claude/skills/ari-parallel-play/bin/worktree.zsh` | open and close a lane's worktree | none | no | needs a suite: it adds and removes worktrees |
| `.config/claude/skills/ari-parallel-play/bin/lane-overlap.zsh` | which lanes may run at once | none | no | needs a suite: pure over diffs |
| `.config/claude/skills/ari-parallel-play/bin/render-lane-prompt.zsh` | render a lane prompt | none | no | needs a suite: a golden prompt |
| `.config/claude/skills/ari-poem-limerick/bin/check` | verify a limerick grid | none | no | needs a suite: a gate, pure |
| `.config/claude/skills/ari-poem-limerick/bin/init` | make the grid file | none | no | no test needed: mkdir and print |
| `.config/claude/skills/ari-pr-reviewer/bin/gather-pending.zsh` | fetch a pending review into state | none | no | needs a suite against a fake `gh` |
| `.config/claude/skills/ari-pr-reviewer/bin/post-pending-reply.zsh` | reply inside a pending review | none | no | needs a suite against a fake `gh`: it writes to GitHub |
| `.config/claude/skills/ari-skill-pythonscripts/bin/example.py` | the conventions example | none | no | no test needed: an example |
| `.config/claude/skills/ari-skill-pythonscripts/bin/example.zsh` | its entrypoint | none | no | no test needed: an example |
| `.config/claude/skills/ari-skill-review/bin/setup.zsh` | review investigation folder | none | no | no test needed: mkdir and print |
| `.config/claude/skills/ari-skill-shellscripts/bin/example` | the conventions example | `conventions.test.zsh` (42/4) | no | covered |
| `.config/claude/skills/ari-skill-shellscripts/bin/await-lessons` | run the await lessons interactively | none (`await.test.zsh` (139) covers the lib) | no | no test needed: a tutorial |
| `.config/claude/skills/ari-skill-update/bin/init.zsh` | skill-update session setup | `claim.test.zsh` (72) | no | covered |
| `.config/claude/skills/ari-skill-update/bin/record_blobs.zsh` | record a proposal's blobs | `claim.test.zsh` (72) | no | covered for the claim; the hashing: needs cases (fold in) |
| `.config/claude/skills/ari-skill-update/bin/commit_blobs.zsh` | commit exactly the recorded blobs | `claim.test.zsh` (72) | no | covered for the claim; a real commit is not (the suite says so) |
| `.config/claude/skills/ari-spotify/bin/spotify.zsh` | wrapper over concert-mcp | none | no | no test needed: a wrapper |

## Skill `lib/` files

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/claude/skills/ari-diagram-mermaid/lib/contrast.awk` | `bake`'s contrast gate over a `.mmd` | none | no | needs a suite: pure; fold into the `bake` suite above |
| `.config/claude/skills/ari-dotfiles-skill-registry/lib/registry.zsh` | constants and skill classification for the registry scripts (414 lines) | `registry.test.zsh` (15) | no | covered |
| `.config/claude/skills/ari-driving-tmux/lib/wrap.zsh` | lay out a one-line command for a human to read (583 lines) | `link.test.zsh` (88), `copy.test.zsh` (38) | no | covered |
| `.config/claude/skills/ari-gsw-calendar-add/lib/concert_mcp.zsh` | find uv, check the concert-mcp checkout, run one subcommand | none | no | no test needed: a launcher |
| `.config/claude/skills/ari-hemingway--lib/lib/drive.zsh` | Drive helpers: folder id from a URL, a capped gws call, token scopes, folder lookup | loaded by `gdoc_publish.zsh` and `gdoc_finish.zsh`, which `gdoc_dry_run.test.zsh` (92) runs | no | covered through its callers; `drive::folder_id_from` is pure and has no case of its own |
| `.config/claude/skills/ari-hemingway--lib/lib/gdoc_api.py` | Docs API helpers: gws calls and walks over a `documents.get` reply | loaded by `gdoc_asides.py` and `gdoc_bookmarks.py`, which `gdoc_asides.test.zsh` (65) and `gdoc_bookmarks_dry_run.test.zsh` (66) run | no | covered through its callers |
| `.config/claude/skills/ari-hemingway--lib/lib/run_with_timeout.zsh` | pointer to the shellscripts copy (7 lines) | none | no | no test needed: a pointer |
| `.config/claude/skills/ari-hemingway--structure-scaffold/lib/check_definitions_order.jq` | the definitions-table check | `check_mention_matchers.zsh` (24 cases) reads it | no | covered for the matcher, as `check_definitions_order.zsh` above |
| `.config/claude/skills/ari-hemingway--structure-working-doc/lib/asks.jq` | jq for a working doc's asks table | none | no | needs a suite: pure; fold into the `asks.zsh` suite above |
| `.config/claude/skills/ari-operator-mode/lib/marker.zsh` | the per-session marker file | `frontier.test.zsh` (491) runs `bin/mode.zsh`, which sources it | no | covered |
| `.config/claude/skills/ari-skill-pythonscripts/lib/skill_log.py` | log lines for the skills' Python | none | no | no test needed: log and die wrappers (34 lines) |
| `.config/claude/skills/ari-skill-pythonscripts/lib/skill_subprocess.py` | `run_capture`: a subprocess with a timeout, dying with a record on failure | none | no | no test needed: 31 lines over `subprocess` |
| `.config/claude/skills/ari-skill-shellscripts/lib/await.zsh` | one status line for a wait (617 lines) | `await.test.zsh` (139) | placed (ari-zshlib) | covered |
| `.config/claude/skills/ari-skill-shellscripts/lib/dry_run.zsh` | the dry-run gate for mutating skill scripts | `conventions.test.zsh` (42/4) checks its dry-run default | placed (ari-zshlib) | covered |
| `.config/claude/skills/ari-skill-shellscripts/lib/investigation_folder.zsh` | the investigation-folder helper | `investigation_folder.test.zsh` (10) | placed (ari-zshlib) | covered |
| `.config/claude/skills/ari-skill-shellscripts/lib/logging.zsh` | a shim over the dotfiles' log library (20 lines) | none of its own | placed (ari-zshlib) | no test needed: a shim; the format is `log.zsh`'s |
| `.config/claude/skills/ari-skill-shellscripts/lib/run_with_timeout.zsh` | run a command under a wall-clock cap | none | placed (ari-zshlib) | needs a suite: its 124-on-timeout exit code is a contract callers branch on |
| `.config/claude/skills/ari-skill-shellscripts/lib/tail.zsh` | a running command's last lines under a spinner | `tail.test.zsh` (17) | no | covered |
| `.config/claude/skills/ari-skill-update/lib/blobs.zsh` | a proposal's blobs: where a skill is versioned, what its tree holds (348 lines) | `claim.test.zsh` (72) sources it | no | covered for what the claim cases reach; the hashing: needs cases, as `record_blobs.zsh` above |
| `.config/claude/skills/ari-skill-update/lib/claim.zsh` | one driver per skill across sessions | `claim.test.zsh` (72) | no | covered |

## Claude Code hooks, git, Karabiner, AltTab, new-machine and bash scripts

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/claude/bin/initialize.sh` | install terminal-notifier; write the Notification, Stop and PreToolUse hooks into `~/.claude/settings.json` | `test_step_misc.sh` (119) runs a fixture stand-in, not this file | no | needs a suite: it edits `~/.claude/settings.json`; a temp HOME makes it cheap |
| `.config/claude/bin/notification-fire.sh` | Notification hook to a macOS notification (24 lines) | none; `test_step_misc.sh` (119) checks only that it is wired | no | no test needed: the work is `notification-lib.sh`'s |
| `.config/claude/bin/stop-fire.sh` | the same notification at the end of a turn (20 lines) | none; `test_step_misc.sh` (119) checks only that it is wired | no | no test needed: the work is `notification-lib.sh`'s |
| `.config/claude/bin/notification-click-handler.sh` | on a click: activate Terminal, jump tmux to the pane | none | no | no test needed: UI |
| `.config/claude/bin/notification-click-simulator.sh` | click the latest notification by hand | none | no | no test needed: a manual test tool |
| `.config/claude/bin/notification-fire-simulator.sh` | fire a notification with a chosen target | none | no | no test needed: a manual test tool |
| `.config/claude/bin/notification-style.sh` | explain terminal-notifier's alert style here | none | no | no test needed: a diagnostic |
| `.config/claude/bin/pretooluse-headless-chrome-guard.sh` | PreToolUse hook: refuse a headless launch of Chrome.app | none; `test_step_misc.sh` (119) checks only that it is wired | no | needs a suite: a guard, JSON in and an exit code out (S) |
| `.config/claude/bin/pretooluse-pbcopy-guard.sh` | link to `ari-driving-tmux/bin/pretooluse_bash_pbcopy_guard.sh` | `copy.test.zsh` (38) | no | covered: see that row |
| `.config/claude/bin/quickchat.sh` | print a random quickchat line | none | no | no test needed: one random line |
| `.config/claude/lib/notification-lib.sh` | the notification scripts' implementation: resolve the message, record and jump to the tmux target, post, dismiss (191 lines) | none | no | needs a suite for the message and pane resolution against a fake terminal-notifier and tmux |
| `.config/claude/lib/tmux-pane.sh` | tmux pane helpers: the opt-in gate, refusal kinds, the pane lock (254 lines) | `tmux-pane-lib.test.zsh` (22) on `$XDG_CONFIG_HOME`'s copy, `run-refusal-kind` (123), `run-typed-text` (57) | placed (ari-zshlib) | covered |
| `.config/git/bin/git-dotfiles` | the `git df` alias: pick the clone or the bare repo, map `$HOME` paths | `test_git_dotfiles.sh` (7) | placed (git-kit) | covered |
| `.config/git/dotfiles-hooks/pre-commit` | shared tier: `karabiner.json` sorted, a staged `flake.lock` locks each dev repo at a commit on its `origin/main` | `test_push_summary.sh` (49) runs it on one allowed bump commit | no | needs cases for its two refusals (S) |
| `.config/git/local-dotfiles-hooks/pre-commit` | local tier: refuse secret paths and credential-shaped content | none | no | needs a suite: it is the secret gate |
| `.config/git/local-dotfiles-hooks/pre-push` | local tier: run the exoskeleton's suite when a push touches its private plugins | none | no | no test needed: a pass-through to `exo`'s checks |
| `.config/git/template/hooks/pre-commit` | every new repo: prompt on files with trailing whitespace | none | no | no test needed: an interactive prompt |
| `.config/git/template/hooks/prepare-commit-msg` | every new repo: branch prefix and a history summary in the message | none | no | no test needed: a message template read by eye |
| `.config/karabiner/bin/bake` | compile karabiner.ts into `karabiner.json` and `raycast_bindings.json`, sort, stage | none | no | no test needed: a wrapper over the compiler; its staged diff is reviewed before a commit |
| `.config/karabiner/bin/healthcheck` | Karabiner's processes, config, device grab, daemon link, log errors; read-only (378 lines) | `test_step_progress.sh` (54) renders its path only | no | no test needed: it reads live daemon state |
| `.config/karabiner/karabiner.ts/src/scripts/bin/notif-click` | Hyper+N: jump to a waiting notification | none | no | no test needed: UI |
| `.config/karabiner/karabiner.ts/src/scripts/bin/oneshot-popup` | Hyper+O: the tmux-oneshot picker as a popup | none | no | no test needed: UI |
| `.config/karabiner/karabiner.ts/src/scripts/bin/set-fda-perms` | stage a Full Disk Access grant: copy the path, reveal it, open the settings pane | none | no | no test needed: UI; the grant itself is by hand |
| `.config/karabiner/karabiner.ts/src/scripts/bin/karabiner-logs` | pick a Karabiner log with fzf | none | no | no test needed: an fzf picker |
| `.config/karabiner/karabiner.ts/src/scripts/bin/karabiner-recompile` | re-run `bake` | none | no | no test needed: one call |
| `.config/karabiner/karabiner.ts/src/scripts/bin/karabiner-edit-index` | open `index.ts` in a tmux window | none | no | no test needed: one call |
| `.config/karabiner/karabiner.ts/src/scripts/bin/karabiner-hello-world` | echo in a tmux window | none | no | no test needed: an example |
| `.config/karabiner/karabiner.ts/src/scripts/bin/script-example` | print the environment a key script gets | none | no | no test needed: an example |
| `.config/alttab/bin/alttab-free-cert` | make and trust a local code-signing identity (375 lines) | none | no | no test needed: it works on the login keychain and its trust settings (`security`) |
| `.config/new-machine/bin/bootstrap.sh` | fresh Mac to the dotfiles baseline | `test_bootstrap.sh` (37) | placed (dotfiles-cli) | covered |
| `.config/bash/plugins/arg.bash` | check that variables are set (90 lines) | none | placed (ari-zshlib) | no test needed: presence checks |
| `.config/bash/plugins/log.bash` | a minimal bash log library and `run_cmd` (76 lines) | none | placed (ari-zshlib) | no test needed: echo wrappers |

`.config/alttab/bin/alttab-free-build` and `karabiner.ts/src/scripts/bin/karabiner-typing-test` have
their rows under `~/.config/bin`, through the links there.

## nvim Lua

`steps/neovim.zsh` starts nvim headless with the whole config and fails on any load error; that
is the only test of the config files, and it is enough for files that only set options and keys.

| Path | Work | Tests today | Nix? | Verdict |
|---|---|---|---|---|
| `.config/nvim/lua/ari/gitsigns/pr_parsers.lua` | PR number from a commit subject | `pr_parsers_spec.lua` (15/15) | placed (nvim.nix) | covered |
| `.config/nvim/lua/ari/gitsigns/pr_openers.lua` | which opener takes a PR | none | placed (nvim.nix) | needs a suite: fold into `pr_parsers_spec.lua` |
| `.config/nvim/lua/ari/gitsigns/open_relevant_pr.lua` | blame popup, then open the PR | none | placed (nvim.nix) | no test needed: UI over the two modules above |
| `.config/nvim/lua/ari/color/init.lua` | hex parse, grey test, adjust | none | placed (nvim.nix) | needs a suite: pure colour math, runs under plain `lua` |
| `.config/nvim/lua/ari/color/ize.lua` | greyscale and colourize modes | none | placed (nvim.nix) | needs a suite: pure, with `color/init.lua` |
| `.config/nvim/lua/ari/color/theme.lua` | set highlight groups from the colour helpers | none | placed (nvim.nix) | no test needed: applies highlights; the math it calls is in `color/init.lua` |
| `.config/nvim/lua/ari/gitsigns/init.lua` | gitsigns setup and keys | none | placed (nvim.nix) | no test needed: configuration |
| `.config/nvim/lua/ari/operator/tf.lua` | Terraform box-comment operator: wrap and box a paragraph | none | placed (nvim.nix) | needs a suite: `wrap_paragraph` is pure |
| `.config/nvim/lua/ari/claude_slash.lua` | probe Claude Code for slash commands, cache per binary | none | placed (nvim.nix) | needs a suite for the cache key and parse; the probe needs the binary |
| `.config/nvim/after/plugin/modes/search.lua` | lgrep and the search register | none (it carries a TODO for tests) | placed (nvim.nix) | needs a suite: the escaping it plans is pure |
| `.config/nvim/lua/ari/yaml_utils.lua` | YAML key path at the cursor | none | placed (nvim.nix) | needs a suite under `nvim -l` with a buffer: treesitter-dependent |
| `.config/nvim/lua/ari/jq-playground/init.lua` | jq playground buffers | none | placed (nvim.nix) | no test needed: UI |
| `.config/nvim/lua/ari/snacks/init.lua` | picker definitions | none | placed (nvim.nix) | no test needed: configuration of a plugin |
| `.config/nvim/lua/ari/hydra` | hydra heads and git preview | none | placed (nvim.nix) | no test needed: key bindings |
| `.config/nvim/lua/ari/operator/init.lua` | make a custom operator | none | placed (nvim.nix) | no test needed: glue to `operatorfunc` |
| `.config/nvim/lua/ari/cmp` | completion source | none | placed (nvim.nix) | no test needed: plugin glue |
| `.config/nvim/lua/ari/luasnip` | snippets | none | placed (nvim.nix) | no test needed: data |
| `.config/nvim/lua/ari/dap/delve.lua` | delve config | none | placed (nvim.nix) | no test needed: configuration |
| `.config/nvim/lua/ari/keymap.lua` | keymap helper | none | placed (nvim.nix) | no test needed: a wrapper over `vim.keymap.set` |
| `.config/nvim/lua/ari/options.lua` | options | none | placed (nvim.nix) | no test needed: configuration |
| `.config/nvim/lua/ari/lsp.lua` | enable every `lsp/` config | none | placed (nvim.nix) | no test needed: configuration |
| `.config/nvim/lua/ari/mason.lua` | install a Mason package when missing | none | placed (nvim.nix) | no test needed: one call |
| `.config/nvim/lua/ari/lazydev.lua` | lazydev setup | none | placed (nvim.nix) | no test needed: configuration |
| `.config/nvim/after/plugin/modes/quickfix.lua` | quickfix navigation | none | placed (nvim.nix) | no test needed: key bindings |
| `.config/nvim/after/plugin/whitespace.lua` | trailing-whitespace search | none | placed (nvim.nix) | no test needed: key bindings |
| `.config/nvim/after/plugin/developer.lua` | edit nvim files | none | placed (nvim.nix) | no test needed: commands that open files |
| `.config/nvim/after/plugin/inspection/scratch.lua` | scratch buffers | none | placed (nvim.nix) | no test needed: UI |
| `.config/nvim/after/plugin` (the rest) | buffers, doublemap, lsp, modes, textwidth | none | no | no test needed: key bindings and options |
| `.config/nvim/plugin` | plugin setup | none | owns (nvim.nix places the config and the pinned plugins) | no test needed: declarative specs |
| `.config/nvim/after/ftplugin` | per-filetype options | none | placed (nvim.nix) | no test needed: options |
| `.config/nvim/after/ftdetect` | filetype detection | none | placed (nvim.nix) | no test needed: patterns |
| `.config/nvim/lsp` | LSP server configs | none | placed (nvim.nix) | no test needed: data |
| `.config/nvim/init.lua` | load the config | none | placed (nvim.nix) | no test needed: three lines |

## Suites most worth writing next

Ranked by what an untested bug would cost, then by how cheap the suite is. S is an afternoon or
less; M is a day or so.

1. **git-kit** (`git-health`, `git-delete-if-merged-*`, `git-dedupe-case-refs`, `git-ready`) — M.
   They delete branches and refs and rewrite object stores, hourly for `git-health`. One hermetic
   suite over temp repos, in `tests/` beside the harness.
2. **`history.zsh` `histrm`** — S. It deletes lines from the history file.
3. **`notes`** — S. A journal written daily; the install check proves only that it loads.
4. **ari-parallel-play `worktree.zsh` and `lane-overlap.zsh`** — M. They add and remove worktrees
   and decide which lanes run together.
5. **skill-registry `adopt`** — S. It moves skill directories between tiers; extend
   `registry.test.zsh`.
6. **`swift_cache.zsh`** (and with it `swift-cache`, `swift-pkg`, `swift-run`) — M. The cache key
   and trim decide what is rebuilt and what is deleted.
7. **ari-gsw-doc-to-md `doc_to_md.py`** — M. A deterministic converter; golden files from saved
   Doc JSON.
8. **`log.zsh`** — S. Its line format is parsed by bins and tests.
9. **ari-hemingway--lib bins** (`verify-claims-at-sha`, `git-permalink-info`) — S.
10. **pure helpers: `colors.zsh`, `utc.zsh`, `str.zsh`, `.zshrc`'s `prepend_to_path`, and nvim's
    `color/` and `operator/tf.lua`** — S each. Cheap, and they turn the plugin count down fast.

Before any of these: find why `raycast.test.zsh` fails (see **Suites that failed in this run**).
