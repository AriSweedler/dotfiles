"""Asides for a published Google Doc: optional content in its own tab, reached from a marker in the body.

Draft dialect (/ari-hemingway--structure-aside): a marker `([aside n ℹ️](#aside-n))` in the body, a
section `# Aside n: <title>` after `# Useful links`, and, anywhere else, references `[<title>](#aside-n)`
whose text is the aside's title. Two modes:

  --split    strip every `# Aside n:` section out of the body before the Drive markdown upload, after
             checking markers, sections, references, and tab-title length, so nothing uploads on a
             draft the rebuild would reject.
  --rebuild  after the upload: delete stale `Aside n:` tabs, add one tab per section, fill it, chip its
             Drive links, and point every marker and reference at its tab. The Drive re-import deletes
             every tab but the first and drops tab links, so this runs after every publish. Without
             --execute it is a dry run: the lookups run and the batches print, and nothing is sent.

Each aside tab reads: `← Return to main article` (italic, rule below) / `Aside n: <title>` (H1) / the
section body with an empty paragraph between blocks, as the import lays out the main tab, and one empty
paragraph before the footer rule / `← Return to main article` (italic, rule above). The Docs API has no
horizontal-rule or bookmark request: the rules are paragraph borders, and the return link lands on the
marker's nearest preceding heading in the first tab; /ari-hemingway--structure-bookmark moves it onto
the marker afterwards when its setup passes.

Aside bodies:
  - paragraphs; bold markers are dropped
  - `code` spans: Roboto Mono in #188038, the green the import gives the main tab's
  - [text](url) links: a Drive URL becomes one smart chip, a `#aside-m` reference a link to that tab;
    a code span in other link text stays Roboto Mono in the link's colour, as in the main tab
  - fenced code blocks: one paragraph per block, lines joined by soft line breaks, Roboto Mono, shaded
    like a Docs code block
  - diagrams: a line holding only `[![alt](https://mermaid.ink/img/…?width=620)](https://mermaid.live/view#…)`
    (/ari-hemingway--format-gdoc) becomes an inline image linked to its view. Alt text is dropped (the
    Docs API has no request for it); a `base64:` URL over insertInlineImage's 2 kB limit is re-encoded in
    mermaid.ink's shorter `pako:` form of the same state.
Lists, tables, `##` headings, a `mermaid` fence, an empty fence, and any other image fail the split by
aside number; a `# ` heading or the footer ends the section.
"""
import argparse
import base64
import binascii
import json
import os
import re
import zlib
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from skill_log import die, log_info, log_warn
from gdoc_api import (
    FIRST_TAB,
    RETURN_TEXT,
    batch_update,
    check_gws,
    doc_id_from,
    fetch_doc,
    first_tab,
    gws_json,
    marker_text,
    paragraphs,
    run_link,
    tab_by_id,
    text_runs,
)

