---
name: ari-skill-shellscripts
description: Conventions for writing zsh scripts in Claude skills — logging, prereqs, arg parsing, env vars, structure, and mutations that are a dry run unless --execute.
user_invocable: false
---

# Skill Shell Scripts

Conventions for writing zsh scripts in Claude skills. See `bin/example` for a runnable reference implementation that demonstrates every pattern.

## Choosing a conventions skill

This skill covers zsh. For Python, use `/ari-skill-pythonscripts` (its mirror). For any other language (node, ruby, go, …), use that language's conventions skill; if none exists yet, build one first — mirror these — then write the script.

## Rules

### Shell and safety

- **Use zsh, not bash.** macOS ships bash 3.2; zsh is the same modern shell on every machine.
- **`set -euo pipefail` at the top.** Every script. A command substitution's subshell inherits errexit, so a pipeline that fails inside `$(…)` ends the script with no log.
- **Under pipefail, `grep` with no match fails the pipeline, and a consumer that stops early kills its producer.** A filter that may legitimately match nothing is `awk`, or `grep … || true` as the line's last command (mid-pipe it must be wrapped, `{ grep … || true; } |`: unwrapped, a match skips the next stage). A consumer that may stop before the producer is done (`head`, `grep -m1`, `sed … q`, `awk … exit`) kills a long producer with SIGPIPE once the pipe buffer is full, exit 141 and no log: latch and read to EOF, or `setopt localoptions nopipefail` for that one pipeline.
  ```zsh
  # BAD — an empty files array exits 1; a match 400 KB before the end exits 141
  lanes="$(printf '%s\n' "${files[@]}" | grep . | jq -R . | jq -s .)"
  pages="$(strings big.pdf | awk '/Pages/ { print; exit }')"
  # GOOD
  lanes="$(printf '%s\n' "${files[@]}" | awk 'NF' | jq -R . | jq -s .)"
  count="$(printf '%s\n' "${files[@]}" | grep -c . || true)"
  pages="$(strings big.pdf | awk '!found && /Pages/ { print; found=1 }')"
  ```
- **Arithmetic that evaluates to 0 ends a `set -e` script.** `(( n++ ))` is false when `n` is 0, and so is `(( flag ))` on a zero. Write `(( n += 1 ))`, or assign: `n=$(( n + 1 ))`.
- **Python only through its zsh entrypoint.** When a script needs a Python script, call `zsh …/<name>.zsh`, never `python3 …/<name>.py`. The entrypoint owns `PYTHONPATH`; the Python never edits `sys.path`. Shape and rules: `/ari-skill-pythonscripts`.
- **Invoke with the shell name via the `$HOME` form.** `zsh $HOME/.claude/skills/<skill>/bin/<script>`. The matcher expands `$HOME` (but NOT `~`) in the invocation, so the `$HOME` form matches the user's absolute allowlist rule (`Bash(zsh /Users/<you>/.claude/skills/*)`) and runs without a permission prompt; a `~` invocation does NOT match an absolute rule. Allowlist rules MUST be absolute — never a `~`- or `$HOME`-form pattern (a `$HOME` pattern is never expanded, so it matches nothing). NEVER `cd` then run a relative `bin/x` path, and NEVER pipe the output (no `| head`, no `2>&1 | …` in the documented form): a `cd` prefix, relative path, or pipe breaks the match. Include a shebang (`#!/usr/bin/env zsh`) for documentation, but NEVER rely on it for execution.

### Naming

