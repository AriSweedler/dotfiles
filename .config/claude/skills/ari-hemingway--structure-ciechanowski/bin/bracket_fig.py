#!/usr/bin/env python3
"""Emit a scene2d bracket figure to stdout. A segmented control `f` picks the format; every
layer of a format is visible only when f equals its value.

    python3 bracket_fig.py --formats 1,2,3 --default 2 [--token blue] [--state name:value:label:caption]* > figures/x.json

Formats: 0: 2 teams  1: 4 teams  2: 12 teams, 4 byes  3: 16 teams  4: 24 teams, 8 byes.
When byes == (teams-byes)/2 each second-round game is one bye team against one first-round
winner (the real 12- and 24-team shapes); otherwise a plain binary tree. A readout counts
the games. The default must equal one declared state.
"""
import argparse
import json
import math

FORMATS = {0: (2, 0, "2 teams"), 1: (4, 0, "4 teams"), 2: (12, 4, "12 teams"), 3: (16, 0, "16 teams"), 4: (24, 8, "24 teams")}
X0, X1, H = -10.0, 8.6, 10.4


def vis(v):
    return f"1 - min(abs(f-{v}),1)"


def tree(v, leaves, tok, L, pre, x_start, ncols):
    """leaves: (y, label|None) at column x_start; draws a binary tree rightward over ncols columns."""
    dx = (X1 - x_start) / ncols
    cur = leaves
    for ci in range(ncols):
        x = x_start + ci * dx
        nxt = []
        for j in range(0, len(cur), 2):
            (ya, la), (yb, lb) = cur[j], cur[j + 1]
            for y, lab in ((ya, la), (yb, lb)):
                L.append({"id": f"{pre}h{ci}-{len(L)}", "kind": "segment", "from": [x, y], "to": [x + dx - 0.4, y], "stroke": tok, "width": 1.3, "visible": vis(v)})
                if lab is not None:
                    L.append({"id": f"{pre}t{ci}-{len(L)}", "kind": "text", "at": [x - 0.3, y], "text": lab, "size": 11, "align": "right", "visible": vis(v)})
            ym = (ya + yb) / 2
            L.append({"id": f"{pre}v{ci}-{len(L)}", "kind": "segment", "from": [x + dx - 0.4, ya], "to": [x + dx - 0.4, yb], "stroke": tok, "width": 1.3, "visible": vis(v)})
            nxt.append((ym, None))
        cur = nxt
    return (X1 - 0.4, cur[0][0])


def seed_order(n):
    o = [1]
    while len(o) < n:
        m = len(o) * 2 + 1
        o = [x for pair in zip(o, [m - x for x in o]) for x in pair]
    return o


def layers_for(v, tok):
    teams, byes, _ = FORMATS[v]
    L = []
    pre = f"f{v}-"
    n1 = teams - byes
    if byes and byes == n1 // 2:
        nb = byes
        hb = H / nb
        r1 = list(range(byes + 1, teams + 1))
        pairs = [(r1[i], r1[-1 - i]) for i in range(n1 // 2)]
        dx1 = 3.2
        leaves = []
        for k in range(1, nb + 1):
            top = H / 2 - (k - 1) * hb
            yb, y1, y2 = top - hb * 0.22, top - hb * 0.52, top - hb * 0.82
            a, b = pairs[nb - k]
            L.append({"id": f"{pre}bye{k}", "kind": "text", "at": [X0 + dx1 - 0.3, yb], "text": f"{k}  (bye)", "size": 11, "align": "right", "visible": vis(v)})
            for y, s in ((y1, a), (y2, b)):
                L.append({"id": f"{pre}s{s}", "kind": "text", "at": [X0 - 0.3, y], "text": f"{s}", "size": 11, "align": "right", "visible": vis(v)})
                L.append({"id": f"{pre}r1-{s}", "kind": "segment", "from": [X0, y], "to": [X0 + dx1 - 0.4, y], "stroke": tok, "width": 1.3, "visible": vis(v)})
            L.append({"id": f"{pre}r1v{k}", "kind": "segment", "from": [X0 + dx1 - 0.4, y1], "to": [X0 + dx1 - 0.4, y2], "stroke": tok, "width": 1.3, "visible": vis(v)})
            ym = (y1 + y2) / 2
            L.append({"id": f"{pre}r1w{k}", "kind": "segment", "from": [X0 + dx1 - 0.4, ym], "to": [X0 + dx1, ym], "stroke": tok, "width": 1.3, "visible": vis(v)})
            leaves += [(yb, None), (ym, None)]
        xe, ye = tree(v, leaves, tok, L, pre, X0 + dx1, int(math.log2(nb)) + 1)
    else:
        o = seed_order(teams)
        ys = [H / 2 - (i + 0.5) * H / teams for i in range(teams)]
        leaves = [(ys[i], str(o[i])) for i in range(teams)]
        xe, ye = tree(v, leaves, tok, L, pre, X0, int(math.log2(teams)))
    L.append({"id": f"{pre}champ", "kind": "text", "at": [xe + 0.5, ye], "text": "champion", "size": 12, "align": "left", "visible": vis(v)})
    return L


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--formats", default="1,2,3", help="comma list of format ids (0-4)")
    ap.add_argument("--default", type=int, default=2, help="format shown first (must equal a state)")
    ap.add_argument("--token", default="blue", help="palette token for the lines")
    ap.add_argument("--state", action="append", default=[], help="name:value:label:caption (repeat)")
    a = ap.parse_args()
    fs = [int(x) for x in a.formats.split(",")]
    layers = []
    for v in fs:
        layers += layers_for(v, a.token)
    games = " + ".join(f"({vis(v)})*{FORMATS[v][0] - 1}" for v in fs)
    spec = {"shows": {"type": "scene2d", "view": {"x": [-11.2, 11.2], "y": [-6, 6]}, "layers": layers,
                      "readouts": [{"id": "games", "at": [-10.9, -5.6], "text": "games: {" + games + ":.0f}", "token": "grey"}]},
            "manipulates": {"controls": [{"kind": "segmented", "name": "f",
                                          "options": [{"value": v, "label": FORMATS[v][2]} for v in fs],
                                          "default": a.default, "token": a.token}]},
            "notice": {"steps": "none", "point_at": [], "states": []}}
    for st in a.state:
        name, val, label, cap = st.split(":", 3)
        spec["notice"]["states"].append({"name": name, "f": int(val), "label": label, "caption": cap})
    print(json.dumps(spec, separators=(",", ":")))


if __name__ == "__main__":
    main()