TAB_TITLE_MAX_UNITS = 50  # Docs: "The tab title cannot be longer than 50 characters"
SECTION_RE = re.compile(r"^# Aside (\d+): (.+?)\s*$")
ANCHOR_LINK_RE = re.compile(r"\[([^\]]+)\]\(#aside-(\d+)\)")
INLINE_RE = re.compile(r"`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)")
BOLD_RE = re.compile(r"\*\*([^*]+)\*\*")
TITLE_MARKUP = (
    (re.compile(r"`([^`]+)`"), r"\1"),
    (re.compile(r"\[([^\]]+)\]\([^)]*\)"), r"\1"),
    (BOLD_RE, r"\1"),
)
H1_RE = re.compile(r"^# ")
FOOTER_PREFIX = "🤖🌸"
FENCE = "```"
MERMAID_FENCE = "```mermaid"
UNSUPPORTED = (
    (re.compile(r"^\s*([-*+]|\d+\.)\s"), "list"),
    (re.compile(r"^\s*\|"), "table"),
    (re.compile(r"^#"), "heading"),
)
IMAGE_LINE_RE = re.compile(r"^\[!\[([^\]]*)\]\((\S+?)\)\]\((\S+?)\)$")
IMAGE_FORM = "[![alt](https://mermaid.ink/img/…)](https://mermaid.live/view#…)"
# Same invariant as gdoc_finish.zsh: a diagram opens fullscreen, not in the editor.
IMAGE_LINK_PREFIX = "https://mermaid.live/view#"
IMAGE_URI_MAX_BYTES = 2048  # Docs insertInlineImage: "The URI can be at most 2 kB in length"
IMAGE_WIDTH_MAX_PX = 624  # 468 pt of Letter text width at Docs' 0.75 pt per px; bake's contract is 620
IMAGE_TYPES = ("jpeg", "png")  # mermaid.ink's ?type= values that insertInlineImage accepts; jpeg is the default
CODE_SPAN_RE = re.compile(r"`[^`]+`")
URLSAFE_TO_STANDARD = str.maketrans("-_", "+/")
INK_IMG_PREFIX = "https://mermaid.ink/img/"
INK_BASE64_PREFIX = "https://mermaid.ink/img/base64:"
INK_PAKO_PREFIX = "https://mermaid.ink/img/pako:"
# Same allowlist as gdoc_finish.zsh: insertRichLink accepts Drive file and folder URLs only.
DRIVE_LINK_RE = re.compile(r"^https://(docs|drive)\.google\.com/(.*/d/|drive/folders/)([A-Za-z0-9_-]+)")
ANCHOR_PREFIX = "#aside-"
STALE_TAB_RE = re.compile(r"^Aside \d+:")
MONO_FONT = "Roboto Mono"
# #188038, read off the main tab: Drive's import gives inline code this colour, the API gives none.
INLINE_CODE_COLOR = {"color": {"rgbColor": {"red": 0.09411765, "green": 0.5019608, "blue": 0.21960784}}}
LINE_BREAK = "\u000b"  # soft line break inside one paragraph
RULE = {
    "color": {"color": {"rgbColor": {"red": 0.6, "green": 0.6, "blue": 0.6}}},
    "width": {"magnitude": 1, "unit": "PT"},
    "padding": {"magnitude": 6, "unit": "PT"},
    "dashStyle": "SOLID",
}
# Docs' code-block grey #F1F3F4. The main tab gets a native code block from the Drive import; the API
# cannot insert that building block into a tab, so a fenced block here is a shaded paragraph instead.
CODE_BLOCK_SHADING = {"backgroundColor": {"color": {"rgbColor": {"red": 0.945098, "green": 0.952941, "blue": 0.956863}}}}


def u16len(text):
    """Docs API indices count UTF-16 code units; ℹ️ is two, an astral emoji is two."""
    return len(text.encode("utf-16-le")) // 2


def tab_title(n, title):
    return f"Aside {n}: {title}"


# --- Draft parsing ---


def strip_markup(text):
    """Drop code, link, and bold markup, keeping the words."""
    for pattern, replacement in TITLE_MARKUP:
        text = pattern.sub(replacement, text)
    return text


def clean_title(n, raw):
    """Tab titles are plain text."""
    title = strip_markup(raw)
    if title != raw:
        log_info(f"aside title markup stripped | n='{n}' raw='{raw}' title='{title}'")
    return title


def check_title_length(n, title):
    full = tab_title(n, title)
    units = u16len(full)
    if units > TAB_TITLE_MAX_UNITS:
        die(f"aside tab title too long | n='{n}' title='{full}' units='{units}' max='{TAB_TITLE_MAX_UNITS}'")


def split_draft(lines):
    """Return (body_lines, sections) where sections is {n: {"title", "lines"}}."""
    body, sections = [], {}
    current = None
    for line in lines:
        header = SECTION_RE.match(line)
        if header:
            n = int(header.group(1))
            if n in sections:
                die(f"duplicate aside section | n='{n}' title='{header.group(2)}'")
            title = clean_title(n, header.group(2))
            check_title_length(n, title)
            current = {"title": title, "lines": []}
            sections[n] = current
            continue
        if current is not None and (H1_RE.match(line) or line.startswith(FOOTER_PREFIX)):
            current = None
        if current is not None:
            current["lines"].append(line)
            continue
        body.append(line)
    return body, sections


def classify_anchor_links(body_lines):
    """Every `[text](#aside-n)` in the body: {n: marker text} for markers, [(n, text)] for references."""
    markers, references = {}, []
    for line in body_lines:
        for match in ANCHOR_LINK_RE.finditer(line):
            text, n = match.group(1), int(match.group(2))
            if text == marker_text(n):
                if n in markers:
                    die(f"marker used twice | n='{n}' text='{text}'")
                markers[n] = text
                continue
            references.append((n, text))
    return markers, references


def check_pairing(markers, sections):
    unmatched_markers = sorted(set(markers) - set(sections))
    unmatched_sections = sorted(set(sections) - set(markers))
    if unmatched_markers or unmatched_sections:
        die(
            "markers and aside sections do not pair up | "
            f"markers_without_section='{unmatched_markers}' sections_without_marker='{unmatched_sections}'"
        )