- **`readonly` for constants, never for `DRY_RUN`.** `ALL_CAPS` for globals, `snake_case` for locals. `DRY_RUN` belongs to `lib/dry_run.zsh` (§ Dry run): a script never declares it. An environment prefix `NAME=value cmd` is refused as `read-only variable` when `NAME` is a constant, so a prefix takes a name of its own (`WANT_COMMENT="${COMMENT}" cmd`, never `COMMENT="${COMMENT}" cmd`).
- **`snake_case` everywhere.** Functions, variables, file names.
- **Never name a variable after a zsh special parameter.** `local path=` rebinds `PATH` (`path` is the array tied to it) and `local status=` shadows the last exit code; the failure surfaces far from the assignment as `command not found` or a wrong `$?`. `USERNAME` is the login name and an assignment to it is silently ignored. Off limits: `path`, `status`, `cdpath`, `fpath`, `manpath`, `argv`, `pipestatus`, `reply`, `match`, `MATCH`, `options`, `functions`, `signals`, `prompt`, `watch`, `histchars`, `RANDOM`, `SECONDS`, `LINENO`, `PWD`, `OLDPWD`, `USERNAME`, `TTY`, `HOST`. Use `file`, `dir`, `exit_code`, `result`, `person`, `have_tty` instead.
- **Always `"${x}"`, and never quotes inside an associative-array subscript.** Never bare `$x`. Never unquoted `${x}`. Every variable expansion gets braces and double quotes, except the key of an associative array: a subscript does not word-split, and zsh keeps quotes there as part of the key, so `m["${id}"]` and `m[$id]` are two different keys and the mismatched read dies `parameter not set` under `set -u`. Write `m[$id]`; `${m[${id}]}` is fine too.
  ```zsh
  # BAD — the key is "k" with its quotes; a read with other quoting finds nothing
  files_of["${id}"]="${list}"; print -- "${files_of["${id}"]}"
  # GOOD
  files_of[$id]="${list}"; print -- "${files_of[$id]}"
  ```
- **A conditional flag and its value travel in an array.** `${body:+-d "${body}"}` is ONE word in zsh (`-d <body>` as a single argument), unlike bash. Write `local -a data; [[ -n "${body}" ]] && data=(-d "${body}"); curl "${data[@]}" …`; an empty declared array is fine under `set -u`.
- **Function comments use `#######` headers.** Document Globals, Arguments, Returns.

### Control flow

- **Hoist 2-branch `if/else` into a named function with early returns.** Inline `if cond; then A; else B; fi` blocks hide intent. Lift them into a function whose name describes the choice, handle the special case with an early `return`, and let the default fall through. Each branch gets its own `if` block (no `&& {...}` shortcuts) and a log line so the chosen path is visible in stderr. Applies in `main`, not just helper functions.
  ```zsh
  # BAD — branches hidden inline, no observability
  if [[ "${edited}" == "true" ]]; then
      footer="${EDITED_FOOTER}"
  else
      footer="${AI_FOOTER}"
  fi

  # GOOD — named function, early return per branch, one log per path
  choose_footer() {
      local edited="${1}"
      if [[ "${edited}" == "true" ]]; then
          log::info "Using edited footer | edited='${edited}'"
          echo "${EDITED_FOOTER}"
          return
      fi
      log::info "Using AI footer | edited='${edited}'"
      echo "${AI_FOOTER}"
  }
  footer="$(choose_footer "${edited}")"
  ```
  Multi-branch (`if/elif/elif/else`) follows the same shape: each non-default branch becomes an early-return guard with its own log line; the else body is the function's tail.

### Output and errors

- **Stdout for data, stderr for logs.** Structured output (JSON, delimited sections) to stdout. Logging to stderr.
- **Labeled output via heredoc.** Scripts producing multiple values MUST end with `key=value` lines from a `cat <<EOF` heredoc; a list of records goes before it, one JSON object per line between `=== start NAME ===` and `=== end NAME ===`. A mutating script's heredoc includes `dry_run=1|0`. Document the output once, in `help()`'s `Output:` section, never in the header comment.
  ```zsh
  cat <<EOF
  owner_repo=${owner_repo}
  sha=${sha}
  EOF
  ```
