"""MessageDisplay hook: show every bare bead id in Claude's message as its link.

Claude Code runs this once per batch of lines it is about to display, with the hook payload as
JSON on stdin (`delta` holds the lines, `message_id` the message, `final` its last batch). When a
line names a bead id that bd knows and that is not already a link, the hook answers with
`displayContent`: the same lines with the id replaced by the link bead_link.zsh mints. It prints
nothing when there is nothing to change, and Claude Code then shows the original. The change is
on screen only; the transcript keeps what Claude wrote.

Left alone: ids inside code fences, inline code, Markdown links and URLs, and ids bd does not
know. Any failure (bd locked, a timeout) also leaves the text alone.

Run only through bead_autolink.zsh. Conventions: /ari-skill-pythonscripts.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

from skill_log import die, log_warn

COMMAND_TIMEOUT_SECONDS = 4
FENCE_MARKERS = ("```", "~~~")
# A state or cache file older than this belongs to a message that never sent its final batch.
STALE_STATE_SECONDS = 24 * 60 * 60


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    parser.add_argument(
        "--workspace", action="append", default=[], metavar="PREFIX=DIR",
        help="a beads workspace on this machine: its bead id prefix and its directory; repeatable",
    )
    parser.add_argument(
        "--state-dir", default=str(Path(tempfile.gettempdir()) / "claude-bead-autolink"),
        help="where the fence state and the link cache are kept",
    )
    parser.add_argument(
        "--cache-seconds", type=int, default=60,
        help="how long a bead's link (or its absence) is reused before bd is asked again",
    )
    parser.add_argument(
        "--linker", default=str(Path(__file__).resolve().parent / "bead_link.zsh"),
        help="the script that mints a link (bead_link.zsh)",
    )
    parser.add_argument("--bd", default="bd", help="the bd binary")
    return parser.parse_args()


def parse_workspaces(specs):
    """Return {prefix: directory} from PREFIX=DIR strings."""
    workspaces = {}
    for spec in specs:
        prefix, separator, directory = spec.partition("=")
        if not separator or not re.fullmatch(r"[a-z][a-z0-9]*", prefix) or not directory:
            die(f"invalid workspace | workspace='{spec}' want='PREFIX=DIR, PREFIX lowercase letters and digits'")
        workspaces[prefix] = Path(directory).expanduser()
    return workspaces


def token_pattern(prefixes):
    """One pattern for everything on a line that matters: spans to leave alone, and bare ids."""
    alternatives = "|".join(re.escape(prefix) for prefix in sorted(prefixes))
    return re.compile(
        r"(?P<code>`[^`\n]*`)"
        r"|(?P<link>\[[^\]\n]*\]\([^)\n]*\))"
        r"|(?P<url>[a-z][a-z0-9+.-]*://\S+)"
        rf"|(?P<id>(?<![\w/.-])(?:{alternatives})-[a-z0-9]{{2,8}}(?:\.[0-9]+)*(?![\w-]))"
    )


def split_fenced(delta, in_fence):
    """Return ([(line, is_prose)], in_fence after the last line). Fence lines are not prose."""
    lines = []
    for line in delta.splitlines(keepends=True):
        if line.lstrip().startswith(FENCE_MARKERS):
            in_fence = not in_fence
            lines.append((line, False))
            continue
        lines.append((line, not in_fence))
    return lines, in_fence


def read_fresh(path, max_age_seconds):
    """Return the file's text, or None when it is missing or older than max_age_seconds."""
    try:
        if time.time() - path.stat().st_mtime > max_age_seconds:
            return None
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def run_bounded(command, what):
    """Run a command with a timeout. Return its stdout, or None when it could not finish."""
    try:
        result = subprocess.run(
            command, capture_output=True, encoding="utf-8",
            timeout=COMMAND_TIMEOUT_SECONDS, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        log_warn(f"command did not finish; leaving the text alone | what='{what}' error='{error}'")
        return None
    return result.stdout


def read_beads(bd, directory, bead_ids):
    """Return {id: bead} for the ids bd knows, or None when bd could not be read."""
    stdout = run_bounded([bd, "-C", str(directory), "show", *bead_ids, "--json"], "bd show")
    if stdout is None:
        return None
    try:
        beads = json.loads(stdout) if stdout.strip() else []
    except json.JSONDecodeError:
        # bd prints no JSON when it knows none of the ids.
        beads = []
    return {bead["id"]: bead for bead in beads or [] if bead.get("title")}


def mint_links(linker, beads):
    """Return {id: Markdown link} from one bead_link.zsh call."""
    command = ["zsh", linker, "--here"]
    for bead_id, bead in beads.items():
        command += ["--bead", bead_id, "--title", bead["title"]]
        if bead.get("status"):
            command += ["--status", bead["status"]]
        if isinstance(bead.get("priority"), int):
            command += ["--priority", str(bead["priority"])]
    stdout = run_bounded(command, "bead_link.zsh") or ""
    links = {}
    for line in stdout.splitlines():
        match = re.match(r"\[([^\]]+)\]\(\S+\)$", line)
        if match and match.group(1) in beads:
            links[match.group(1)] = line
    return links


def resolve_links(bead_ids, workspaces, args, cache_dir):
    """Return {id: link} for the ids that have one, reading the cache first, then bd."""
    links = {}
    unknown_by_prefix = {}
    for bead_id in bead_ids:
        cached = read_fresh(cache_dir / bead_id, args.cache_seconds)
        if cached is None:
            unknown_by_prefix.setdefault(bead_id.split("-", 1)[0], []).append(bead_id)
        elif cached:
            links[bead_id] = cached
    for prefix, missing_ids in unknown_by_prefix.items():
        beads = read_beads(args.bd, workspaces[prefix], missing_ids)
        if beads is None:
            continue
        minted = mint_links(args.linker, beads) if beads else {}
        for bead_id in missing_ids:
            # An empty cache file records that the id has no link, so bd is not asked again at once.
            (cache_dir / bead_id).write_text(minted.get(bead_id, ""), encoding="utf-8")
        links.update(minted)
    return links


def remove_stale(directory):
    for path in directory.iterdir():
        try:
            if time.time() - path.stat().st_mtime > STALE_STATE_SECONDS:
                path.unlink()
        except OSError:
            continue


def main():
    args = parse_args()
    workspaces = parse_workspaces(args.workspace)
    if not workspaces:
        die("no workspace given | want='--workspace PREFIX=DIR'")
    payload = json.load(sys.stdin)
    delta = payload.get("delta") or ""
    message_id = re.sub(r"[^A-Za-z0-9_-]", "_", str(payload.get("message_id") or "no-message-id"))

    fence_dir = Path(args.state_dir) / "fence"
    cache_dir = Path(args.state_dir) / "cache"
    fence_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    fence_file = fence_dir / message_id
    lines, in_fence = split_fenced(delta, fence_file.exists())
    if payload.get("final"):
        fence_file.unlink(missing_ok=True)
        remove_stale(fence_dir)
    elif in_fence:
        fence_file.touch()
    else:
        fence_file.unlink(missing_ok=True)

    pattern = token_pattern(workspaces)
    bead_ids = []
    for line, is_prose in lines:
        if not is_prose:
            continue
        for match in pattern.finditer(line):
            if match.lastgroup == "id" and match.group() not in bead_ids:
                bead_ids.append(match.group())
    if not bead_ids:
        return

    links = resolve_links(bead_ids, workspaces, args, cache_dir)
    if not links:
        return

    def replace(match):
        if match.lastgroup != "id":
            return match.group()
        return links.get(match.group(), match.group())

    display = "".join(pattern.sub(replace, line) if is_prose else line for line, is_prose in lines)
    if display == delta:
        return
    json.dump(
        {"hookSpecificOutput": {"hookEventName": "MessageDisplay", "displayContent": display}},
        sys.stdout,
    )


if __name__ == "__main__":
    main()