def check_reference(n, text, sections, where):
    """A reference reads like the tab it points at, so it stays searchable by tab name."""
    if n not in sections:
        die(f"reference to an aside that has no section | n='{n}' text='{text}' where='{where}'")
    expected = sections[n]["title"]
    if clean_title(n, text) != expected:
        die(f"reference text must be the aside title | n='{n}' text='{text}' expected='{expected}' where='{where}'")


def link_runs(link_text, url):
    """Link text may hold code spans and bold: each code span is a Roboto Mono run that keeps the link,
    bold markers are dropped (aside bodies do not style bold). A reference to an aside is one plain run,
    since it must read like the tab title; so is a Drive link, whose chip replaces the text: two runs
    would make two chips."""
    if url.startswith(ANCHOR_PREFIX) or DRIVE_LINK_RE.match(url):
        return [{"text": strip_markup(link_text), "mono": False, "url": url}]
    return [{**run, "url": url} for run in inline_runs(BOLD_RE.sub(r"\1", link_text))]


def inline_runs(text):
    """Split one paragraph into runs: {text, mono, url}."""
    runs, pos = [], 0
    for match in INLINE_RE.finditer(text):
        if match.start() > pos:
            runs.append({"text": BOLD_RE.sub(r"\1", text[pos:match.start()]), "mono": False, "url": None})
        if match.group(1) is not None:
            runs.append({"text": match.group(1), "mono": True, "url": None})
        else:
            runs.extend(link_runs(match.group(2), match.group(3)))
        pos = match.end()
    if pos < len(text):
        runs.append({"text": BOLD_RE.sub(r"\1", text[pos:]), "mono": False, "url": None})
    return runs


def reject_unsupported(n, line):
    for pattern, kind in UNSUPPORTED:
        if pattern.match(line):
            die(f"unsupported content in aside | n='{n}' kind='{kind}' line='{line.strip()}'")
    if "![" in CODE_SPAN_RE.sub("", line):
        die(f"unsupported content in aside | n='{n}' kind='image' line='{line.strip()}' expected='the diagram line, alone and linked: {IMAGE_FORM}'")


def decode_ink_state(n, payload):
    """bake's base64url JSON state; anything else would re-encode as a different diagram."""
    try:
        raw = base64.b64decode(payload.translate(URLSAFE_TO_STANDARD) + "=" * (-len(payload) % 4), validate=True)
        state = json.loads(raw.decode("utf-8"))
    except (binascii.Error, UnicodeDecodeError, json.JSONDecodeError) as exc:
        die(f"aside image URL is not a mermaid.ink base64 diagram | n='{n}' error='{exc}' payload='{payload[:40]}'")
    if not isinstance(state, dict) or "code" not in state:
        die(f"aside image URL holds no mermaid state | n='{n}' payload='{payload[:40]}' expected='base64url JSON with a code key, as bake mints'")
    return raw


def pako_uri(n, uri):
    """mermaid.ink's base64: payload re-encoded as the deflated pako: payload, query kept."""
    payload, _, query = uri[len(INK_BASE64_PREFIX):].partition("?")
    pako = base64.urlsafe_b64encode(zlib.compress(decode_ink_state(n, payload), 9)).decode("ascii").rstrip("=")
    return INK_PAKO_PREFIX + pako + (f"?{query}" if query else "")


def docs_image_uri(n, uri):
    """The URI insertInlineImage gets: as written when it fits the 2 kB limit, else the pako: form."""
    if len(uri.encode("utf-8")) <= IMAGE_URI_MAX_BYTES:
        return uri
    if not uri.startswith(INK_BASE64_PREFIX):
        die(f"aside image URL too long for the Docs API | n='{n}' bytes='{len(uri.encode('utf-8'))}' max='{IMAGE_URI_MAX_BYTES}' uri='{uri[:80]}'")
    short = pako_uri(n, uri)
    if len(short) > IMAGE_URI_MAX_BYTES:
        die(f"aside image URL too long for the Docs API even as pako | n='{n}' bytes='{len(short)}' max='{IMAGE_URI_MAX_BYTES}'")
    log_info(f"aside image URL re-encoded as pako | n='{n}' bytes='{len(uri.encode('utf-8'))}' pako_bytes='{len(short)}' max='{IMAGE_URI_MAX_BYTES}'")
    return short


