"""Plan column widths for every table in a Google Doc so each table is as short as possible.

Input: a Docs API document JSON (body.content, documentStyle). Output: one JSON object per
table on stdout, in document order:
  {"start", "cols", "rows", "text_width_pt", "mins_pt", "widest_tokens",
   "current_pt", "current_lines", "predicted_current_pt",
   "best_pt", "best_lines", "predicted_best_pt", "feasible", "deficit_pt", "source"}
where source is "model" or "override".

Model. Docs renders imported markdown in Arial 11pt, metric-compatible with Helvetica, so the
AFM advances below predict each character; the header row is bold (Helvetica-Bold advances);
code spans render in a monospace face at 600/1000 em. Each cell has 5pt padding per side. A
cell's height is its greedy word-wrap line count, a row is its tallest cell, and the table is the
sum over rows. Points per line and per row come from measuring PDF exports of published Docs.

Hard rule: no column is narrower than its widest unbreakable token plus padding, so nothing
breaks mid-word. If those minimums exceed the text width the table cannot fit: the plan says so
(feasible=false, deficit_pt, widest_tokens) and the caller decides whether to fold a column or
shorten a token. Nothing is guessed.

Search. Start from widths proportional to each column's total text, then for every ordered pair
of columns try every whole-point transfer from one to the other, keep the transfer that lowers
the modeled line count most (ties move width toward the earlier column), and repeat until no
transfer helps. With two columns this is the exhaustive scan of every split.
"""
import argparse
import json
from pathlib import Path

from at_log import die, log_info, log_warn

FONT_SIZE_PT = 11.0
LINE_HEIGHT_PT = 15.15  # measured: rendered table height minus row padding, per modeled line
CELL_PAD_SIDE_PT = 5.0
CELL_PAD_VERTICAL_PT = 10.0  # 5pt top + 5pt bottom per row
MONO_ADVANCE = 600
DEFAULT_ADVANCE = 556
SPACE_ADVANCE = 278
CHIP_ICON_PT = 20.0  # a smart chip draws an icon before its title
MONO_FONT_NAMES = ("Mono", "Courier", "Consolas", "Menlo")
STEP_PT = 1
MAX_PASSES = 200

HELVETICA = {
    " ": 278, "!": 278, '"': 355, "#": 556, "$": 556, "%": 889, "&": 667, "'": 191, "(": 333, ")": 333,
    "*": 389, "+": 584, ",": 278, "-": 333, ".": 278, "/": 278, "0": 556, "1": 556, "2": 556, "3": 556,
    "4": 556, "5": 556, "6": 556, "7": 556, "8": 556, "9": 556, ":": 278, ";": 278, "<": 584, "=": 584,
    ">": 584, "?": 556, "@": 1015, "A": 667, "B": 667, "C": 722, "D": 722, "E": 667, "F": 611, "G": 778,
    "H": 722, "I": 278, "J": 500, "K": 667, "L": 556, "M": 833, "N": 722, "O": 778, "P": 667, "Q": 778,
    "R": 722, "S": 667, "T": 611, "U": 722, "V": 667, "W": 944, "X": 667, "Y": 667, "Z": 611, "[": 278,
    "\\": 278, "]": 278, "^": 469, "_": 556, "`": 222, "a": 556, "b": 556, "c": 500, "d": 556, "e": 556,
    "f": 278, "g": 556, "h": 556, "i": 222, "j": 222, "k": 500, "l": 222, "m": 833, "n": 556, "o": 556,
    "p": 556, "q": 556, "r": 333, "s": 500, "t": 278, "u": 556, "v": 500, "w": 722, "x": 500, "y": 500,
    "z": 500, "{": 334, "|": 260, "}": 334, "~": 584,
}
HELVETICA_BOLD = {
    " ": 278, "!": 333, '"': 474, "#": 556, "$": 556, "%": 889, "&": 722, "'": 238, "(": 333, ")": 333,
    "*": 389, "+": 584, ",": 278, "-": 333, ".": 278, "/": 278, "0": 556, "1": 556, "2": 556, "3": 556,
    "4": 556, "5": 556, "6": 556, "7": 556, "8": 556, "9": 556, ":": 333, ";": 333, "<": 584, "=": 584,
    ">": 584, "?": 611, "@": 975, "A": 722, "B": 722, "C": 722, "D": 722, "E": 667, "F": 611, "G": 778,
    "H": 722, "I": 278, "J": 556, "K": 722, "L": 611, "M": 833, "N": 722, "O": 778, "P": 667, "Q": 778,
    "R": 722, "S": 667, "T": 611, "U": 722, "V": 667, "W": 944, "X": 667, "Y": 667, "Z": 611, "[": 333,
    "\\": 278, "]": 333, "^": 584, "_": 556, "`": 333, "a": 556, "b": 611, "c": 556, "d": 611, "e": 556,
    "f": 333, "g": 611, "h": 611, "i": 278, "j": 278, "k": 556, "l": 278, "m": 889, "n": 611, "o": 611,
    "p": 611, "q": 611, "r": 389, "s": 556, "t": 333, "u": 611, "v": 556, "w": 778, "x": 556, "y": 556,
    "z": 500, "{": 389, "|": 280, "}": 389, "~": 584,
}


