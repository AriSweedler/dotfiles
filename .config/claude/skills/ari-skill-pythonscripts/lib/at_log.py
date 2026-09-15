"""Canonical stderr logging for Python skill scripts (`log_info/log_warn/log_err/die`).

Conventions and the entrypoint PYTHONPATH bootstrap: /ari-skill-pythonscripts SKILL.md.
Named `at_log` (not `logging`) so it can't shadow the stdlib on PYTHONPATH.
"""
import sys

# Palette mirrors ari-skill-shellscripts/lib/logging.zsh (can't source zsh from Python).
_RED = "\033[31m"
_GREEN = "\033[32m"
_YELLOW = "\033[33m"
_RESET = "\033[0m"


def _emit(color, level, msg):
    print(f"{color}[{level}]{_RESET} {msg}", file=sys.stderr)


def log_info(msg):
    _emit(_GREEN, "INFO", msg)


def log_warn(msg):
    _emit(_YELLOW, "WARN", msg)


def log_err(msg):
    _emit(_RED, "ERROR", msg)


def die(msg):
    """Log an error and exit non-zero."""
    log_err(msg)
    raise SystemExit(1)