def check_image_source(n, uri):
    """Everything about the image Docs would otherwise reject after the tabs batch: the host, a type
    insertInlineImage takes, and a width inside the page."""
    if not uri.startswith(INK_IMG_PREFIX):
        die(f"aside image is not a mermaid.ink render | n='{n}' uri='{uri[:80]}' expected_prefix='{INK_IMG_PREFIX}'")
    query = parse_qs(urlsplit(uri).query)
    image_type = query.get("type", ["jpeg"])[0]
    if image_type not in IMAGE_TYPES:
        die(f"aside image type is not one Docs inserts | n='{n}' type='{image_type}' valid='{', '.join(IMAGE_TYPES)}'")
    width = query.get("width", [""])[0]
    if not width.isdigit() or int(width) > IMAGE_WIDTH_MAX_PX:
        die(f"aside image needs a width inside the page | n='{n}' width='{width}' max='{IMAGE_WIDTH_MAX_PX}' fix='end the mermaid.ink URL with ?width=620'")


def parse_image(n, match):
    """A linked diagram line -> an image block; the link must open the mermaid.live view."""
    _alt, uri, link = match.groups()
    if not link.startswith(IMAGE_LINK_PREFIX):
        die(f"aside image does not link to its mermaid.live view | n='{n}' link='{link[:80]}' expected_prefix='{IMAGE_LINK_PREFIX}'")
    check_image_source(n, uri)
    return {"type": "image", "uri": docs_image_uri(n, uri), "link": link}


def check_aside_links(n, runs, sections):
    for run in runs:
        url = run["url"]
        if not url or not url.startswith(ANCHOR_PREFIX):
            continue
        target = int(url[len(ANCHOR_PREFIX):])
        if run["text"] == marker_text(target):
            die(f"marker inside an aside; markers belong in the body, refer by title here | n='{n}' text='{run['text']}'")
        check_reference(target, run["text"], sections, where=f"aside {n}")


def parse_blocks(n, lines, sections):
    """Aside body lines -> [{type: paragraph, runs} | {type: code, lines} | {type: image, uri, link}]."""
    blocks, paragraph, code = [], [], None

    def flush_paragraph():
        if paragraph:
            runs = inline_runs(" ".join(paragraph))
            check_aside_links(n, runs, sections)
            blocks.append({"type": "paragraph", "runs": runs})
            paragraph.clear()

    for line in lines:
        if code is not None:
            if line.strip() == FENCE:
                if not code:
                    die(f"empty code fence in aside | n='{n}'")
                blocks.append({"type": "code", "lines": code})
                code = None
            else:
                code.append(line)
            continue
        if line.strip().startswith(FENCE):
            if line.strip() == MERMAID_FENCE:
                die(f"mermaid fence in aside would publish as source text | n='{n}' fix='bake it with /ari-diagram-mermaid and write {IMAGE_FORM}'")
            flush_paragraph()
            code = []
            continue
        if not line.strip():
            flush_paragraph()
            continue
        image = IMAGE_LINE_RE.match(line.strip())
        if image:
            flush_paragraph()
            blocks.append(parse_image(n, image))
            continue
        reject_unsupported(n, line)
        paragraph.append(line.strip())
    if code is not None:
        die(f"unterminated code fence in aside | n='{n}'")
    flush_paragraph()
    if not blocks:
        die(f"empty aside section | n='{n}'")
    return blocks


def load_draft(path):
    lines = Path(path).read_text(encoding="utf-8").split("\n")
    body, sections = split_draft(lines)
    markers, references = classify_anchor_links(body)
    check_pairing(markers, sections)
    for n, text in references:
        check_reference(n, text, sections, where="body")
    asides = {n: {"title": s["title"], "blocks": parse_blocks(n, s["lines"], sections)} for n, s in sections.items()}
    return body, markers, references, asides


def drive_links_in(blocks):
    return [run["url"] for block in blocks if block["type"] == "paragraph" for run in block["runs"] if run["url"] and DRIVE_LINK_RE.match(run["url"])]


def image_links(blocks):
    return [block["link"] for block in blocks if block["type"] == "image"]


def count_images(blocks):
    return len(image_links(blocks))


# --- Doc-side lookups ---


def check_drive_targets(asides):
    """insertRichLink fails the whole batch on a target the caller cannot read, so check each first."""
    for n in sorted(asides):
        for url in drive_links_in(asides[n]["blocks"]):
            file_id = DRIVE_LINK_RE.match(url).group(3)
            params = json.dumps({"fileId": file_id, "fields": "id", "supportsAllDrives": True})
            what = f"Drive link target in aside is unreadable; the chip batch would fail | n='{n}' url='{url}'"
            reply = gws_json(["drive", "files", "get", "--params", params], what=what)
            if "error" in reply:
                die(f"{what} error='{json.dumps(reply['error'])[:200]}'")


