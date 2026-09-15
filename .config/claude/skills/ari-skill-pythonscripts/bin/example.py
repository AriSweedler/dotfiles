#!/usr/bin/env python3
"""Reference Python skill script. Run: zsh $HOME/.claude/skills/ari-skill-pythonscripts/bin/example.zsh --help

Demonstrates every ari-skill-pythonscripts convention: shared logging (imported
bare; the entrypoint set PYTHONPATH), argparse (free --help), prereq check,
parse -> validate -> logic, stdout=data / stderr=logs, errors that name the
offending value, --dry-run, bounded subprocess, UTF-8 file write, and the
--force overwrite guard.
"""
import argparse
import shutil
from pathlib import Path

from at_log import log_info, die
from at_subprocess import run_capture

VALID_MODES = ("reg", "compare")
PREREQS = ("git",)


def check_prerequisites():
    missing = [binary for binary in PREREQS if shutil.which(binary) is None]
    if missing:
        die(f"missing prerequisites | missing='{', '.join(missing)}'")


def parse_args():
    parser = argparse.ArgumentParser(description="Reference example skill script.")
    parser.add_argument("--mode", required=True, help=f"one of {', '.join(VALID_MODES)}")
    parser.add_argument("--target", action="append", default=[], help="repeatable target")
    parser.add_argument("--out", help="write the result to PATH instead of stdout")
    parser.add_argument("--force", action="store_true", help="overwrite --out if it exists")
    parser.add_argument("--dry-run", dest="dry_run", action="store_true", help="log actions, change nothing")
    return parser.parse_args()


def emit(result, args):
    if not args.out:
        print(result)  # stdout is data
        return
    out_path = Path(args.out)
    if out_path.exists() and not args.force:
        die(f"output exists | path='{out_path}' hint='pass --force to overwrite'")
    out_path.write_text(result + "\n", encoding="utf-8")
    log_info(f"wrote result | path='{out_path}'")
    print(str(out_path))


def main():
    args = parse_args()
    mode = args.mode.lower()
    if mode not in VALID_MODES:
        die(f"invalid mode | mode='{mode}' valid='{', '.join(VALID_MODES)}'")
    check_prerequisites()

    log_info(f"running | mode='{mode}' targets='{', '.join(args.target)}' dry_run='{args.dry_run}'")
    head = run_capture(["git", "rev-parse", "--short", "HEAD"], timeout_s=10, what="resolve HEAD").stdout.strip()

    if args.dry_run:
        log_info(f"dry-run: would emit | head='{head}'")
        return
    emit(head, args)


if __name__ == "__main__":
    main()