def is_mono(run):
    family = run.get("textStyle", {}).get("weightedFontFamily", {}).get("fontFamily", "")
    return any(name in family for name in MONO_FONT_NAMES)


def text_width_pt(text, mono, bold, size):
    if mono:
        return len(text) * MONO_ADVANCE * size / 1000
    table = HELVETICA_BOLD if bold else HELVETICA
    return sum(table.get(ch, DEFAULT_ADVANCE) for ch in text) * size / 1000


def paragraph_tokens(paragraph, header):
    """(text, width_pt) for every space-separated token in one paragraph, in order."""
    tokens = []
    for element in paragraph.get("elements", []):
        run = element.get("textRun")
        if run is None:
            chip = element.get("richLink")
            if chip is not None:
                title = chip.get("richLinkProperties", {}).get("title", "") or "chip"
                tokens.append((title, CHIP_ICON_PT + text_width_pt(title, False, header, FONT_SIZE_PT)))
            continue
        style = run.get("textStyle", {})
        size = style.get("fontSize", {}).get("magnitude", FONT_SIZE_PT)
        bold = header or bool(style.get("bold"))
        for word in run.get("content", "").rstrip("\n").split(" "):
            if word:
                tokens.append((word, text_width_pt(word, is_mono(run), bold, size)))
    return tokens


