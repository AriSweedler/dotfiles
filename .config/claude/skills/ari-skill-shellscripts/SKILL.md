---
name: ari-skill-shellscripts
description: Conventions for writing zsh scripts in Claude skills — logging, prereqs, arg parsing, env vars, structure.
user_invocable: false
---

# Skill Shell Scripts

Conventions for writing zsh scripts in Claude skills. See `bin/example` for a runnable reference implementation that demonstrates every pattern.

## Choosing a conventions skill

This skill covers zsh. For Python, use `/ari-skill-pythonscripts` (its mirror). For any other language (node, ruby, go, …), use that language's conventions skill; if none exists yet, build one first — mirror these — then write the script.

## Rules

### Shell and safety

- **Use zsh, not bash.** Bash version varies across machines; zsh is consistently modern.
- **`set -euo pipefail` at the top.** Every script.
- **Python only through its zsh entrypoint.** When a script needs a Python script, call `zsh …/<name>.zsh`, never `python3 …/<name>.py`. The entrypoint owns `PYTHONPATH`; the Python never edits `sys.path`. Shape and rules: `/ari-skill-pythonscripts`.
- **Invoke with the shell name via the `$HOME` form.** `zsh $HOME/.claude/skills/<skill>/bin/<script>`. The matcher expands `$HOME` (but NOT `~`) in the invocation, so the `$HOME` form matches the user's absolute allowlist rule (`Bash(zsh /Users/<you>/.claude/skills/*)`) and runs without a permission prompt; a `~` invocation does NOT match an absolute rule. Allowlist rules MUST be absolute — never a `~`- or `$HOME`-form pattern (a `$HOME` pattern is never expanded, so it matches nothing). NEVER `cd` then run a relative `bin/x` path, and NEVER pipe the output (no `| head`, no `2>&1 | …` in the documented form): a `cd` prefix, relative path, or pipe breaks the match. Include a shebang (`#!/usr/bin/env zsh`) for documentation, but NEVER rely on it for execution.

### Naming

- **`readonly` for constants.** `ALL_CAPS` for globals, `snake_case` for locals.
- **`snake_case` everywhere.** Functions, variables, file names.
- **Never name a variable after a zsh special parameter.** `local path=` rebinds `PATH` (`path` is the array tied to it) and `local status=` shadows the last exit code; the failure surfaces far from the assignment as `command not found` or a wrong `$?`. Off limits: `path`, `status`, `cdpath`, `fpath`, `manpath`, `argv`, `pipestatus`, `reply`, `match`, `MATCH`, `options`, `functions`, `signals`, `prompt`, `watch`, `histchars`, `RANDOM`, `SECONDS`, `LINENO`, `PWD`, `OLDPWD`. Use `file`, `dir`, `exit_code`, `result` instead.
- **Always `"${x}"`.** Never bare `$x`. Never unquoted `${x}`. Every variable expansion gets braces and double quotes.
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
- **Labeled output via heredoc.** Scripts producing multiple values MUST use `key=value` lines via a `cat <<EOF` heredoc at the end. Do NOT repeat the output format in the header comment.
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

- **`--dry-run` for any script that mutates state.** Under it, log what would happen (via `run_cmd`) and make no external change. Read-only scripts omit it.
- **Mutating scripts are idempotent.** Guard each state change with an existence check so a second run is a no-op, not an error.

## File layout

- `bin/` — all scripts (per-skill gatherers, utilities, sync/push tools)
- `lib/` — shared libraries (logging, helpers) sourced by other scripts

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
- `run_cmd` / `run_cmd_cap` — wrap command execution, log before and on failure. Set `lvl`/`lvl_fail` to control levels (default INFO/ERR).

Never interpolate values into the message. Separate message from data with `|`. Key name MUST match variable name.

```
BAD:  log::err "Invalid mode ${mode}"
GOOD: log::err "Invalid mode | mode='${mode}' valid_modes='${(j:, :)VALID_MODES}'"
```

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

## Investigation folders

Scripts that stage runtime state under `/tmp` MUST use the shared helper, not hand-roll the timestamped path. It creates `<root>/<skill>/<UTC-timestamp>/` (so concurrent sessions never clash) and prints the path. Logging stays with the caller.

```zsh
source "${SKILLS_DIR}/ari-skill-shellscripts/lib/investigation_folder.zsh"
dir="$(mk_investigation_dir /tmp/skill-update "${skill}")"
```

## Prerequisites

Use `command -v`, never `which`. Check all at once and list all missing — see `bin/example`'s `check_prerequisites`.

## Environment variables

Validate before use. `${VAR:?message}` for required, `${VAR:-default}` for optional.

## Script structure

Four phases: **parse → massage → validate → logic.**

1. **Parse** — `--help` first, then `while (( $# > 0 )); do case` for flags. Never positional args — use repeated flags for arrays (`--target foo --target bar`). Use `${2:?--flag requires a value}` to catch missing values.
2. **Massage** — normalize case (`${mode:l}`), expand shortnames, split comma-separated into arrays (`${(@s/,/)val}`), multiline to array (`${(@f)$(cmd)}`).
3. **Validate** — check required args, sane values. After massage, not during parse.
4. **Logic** — the actual work. No more argument handling.

## Validation

Run `zsh -n script.zsh` to syntax-check — built into zsh, no install. You MUST `zsh -n` a script before committing it.

## Example

A runnable reference script lives at `bin/example`:

```zsh
zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --help
zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --mode reg --target pr --verbose
zsh $HOME/.claude/skills/ari-skill-shellscripts/bin/example --mode compare --dry-run
```
