#!/usr/bin/env python3
"""Emit a scene2d pay ladder to stdout: horizontal rungs stacked upward, each appearing when
the year slider reaches its start year. A later figure reuses the same rungs and adds one.

    python3 ladder_fig.py --min 1950 --max 2026 --default 2026 \\
        --rung '1956:scholarship: tuition, fees, room, board, books:grey:school' \\
        --rung '2021:education awards, up to $5,980 a year:green:school' \\
        [--state name:year:label:caption]* > figures/x.json

Each --rung is year:label:token:source; the label may contain colons (the last two fields are
token and source). A fractional year (2021.5) orders two rungs of one year. Point prose at box<i>.
"""
import argparse
import json


def parse_rung(s):
    head, tok, src = s.rsplit(":", 2)
    yr, label = head.split(":", 1)
    return float(yr), label, tok, src


def visibility(yr):
    if yr == int(yr):
        return f"clamp(floor(y)-{int(yr)}+1,0,1)"
    return f"clamp(y-{yr}+0.5,0,1)"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rung", action="append", default=[], required=True, help="year:label:token:source (repeat, bottom first)")
    ap.add_argument("--min", type=int, required=True, help="slider minimum year")
    ap.add_argument("--max", type=int, required=True, help="slider maximum year")
    ap.add_argument("--default", type=int, required=True, help="slider default (must equal a state)")
    ap.add_argument("--state", action="append", default=[], help="name:year:label:caption (repeat)")
    a = ap.parse_args()
    rungs = [parse_rung(r) for r in a.rung]
    layers = []
    h, gap = 1.0, 0.25
    for i, (yr, label, tok, src) in enumerate(rungs):
        y0 = -4.2 + i * (h + gap)
        vis = visibility(yr)
        layers.append({"id": f"box{i}", "kind": "polygon", "points": [[-9, y0], [3, y0], [3, y0 + h], [-9, y0 + h]], "fill": tok, "visible": vis})
        layers.append({"id": f"lab{i}", "kind": "text", "at": [-8.7, y0 + h / 2], "text": label, "size": 12, "align": "left", "visible": vis})
        layers.append({"id": f"src{i}", "kind": "text", "at": [3.4, y0 + h / 2], "text": f"from {src}, {int(yr)}", "size": 11, "align": "left", "visible": vis})
    layers.append({"id": "baseline", "kind": "segment", "from": [-9, -4.45], "to": [9, -4.45], "stroke": "grey", "width": 1})
    spec = {"shows": {"type": "scene2d", "view": {"x": [-10, 10], "y": [-5, 3.5]}, "caveats": {"simplified": True},
                      "layers": layers, "readouts": [{"id": "year", "at": [-9, 3.0], "text": "{y:.0f}", "token": "grey"}]},
            "manipulates": {"controls": [
                {"kind": "slider", "name": "y", "label": "year", "min": a.min, "max": a.max, "step": 1, "default": a.default,
                 "width": "long", "token": "grey", "format": "{y:.0f}"},
                {"kind": "play", "target": "y", "rate": 6, "loop": False, "autoplay": False}]},
            "notice": {"steps": "buttons", "point_at": [f"box{i}" for i in range(len(rungs))], "states": []}}
    for st in a.state:
        name, val, label, cap = st.split(":", 3)
        spec["notice"]["states"].append({"name": name, "y": int(val), "label": label, "caption": cap})
    print(json.dumps(spec, separators=(",", ":")))


if __name__ == "__main__":
    main()
