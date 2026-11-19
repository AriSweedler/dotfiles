"""Canonical dry-run gate for Python skill scripts that mutate anything.

Conventions: /ari-skill-pythonscripts SKILL.md (### Mutations). Mirrors
ari-skill-shellscripts/lib/dry_run.zsh; import it through the entrypoint's
PYTHONPATH, never re-define it inline.
"""
import os
import shlex
from pathlib import Path

from skill_log import die, log_err, log_info, log_warn
from skill_subprocess import run_capture

_DRY_RUN_RESOLVED = False
MUT_COUNT = 0


def resolve_dry_run(execute, dry_run):
    """Decide whether this run acts; export DRY_RUN=1|0 for child scripts.

    Acts only when --execute is on this command line, --dry-run is not, and no
    parent exported a DRY_RUN other than empty or 0.
    """
    global _DRY_RUN_RESOLVED
    inherited = os.environ.get("DRY_RUN", "")
    _DRY_RUN_RESOLVED = True
    if dry_run:
        os.environ["DRY_RUN"] = "1"
        if execute:
            log_warn("Dry run: --dry-run overrides --execute; nothing will change | fix='drop --dry-run'")
            return
        log_info("Dry run: --dry-run given; nothing will change")
        return
    if inherited and inherited != "0":
        os.environ["DRY_RUN"] = "1"
        if execute:
            log_warn(f"Dry run: inherited DRY_RUN overrides --execute; nothing will change | inherited='{inherited}' fix='unset DRY_RUN'")
            return
        log_info(f"Dry run: inherited from the parent; nothing will change | inherited='{inherited}'")
        return
    if not execute:
        os.environ["DRY_RUN"] = "1"
        log_info("Dry run: the default; nothing will change | rerun='--execute'")
        return
    os.environ["DRY_RUN"] = "0"
    log_info("Executing: --execute given")


def is_dry_run():
    """True unless this process resolved to act; an inherited DRY_RUN=0 alone never acts."""
    return not (_DRY_RUN_RESOLVED and os.environ.get("DRY_RUN", "1") == "0")


def dry_run_value():
    """1 for a dry run, 0 for an act: the stdout value, without reading DRY_RUN."""
    return 1 if is_dry_run() else 0


def change_count():
    """How many mutations this run has logged or made."""
    return MUT_COUNT


def _warn_unresolved(caller):
    if not _DRY_RUN_RESOLVED:
        log_err(f"{caller} before resolve_dry_run; treating as a dry run | fix='call resolve_dry_run after the parse step'")


def run_mut(cmd, timeout_s, *, what=None, dry_out=None):
    """Run one mutating command, or log it in a dry run and return dry_out."""
    global MUT_COUNT
    _warn_unresolved("run_mut")
    MUT_COUNT += 1
    if is_dry_run():
        log_info(f"would run | cmd='{' '.join(shlex.quote(part) for part in cmd)}'")
        return dry_out
    return run_capture(cmd, timeout_s, what=what)


def write_mut(path, text, *, append=False):
    """Write text to path, or log the write it would make in a dry run."""
    global MUT_COUNT
    target = Path(path)
    mode = "append" if append else "replace"
    if not target.parent.is_dir():
        die(f"missing parent directory | file='{target}' parent='{target.parent}' hint='create it with run_mut first'")
    _warn_unresolved("write_mut")
    MUT_COUNT += 1
    if is_dry_run():
        log_info(f"would write | file='{target}' bytes='{len(text.encode('utf-8'))}' mode='{mode}'")
        return
    log_info(f"writing | file='{target}' mode='{mode}'")
    try:
        with target.open(mode="a" if append else "w", encoding="utf-8") as handle:
            handle.write(text)
    except OSError as exc:
        die(f"cannot write | file='{target}' error='{exc.strerror}'")


def report_dry_run(script_file, argv):
    """Closing log line: the exact rerun with --execute, Executed, or Nothing to change.

    script_file is the caller's __file__; the rerun names its sibling .zsh
    entrypoint under the skill's bin/, where the house layout puts it.
    """
    if MUT_COUNT == 0:
        log_info("Nothing to change | changes='0'")
        return
    if not is_dry_run():
        log_info(f"Executed | changes='{MUT_COUNT}'")
        return
    script = Path(script_file)
    entrypoint = f"$HOME/.claude/skills/{script.parent.parent.name}/bin/{script.stem}.zsh"
    args = [arg for arg in argv if arg not in ("--dry-run", "--execute")]
    rerun = " ".join(["zsh", entrypoint, *(shlex.quote(arg) for arg in args), "--execute"])
    log_info(f"Dry run; nothing changed | changes='{MUT_COUNT}' rerun='{rerun}'")
