"""figlib: helpers that build scene2d figure specs as plain dicts, then dump them as JSON.

Import from a generator (`from figlib import *`, with this bin/ on PYTHONPATH or as the
generator's own directory) and compose:

    layers = [box("pot", -5, -1, 5, 1, fill="blue", vis=ge("y", 2024)), text("lab", 0, 1.4, "pool")]
    s = spec(view=((-10, 10), (-5, 5)), layers=layers,
             controls=[slider("y", "season", 1990, 2026, 2026, fmt="{y:.0f}"), play("y", 6)],
             states=[state("s1", "2026", "Eighteen schools share one pot.", y=2026)],
             point_at=["pot"])
    dump(s, "figures/conference.json")

The expression grammar has no comparisons; the four idioms below express them for an
integer control (see DESIGN.md "Expression grammar" in the explainers repo):
    eq(var, v)         1 when var == v
    inrange(var, f, t) 1 when f <= var <= t
    ge(var, v)         1 when var >= v
    lt(var, v)         1 when var < v
"""
import json
import math

K = math.cos(math.radians(38))  # mercator-ish x squeeze used by the map generators


def eq(var, v):
    return f"1 - min(abs({var}-{v}),1)"


def inrange(var, f, t):
    return f"clamp(min({var}-{f}+1, {t}-{var}+1),0,1)"


def ge(var, v):
    return f"clamp({var}-{v}+1,0,1)"


def lt(var, v):
    return f"clamp({v}-{var},0,1)"


def text(id, x, y, s, size=12, align="left", vis=None, **kw):
    d = {"id": id, "kind": "text", "at": [x, y], "text": s, "size": size, "align": align}
    d.update(kw)
    if vis is not None:
        d["visible"] = vis
    return d


def box(id, x0, y0, x1, y1, fill=None, stroke=None, vis=None, **kw):
    d = {"id": id, "kind": "polygon", "points": [[x0, y0], [x1, y0], [x1, y1], [x0, y1]]}
    if fill:
        d["fill"] = fill
    if stroke:
        d["stroke"] = stroke
    if vis is not None:
        d["visible"] = vis
    d.update(kw)
    return d


def seg(id, a, b, tok="grey", vis=None, **kw):
    d = {"id": id, "kind": "segment", "from": list(a), "to": list(b), "stroke": tok}
    d.update(kw)
    if vis is not None:
        d["visible"] = vis
    return d


def arrow(id, a, b, tok="grey", vis=None, **kw):
    d = {"id": id, "kind": "arrow", "from": list(a), "to": list(b), "stroke": tok, "width": 1.5}
    d.update(kw)
    if vis is not None:
        d["visible"] = vis
    return d


def circle(id, cx, cy, r, fill=None, stroke=None, vis=None, **kw):
    d = {"id": id, "kind": "circle", "cx": cx, "cy": cy, "r": r}
    if fill:
        d["fill"] = fill
    if stroke:
        d["stroke"] = stroke
    if vis is not None:
        d["visible"] = vis
    d.update(kw)
    return d


def slider(name, label, mn, mx, default, tok="grey", step=1, fmt=None, width="long", values=None):
    d = {"kind": "slider", "name": name, "label": label, "default": default, "token": tok, "width": width}
    if values:
        d["values"] = values
    else:
        d.update({"min": mn, "max": mx, "step": step})
    if fmt:
        d["format"] = fmt
    return d


def segmented(name, options, default, tok="grey"):
    return {"kind": "segmented", "name": name, "options": [{"value": v, "label": l} for v, l in options],
            "default": default, "token": tok}


def toggle(name, off, on, default, tok="grey", position="below"):
    return {"kind": "toggle", "name": name, "label": [off, on], "default": default, "token": tok, "position": position}


def play(target, rate, loop=False):
    return {"kind": "play", "target": target, "rate": rate, "loop": loop, "autoplay": False}


def state(name, label, caption, **controls):
    d = {"name": name, "label": label, "caption": caption}
    d.update(controls)
    return d


def spec(view, layers, controls, states, point_at, readouts=None, caveats=None, steps="buttons"):
    """Assemble the three top-level keys. `steps` becomes "none" automatically when every
    control is a segmented, a toggle or a chips control (one pill: the stepper would duplicate it).
    assemble.py applies the same rule, so a spec is reviewed and published with the same controls."""
    s = {"shows": {"type": "scene2d", "view": {"x": list(view[0]), "y": list(view[1])}, "layers": layers}}
    if readouts:
        s["shows"]["readouts"] = readouts
    if caveats:
        s["shows"]["caveats"] = caveats
    s["manipulates"] = {"controls": controls}
    kinds = {c["kind"] for c in controls}
    if kinds and kinds <= {"segmented", "toggle", "chips"}:
        steps = "none"
    s["notice"] = {"steps": steps, "point_at": point_at, "states": states}
    return s


def dump(s, path):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(s, separators=(",", ":")))


if __name__ == "__main__":
    print(__doc__)
