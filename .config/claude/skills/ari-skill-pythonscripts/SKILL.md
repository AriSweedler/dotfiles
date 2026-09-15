---
name: ari-skill-pythonscripts
description: Conventions for writing Python scripts in Claude skills — logging, prereqs, arg parsing, subprocesses, encoding, structure. The Python mirror of ari-skill-shellscripts.
user_invocable: false
---

# Skill Python Scripts

Conventions for writing Python scripts in Claude skills. The Python mirror of `ari-skill-shellscripts`. See `bin/example.zsh` + `bin/example.py` for a runnable reference that demonstrates every pattern.

## Choosing a conventions skill

zsh → `/ari-skill-shellscripts`, Python → this skill. For any other language, use that language's conventions skill, building one (mirror these) first if none exists. The full rule lives in `/ari-skill-shellscripts` → "Choosing a conventions skill".

## Rules

### Language and safety

- **Standard library only.** Skills run without `pip install`. If a third-party dependency is genuinely unavoidable, say so explicitly and gate on it.
- **Only the shell runs Python.** Every `.py` ships with a sibling `.zsh` entrypoint, and that entrypoint is the only way the script is ever run: `zsh $HOME/.claude/skills/<skill>/bin/<entrypoint>.zsh`. Never `python3 …/script.py`, by hand or from another script; a script without an entrypoint gets one before it runs. The shell owns the environment (`PYTHONPATH`, `PYTHONDONTWRITEBYTECODE`); the Python owns the logic and never touches `sys.path`.
- **Invoke via the `$HOME` form, never `cd`+relative, never piped.** The matcher expands `$HOME` (but NOT `~`) in the invocation, so the `$HOME` form matches the user's absolute allowlist rule (`Bash(zsh /Users/arisweedler/.claude/skills/*)`) and runs without a prompt; a `~` invocation does NOT match an absolute rule, and allowlist rules MUST be absolute (never a `~`- or `$HOME`-form pattern). A `cd` prefix, a relative `bin/x` path, or output piping (`| head`, `2>&1 | …`) also breaks the match.
- **Ship a thin zsh entrypoint per script, and it MUST export `PYTHONPATH` before running the Python.** That export is the entire bootstrap for the shared lib — omit it and every run dies immediately with `ModuleNotFoundError: No module named 'at_log'`. Copy this shape (follow `/ari-skill-shellscripts` for the rest of the entrypoint):
  ```zsh
  readonly SCRIPT_DIR="${0:A:h}"
  # Through the symlink farm, not ${SCRIPT_DIR:h:h}: skills are spread across dotfiles tiers.
  readonly SKILLS_DIR="${HOME}/.claude/skills"
  export PYTHONPATH="${SKILLS_DIR}/ari-skill-pythonscripts/lib${PYTHONPATH:+:${PYTHONPATH}}"
  export PYTHONDONTWRITEBYTECODE=1
  exec python3 "${SCRIPT_DIR}/your_script.py" "${@}"
  ```
- **Keep imports light.** Homebrew's `python3.14` has a slow cold start; a script that pulls heavy modules pays it every run.
- **No bare `except`.** Let unexpected errors surface with a traceback. Convert *expected* failures (bad input, missing file, failed subprocess) into a clean `die()`.

### Naming

- **`snake_case`** for functions, variables, files; **`UPPER_CASE`** for module-level constants. No invented abbreviations.

### Control flow

- **Named functions with early returns.** Lift a two-branch `if/else` into a function whose name describes the choice; handle the special case with an early `return`/`die`, let the default fall through. One concern per function.

### Output and errors

- **Stdout for data, stderr for logs.** The result (a path, JSON, the value) to stdout; all logging to stderr. A caller parses stdout.
- **`key='value'` records.** Separate the message from data with `|`; never interpolate values into the message; the key name matches the variable name. Errors name the offending value AND the constraint.
  - GOOD: `die(f"invalid mode | mode='{mode}' valid='{', '.join(VALID_MODES)}'")`
  - BAD: `die(f"invalid mode {mode}")`

### Arguments

- **Use `argparse`** (free `--help`). No positional soup — named flags; `action="append"` for repeatable lists. Validate after parsing: normalize (`.lower()`), check allowed values, then run.

### Encoding and paths

- **Always `encoding="utf-8"`** on `read_text`, `write_text`, `open`, and `subprocess.run`. The platform default is not UTF-8 everywhere; data contains emoji and smart quotes.
- **Use `pathlib.Path`,** not `os.path` string-joining.

### Mutations

- **`--dry-run` for any script that changes state** — log what would happen, change nothing.
- **Idempotent.** Guard each change so a second run is a no-op. Refuse to overwrite an existing output file without `--force`.

## File layout

- `bin/` — scripts (each a `<name>.zsh` entrypoint + `<name>.py`).
- `lib/` — shared modules on `PYTHONPATH`.

## Logging

**Import the canonical lib — never re-define the log functions inline.** `lib/at_log.py` provides `log_info`, `log_warn`, `log_err`, `die` (colorized to stderr), named `at_log` (not `logging`) so it can't shadow the stdlib. `lib/at_subprocess.py` provides `run_capture`.

Because the entrypoint put `lib/` on `PYTHONPATH` (see `### Language and safety`), the Python imports them bare — no per-file `sys.path` code:

```python
from at_log import log_info, log_warn, log_err, die
from at_subprocess import run_capture
```

There is no by-hand form: a script run by hand goes through its entrypoint too. A `sys.path.insert` in a `.py` is a bug; fix it by giving the script an entrypoint.

## Subprocesses

**Bound every external/network command** with a wall-clock cap, via `run_capture(cmd, timeout_s, what=...)` from `lib/at_subprocess.py`. It runs `cmd` (a list) with a timeout, captures UTF-8 text, and on a missing binary / timeout / non-zero exit `die`s with a `key='value'` record naming `rc` and the head of stderr. A hung child under no timeout wedges the caller.

## Prerequisites

Check with `shutil.which`, never by shelling out. List every missing binary at once:

```python
missing = [b for b in PREREQS if shutil.which(b) is None]
if missing:
    die(f"missing prerequisites | missing='{', '.join(missing)}'")
```

## Environment variables

Validate before use. Required: `value = os.environ.get("VAR") or die("VAR not set | …")`. Optional: `os.environ.get("VAR", default)`.

## Script structure

`main()` reads top to bottom: **parse → validate → load → logic.** Define helpers before their callers (leaf functions first, `main` last).

## Validation

Run `python3 -m py_compile script.py` before committing — the Python analog of `zsh -n`. You MUST compile-check a script before committing it.

## Example

A runnable reference lives at `bin/example.zsh` (entrypoint) + `bin/example.py`:

```zsh
zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --help
zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --mode reg --target a --target b
zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --mode compare --out /tmp/example.out --force
```