- **Error messages name the offending value and what was expected.** When a check fails, the message MUST carry the bad value and the constraint (`| mode='x' valid_modes='a, b'`), not just "invalid". Fix opaque messages at their source, not the call site.
- **`--help` is mandatory.** Every script MUST support `-h`/`--help` via a `help()` heredoc, using log colors for section headers and flags.
- **On an unknown flag, print the error AND call `help`.**
  ```zsh
  help() {
      cat <<EOF
  ${c_green}git-permalink-info${c_rst} — extract owner/repo and SHA for GitHub permalinks

  ${c_bold}Usage:${c_rst}
    zsh $HOME/.claude/skills/<skill>/bin/git-permalink-info [--ref REF]

  ${c_bold}Options:${c_rst}
    --ref REF   Git ref to resolve (default: origin/main)
    -h, --help  Show this help
  EOF
  }
  ```

### Portability

- **Use `awk`, not `sed`.** BSD (macOS) and GNU (Linux) sed differ on ranges, in-place editing, and compound expressions; `awk` is consistent across both. The one exception is in-place file editing (`sed -i`), which has no clean `awk` equivalent — wrap its platform difference (next rule).
- **Wrap platform differences in named functions.** When platform-dependent behavior is unavoidable, write a function whose name describes the transformation (not the tool). Switch on `$OSTYPE` inside it.
  ```zsh
  inplace_replace() {
      if [[ "${OSTYPE}" == darwin* ]]; then
          sed -i '' "s/${1}/${2}/g" "${3}"
      else
          sed -i "s/${1}/${2}/g" "${3}"
      fi
  }
  ```

### Mutations

A *mutation* changes something the script did not create in this run: a file at a path the caller named (under `/tmp` too), a repo's working tree or index, a commit or push, any remote write (`gh pr create`, `gh api -X POST`, `curl -X POST`, `gws … create|update|batchUpdate`, `kubectl apply`), a send, a delete. Not a mutation: reads (`git fetch`, `gh api` GET), `mktemp` scratch, the script's own investigation folder (`mk_investigation_dir`), its own cache. Unsure → it is a mutation.

