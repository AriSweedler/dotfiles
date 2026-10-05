#!/usr/bin/env python3
"""Assemble <folder>/article/index.html from the repo template, article/body.html,
figures/<slug>.json and the scaffold's definitions table.

    python3 assemble.py --folder <investigation folder> [--repo <explainers repo>]
                        [--definitions <path>] [--out <path>]

The contract the author writes:
  article/body.html   prose with figure placeholders and four block markers:
                        <!-- hero --> <figure data-spec="hero" data-aspect="3:1" id="fig-hero">
                          <figcaption>...</figcaption></figure> <!-- /hero -->
                        <section id="..."> ... </section>   (one per subsystem)
                        <!-- further --> <li>...</li> <!-- /further -->
                        <!-- final --> <p>...</p> <!-- /final -->
                      A placeholder <figure data-spec="<slug>" data-aspect="W:H" id="fig-<slug>"> keeps its
                      <figcaption>; the spec from figures/<slug>.json is injected as the JSON script.
  article/meta.json   {title, description, url, lede, slugs?: {term: glossary-slug}, tokens?: {name: [light, dark]}}
  figures/<slug>.json one spec per figure
  scaffold/definitions_final.json   rows [{term, definition, doc_url, short?}] -> the glossary

Per figure the assembler prunes notice.point_at to the ids the body references (the validator
warns otherwise) and sets notice.steps to "none" when every control is a segmented, a toggle or a chips control
(one pill). The glossary <dt> shows `Term (short)` when the row declares a short form.
"""
import argparse
import html
import json
import re
from pathlib import Path

from common import add_root_args, die, load_json, resolve_folder, resolve_repo, slugify, tokens_css

GENERATOR_META = '<meta name="generator" content="[🤖 AI generated] Claude Code with the ari-hemingway skill">'
FOOTER = '<footer class="x-footer"><p>🤖🌸 Generated with Claude Code with the ari-hemingway skill</p></footer>'
PLACEHOLDER = re.compile(r'<figure data-spec="([a-z0-9-]+)" data-aspect="([0-9]+:[0-9]+)" id="(fig-[a-z0-9-]+)">(.*?)</figure>', re.S)
REF = re.compile(r'data-fig="(fig-[a-z0-9-]+)"\s+data-ref="([A-Za-z0-9_-]+)"')


def block(body, name):
    m = re.search(rf"<!-- {name} -->(.*?)<!-- /{name} -->", body, re.S)
    if not m:
        die(f"body.html lacks a block | block='<!-- {name} --> ... <!-- /{name} -->'")
    return m.group(1).strip()


def esc(s):
    return html.escape(str(s), quote=True)


def inject_figures(body, figures_dir):
    refs = {}
    for m in REF.finditer(body):
        refs.setdefault(m.group(1), set()).add(m.group(2))
    count = 0

    def inject(m):
        nonlocal count
        slug, aspect, fid, inner = m.groups()
        spec_path = figures_dir / f"{slug}.json"
        if not spec_path.is_file():
            die(f"figure spec missing | fid='{fid}' spec='{spec_path}'")
        spec = load_json(spec_path)
        for key in ("shows", "manipulates", "notice"):
            if key not in spec:
                die(f"figure spec lacks a top-level key | fid='{fid}' key='{key}'")
        used = refs.get(fid, set())
        spec["notice"]["point_at"] = [p for p in spec["notice"].get("point_at", []) if p in used]
        kinds = {c["kind"] for c in spec["manipulates"].get("controls", [])}
        if kinds and kinds <= {"segmented", "toggle", "chips"}:
            spec["notice"]["steps"] = "none"
        count += 1
        return (f'<figure class="x-fig" id="{fid}" data-aspect="{aspect}">\n'
                f'<script type="application/json">{json.dumps(spec, separators=(",", ":"), ensure_ascii=False)}</script>\n'
                f"{inner.strip()}\n</figure>")

    return PLACEHOLDER.sub(inject, body), count


