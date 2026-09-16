"""Measure every table in a Google Docs PDF export, from the export alone (stdlib only).

The Docs API reports no layout, but the PDF export does: it emits one clip rectangle per table
cell in page points with y running down from the top, `x y w h re W* n`. Cells are clustered
into tables by vertical adjacency. A segment that starts at the top margin continues the
previous page's last table, and its first row is the header row Docs repeats on every page.

Output: one JSON object per table on stdout, in document order:
  {"table": n, "pages": [...], "rows": r, "cols": c,
   "height_pt": rendered height summed over pages, repeated headers included,
   "content_height_pt": the same minus repeated header rows,
   "row_heights_pt": [...]}
A row Docs splits across a page break counts once per page, so `rows` can exceed the
table's true row count by one per split; the heights stay exact.
"""
import argparse
import json
import re
import sys
import zlib
from pathlib import Path

from at_log import die, log_info

OBJ_RE = re.compile(rb"(\d+) 0 obj(.*?)endobj", re.S)
STREAM_RE = re.compile(rb"stream\r?\n(.*?)\r?\nendstream", re.S)
CLIP_RE = re.compile(r"(-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (-?[\d.]+) re\s+W\* n")
GAP_PT = 3.0
TOP_MARGIN_PT = 72.0


def parse_args():
    parser = argparse.ArgumentParser(description="Measure every table in a Google Docs PDF export.")
    parser.add_argument("--pdf", required=True, help="PDF exported from Google Docs")
    return parser.parse_args()


def objects(data):
    return {int(m.group(1)): m.group(2) for m in OBJ_RE.finditer(data)}


def inflate(body):
    m = STREAM_RE.search(body)
    if not m:
        return b""
    raw = m.group(1)
    if b"/FlateDecode" not in body:
        return raw
    try:
        return zlib.decompress(raw)
    except zlib.error:
        return zlib.decompressobj().decompress(raw)


def page_ids(objs):
    roots = [b for b in objs.values() if b"/Type /Pages" in b and b"/Kids" in b]
    if not roots:
        die("no Pages root in PDF | hint='is this a Google Docs export?'")
    kids = re.search(rb"/Kids \[(.*?)\]", roots[0], re.S).group(1)
    return [int(k) for k in re.findall(rb"(\d+) 0 R", kids)]


def page_content(objs, page_id):
    body = objs[page_id]
    refs = re.search(rb"/Contents (\[.*?\]|\d+ 0 R)", body, re.S)
    if not refs:
        return ""
    ids = [int(k) for k in re.findall(rb"(\d+) 0 R", refs.group(1))]
    return b"\n".join(inflate(objs[i]) for i in ids).decode("latin-1")


def cells_on_page(content):
    cells = []
    for m in CLIP_RE.finditer(content):
        x, y, w, h = (float(v) for v in m.groups())
        if w > 0 and h > 0:
            cells.append({"x": x, "y": y, "w": w, "h": h})
    return cells


def cluster(cells):
    tables = []
    for cell in sorted(cells, key=lambda c: (c["y"], c["x"])):
        for table in tables:
            top = min(c["y"] for c in table)
            bottom = max(c["y"] + c["h"] for c in table)
            if cell["y"] <= bottom + GAP_PT and cell["y"] + cell["h"] >= top - GAP_PT:
                table.append(cell)
                break
        else:
            tables.append([cell])
    return tables


def rows_of(cells):
    by_y = {}
    for c in cells:
        key = round(c["y"], 1)
        by_y[key] = max(by_y.get(key, 0.0), c["h"])
    return [round(by_y[k], 2) for k in sorted(by_y)]


def summarize(segments):
    first_rows = rows_of(segments[0][1])
    header_h = first_rows[0]
    row_heights = list(first_rows)
    repeated = 0.0
    for _, cells in segments[1:]:
        rows = rows_of(cells)
        if rows and abs(rows[0] - header_h) < 0.01:
            repeated += rows[0]
            rows = rows[1:]
        row_heights.extend(rows)
    height = sum(sum(rows_of(cells)) for _, cells in segments)
    first_y = min(c["y"] for c in segments[0][1])
    cols = len({round(c["x"], 1) for c in segments[0][1] if abs(c["y"] - first_y) < 0.01})
    return {
        "pages": [p for p, _ in segments],
        "rows": len(row_heights),
        "cols": cols,
        "height_pt": round(height, 2),
        "content_height_pt": round(height - repeated, 2),
        "row_heights_pt": row_heights,
    }


def collect_tables(objs):
    tables = []
    for page_num, pid in enumerate(page_ids(objs), start=1):
        segments = [s for s in cluster(cells_on_page(page_content(objs, pid))) if len(s) > 1]
        segments.sort(key=lambda s: min(c["y"] for c in s))
        for seg in segments:
            top = min(c["y"] for c in seg)
            continues = tables and top <= TOP_MARGIN_PT + GAP_PT and tables[-1][-1][0] == page_num - 1
            if continues:
                tables[-1].append((page_num, seg))
            else:
                tables.append([(page_num, seg)])
    return tables


def main():
    args = parse_args()
    pdf = Path(args.pdf)
    if not pdf.is_file():
        die(f"pdf not found | pdf='{pdf}'")
    objs = objects(pdf.read_bytes())
    tables = collect_tables(objs)
    log_info(f"measured tables | pdf='{pdf}' pages='{len(page_ids(objs))}' tables='{len(tables)}'")
    for n, segments in enumerate(tables, start=1):
        out = {"table": n}
        out.update(summarize(segments))
        sys.stdout.write(json.dumps(out) + "\n")


if __name__ == "__main__":
    main()