- **A script that mutates is a dry run unless `--execute` is on its own command line.** Without `--execute` it runs every read and check, logs each mutation it would make, makes none, and exits 0, or non-zero on the same check failures the real run would hit. A script that never mutates takes neither flag.
- **The act flag is `--execute`. NEVER `--apply`, `--yes`, `--confirm`, `--force` or `--no-dry-run`.** Moving a script onto this convention renames its act flag and adds `--execute` to every documented invocation of it, in the same change; a call left without it silently becomes a preview.
- **`--dry-run` is the default said explicitly, and dry run wins.** It overrides `--execute` in either order and exports `DRY_RUN=1`.
- **`DRY_RUN` is `1` (dry run) or `0` (act), never `true`/`false`, and a script reads it only through `is_dry_run`.** An inherited `DRY_RUN` other than empty or `0` forces a dry run, `--execute` or not. An inherited `DRY_RUN=0` never makes a script act: only `--execute` on its own command line does.
- **A dry run runs the whole script.** Only the mutations stand in: NEVER branch on `is_dry_run` to skip the reads and checks the real run makes. `is_dry_run` decides a stand-in (a placeholder value, or a tool's own dry run such as `gws … --dry-run` in place of the write) or a closing line, nothing else.
- **A mutation never widens its scope by default.** A missing target is an error, never "all"; widening takes an explicit flag (`--all`).
- **Call a mutating child script directly and pass it `--execute`.** The exported `DRY_RUN=1` turns it back into a dry run during the parent's dry run, and the child shows its own preview. A child that does not source `lib/dry_run.zsh` (a Python script, an external CLI, a script not yet on this convention) goes through `run_mut` instead.
- **Confirm an act by `dry_run=0` in the output, never by exit 0.** A dry run exits 0 too.
- **A SKILL.md that documents a mutating script shows the dry-run invocation first**, then the `--execute` one, and says whether `--execute` waits for the user's `yes` or runs unattended.
- **Mutating scripts are idempotent.** Guard each mutation with an existence or equality check (`cmp -s`) so a second run changes nothing; the guard runs in a dry run too, so the preview lists only what `--execute` would change.

## File layout

- `bin/` — all scripts (per-skill gatherers, utilities, sync/push tools)
- `lib/` — shared libraries (logging, dry run, helpers, await) sourced by other scripts
- `tests/` — automated checks of the libraries; `lessons/` — ordered interactive walkthroughs for a person

## Logging

**Source the canonical implementation — never re-define the `log::*` block inline.** Every script MUST open with this exact preamble, right after `set -euo pipefail`, with no comment inside it:

```zsh
readonly SCRIPT_DIR="${0:A:h}"
readonly SKILLS_DIR="${HOME}/.claude/skills"
readonly LIB_LOGGING="${SKILLS_DIR}/ari-skill-shellscripts/lib/logging.zsh"
if [[ ! -r "${LIB_LOGGING}" ]]; then
  print -u2 "[ERROR] missing shared logging lib | path='${LIB_LOGGING}'"
  exit 1
fi
source "${LIB_LOGGING}"
```

Shared libs resolve through the symlink farm (`SKILLS_DIR`), never a relative hop from `SCRIPT_DIR`: skills are versioned across dotfiles tiers (`/ari-dotfiles-skill-registry`), so `${SCRIPT_DIR:h:h}` lands in whichever tier root the script happens to live in. `${0:A:h}` is the script's real dir with symlinks resolved, even when sourced; use `SCRIPT_DIR` only for the skill's own `lib/`. A sourced lib uses `return 1` in place of `exit 1`. `bin/example` opens with this exact preamble.

The sourced lib provides, all colorized to stderr:

- `log::info`, `log::err`, etc. — single-line; one `key='value'` record per call.
- `log::INFO`, `log::ERR`, etc. — multiline; dump captured multi-line output (one log line per input line, `|` prefixed).
- `run_cmd` / `run_cmd_cap` — wrap command execution, log before and on failure. Set `lvl`/`lvl_fail` to control levels (default INFO/ERR). A mutation goes through `run_mut` (§ Dry run), never bare `run_cmd`.

Never interpolate values into the message. Separate message from data with `|`. Key name MUST match variable name.

```
BAD:  log::err "Invalid mode ${mode}"
GOOD: log::err "Invalid mode | mode='${mode}' valid_modes='${(j:, :)VALID_MODES}'"
```

## Dry run

Every mutating script sources `lib/dry_run.zsh` right after the logging preamble, then:

- `resolve_dry_run "${execute}" "${dry_run}"` — right after the parse loop. Applies § Mutations and exports `DRY_RUN`; WARNs when it overrides an explicit `--execute`.
- `run_mut <cmd…>` — every mutating command. Logs `would run | cmd=…` (shell-quoted, so the line can be copied) in a dry run, else runs it through `run_cmd`. Until `resolve_dry_run` has run, every call is a dry run.
- `… | write_mut FILE [--append]` — every file write. In a dry run it drains stdin and logs `would write | file='…' bytes='…'`.
- `run_mut --dry-out '<placeholder>' <cmd…>` — a mutation whose stdout a later step needs: the placeholder stands in for it in a dry run. Inside `$(…)` the call counts in the subshell only, so add `(( MUT_COUNT += 1 ))` after it.
- `report_dry_run "${SCRIPT_PATH}" "${args[@]}"` — the closing log line: the exact rerun with `--execute` in the `$HOME` form, `Executed`, or `Nothing to change`. `readonly SCRIPT_PATH="${0:a}"` at the top level (inside a function `$0` is its name); `args` is the original `"$@"`.

**NEVER put a redirect or a pipe on a `run_mut` line.** The shell applies it to `run_mut` itself, so a dry run still truncates the file or kills the producer:

```zsh
# BAD — out.json is emptied in a dry run; the producer dies of SIGPIPE
run_mut jq '.x = 1' in.json > out.json
seq 1 400000 | run_mut tee out.txt
# GOOD
jq '.x = 1' in.json | write_mut out.json
seq 1 400000 | write_mut out.txt
```

The shape, condensed from `bin/example` (its `copy_skill_file` spells the guard out as a function):

```zsh
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/dry_run.zsh"
readonly SCRIPT_PATH="${0:a}"

main() {
  local -a args=("${@}")
  local execute=false dry_run=false
  while (( $# > 0 )); do case "${1}" in
    --execute) execute=true; shift ;;
    --dry-run) dry_run=true; shift ;;
    …
  esac; done
  resolve_dry_run "${execute}" "${dry_run}"
  …
  cmp -s "${src}" "${dest}" || run_mut cp "${src}" "${dest}"
  print -l -- "${targets[@]}" | write_mut "${out_dir}/manifest.txt"
  report_dry_run "${SCRIPT_PATH}" "${args[@]}"
  cat <<EOF
dry_run=${DRY_RUN}
changes=${MUT_COUNT}
EOF
}
```

A dry run of it, on stderr:

```
[INFO] Dry run: the default; nothing will change | rerun='--execute'
[INFO] would run | cmd=mkdir -p 'ex dir'
[INFO] would run | cmd=cp /Users/<you>/.claude/skills/ari-poem-limerick/SKILL.md 'ex dir/ari-poem-limerick.SKILL.md'
[INFO] would write | file='ex dir/manifest.txt' bytes='18' mode='replace'
[INFO] Dry run; nothing changed | changes='3' rerun='zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --mode reg --target ari-poem-limerick --out-dir 'ex dir' --execute'
```

When the user, not Claude, runs the `--execute` step, hand the `rerun` command to `/ari-driving-tmux`. Python scripts honour the same `DRY_RUN` contract (`/ari-skill-pythonscripts`). The dotfiles kernel's `is_dry_run`/`run_mut` (`~/.config/dotfiles/lib/run.zsh`) read another variable with the opposite default; this lib refuses to load over them.

## Bounded subprocesses

Any backgrounded command that talks to a network or external process MUST have a wall-clock cap. `set -e` plus a hung child wedges the session silently.

Source `run_with_timeout` from the shared lib (reusing `SKILLS_DIR` from the logging block). It prefers `timeout`/`gtimeout` and falls back to a poll-and-SIGKILL loop; it returns the command's exit code, or `124` on timeout (mirrors GNU `timeout`).

```zsh
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/run_with_timeout.zsh"

local exit_code=0
err_file="$(mktemp)"
run_with_timeout 30 "${err_file}" git fetch origin main || exit_code=$?
# 0 = success; 124 = timed out; other = real failure (head "${err_file}" for the reason)
```

## Waiting with a visible state

A script that waits on something slow MUST say whose turn it is, and MUST let the library end the line. Source `lib/await.zsh` on the line after `source "${LIB_LOGGING}"`, before any function is defined: `await::_guard` is an alias and expands only in functions parsed after it.

`await::run` draws one status line while a step runs and ends it from the step's exit code: a green ✓ on 0, a red ✗ with the code otherwise, 124 when `--timeout` kills the step, 130 on ctrl-c. The spinner is a background renderer, so it moves while the step blocks. Interactive mode (the outermost wait's stderr is a tty, or `AWAIT_INTERACTIVE=1`) redraws the line in place; plain mode (not a tty, or `AWAIT_INTERACTIVE=0`) prints one `[AWAIT]` line per state change and nothing on a tick, for logs and agents, and its `[AWAIT] ✓`/`✗` line is the step's last stderr line.

