#!/usr/bin/env python3
"""Build a scratch article that mounts the given figure specs, the first one in the hero slot.

    python3 scratch_page.py --out <dir>/index.html fig-sec=figures/sec.json:16:9 [fig-x=spec.json[:W:H] ...]

Each mount is `<fig-id>=<spec.json>[:<aspect>]`; the aspect defaults to 16:9. The page is a
real template instance, so `node tools/explainers.cjs validate|states|build` run on it and a
headless browser renders it when served from the repo root. Use one page per figure for
screenshots: a fragment deep link (#fig-x=state) on the full article screenshots blank.
"""
import argparse
from pathlib import Path

from common import add_root_args, die, resolve_repo, tokens_css


def mount(entry):
    if "=" not in entry:
        die(f"bad mount, expected fig-id=spec.json[:W:H] | entry='{entry}'")
    fid, rest = entry.split("=", 1)
    spec_path, _, aspect = rest.partition(":")
    aspect = aspect or "16:9"
    spec = Path(spec_path).read_text(encoding="utf-8").strip()
    return (f'<figure class="x-fig" id="{fid}" data-aspect="{aspect}">\n'
            f'<script type="application/json">{spec}</script>\n'
            f"<figcaption>Scratch.</figcaption>\n</figure>")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_root_args(ap, folder=False)
    ap.add_argument("--out", required=True, help="path of the scratch index.html to write")
    ap.add_argument("mounts", nargs="+", help="fig-id=spec.json[:W:H], first one lands in the hero slot")
    args = ap.parse_args()
    repo = resolve_repo(args)
    blocks = [mount(m) for m in args.mounts]
    t = (repo / "template" / "article.html").read_text(encoding="utf-8")
    t = (t.replace("{{tokens}}", tokens_css()).replace("{{title}}", "Scratch").replace("{{description}}", "scratch")
         .replace("{{url}}", "https://example.invalid/scratch/").replace("{{lede}}", "Scratch page.")
         .replace("{{hero}}", blocks[0]))
    rest = "\n".join(blocks[1:])
    t = (t.replace("{{sections}}", f'<section id="scratch"><h2>Scratch</h2>{rest}</section>')
         .replace("{{further}}", "<li>none</li>").replace("{{final}}", "<p>none</p>").replace("{{glossary}}", ""))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(t, encoding="utf-8")
    print(out)


if __name__ == "__main__":
    main()