def find_marker_run(tab, n):
    """The marker run for n: anchor URL after an import, or a tab link left by an earlier rebuild."""
    anchor, text = f"{ANCHOR_PREFIX}{n}", marker_text(n)
    for paragraph_element in paragraphs(tab):
        for run in text_runs(paragraph_element):
            link = run_link(run)
            if run["textRun"]["content"] == text and (link.get("url") == anchor or "tabId" in link):
                return paragraph_element, run
    die(f"marker not found in first tab | n='{n}' anchor='{anchor}' text='{text}'")


def find_reference_runs(tab, n, title, stale_tab_ids):
    """Body references to aside n: anchor URL after an import, or a link to a tab the last rebuild made."""
    anchor, text = f"{ANCHOR_PREFIX}{n}", marker_text(n)
    found = []
    for paragraph_element in paragraphs(tab):
        for run in text_runs(paragraph_element):
            link = run_link(run)
            content = run["textRun"]["content"]
            if content == text:
                continue
            if link.get("url") == anchor or (link.get("tabId") in stale_tab_ids and content == title):
                found.append(run)
    return found


def nearest_heading_id(tab, paragraph_element):
    heading_id = None
    for candidate in paragraphs(tab):
        if candidate["startIndex"] > paragraph_element["startIndex"]:
            break
        heading_id = candidate["paragraph"]["paragraphStyle"].get("headingId", heading_id)
    if heading_id is None:
        die(f"no heading precedes the marker; the return link has no target | marker_start='{paragraph_element['startIndex']}'")
    return heading_id


def stale_aside_tabs(doc_json):
    return [
        tab["tabProperties"]
        for tab in doc_json["tabs"]
        if tab["tabProperties"]["tabId"] != FIRST_TAB and STALE_TAB_RE.match(tab["tabProperties"].get("title", ""))
    ]


# --- Request builders ---


class TabText:
    """Accumulate the text of one new tab and hand back UTF-16 ranges as it grows."""

    def __init__(self):
        self.parts = []
        self.pos = 1  # a new tab's body starts at index 1

    def add(self, text):
        start = self.pos
        self.parts.append(text)
        self.pos += u16len(text)
        return start, self.pos

    def text(self):
        return "".join(self.parts)


def text_style(tab_id, start, end, style, fields):
    return {"updateTextStyle": {"range": {"tabId": tab_id, "startIndex": start, "endIndex": end}, "textStyle": style, "fields": fields}}


def paragraph_style(tab_id, start, end, style, fields):
    return {"updateParagraphStyle": {"range": {"tabId": tab_id, "startIndex": start, "endIndex": end}, "paragraphStyle": style, "fields": fields}}


def code_span_style(tab_id, start, end, linked):
    """A code span is green, as the import makes the main tab's; inside a link it keeps the link's
    colour, as the main tab's does."""
    if linked:
        return text_style(tab_id, start, end, {"weightedFontFamily": {"fontFamily": MONO_FONT}}, "weightedFontFamily")
    return text_style(tab_id, start, end, {"weightedFontFamily": {"fontFamily": MONO_FONT}, "foregroundColor": INLINE_CODE_COLOR}, "weightedFontFamily,foregroundColor")


def return_link(target):
    return {"link": target, "italic": True}


def link_style_for(url, tab_ids):
    """A `#aside-m` reference links to that tab; a chip cannot point at a tab, so it is a text link."""
    if url.startswith(ANCHOR_PREFIX):
        return {"link": {"tabId": tab_ids[int(url[len(ANCHOR_PREFIX):])]}}
    return {"link": {"url": url}}


def chip_requests(tab_id, start, end, url):
    """Replace a Drive link's text with a smart chip. richLinkProperties carries only uri; the server
    resolves the title and rejects title or mimeType."""
    return [
        {"deleteContentRange": {"range": {"tabId": tab_id, "startIndex": start, "endIndex": end}}},
        {"insertRichLink": {"location": {"tabId": tab_id, "index": start}, "richLinkProperties": {"uri": url}}},
    ]


def image_requests(tab_id, index, uri, link):
    """An inline image in the empty paragraph at index, then its link. No objectSize: Docs sizes it from
    the image's resolution, and the verify read checks it fits one page, as the main tab's does."""
    return [
        {"insertInlineImage": {"location": {"tabId": tab_id, "index": index}, "uri": uri}},
        text_style(tab_id, index, index + 1, {"link": {"url": link}}, "link"),
    ]


def placement_requests(tab_id, chips, images):
    """Chips and images change the tab's length, so they run after every style and highest index
    first, which keeps each earlier range valid."""
    placements = [(start, chip_requests(tab_id, start, end, url)) for start, end, url in chips]
    placements += [(index, image_requests(tab_id, index, uri, link)) for index, uri, link in images]
    return [request for _, requests in sorted(placements, key=lambda placement: placement[0], reverse=True) for request in requests]