```zsh
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/await.zsh"

step() {
  frob || return 1
  await::user "your turn: press a key"; {
    read -k 1 -s < /dev/tty
  }
  await::computer "frobbing some more…"; {
    log::info "Frobbing | widget='${1}'"     # lands above the line; no await::note needed
    frob_more
  }
}
await::run --slots 3 --timeout 60 "frobbing the widget…" -- step foo bar     # 0, step's code, 124 or 130
```

Inside the step:

- `await::computer "msg"` is the machine's turn (grey spinner); `await::user "msg"` is the person's (magenta pulse, one bell). **Each MUST be followed by `; {` and an indented `}` group holding that turn's work**; the library warns once per site when the group is missing.
- `await::progress N` fills `--slots`. With `--slots` the current cell and the frame beside the message both spin: one slot reads `[⠋] ⠋ copying…` on the machine's turn, `[⠋] ◆ press a key` on the person's (only the frame pulses), `[✓] ✓ copying…` when done. That is correct; never hide it.
- **Log inside a step as anywhere else (`log::info`, `run_mut`).** Interactive, `await::run` relays every stderr line above the status line and the ✓ or ✗ line comes last; plain, the line passes through as it came. NEVER redirect a step's stderr to keep the line clean (`2>/dev/null`, `2>&1`): the relay then sees nothing. Only stderr is relayed: a step's stdout lands on the line, so status goes through `log::*` and data is printed after the wait. A bare `await::_guard` has no relay.
- `await::note "text"` prints one line above the status line that is not a log record (a hint for the person); plain mode tags it `[AWAIT] note:`. NEVER report one event through both `log::*` and `await::note`.
- A question inside a wait is `await::user "…"` plus a read from `/dev/tty`, never a bare stderr prompt: the relay forwards whole lines, so a prompt with no newline stays unseen.
- A step that backgrounds a command MUST `wait` for it or give it its own stderr: the ✓ waits up to a second for the step's stderr to close, then the child's later lines print under the ✓. A tool that tests its stderr for a tty (colour, a progress bar) sees a pipe under the relay.

