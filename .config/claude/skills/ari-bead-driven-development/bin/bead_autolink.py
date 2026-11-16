"""MessageDisplay hook: on screen, show every bead mention in Claude's message as its card link.

Claude Code runs this once per batch of lines it is about to display, with the hook payload as
JSON on stdin (`delta` holds the lines, `message_id` the message, `final` its last batch). The
transcript names a bead as `[beads-o27]` and ends the text block with a short definition line,
`[beads-o27]: <scotty url>?bead=beads-o27`, which Ari's phone opens. On screen the terminal wants
the card link instead, whose click opens the bead's tmux card. So for each bead id bd knows, the
hook answers with `displayContent`: the same lines with every mention of it (a bare id, a
`[beads-o27]` shortcut reference, or an inline link to its short URL) replaced by an inline link
to its card URL, and its definition line removed, with the blank line a removed trailing block
leaves. It prints nothing when there is nothing to change, and Claude Code then shows the
original. The change is on screen only: the transcript keeps what Claude wrote.

Both URLs come from bead_link.zsh, the one builder of them: its default output is the short URL,
and `--card` the card URL. Left alone: ids inside code fences and inline code, an inline link to
any other URL (a card URL included), a full reference (`[text][beads-o27]`), bare URLs, other
reference definitions, and ids bd does not know, whose definition lines stay too. Any failure
(bd locked, a timeout) also leaves the text as written, so a mention never loses its target.

Run only through bead_autolink.zsh. Conventions: /ari-skill-pythonscripts.
"""
import argparse
import json
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
        help="how long a bead's URLs (or their absence) are reused before bd is asked again",
    )
    parser.add_argument(
        "--linker", default=str(Path(__file__).resolve().parent / "bead_link.zsh"),
        help="the script that builds a bead's URLs (bead_link.zsh)",
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


def id_pattern(prefixes):
    """A bead id of one of the prefixes, as a regex fragment."""
    alternatives = "|".join(re.escape(prefix) for prefix in sorted(prefixes))
    return rf"(?:{alternatives})-[a-z0-9]{{2,8}}(?:\.[0-9]+)*"


def definition_pattern(prefixes):
    """A whole line that defines a bead id's reference: `[beads-o27]: <url>`."""
    return re.compile(rf"[ ]{{0,3}}\[(?P<id>{id_pattern(prefixes)})\]:[ \t]*\S+[ \t]*\r?\n?")


def token_pattern(prefixes):
    """One pattern for everything inside a line that matters: spans to leave alone, and mentions.

    A `link` is a mention when its URL names a bead (`bead=<id>`); a `reference` with a `label`
    group is a full reference, left alone.
    """
    bead_id = id_pattern(prefixes)
    return re.compile(
        r"(?P<code>`[^`\n]*`)"
        rf"|(?P<link>\[(?P<link_label>[^\]\n]*)\]\((?P<link_url>[^)\s]*[?&]bead=(?P<link_id>{bead_id}))\))"
        r"|(?P<other_link>\[[^\]\n]*\]\([^)\n]*\))"
        rf"|(?P<full>\]\[{bead_id}\])"
        rf"|(?P<reference>\[(?P<ref_id>{bead_id})\](?P<label>\[[^\]\n]*\])?)"
        r"|(?P<url>[a-z][a-z0-9+.-]*://\S+)"
        rf"|(?P<id>(?<![\w/.-]){bead_id}(?![\w-]))"
    )


def mentioned_id(match):
    """Return the bead id a token match mentions, else None."""
    if match.lastgroup == "id":
        return match.group()
    if match.lastgroup == "reference" and match.group("label") is None:
        return match.group("ref_id")
    if match.lastgroup == "link":
        return match.group("link_id")
    return None


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


def linker_urls(linker, beads, card):
    """Return {id: URL} from the definition lines of one bead_link.zsh call."""
    command = ["zsh", linker, "--here", *(["--card"] if card else [])]
    for bead_id, bead in beads.items():
        command += ["--bead", bead_id, "--title", bead["title"]]
        if bead.get("status"):
            command += ["--status", bead["status"]]
        if isinstance(bead.get("priority"), int):
            command += ["--priority", str(bead["priority"])]
    stdout = run_bounded(command, "bead_link.zsh --card" if card else "bead_link.zsh") or ""
    urls = {}
    for line in stdout.splitlines():
        match = re.match(r"\[([^\]]+)\]: (\S+)$", line)
        if match and match.group(1) in beads:
            urls[match.group(1)] = match.group(2)
    return urls


def mint_urls(linker, beads):
    """Return {id: {"short": URL, "card": URL}} for the beads both calls could build."""
    short = linker_urls(linker, beads, card=False)
    card = linker_urls(linker, beads, card=True)
    return {
        bead_id: {"short": short[bead_id], "card": card[bead_id]}
        for bead_id in beads if bead_id in short and bead_id in card
    }


def read_cached(path, max_age_seconds):
    """Return (hit, urls): a fresh cache entry's URLs, None for a recorded absence."""
    text = read_fresh(path, max_age_seconds)
    if text is None:
        return False, None
    if not text:
        return True, None
    try:
        urls = json.loads(text)
    except json.JSONDecodeError:
        return False, None
    if not isinstance(urls, dict) or not {"short", "card"} <= urls.keys():
        return False, None
    return True, urls


def resolve_urls(bead_ids, workspaces, args, cache_dir):
    """Return {id: {"short", "card"}} for the ids that have both, reading the cache first, then bd."""
    found = {}
    unknown_by_prefix = {}
    for bead_id in bead_ids:
        hit, urls = read_cached(cache_dir / bead_id, args.cache_seconds)
        if not hit:
            unknown_by_prefix.setdefault(bead_id.split("-", 1)[0], []).append(bead_id)
        elif urls:
            found[bead_id] = urls
    for prefix, missing_ids in unknown_by_prefix.items():
        beads = read_beads(args.bd, workspaces[prefix], missing_ids)
        if beads is None:
            continue
        minted = mint_urls(args.linker, beads) if beads else {}
        for bead_id in missing_ids:
            # An empty cache file records that the id has no URLs, so bd is not asked again at once.
            entry = json.dumps(minted[bead_id]) if bead_id in minted else ""
            (cache_dir / bead_id).write_text(entry, encoding="utf-8")
        found.update(minted)
    return found


def remove_stale(directory):
    for path in directory.iterdir():
        try:
            if time.time() - path.stat().st_mtime > STALE_STATE_SECONDS:
                path.unlink()
        except OSError:
            continue


def collect_ids(lines, definition, pattern):
    """Return the bead ids the prose lines mention or define, in order of appearance."""
    bead_ids = []
    for line, is_prose in lines:
        if not is_prose:
            continue
        defined = definition.fullmatch(line)
        found = [defined.group("id")] if defined else [mentioned_id(m) for m in pattern.finditer(line)]
        for bead_id in found:
            if bead_id and bead_id not in bead_ids:
                bead_ids.append(bead_id)
    return bead_ids


def display_lines(lines, definition, pattern, urls):
    """Return the lines to display: mentions as card links, known bead definition lines removed."""
    def replace(match):
        bead_id = mentioned_id(match)
        if bead_id not in urls:
            return match.group()
        if match.lastgroup == "link":
            if match.group("link_url") != urls[bead_id]["short"]:
                return match.group()
            return f"[{match.group('link_label')}]({urls[bead_id]['card']})"
        return f"[{bead_id}]({urls[bead_id]['card']})"

    shown = []
    removed_tail = False
    for line, is_prose in lines:
        defined = definition.fullmatch(line) if is_prose else None
        if defined and defined.group("id") in urls:
            removed_tail = True
            continue
        if is_prose and line.strip():
            removed_tail = False
        shown.append(pattern.sub(replace, line) if is_prose else line)
    if removed_tail:
        # A trailing definition block was removed: drop the blank lines that set it off.
        while shown and not shown[-1].strip():
            shown.pop()
    return shown


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

    definition = definition_pattern(workspaces)
    pattern = token_pattern(workspaces)
    bead_ids = collect_ids(lines, definition, pattern)
    if not bead_ids:
        return

    urls = resolve_urls(bead_ids, workspaces, args, cache_dir)
    if not urls:
        return

    display = "".join(display_lines(lines, definition, pattern, urls))
    if display == delta:
        return
    json.dump(
        {"hookSpecificOutput": {"hookEventName": "MessageDisplay", "displayContent": display}},
        sys.stdout,
    )


if __name__ == "__main__":
    main()
