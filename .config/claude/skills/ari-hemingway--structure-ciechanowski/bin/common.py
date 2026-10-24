"""Shared argument handling for the ciechanowski bin/ scripts: the two roots every tool needs.

    --folder  the investigation folder   (fallback: $INVESTIGATION_FOLDER)
    --repo    the explainers repo        (fallback: $EXPLAINERS_REPO, then ~/Desktop/workspace/explainers)

The default palette tokens are the six the template's comment describes; `article/meta.json`
may override them with a `tokens` map {name: [light, dark]}.
"""
import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_REPO = Path.home() / "Desktop" / "workspace" / "explainers"
DEFAULT_TOKENS = {
    "red": ("#c0202a", "#ff7b7b"),
    "blue": ("#1f5fbf", "#7cb0ff"),
    "orange": ("#c25a00", "#ffa552"),
    "green": ("#1b7f4e", "#4fd59a"),
    "purple": ("#7a3ea8", "#c99bff"),
    "grey": ("#6b665f", "#a8a199"),
}


def die(msg):
    print(f"[ERROR] {msg}", file=sys.stderr)
    sys.exit(1)


def add_root_args(parser, folder=True, repo=True):
    if folder:
        parser.add_argument("--folder", default=os.environ.get("INVESTIGATION_FOLDER"),
                            help="investigation folder (default: $INVESTIGATION_FOLDER)")
    if repo:
        parser.add_argument("--repo", default=os.environ.get("EXPLAINERS_REPO", str(DEFAULT_REPO)),
                            help="explainers repo (default: $EXPLAINERS_REPO or ~/Desktop/workspace/explainers)")
    return parser


def resolve_folder(args):
    if not args.folder:
        die("no investigation folder | pass --folder or set INVESTIGATION_FOLDER")
    folder = Path(args.folder).expanduser()
    if not folder.is_dir():
        die(f"investigation folder missing | folder='{folder}'")
    return folder


def resolve_repo(args):
    repo = Path(args.repo).expanduser()
    if not (repo / "template" / "article.html").is_file():
        die(f"not an explainers repo (template/article.html missing) | repo='{repo}'")
    return repo


def tokens_css(tokens=None):
    """The `{{tokens}}` block of template/article.html from a {name: (light, dark)} map."""
    toks = tokens or DEFAULT_TOKENS
    return "\n    ".join(f"--c-{name}: light-dark({light}, {dark});" for name, (light, dark) in toks.items())


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def slugify(term):
    out = []
    for ch in term.lower():
        if ch.isalnum() and ord(ch) < 128:
            out.append(ch)
        elif out and out[-1] != "-":
            out.append("-")
    return "".join(out).strip("-")


if __name__ == "__main__":
    print(__doc__)
