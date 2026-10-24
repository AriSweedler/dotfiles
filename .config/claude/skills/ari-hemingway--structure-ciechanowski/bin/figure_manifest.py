#!/usr/bin/env python3
"""Build the figure-review manifest the figure_audit workflow reads: one entry per figure in
article/body.html joined with its concept's insight, its spec and its screenshot.

    python3 figure_manifest.py --folder <investigation folder> [--out <folder>/figure-review/manifest.json]

Inputs: article/body.html (placeholders <figure data-spec data-aspect id> and the prose
around them), article/meta.json (slugs: term -> glossary slug), insights.json (rows with
term, definition = the key insight, shows), figures/<slug>.json, preview/c-<slug>.png.
Output: the manifest (a JSON array) and, on stdout, the `figures` argument for the workflow:
[{slug, fid, aspect}, ...].
"""
import argparse
import json
import re
from pathlib import Path

from common import add_root_args, die, load_json, resolve_folder, slugify

PLACEHOLDER = re.compile(r'<figure data-spec="([a-z0-9-]+)" data-aspect="([0-9]+:[0-9]+)" id="(fig-[a-z0-9-]+)">(.*?)</figure>', re.S)
SECTION = re.compile(r'<section id="([^"]+)">\s*<h2>(.*?)</h2>', re.S)
DFN = re.compile(r'<dfn id="t-([a-z0-9-]+)">')
TAG = re.compile(r"<[^>]+>")


def strip(html_text):
    return re.sub(r"\s+", " ", TAG.sub("", html_text)).strip()


def section_at(body, pos):
    name = "opening"
    for m in SECTION.finditer(body):
        if m.start() > pos:
            break
        name = strip(m.group(2))
    return name


def term_at(body, pos, slug_to_term):
    """The concept a figure belongs to: the nearest <dfn> before it."""
    last = None
    for m in DFN.finditer(body, 0, pos):
        last = m.group(1)
    if last is None:
        return None
    return slug_to_term.get(last, last)


def paragraph_after(body, end):
    m = re.compile(r"<p>(.*?)</p>", re.S).search(body, end)
    return m.group(0) if m else ""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_root_args(ap, repo=False)
    ap.add_argument("--out", help="manifest path (default: <folder>/figure-review/manifest.json)")
    args = ap.parse_args()
    folder = resolve_folder(args)
    body_path = folder / "article" / "body.html"
    if not body_path.is_file():
        die(f"body.html missing | path='{body_path}'")
    body = body_path.read_text(encoding="utf-8")
    meta = load_json(folder / "article" / "meta.json") if (folder / "article" / "meta.json").is_file() else {}
    slug_to_term = {v: k for k, v in meta.get("slugs", {}).items()}
    insights = {}
    if (folder / "insights.json").is_file():
        for row in load_json(folder / "insights.json")["rows"]:
            insights[row["term"]] = row
            slug_to_term.setdefault(slugify(row["term"]), row["term"])
    entries = []
    for m in PLACEHOLDER.finditer(body):
        slug, aspect, fid, inner = m.groups()
        term = term_at(body, m.start(), slug_to_term)
        row = insights.get(term, {}) if term else {}
        prose = paragraph_after(body, m.end())
        refs = sorted(set(re.findall(rf'data-fig="{fid}"\s+data-ref="([A-Za-z0-9_-]+)"', prose)))
        states = sorted(set(re.findall(rf'href="#{fid}"\s+data-state="([A-Za-z0-9_-]+)"', prose)))
        screenshot = folder / "preview" / f"c-{slug}.png"
        entries.append({
            "slug": slug, "fid": fid, "aspect": aspect,
            "term": term or "(hero: the whole system)",
            "section": section_at(body, m.start()),
            "insight": row.get("definition", ""),
            "shows": row.get("shows", ""),
            "caption": strip(inner),
            "prose_after": prose,
            "data_refs_used": refs, "states_linked": states,
            "spec": str(folder / "figures" / f"{slug}.json"),
            "screenshot": str(screenshot) if screenshot.is_file() else "",
        })
    out = Path(args.out) if args.out else folder / "figure-review" / "manifest.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(entries, indent=1, ensure_ascii=False), encoding="utf-8")
    missing_shots = [e["slug"] for e in entries if not e["screenshot"]]
    if missing_shots:
        print(f"[WARN] no screenshot for: {', '.join(missing_shots)} (run shot.zsh first)", file=__import__("sys").stderr)
    print(json.dumps([{"slug": e["slug"], "fid": e["fid"], "aspect": e["aspect"]} for e in entries]))


if __name__ == "__main__":
    main()
