"""Bounded subprocess helper: run a command under a wall-clock cap, die on failure.

Conventions: /ari-skill-pythonscripts SKILL.md (## Subprocesses). Ships paired with
at_log (imported below); both are on PYTHONPATH via the entrypoint.
"""
import subprocess

from at_log import die


def run_capture(cmd, timeout_s, *, what=None):
    """Run cmd (a non-empty list) with a timeout, capturing UTF-8 stdout/stderr.

    Returns the CompletedProcess on success; on a missing binary, timeout, or
    non-zero exit, dies with a `key='value'` record. `what` names the operation
    in error messages (defaults to the binary name).
    """
    if not isinstance(cmd, (list, tuple)) or not cmd:
        die(f"run_capture needs a non-empty command list | cmd='{cmd!r}'")
    label = what or cmd[0]
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, encoding="utf-8", timeout=timeout_s
        )
    except FileNotFoundError:
        die(f"{label}: binary not found | bin='{cmd[0]}'")
    except subprocess.TimeoutExpired:
        die(f"{label}: timed out | timeout_s='{timeout_s}'")
    if result.returncode != 0:
        die(f"{label}: failed | rc='{result.returncode}' stderr='{result.stderr.strip()[:300]}'")
    return result
