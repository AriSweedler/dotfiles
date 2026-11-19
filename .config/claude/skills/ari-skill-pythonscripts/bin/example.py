#!/usr/bin/env python3
"""Reference Python skill script. Run: zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --help

Demonstrates every ari-skill-pythonscripts convention: shared logging (imported
bare; the entrypoint set PYTHONPATH), argparse with a prog naming the entrypoint,
prereq check, parse -> validate -> logic, stdout=data / stderr=logs, errors that
name the offending value, the dry-run gate (--execute to act), bounded
subprocess, UTF-8 file write, the idempotency guard, and the dry_run=/changes=
stdout block.
"""
import argparse
import shutil
import sys
from pathlib import Path

from dry_run import change_count, dry_run_value, report_dry_run, resolve_dry_run, write_mut
from skill_log import die, log_info
from skill_subprocess import run_capture

VALID_MODES = ("reg", "compare")
PREREQS = ("git",)


def check_prerequisites():
    missing = [binary for binary in PREREQS if shutil.which(binary) is None]
    if missing:
        die(f"missing prerequisites | missing='{', '.join(missing)}'")


def parse_args():
    script = Path(__file__)
    prog = f"zsh $HOME/.claude/skills/{script.parent.parent.name}/bin/{script.stem}.zsh"
    parser = argparse.ArgumentParser(prog=prog, description="Reference example skill script.")
    parser.add_argument("--mode", required=True, help=f"one of {', '.join(VALID_MODES)}")
    parser.add_argument("--target", action="append", default=[], help="repeatable target")
    parser.add_argument("--out", help="write the result to PATH instead of stdout")
    parser.add_argument("--execute", action="store_true", help="make the changes; without it, a dry run")
    parser.add_argument("--dry-run", dest="dry_run", action="store_true", help="the default; overrides --execute")
    return parser.parse_args()


def read_if_present(path):
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return None
    except (OSError, UnicodeDecodeError) as exc:
        die(f"cannot read existing output | path='{path}' error='{exc}'")


def emit(result, out):
    if not out:
        print(result)  # stdout is data
        return
    out_path = Path(out)
    content = result + "\n"
    if read_if_present(out_path) == content:
        log_info(f"unchanged | path='{out_path}'")
    else:
        write_mut(out_path, content)
    print(str(out_path))


def main():
    args = parse_args()
    mode = args.mode.lower()
    if mode not in VALID_MODES:
        die(f"invalid mode | mode='{mode}' valid_modes='{', '.join(VALID_MODES)}'")
    check_prerequisites()
    resolve_dry_run(args.execute, args.dry_run)

    log_info(f"running | mode='{mode}' targets='{', '.join(args.target)}'")
    head = run_capture(["git", "rev-parse", "--short", "HEAD"], timeout_s=10, what="resolve HEAD").stdout.strip()
    emit(head, args.out)
    report_dry_run(__file__, sys.argv[1:])
    print(f"dry_run={dry_run_value()}")
    print(f"changes={change_count()}")


if __name__ == "__main__":
    main()