A step that logs once and reports `await::progress 1` under `--slots 2`, on the terminal once the wait has ended, then the same run with stderr on a pipe:

```
[INFO] copying | rel='a.gcode'
[✓✓] ✓ copying…
```

```
[AWAIT] computer 0/2: copying… | elapsed_s='0' | args='step'
[INFO] copying | rel='a.gcode'
[AWAIT] computer 1/2: copying… | elapsed_s='0' | args='step'
[AWAIT] ✓ success 2/2: copying… | elapsed_s='0'
```

Underneath: the grammar of both entry points is `[--timeout S] [--slots N] "<message>" -- <rest…>`. `await::_guard "<message>" -- "$@"` is the primitive under `await::run`, for a function that owns its message: an alias that installs the function's EXIT and INT traps and ends the line when it returns (`--timeout` is display-only there). A helper outside a wait prints `YOU MUST CALL <name> INSIDE await::run OR await::_guard (AWAIT_FD is unset)` and returns 2. A wait inside a wait nests: the outer line freezes, the inner draws one space further in, and when the inner ends the outer resumes on a fresh line with its clock still running. `await::success "msg"` and `await::failure "msg" [rc]` by hand are allowed inside a wait; the function's return then only reaps.

When a probe can say where things stand, let the loop be declarative: the probe prints `<state> <message>` (and `progress <n>` lines), and `await::until --interval 0.2 --timeout 30 -- probe` draws and returns 0, 1, 124, 130 or 2. Every other stdout line is an unknown state (2). The probe's stderr is relayed like a step's, and the probe runs every interval, so it logs a change of state, never a look. It runs in a command substitution, so its state lives in a file or the world, never a variable, and it never leaves a child behind.

Learn it by watching: `zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/await-lessons` runs ten lessons in order (`--list` prints what each teaches; `--only N` one of them). The automated checks are `zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/await.test.zsh`.

## Investigation folders

