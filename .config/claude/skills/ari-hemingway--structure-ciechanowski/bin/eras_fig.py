#!/usr/bin/env python3
"""Emit a scene2d staircase timeline to stdout: one bar per era along a year axis, a year
slider with a dashed marker, and per-era text that appears only while the marker is inside
that era.

    python3 eras_fig.py --min 1988 --max 2032 --default 2026 \\
        --era '1998:2014:Bowl Championship Series:orange:Standings pick two teams.:Four bowls, then a title game.' \\
        --era '2014:2024:4-team playoff:blue:A committee ranks the top four.:Two bowls host the semifinals.' \\
        [--state name:year:label:caption]* > figures/x.json

Each --era is from:to_exclusive:label:token:line1:line2 (lines may be empty). Point prose at
era<i> or marker. The default year must equal one declared state.
"""
import argparse
import json


def parse_era(s):
    parts = s.split(":", 5)
    if len(parts) < 4:
        raise SystemExit(f"[ERROR] bad --era, expected from:to:label:token[:line1[:line2]] | era='{s}'")
    while len(parts) < 6:
        parts.append("")
    return int(parts[0]), int(parts[1]), parts[2], parts[3], parts[4], parts[5]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--era", action="append", default=[], required=True, help="from:to:label:token:line1:line2 (repeat)")
    ap.add_argument("--min", type=int, required=True, help="first year on the axis")
    ap.add_argument("--max", type=int, required=True, help="last year on the axis")
    ap.add_argument("--default", type=int, required=True, help="slider default (must equal a state)")
    ap.add_argument("--tick-every", type=int, default=10, help="axis tick spacing in years")
    ap.add_argument("--state", action="append", default=[], help="name:year:label:caption (repeat)")
    a = ap.parse_args()
    eras = [parse_era(e) for e in a.era]
    X0, X1 = a.min, a.max

    def X(y):
        return round(-10 + 20 * (y - X0) / (X1 - X0), 3)

    layers = [{"id": "axis", "kind": "segment", "from": [-10, -1.2], "to": [10, -1.2], "stroke": "grey", "width": 1}]
    first_tick = X0 + (-X0) % a.tick_every
    for y in range(first_tick, X1 + 1, a.tick_every):
        layers.append({"id": f"tick{y}", "kind": "segment", "from": [X(y), -1.2], "to": [X(y), -1.5], "stroke": "grey", "width": 1})
        layers.append({"id": f"tl{y}", "kind": "text", "at": [X(y), -1.95], "text": str(y), "size": 11, "align": "center"})
    for i, (f, t, label, tok, l1, l2) in enumerate(eras):
        y0, h = -0.9, 1.6
        inside = f"clamp(min(y-{f}+1, {t}-y),0,1)"  # 1 for f <= y < t on an integer slider
        pts = [[X(f), y0], [X(t), y0], [X(t), y0 + h], [X(f), y0 + h]]
        layers.append({"id": f"era{i}", "kind": "polygon", "points": pts, "fill": tok, "visible": 1})
        layers.append({"id": f"era{i}-hi", "kind": "polygon", "points": pts, "stroke": tok, "width": 3, "highlight": True, "visible": inside})
        if t - f >= 5:
            layers.append({"id": f"lab{i}", "kind": "text", "at": [(X(f) + X(t)) / 2, 1.2], "text": label, "size": 11, "align": "center"})
        layers.append({"id": f"name{i}", "kind": "text", "at": [-10, -2.6], "text": label, "size": 13, "align": "left", "visible": inside})
        if l1:
            layers.append({"id": f"txt{i}a", "kind": "text", "at": [-10, -3.2], "text": l1, "size": 12, "align": "left", "visible": inside})
        if l2:
            layers.append({"id": f"txt{i}b", "kind": "text", "at": [-10, -3.9], "text": l2, "size": 12, "align": "left", "visible": inside})
    marker_x = f"-10+20*(y-{X0})/{X1 - X0}"
    layers.append({"id": "marker", "kind": "segment", "from": [marker_x, -1.2], "to": [marker_x, 0.9], "stroke": "grey", "width": 1.5, "dash": [4, 3]})
    spec = {"shows": {"type": "scene2d", "view": {"x": [-10.6, 10.6], "y": [-4.4, 2.0]}, "caveats": {"simplified": True},
                      "layers": layers, "readouts": [{"id": "yr", "at": [10, -2.6], "text": "{y:.0f}", "token": "grey"}]},
            "manipulates": {"controls": [
                {"kind": "slider", "name": "y", "label": "year", "min": X0, "max": X1, "step": 1, "default": a.default,
                 "width": "long", "token": "grey", "format": "{y:.0f}"},
                {"kind": "play", "target": "y", "rate": 8, "loop": False, "autoplay": False}]},
            "notice": {"steps": "buttons", "point_at": [f"era{i}" for i in range(len(eras))] + ["marker"], "states": []}}
    for st in a.state:
        name, val, label, cap = st.split(":", 3)
        spec["notice"]["states"].append({"name": name, "y": int(val), "label": label, "caption": cap})
    print(json.dumps(spec, separators=(",", ":")))


if __name__ == "__main__":
    main()