def build_fill_requests(tab_id, heading, blocks, target, tab_ids):
    """Text plus styles for one aside tab, then the chips and images. Blocks are separated by an empty
    paragraph, as the import lays out the main tab, and one empty paragraph sits between the last block
    and the footer rule; an image block is an empty paragraph its image is inserted into. The footer has
    no trailing newline so it merges into the empty paragraph a new tab starts with, leaving nothing
    after the rule."""
    tab = TabText()
    styles, chips, images = [], [], []
    start, end = tab.add(RETURN_TEXT + "\n")
    styles.append(paragraph_style(tab_id, start, end, {"borderBottom": RULE}, "borderBottom"))
    styles.append(text_style(tab_id, start, end - 1, return_link(target), "link,italic"))
    start, end = tab.add(heading + "\n")
    styles.append(paragraph_style(tab_id, start, end, {"namedStyleType": "HEADING_1"}, "namedStyleType"))
    for position, block in enumerate(blocks):
        if position > 0:
            tab.add("\n")
        if block["type"] == "code":
            start, end = tab.add(LINE_BREAK.join(block["lines"]) + "\n")
            styles.append(text_style(tab_id, start, end - 1, {"weightedFontFamily": {"fontFamily": MONO_FONT}}, "weightedFontFamily"))
            styles.append(paragraph_style(tab_id, start, end, {"shading": CODE_BLOCK_SHADING}, "shading"))
            continue
        if block["type"] == "image":
            start, _ = tab.add("\n")
            images.append((start, block["uri"], block["link"]))
            continue
        for run in block["runs"]:
            start, end = tab.add(run["text"])
            if run["mono"]:
                styles.append(code_span_style(tab_id, start, end, linked=bool(run["url"])))
            if run["url"] and DRIVE_LINK_RE.match(run["url"]):
                chips.append((start, end, run["url"]))
            elif run["url"]:
                styles.append(text_style(tab_id, start, end, link_style_for(run["url"], tab_ids), "link"))
        tab.add("\n")
    tab.add("\n")
    start, end = tab.add(RETURN_TEXT)
    styles.append(paragraph_style(tab_id, start, end + 1, {"borderTop": RULE}, "borderTop"))
    styles.append(text_style(tab_id, start, end, return_link(target), "link,italic"))
    insert = {"insertText": {"location": {"tabId": tab_id, "index": 1}, "text": tab.text()}}
    return [insert, *styles, *placement_requests(tab_id, chips, images)], len(chips)


def relink_request(run, tab_id):
    return text_style(FIRST_TAB, run["startIndex"], run["endIndex"], {"link": {"tabId": tab_id}}, "link")


def return_target(tab, paragraph_element):
    """The heading above the marker; gdoc_bookmarks.py upgrades this to a bookmark afterwards."""
    return {"heading": {"id": nearest_heading_id(tab, paragraph_element), "tabId": FIRST_TAB}}


def verify_aside_chips(tab, tab_id, n, expected_chips):
    """Every Drive link is a chip, and as many as planned."""
    plain = [run_link(run).get("url") for p in paragraphs(tab) for run in text_runs(p) if DRIVE_LINK_RE.match(run_link(run).get("url") or "")]
    chips = sum(1 for p in paragraphs(tab) for element in p["paragraph"]["elements"] if "richLink" in element)
    if plain or chips != expected_chips:
        die(f"aside tab Drive links are not all chips | n='{n}' tab='{tab_id}' plain='{plain}' chips='{chips}' expected='{expected_chips}'")


def content_box(tab, tab_id):
    """The page's text area in points, from the tab's documentStyle."""
    style = tab.get("documentStyle")
    if style is None:
        die(f"aside tab has no documentStyle; image fit unknown | tab='{tab_id}'")
    width = style["pageSize"]["width"]["magnitude"] - style["marginLeft"]["magnitude"] - style["marginRight"]["magnitude"]
    height = style["pageSize"]["height"]["magnitude"] - style["marginTop"]["magnitude"] - style["marginBottom"]["magnitude"]
    return width, height