Scripts that stage runtime state under `/tmp` MUST use the shared helper, not hand-roll the timestamped path. It creates `<root>/<skill>/<UTC-timestamp>/` and prints the path. A folder that already exists is never reused: the next call gets `<UTC-timestamp>-2`, then `-3`, e.g. `/tmp/skill-update/foo/20261106T194643Z`, `…Z-2`, `…Z-3`. Treat the leaf as opaque: never glob for it or add your own suffix loop. On failure it prints one `[ERROR]` line and returns 1, so check the call. Logging otherwise stays with the caller.

```zsh
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
dir="$(mk_investigation_dir /tmp/skill-update "${skill}")" || exit 1
```

## Prerequisites

Use `command -v`, never `which`. Check all at once and list all missing — see `bin/example`'s `check_prerequisites`.

## Environment variables

Validate before use. `${VAR:?message}` for required, `${VAR:-default}` for optional.

## Script structure

Four phases: **parse → massage → validate → logic.**

1. **Parse** — `--help` first, then `while (( $# > 0 )); do case` for flags. Never positional args — use repeated flags for arrays (`--target foo --target bar`). Use `${2:?--flag requires a value}` to catch missing values. A mutating script calls `resolve_dry_run` right after the loop.
2. **Massage** — normalize case (`${mode:l}`), expand shortnames, split comma-separated into arrays (`${(@s/,/)val}`), multiline to array (`${(@f)$(cmd)}`).
3. **Validate** — check required args, sane values. After massage, not during parse.
4. **Logic** — the actual work. No more argument handling. Every mutation through `run_mut` or `write_mut`; a mutating script ends with `report_dry_run` and a heredoc carrying `dry_run=`.

## Validation

**Before committing a change to this skill or to any skill's zsh scripts, you MUST syntax-check each changed script and run each test file.** Each exits 1 on a failure:

```zsh
zsh -n <each changed script>
zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/conventions.test.zsh --skill <each skill you changed>
zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/await.test.zsh
zsh $HOME/.claude/skills/ari-skill-shellscripts/tests/investigation_folder.test.zsh
```

`conventions.test.zsh` proves the rules above in a throwaway zsh (`lib/dry_run.zsh` and `bin/example` among them), then lints zsh scripts; without `--skill` it lints every skill. One line per finding, `FAIL  <file>:<line>  <what and the fix>`, then `summary  pass=N fail=N warn=N`:

- **FAIL** — a rule broken for certain; fails the run. Quotes inside an associative-array subscript. A bin/ script with a `--dry-run` arm or a `run_mut` call and no `--execute` arm (its default acts), or no `resolve_dry_run` call. A local `run_mut`/`is_dry_run`/`resolve_dry_run`/`write_mut`/`report_dry_run` definition. `DRY_RUN` compared with or set to `true`/`false`. A redirect or pipe on a `run_mut` line.
- **WARN** — a heuristic match to read and fix: an `--apply`/`--yes`/`--confirm`/`--no-dry-run` arm; under pipefail, `grep` not last, or `head` / `grep -m` / `sed q` / `awk exit` on a pipeline.
- A line ending in `# lint: ok` is skipped, FAIL or WARN, once a person has reviewed it.
- The lint cannot see a script that mutates with no flags at all: the definition in § Mutations is the check there.

A FAIL in a skill you did not change is listed in your report under that skill's name, never fixed unasked and never a reason to hold your own commit; `--skill` scopes the gate to what you changed.

**A convention here broken in use, or wrong, is a `/ari-skill-update ari-skill-shellscripts` in the same session, unasked:** a script exited 141 or died `parameter not set`, a run meant as a dry run acted, or a rule here misled. The update adds the rule and an `expect_rc` case or a lint fixture that fails without it.

## Example

```zsh
zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --help
zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --mode reg --target pr --verbose
zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --mode compare --target ari-poem-limerick --out-dir /tmp/example-out
zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --mode compare --target ari-poem-limerick --out-dir /tmp/example-out --execute
```

The first `--out-dir` run logs the copies; the second, with `--execute`, makes them, and a repeat of it changes nothing.
