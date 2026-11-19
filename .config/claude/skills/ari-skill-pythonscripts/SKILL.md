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
- **Invoke via the `$HOME` form, never `cd`+relative, never piped.** The matcher expands `$HOME` (but NOT `~`) in the invocation, so the `$HOME` form matches the user's absolute allowlist rule (`Bash(zsh /Users/<you>/.claude/skills/*)`) and runs without a prompt; a `~` invocation does NOT match an absolute rule, and allowlist rules MUST be absolute (never a `~`- or `$HOME`-form pattern). A `cd` prefix, a relative `bin/x` path, or output piping (`| head`, `2>&1 | …`) also breaks the match.
- **Ship a thin zsh entrypoint per script, and it MUST export `PYTHONPATH` before running the Python.** That export is the entire bootstrap for the shared lib — omit it and every run dies immediately with `ModuleNotFoundError: No module named 'skill_log'`. This is the whole file; nothing else belongs in it:
  ```zsh
  #!/usr/bin/env zsh
  set -euo pipefail
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
  - GOOD: `die(f"invalid mode | mode='{mode}' valid_modes='{', '.join(VALID_MODES)}'")`
  - BAD: `die(f"invalid mode {mode}")`

### Arguments

- **Use `argparse`** (free `--help`). No positional soup — named flags; `action="append"` for repeatable lists. Set `prog=` to the entrypoint's `$HOME` form so `--help` never names the `.py`. Validate after parsing: normalize (`.lower()`), check allowed values, then run.

### Encoding and paths

- **Always `encoding="utf-8"`** on `read_text`, `write_text`, `open`, and `subprocess.run`. The platform default is not UTF-8 everywhere; data contains emoji and smart quotes.
- **Use `pathlib.Path`,** not `os.path` string-joining.

### Mutations

A *mutation* changes something the script did not create in this run: a file at a path the caller named, a repo's working tree or index, a commit or push, any remote write, a send, a delete. Not a mutation: a read, `tempfile` scratch, a `/tmp` folder the script creates for this run. Unsure → it is a mutation.

- **A mutating script is a dry run unless `--execute` is on its own command line.** Without it the script runs every read and check, logs each mutation it would make, makes none, and exits 0, or non-zero on the same check failures the real run would hit.
- **A read-only script takes neither `--execute` nor `--dry-run`;** the flags do not exist in its `argparse`.
- **The act flag is `--execute`.** Never `--apply`, `--yes`, `--confirm`, `--force` or `--no-dry-run`. `--dry-run` states the default explicitly and overrides `--execute` in either order.
- **`DRY_RUN` is `1` (dry run) or `0` (act), read only through `is_dry_run()`.** An inherited `DRY_RUN` other than empty or `0` forces a dry run, `--execute` or not; an inherited `DRY_RUN=0` never makes a script act.
- **A dry run runs the whole script.** Only the mutations stand in: never branch on `is_dry_run()` to skip the reads and checks the real run makes.
- **A mutation never widens its scope by default.** A missing target is an error, never "all"; widening takes an explicit flag (`--all`).
- **Idempotent.** Guard each change with an existence or equality check so a second run changes nothing; the guard runs in a dry run too, so the preview lists only what `--execute` would change.
- **A mutating child script is called with `--execute` in its argv.** The exported `DRY_RUN=1` turns it back into a dry run under a dry-run parent.
- **Confirm an act by `dry_run=0` on stdout, never by exit 0.** A dry run exits 0 too.
- **A skill that documents a mutating script shows the dry-run invocation first,** then the `--execute` one, and says whether `--execute` waits for the user's `yes` or runs unattended.
- **Import the gate from `lib/dry_run.py` — never re-define it inline.** `resolve_dry_run(execute, dry_run)` after the parse and validate steps, `run_mut(cmd, timeout_s)` and `write_mut(path, text)` for every mutation, then `report_dry_run(__file__, sys.argv[1:])` as the last log line and `dry_run_value()`/`change_count()` in the stdout block.

## File layout

- `bin/` — scripts (each a `<name>.zsh` entrypoint + `<name>.py`).
- `lib/` — shared modules on `PYTHONPATH`.

## Logging

**Import the canonical lib — never re-define the log functions inline.** `lib/skill_log.py` provides `log_info`, `log_warn`, `log_err`, `die` (colorized to stderr), named `skill_log` (not `logging`) so it can't shadow the stdlib. `lib/skill_subprocess.py` provides `run_capture`, and `lib/dry_run.py` the mutation gate (`### Mutations`).

Because the entrypoint put `lib/` on `PYTHONPATH` (see `### Language and safety`), the Python imports them bare — no per-file `sys.path` code:

```python
from skill_log import log_info, log_warn, log_err, die
from skill_subprocess import run_capture
```

There is no by-hand form: a script run by hand goes through its entrypoint too. A `sys.path.insert` in a `.py` is a bug; fix it by giving the script an entrypoint.

## Subprocesses

**Bound every external/network command** with a wall-clock cap, via `run_capture(cmd, timeout_s, what=...)` from `lib/skill_subprocess.py`. It runs `cmd` (a list) with a timeout, captures UTF-8 text, and on a missing binary / timeout / non-zero exit `die`s with a `key='value'` record naming `rc` and the head of stderr. A hung child under no timeout wedges the caller.

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

Compile-check every changed `.py` — `lib/` modules included — before committing: `PYTHONPYCACHEPREFIX=/tmp/skill-pyc python3 -m py_compile <path>`. It compiles without running the script, so it does not break "Only the shell runs Python"; the cache prefix keeps `__pycache__` out of the skill directory.

## Example

A runnable reference lives at `bin/example.zsh` (entrypoint) + `bin/example.py`:

```zsh
zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --help
zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --mode reg --target a --target b
zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --mode compare --out /tmp/example.out
zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --mode compare --out /tmp/example.out --execute
```

The first `--out` run is a dry run: it logs the write it would make. The second, with `--execute`, makes it, and a repeat of that changes nothing. A dry run of the first, on stderr, then stdout:

```
[INFO] Dry run: the default; nothing will change | rerun='--execute'
[INFO] running | mode='compare' targets=''
[INFO] would write | file='/tmp/example.out' bytes='13' mode='replace'
[INFO] Dry run; nothing changed | changes='1' rerun='zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --mode compare --out /tmp/example.out --execute'
/tmp/example.out
dry_run=1
changes=1
```