def verify_aside_images(tab, tab_id, n, expected_links):
    """The main tab's image checks, on an aside tab: the planned images in order, each linked to its own
    mermaid.live view and inside one page."""
    elements = [element["inlineObjectElement"] for p in paragraphs(tab) for element in p["paragraph"]["elements"] if "inlineObjectElement" in element]
    if len(elements) != len(expected_links):
        die(f"aside tab images missing | n='{n}' tab='{tab_id}' images='{len(elements)}' expected='{len(expected_links)}'")
    if not elements:
        return
    max_width, max_height = content_box(tab, tab_id)
    for element, expected in zip(elements, expected_links):
        image_id = element["inlineObjectId"]
        url = element.get("textStyle", {}).get("link", {}).get("url", "")
        if url != expected:
            die(f"aside tab image does not link to its mermaid.live view | n='{n}' tab='{tab_id}' image='{image_id}' url='{url[:80]}' expected='{expected[:80]}'")
        size = tab.get("inlineObjects", {}).get(image_id, {}).get("inlineObjectProperties", {}).get("embeddedObject", {}).get("size")
        if size is None:
            die(f"aside tab image has no size; fit unknown | n='{n}' tab='{tab_id}' image='{image_id}'")
        width, height = size["width"]["magnitude"], size["height"]["magnitude"]
        if width > max_width or height > max_height:
            die(f"aside tab image exceeds one page | n='{n}' tab='{tab_id}' image='{image_id}' width_pt='{width}' height_pt='{height}' max_width_pt='{max_width}' max_height_pt='{max_height}'")


def verify_aside_tab(doc_json, tab_id, n, expected_chips, expected_links):
    tab = tab_by_id(doc_json, tab_id)
    verify_aside_chips(tab, tab_id, n, expected_chips)
    verify_aside_images(tab, tab_id, n, expected_links)


# --- Modes ---


def run_split(args):
    body, markers, references, asides = load_draft(args.file)
    out = Path(args.body_out)
    if out.exists() and not args.force:
        die(f"output exists | path='{out}' hint='pass --force to overwrite'")
    out.write_text("\n".join(body), encoding="utf-8")
    for n in sorted(asides):
        refs = sum(1 for ref_n, _ in references if ref_n == n)
        drive = len(drive_links_in(asides[n]["blocks"]))
        images = count_images(asides[n]["blocks"])
        log_info(f"aside section split out | n='{n}' title='{asides[n]['title']}' marker='{markers[n]}' blocks='{len(asides[n]['blocks'])}' body_references='{refs}' drive_links='{drive}' images='{images}'")
    print(len(asides))  # stdout is data: how many tabs --rebuild will add


def outcome(dry_run, done, planned):
    """A dry run logs what it would do: a past-tense line there reads as if the tabs were already gone."""
    if dry_run:
        return planned
    return done


def first_tab_links(doc_json, asides, stale_tab_ids):
    """Every marker, its return target and its references, found before anything is sent: a lookup that
    fails after the tabs batch would leave empty tabs and markers pointing at deleted ones. Adding or
    deleting tabs moves nothing in the first tab, so these ranges hold for the fill batch."""
    tab = first_tab(doc_json)
    links = {}
    for n in sorted(asides):
        paragraph_element, marker_run = find_marker_run(tab, n)
        references = find_reference_runs(tab, n, asides[n]["title"], stale_tab_ids)
        links[n] = {"marker": marker_run, "return": return_target(tab, paragraph_element), "references": references}
    return links