def glossary_rows(rows, slugs):
    out = []
    for r in rows:
        s = slugs.get(r["term"]) or slugify(r["term"])
        dt = html.escape(r["term"])
        if r.get("short"):
            dt += f' ({html.escape(r["short"])})'
        src = f' <a rel="external" href="{html.escape(r["doc_url"])}">source</a>' if r.get("doc_url") else ""
        out.append(f'    <div class="row" id="g-{s}">\n      <dt>{dt} <a class="x-back" href="#t-{s}" '
                   f'aria-label="back to first use">↩</a></dt>\n      <dd>{html.escape(r["definition"])}{src}</dd>\n    </div>')
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_root_args(ap)
    ap.add_argument("--definitions", help="definitions table (default: <folder>/scaffold/definitions_final.json)")
    ap.add_argument("--out", help="output path (default: <folder>/article/index.html)")
    ap.add_argument("--allow-missing-source", dest="allow_missing_source", action="store_true",
                    help="publish a glossary row that has no doc_url (the format skill forbids it; a bare row is otherwise a fatal error)")
    args = ap.parse_args()
    folder = resolve_folder(args)
    repo = resolve_repo(args)
    article = folder / "article"
    defs_path = Path(args.definitions) if args.definitions else folder / "scaffold" / "definitions_final.json"
    for required in (article / "body.html", article / "meta.json", defs_path):
        if not required.is_file():
            die(f"input missing | path='{required}'")
    meta = load_json(article / "meta.json")
    for key in ("title", "description", "url", "lede"):
        if key not in meta:
            die(f"meta.json lacks a key | key='{key}' required='title, description, url, lede'")
    body = (article / "body.html").read_text(encoding="utf-8")
    fids = re.findall(r'<figure[^>]*\sid="(fig-[a-z0-9-]+)"', body)
    dups = sorted({f for f in fids if fids.count(f) > 1})
    if dups:
        die(f"duplicate figure id in body.html | ids='{', '.join(dups)}'")
    body, nfig = inject_figures(body, folder / "figures")
    leftover = re.findall(r'<figure[^>]*data-spec="([^"]+)"', body)
    if leftover:
        die(f"placeholder not matched (attribute order must be data-spec, data-aspect, id) | specs='{', '.join(leftover)}'")
    hero = block(body, "hero")
    sections = body.split("<!-- /hero -->", 1)[1]
    further = block(sections, "further")
    final = block(sections, "final")
    sections = re.sub(r"<!-- further -->.*?<!-- /further -->", "", sections, flags=re.S)
    sections = re.sub(r"<!-- final -->.*?<!-- /final -->", "", sections, flags=re.S).strip()
    rows = load_json(defs_path)["rows"]
    bare = [r["term"] for r in rows if not r.get("doc_url")]
    if bare and not args.allow_missing_source:
        die(f"glossary row without a source; every row links its doc_url (pass --allow-missing-source to override) | terms='{', '.join(bare)}'")
    for r in rows:
        if r.get("doc_url") and not str(r["doc_url"]).startswith("https://"):
            die(f"doc_url is not an https URL | term='{r['term']}' url='{r['doc_url']}'")
    tokens = {k: tuple(v) for k, v in meta["tokens"].items()} if meta.get("tokens") else None
    t = (repo / "template" / "article.html").read_text(encoding="utf-8")
    out = (t.replace("{{tokens}}", tokens_css(tokens)).replace("{{title}}", esc(meta["title"]))
           .replace("{{description}}", esc(meta["description"])).replace("{{url}}", esc(meta["url"]))
           .replace("{{lede}}", esc(meta["lede"])).replace("{{hero}}", hero).replace("{{sections}}", sections)
           .replace("{{further}}", further).replace("{{final}}", final)
           .replace("{{glossary}}", glossary_rows(rows, meta.get("slugs", {}))))
    out = out.replace('<meta name="format-detection" content="telephone=no">',
                      GENERATOR_META + '\n<meta name="format-detection" content="telephone=no">')
    out = out.replace("</main>\n</body>", f"</main>\n{FOOTER}\n</body>")
    out_path = Path(args.out) if args.out else article / "index.html"
    out_path.write_text(out, encoding="utf-8")
    words = len(re.sub(r"<[^>]+>", " ", re.sub(r"<script.*?</script>", "", out, flags=re.S)).split())
    print(f"assembled {out_path}: {nfig} figures, {len(rows)} glossary rows, ~{words} words of prose")


if __name__ == "__main__":
    main()
