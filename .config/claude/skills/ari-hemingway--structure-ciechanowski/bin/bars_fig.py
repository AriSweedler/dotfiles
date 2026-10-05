#!/usr/bin/env python3
"""Emit a scene2d horizontal bar chart (dollars as lengths) to stdout.

    python3 bars_fig.py --max 100 --unit '$M' --row 'ACC:47.1:blue' --row 'Big 12:19.9:orange' [--title '...'] > figures/x.json

Each --row is label:value:token; bars share one scale (--max). A control-less figure: the
assembler sets notice.steps to none. Point prose at bar<i>.
"""
import argparse
import json


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--row", action="append", default=[], required=True, help="label:value:token (repeat)")
    ap.add_argument("--max", type=float, default=100, help="value drawn as the full bar length")
    ap.add_argument("--unit", default="$M", help="unit suffix for the value label ($M prints as $<v>M)")
    ap.add_argument("--title", default="", help="optional title text above the bars")
    a = ap.parse_args()
    rows = [r.split(":") for r in a.row]
    n = len(rows)
    H = 8.0
    h = H / n * 0.62
    layers = []
    for i, (label, val, tok) in enumerate(rows):
        val = float(val)
        y = 3.6 - i * (H / n)
        x1 = -5 + 10 * val / a.max
        layers.append({"id": f"bar{i}", "kind": "polygon",
                       "points": [[-5, y - h / 2], [x1, y - h / 2], [x1, y + h / 2], [-5, y + h / 2]], "fill": tok})
        layers.append({"id": f"lab{i}", "kind": "text", "at": [-5.3, y], "text": label, "size": 12, "align": "right"})
        value_text = f"${val:g}M" if a.unit == "$M" else f"{val:g}{a.unit}"
        layers.append({"id": f"val{i}", "kind": "text", "at": [x1 + 0.25, y], "text": value_text, "size": 12, "align": "left"})
    layers.append({"id": "axis", "kind": "segment", "from": [-5, -4.6], "to": [-5, 4.4], "stroke": "grey", "width": 1})
    if a.title:
        layers.append({"id": "title", "kind": "text", "at": [-5, 4.9], "text": a.title, "size": 12, "align": "left"})
    spec = {"shows": {"type": "scene2d", "view": {"x": [-10, 8], "y": [-5, 5.4]}, "layers": layers},
            "manipulates": {"controls": []},
            "notice": {"steps": "none", "point_at": [f"bar{i}" for i in range(n)], "states": []}}
    print(json.dumps(spec, separators=(",", ":")))


if __name__ == "__main__":
    main()