def run_rebuild(args):
    _, _, _, asides = load_draft(args.file)
    doc = doc_id_from(args.doc)
    check_drive_targets(asides)
    doc_json = fetch_doc(doc)
    stale = stale_aside_tabs(doc_json)
    stale_tab_ids = {tab["tabId"] for tab in stale}
    links = first_tab_links(doc_json, asides, stale_tab_ids)
    tab_requests = [{"deleteTab": {"tabId": tab["tabId"]}} for tab in stale]
    for tab in stale:
        log_info(f"{outcome(args.dry_run, 'stale aside tab deleted', 'would delete stale aside tab')} | tab='{tab['tabId']}' title='{tab['title']}'")
    for index, n in enumerate(sorted(asides), start=1):
        tab_requests.append({"addDocumentTab": {"tabProperties": {"title": tab_title(n, asides[n]["title"]), "index": index}}})
    if args.first_tab_title:
        tab_requests.append({"updateDocumentTabProperties": {"tabProperties": {"tabId": FIRST_TAB, "title": args.first_tab_title}, "fields": "title"}})
    reply = batch_update(doc, tab_requests, doc_json["revisionId"], args.dry_run, what="tabs batch")
    new_tab_ids = [r["addDocumentTab"]["tabProperties"]["tabId"] for r in reply.get("replies", []) if "addDocumentTab" in r]
    if args.dry_run:
        new_tab_ids = [f"NEW_TAB_{n}" for n in sorted(asides)]
    if len(new_tab_ids) != len(asides):
        die(f"addDocumentTab replies do not match sections | replies='{len(new_tab_ids)}' sections='{len(asides)}'")
    tab_ids = dict(zip(sorted(asides), new_tab_ids))

    revision = doc_json["revisionId"] if args.dry_run else fetch_doc(doc)["revisionId"]
    fill_requests, summary, expected_chips = [], [], {}
    for n in sorted(asides):
        tab_id, marker_run, references = tab_ids[n], links[n]["marker"], links[n]["references"]
        requests, n_chips = build_fill_requests(tab_id, tab_title(n, asides[n]["title"]), asides[n]["blocks"], links[n]["return"], tab_ids)
        fill_requests.extend(requests)
        fill_requests.append(relink_request(marker_run, tab_id))
        fill_requests.extend(relink_request(run, tab_id) for run in references)
        expected_chips[n] = n_chips
        n_images = count_images(asides[n]["blocks"])
        summary.append({"n": n, "title": asides[n]["title"], "tab": tab_id, "return": "heading", "chips": n_chips, "images": n_images, "body_references": len(references), "marker_range": [marker_run["startIndex"], marker_run["endIndex"]]})
        log_info(f"{outcome(args.dry_run, 'aside tab rebuilt', 'would rebuild aside tab')} | n='{n}' title='{asides[n]['title']}' tab='{tab_id}' return='heading' chips='{n_chips}' images='{n_images}' body_references='{len(references)}' marker_range='{marker_run['startIndex']}-{marker_run['endIndex']}'")
    batch_update(doc, fill_requests, revision, args.dry_run, what="fill batch")
    if args.dry_run:
        return
    doc_json = fetch_doc(doc)
    for n in sorted(asides):
        verify_aside_tab(doc_json, tab_ids[n], n, expected_chips[n], image_links(asides[n]["blocks"]))
    print(json.dumps({"doc": doc, "asides": summary}, ensure_ascii=False))


def parse_args():
    parser = argparse.ArgumentParser(description="Split aside sections out of a draft, or rebuild them as tabs on the published Doc.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--split", action="store_true", help="write the draft without its aside sections to --body-out")
    mode.add_argument("--rebuild", action="store_true", help="rebuild the aside tabs of --doc from the draft")
    parser.add_argument("--file", required=True, help="the markdown draft (with aside sections)")
    parser.add_argument("--body-out", dest="body_out", help="--split: where to write the body without aside sections")
    parser.add_argument("--force", action="store_true", help="--split: overwrite --body-out")
    parser.add_argument("--doc", help="--rebuild: Google Doc id or URL")
    parser.add_argument("--first-tab-title", dest="first_tab_title", help="--rebuild: rename the first tab (the import resets it to 'Tab 1')")
    parser.add_argument("--execute", action="store_true", help="--rebuild: send the batches; without it the rebuild is a dry run")
    parser.add_argument("--dry-run", dest="dry_run_flag", action="store_true", help="--rebuild: the default made explicit; wins over --execute and exports DRY_RUN=1")
    return parser.parse_args()


def resolve_dry_run(execute, dry_run_flag):
    """ari-skill-shellscripts' lib/dry_run.zsh, in Python: act only on --execute on this command line;
    --dry-run, or an inherited DRY_RUN other than empty or 0, wins over it. Exports DRY_RUN (1 = dry
    run, 0 = act) and returns True for a dry run."""
    inherited = os.environ.get("DRY_RUN", "")
    if dry_run_flag:
        os.environ["DRY_RUN"] = "1"
        if execute:
            log_warn("Dry run: --dry-run overrides --execute; nothing will change | fix='drop --dry-run'")
            return True
        log_info("Dry run: --dry-run given; nothing will change")
        return True
    if inherited not in ("", "0"):
        os.environ["DRY_RUN"] = "1"
        if execute:
            log_warn(f"Dry run: inherited DRY_RUN overrides --execute; nothing will change | inherited='{inherited}' fix='unset DRY_RUN'")
            return True
        log_info(f"Dry run: inherited from the parent; nothing will change | inherited='{inherited}'")
        return True
    if not execute:
        log_info("Dry run: the default; nothing will change | next='show the user the batches; --execute only after they reply'")
        os.environ["DRY_RUN"] = "1"
        return True
    log_info("Executing: --execute given")
    os.environ["DRY_RUN"] = "0"
    return False


def main():
    args = parse_args()
    if args.split and not args.body_out:
        die("--split needs --body-out")
    if args.rebuild and not args.doc:
        die("--rebuild needs --doc")
    if args.split:
        run_split(args)
        return
    args.dry_run = resolve_dry_run(args.execute, args.dry_run_flag)
    check_gws()
    run_rebuild(args)


if __name__ == "__main__":
    main()