def wrap_lines(widths, avail_pt):
    """Greedy word wrap; a token wider than the column still costs the extra lines Docs adds."""
    if not widths:
        return 1
    space = SPACE_ADVANCE * FONT_SIZE_PT / 1000
    lines, current = 1, 0.0
    for width in widths:
        if current == 0:
            current = width
        elif current + space + width <= avail_pt:
            current += space + width
        else:
            lines += 1
            current = width
    overflow = sum(int(-(-width // avail_pt)) - 1 for width in widths if width > avail_pt)
    return lines + overflow


def cell_paragraphs(cell):
    return [block["paragraph"] for block in cell.get("content", []) if "paragraph" in block]


def table_grid(table):
    """Per row, per column: a list of paragraphs, each a list of token widths."""
    grid = []
    for row_index, row in enumerate(table["tableRows"]):
        header = row_index == 0
        grid.append([[[w for _, w in paragraph_tokens(p, header)] for p in cell_paragraphs(cell)] for cell in row["tableCells"]])
    return grid


def widest_tokens(table):
    """Per column, the (text, width_pt) of the widest single token anywhere in that column."""
    cols = table["columns"]
    best = [("", 0.0)] * cols
    for row_index, row in enumerate(table["tableRows"]):
        for col, cell in enumerate(row["tableCells"][:cols]):
            for paragraph in cell_paragraphs(cell):
                for text, width in paragraph_tokens(paragraph, row_index == 0):
                    if width > best[col][1]:
                        best[col] = (text, width)
    return best


def cell_lines(paragraphs, avail_pt):
    return sum(wrap_lines(widths, avail_pt) for widths in paragraphs) or 1


def table_lines(grid, widths):
    total = 0
    for row in grid:
        total += max(cell_lines(paragraphs, widths[col] - 2 * CELL_PAD_SIDE_PT) for col, paragraphs in enumerate(row[: len(widths)]))
    return total


def predicted_height_pt(grid, widths):
    return round(table_lines(grid, widths) * LINE_HEIGHT_PT + len(grid) * CELL_PAD_VERTICAL_PT, 1)


def column_totals(grid, cols):
    totals = [0.0] * cols
    for row in grid:
        for col, paragraphs in enumerate(row[:cols]):
            totals[col] += sum(sum(widths) for widths in paragraphs)
    return totals


def proportional_start(mins, totals, text_width):
    """Whole-point widths that honour every minimum and sum to the text width."""
    spare = text_width - sum(mins)
    weight_sum = sum(totals) or 1.0
    widths = [int(mins[col] + spare * totals[col] / weight_sum) for col in range(len(mins))]
    remainder = int(text_width) - sum(widths)
    col = 0
    while remainder > 0:
        widths[col % len(widths)] += 1
        remainder -= 1
        col += 1
    return widths


def best_transfer(grid, widths, mins, src, dst):
    """The transfer amount from src to dst (1pt steps) with the fewest lines; None if none helps."""
    base = table_lines(grid, widths)
    slack = int(widths[src] - mins[src])
    best = None
    for amount in range(STEP_PT, slack + 1, STEP_PT):
        trial = list(widths)
        trial[src] -= amount
        trial[dst] += amount
        lines = table_lines(grid, trial)
        better = lines < base if best is None else lines < best[0]
        tie_left = lines == (base if best is None else best[0]) and dst < src
        if better or (tie_left and best is None and lines < base + 1 and lines <= base):
            best = (lines, amount) if better or lines < base else best
            if lines == base and dst < src and best is None:
                best = (lines, amount)
    return best


def optimize(grid, mins, text_width):
    """Pairwise exhaustive transfers until no transfer lowers the modeled line count."""
    cols = len(mins)
    widths = proportional_start(mins, column_totals(grid, cols), text_width)
    lines = table_lines(grid, widths)
    for _ in range(MAX_PASSES):
        move = None
        for src in range(cols):
            for dst in range(cols):
                if src == dst:
                    continue
                found = best_transfer(grid, widths, mins, src, dst)
                if found is None:
                    continue
                if move is None or found[0] < move[0] or (found[0] == move[0] and dst < move[2]):
                    move = (found[0], src, dst, found[1])
        if move is None or move[0] > lines:
            break
        if move[0] == lines and not move[2] < move[1]:
            break
        lines = move[0]
        widths[move[1]] -= move[3]
        widths[move[2]] += move[3]
        if move[0] == lines and move[2] < move[1]:
            continue
    return widths, lines


def current_widths(table, cols, text_width):
    props = table.get("tableStyle", {}).get("tableColumnProperties", [])
    widths = []
    for col in range(cols):
        magnitude = props[col].get("width", {}).get("magnitude") if col < len(props) else None
        widths.append(float(magnitude) if magnitude else text_width / cols)
    return widths


def parse_overrides(values):
    overrides = {}
    for value in values:
        start, sep, rest = value.partition(":")
        if not sep or not start.strip().isdigit():
            die(f"invalid --override | override='{value}' expected='START:w1,w2,...'")
        try:
            widths = [float(w) for w in rest.split(",") if w.strip()]
        except ValueError:
            die(f"invalid --override widths | override='{value}' expected='comma-separated points'")
        overrides[int(start)] = widths
    return overrides


def plan_table(block, text_width, overrides):
    table = block["table"]
    cols = table["columns"]
    grid = table_grid(table)
    widest = widest_tokens(table)
    mins = [width + 2 * CELL_PAD_SIDE_PT + STEP_PT for _, width in widest]
    current = current_widths(table, cols, text_width)
    plan = {
        "start": block["startIndex"],
        "cols": cols,
        "rows": len(grid),
        "text_width_pt": text_width,
        "mins_pt": [round(m, 1) for m in mins],
        "widest_tokens": [text for text, _ in widest],
        "current_pt": [round(w, 1) for w in current],
        "current_lines": table_lines(grid, current),
        "predicted_current_pt": predicted_height_pt(grid, current),
        "source": "model",
        "feasible": True,
        "deficit_pt": 0.0,
    }
    if block["startIndex"] in overrides:
        widths = overrides[block["startIndex"]]
        if len(widths) != cols:
            die(f"override column count mismatch | start='{block['startIndex']}' given='{len(widths)}' cols='{cols}'")
        plan.update(source="override", best_pt=widths, best_lines=table_lines(grid, widths), predicted_best_pt=predicted_height_pt(grid, widths))
        return plan
    deficit = sum(mins) - text_width
    if deficit > 0:
        plan.update(feasible=False, deficit_pt=round(deficit, 1), best_pt=None, best_lines=None, predicted_best_pt=None)
        return plan
    widths, lines = optimize(grid, mins, text_width)
    if lines > plan["current_lines"]:
        widths, lines = [int(round(w)) for w in current], plan["current_lines"]
    plan.update(best_pt=[float(w) for w in widths], best_lines=lines, predicted_best_pt=predicted_height_pt(grid, widths))
    return plan


def text_width_from(doc):
    style = doc.get("documentStyle", {})
    try:
        return float(style["pageSize"]["width"]["magnitude"]) - float(style["marginLeft"]["magnitude"]) - float(style["marginRight"]["magnitude"])
    except KeyError:
        die("documentStyle lacks pageSize or margins | hint='fetch with fields including documentStyle'")


def log_plan(plan):
    if not plan["feasible"]:
        tokens = ", ".join(f"col{col}='{text}'" for col, text in enumerate(plan["widest_tokens"]))
        log_warn(f"table cannot fit | start='{plan['start']}' cols='{plan['cols']}' mins_pt='{plan['mins_pt']}' text_width_pt='{plan['text_width_pt']}' deficit_pt='{plan['deficit_pt']}' widest_tokens='{tokens}' hint='fold a column or shorten a token'")
        return
    if plan["source"] == "override":
        log_info(f"table widths overridden | start='{plan['start']}' widths_pt='{plan['best_pt']}' lines='{plan['best_lines']}'")
        return
    log_info(f"table widths planned | start='{plan['start']}' cols='{plan['cols']}' current='{plan['current_pt']} pt, {plan['current_lines']} lines' best='{plan['best_pt']} pt, {plan['best_lines']} lines'")


def parse_args():
    parser = argparse.ArgumentParser(description="Plan the column widths that make every table in a Google Doc shortest, with no mid-word breaks.")
    parser.add_argument("--doc-json", dest="doc_json", required=True, help="Docs API document JSON (body.content and documentStyle)")
    parser.add_argument("--override", action="append", default=[], help='"START:w1,w2,..." explicit widths in points for the table at START (repeatable; logged)')
    return parser.parse_args()


def main():
    args = parse_args()
    doc_path = Path(args.doc_json)
    if not doc_path.is_file():
        die(f"doc json not found | doc_json='{doc_path}'")
    doc = json.loads(doc_path.read_text(encoding="utf-8"))
    overrides = parse_overrides(args.override)
    text_width = text_width_from(doc)
    tables = [block for block in doc.get("body", {}).get("content", []) if "table" in block]
    known = {block["startIndex"] for block in tables}
    for start in overrides:
        if start not in known:
            die(f"override names no table | start='{start}' tables='{sorted(known)}'")
    for block in tables:
        plan = plan_table(block, text_width, overrides)
        log_plan(plan)
        print(json.dumps(plan))
    log_info(f"tables planned | count='{len(tables)}' text_width_pt='{text_width}'")


if __name__ == "__main__":
    main()
