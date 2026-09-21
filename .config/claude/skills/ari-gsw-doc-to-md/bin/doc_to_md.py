#!/usr/bin/env python3
"""Google Docs JSON -> Markdown converter.

Fetches a doc via the `gws` CLI (or reads a saved JSON) and renders markdown.
Tab-aware: a `?tab=<tabId>` in the source URL (or `--tab`) renders just that tab;
with no tab, a single-tab doc renders as-is and a multi-tab doc errors (use
/ari-gsw-read to expand it into one file per tab). Two dialects: the default
reads well; `--publish` emits the /ari-hemingway--format-gdoc dialect (title as
the first line, Drive URLs raw, linked images via mermaid.ink) so the output
feeds /ari-hemingway--share-gdoc unchanged. Logs go to stderr as `key='value'`
records (message separated from data by `|`); only the result — the output
path, or the markdown under --stdout — goes to stdout.
"""
import argparse
import base64
import json
import re
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path

from at_log import log_info, log_warn, die  # on PYTHONPATH via the entrypoint
from at_subprocess import run_capture

GWS_TIMEOUT_S = 90
TMP_JSON_DIR = Path("/tmp/ari-gsw-doc-to-md")
DOC_ID_RE = re.compile(r"/(?:document|file)/d/([a-zA-Z0-9_-]+)")
OPEN_ID_RE = re.compile(r"[?&]id=([a-zA-Z0-9_-]+)")
BARE_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{20,}$")
TAB_ID_RE = re.compile(r"[?&]tab=([a-zA-Z0-9._-]+)")
DRIVE_URL_RE = re.compile(r"^https://(?:docs|drive)\.google\.com/")
MERMAID_LIVE_RE = re.compile(r"^https://mermaid\.live/(?:edit|view)#pako:([A-Za-z0-9_-]+)")
MERMAID_INK_PREFIX = "https://mermaid.ink/img/base64:"
DOCS_IMAGE_WIDTH_PX = 620  # 465 pt: inside a Letter page's 468 pt text width

HEADING_PREFIX = {
    "TITLE": "# ",
    "SUBTITLE": "## ",
    "HEADING_1": "# ",
    "HEADING_2": "## ",
    "HEADING_3": "### ",
    "HEADING_4": "#### ",
    "HEADING_5": "##### ",
    "HEADING_6": "###### ",
}
ORDERED_GLYPHS = {"DECIMAL", "ZERO_DECIMAL", "ALPHA", "UPPER_ALPHA", "ROMAN", "UPPER_ROMAN"}
MONOSPACE_HINTS = ("Mono", "Consolas", "Courier", "Source Code")


@dataclass(frozen=True)
class RenderContext:
    """Per-body lookup tables plus the output dialect, threaded through rendering."""
    inline_objects: dict
    lists: dict
    publish: bool


def parse_json_or_die(text, where):
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        die(f"{where} is not JSON | head='{text[:200]!r}'")
    if not isinstance(value, dict):
        die(f"{where} is not a JSON object | type='{type(value).__name__}'")
    return value


# ----- fetch -----

def resolve_doc_id(source):
    """Extract a document ID from a Docs/Drive URL, or accept a bare ID."""
    for pattern in (DOC_ID_RE, OPEN_ID_RE):
        match = pattern.search(source)
        if match:
            return match.group(1)
    if BARE_ID_RE.match(source):
        return source
    die(f"not a Google Doc URL or id | source='{source}' accepts='.../document/d/<id>, .../file/d/<id>, ?id=<id>, or a bare id'")


def resolve_requested_tab_id(args):
    """The tab to render: --tab wins, else a tab= in the source URL, else None."""
    if args.tab:
        return args.tab
    if args.source:
        match = TAB_ID_RE.search(args.source)
        if match:
            return match.group(1)
    return None


def save_raw_json(doc_id, text):
    """Persist the fetched JSON to /tmp so --json-file re-runs skip the network."""
    try:
        TMP_JSON_DIR.mkdir(parents=True, exist_ok=True)
        path = TMP_JSON_DIR / f"{doc_id}.json"
        path.write_text(text, encoding="utf-8")
        log_info(f"saved raw json | path='{path}'")
    except OSError as err:
        log_warn(f"could not save raw json | err='{err}'")


def fetch_doc(doc_id):
    """Fetch the Docs API JSON for doc_id via the gws CLI, tabs included."""
    log_info(f"fetching | doc_id='{doc_id}'")
    result = run_capture(
        ["gws", "docs", "documents", "get", "--params",
         json.dumps({"documentId": doc_id, "includeTabsContent": True}), "--format", "json"],
        GWS_TIMEOUT_S,
        what="gws docs documents get",
    )
    save_raw_json(doc_id, result.stdout)
    return parse_json_or_die(result.stdout, "gws output")


# ----- publish dialect helpers -----

def is_drive_url(url):
    return bool(DRIVE_URL_RE.match(url or ""))


def mermaid_ink_url(live_url):
    """Derive the mermaid.ink PNG URL from a mermaid.live pako link, or None.
    Same state JSON, re-encoded as plain base64url — what ari-diagram-mermaid's
    bake emits for MERMAID_FORMAT=ink_url."""
    match = MERMAID_LIVE_RE.match(live_url)
    if not match:
        return None
    payload = match.group(1)
    try:
        raw = base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
        state = json.loads(zlib.decompress(raw).decode("utf-8"))
    except (ValueError, zlib.error) as err:
        log_warn(f"could not decode mermaid.live payload | live_url='{live_url[:80]}' err='{err}'")
        return None
    if not isinstance(state, dict) or not state.get("code"):
        log_warn(f"mermaid.live payload has no code | live_url='{live_url[:80]}'")
        return None
    compact = json.dumps(state, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    encoded = base64.urlsafe_b64encode(compact).decode("ascii").rstrip("=")
    return f"{MERMAID_INK_PREFIX}{encoded}"


def render_linked_image(alt, content_uri, link):
    """Publish dialect: an image linked to its mermaid.live source renders from
    mermaid.ink at Docs width, so the expiring contentUri never reaches the draft."""
    ink_url = mermaid_ink_url(link)
    if ink_url is None:
        log_warn(f"image link is not a mermaid.live source, keeping contentUri | link='{link[:80]}'")
        return f"[![{alt}]({content_uri})]({link})"
    return f"[![{alt}]({ink_url}?width={DOCS_IMAGE_WIDTH_PX})]({link})"


# ----- inline element rendering -----

def wrap(text, left, right):
    """Wrap non-whitespace content, leaving leading/trailing spaces outside markers."""
    stripped = text.strip()
    if not stripped:
        return text
    lead = text[: len(text) - len(text.lstrip())]
    trail = text[len(text.rstrip()):]
    return f"{lead}{left}{stripped}{right}{trail}"


def run_link(run):
    return (run.get("textStyle", {}).get("link") or {}).get("url")


def render_text_run_inner(run):
    """Render a text run's emphasis (bold/italic/monospace) but NOT its link."""
    content = run.get("content", "").replace("\n", "")
    if content == "":
        return ""
    style = run.get("textStyle", {})
    out = content
    family = (style.get("weightedFontFamily") or {}).get("fontFamily", "")
    if any(hint in family for hint in MONOSPACE_HINTS):
        out = wrap(out, "`", "`")
    if style.get("bold"):
        out = wrap(out, "**", "**")
    if style.get("italic"):
        out = wrap(out, "*", "*")
    return out


def render_text_link(text, link, ctx):
    """A linked run group. Publish dialect renders a Drive URL raw so the publish
    step can chip it (a chip shows the target's title, so the anchor text goes)."""
    if ctx.publish and is_drive_url(link):
        if text.strip():
            log_warn(f"dropped anchor text for a Drive URL | text='{text.strip()}' url='{link}'")
        return link
    return f"[{text}]({link})"


def render_rich_link(element, ctx):
    props = element.get("richLink", {}).get("richLinkProperties", {})
    uri = props.get("uri", "")
    title = props.get("title") or uri or "link"
    if not uri:
        return title
    if ctx.publish and is_drive_url(uri):
        return uri
    return f"[{title}]({uri})"


def render_person(element):
    props = element.get("person", {}).get("personProperties", {})
    name = props.get("name")
    email = props.get("email")
    if name and email:
        return f"{name} <{email}>"
    if name:
        return name
    if email:
        return f"<{email}>"
    return ""


def render_date_element(element):
    props = element.get("dateElement", {}).get("dateElementProperties", {})
    return props.get("displayText", "")


def render_inline_object(element, ctx):
    inline = element.get("inlineObjectElement", {})
    embedded = (
        ctx.inline_objects.get(inline.get("inlineObjectId", ""), {})
        .get("inlineObjectProperties", {})
        .get("embeddedObject", {})
    )
    uri = (embedded.get("imageProperties") or {}).get("contentUri", "")
    if not uri:
        return ""
    alt = embedded.get("title") or embedded.get("description") or "image"
    link = (inline.get("textStyle", {}).get("link") or {}).get("url")
    if ctx.publish and link:
        return render_linked_image(alt, uri, link)
    return f"![{alt}]({uri})"


def render_elements(elements, ctx):
    """Render a paragraph's inline elements, coalescing adjacent runs that share
    one link URL into a single markdown link (Google splits styled phrases into
    several runs, which would otherwise produce duplicate adjacent links)."""
    parts = []
    index = 0
    count = len(elements)
    while index < count:
        element = elements[index]
        if "textRun" in element:
            link = run_link(element["textRun"])
            if link:
                group = []
                while (
                    index < count
                    and "textRun" in elements[index]
                    and run_link(elements[index]["textRun"]) == link
                ):
                    group.append(render_text_run_inner(elements[index]["textRun"]))
                    index += 1
                parts.append(render_text_link("".join(group), link, ctx))
                continue
            parts.append(render_text_run_inner(element["textRun"]))
        elif "richLink" in element:
            parts.append(render_rich_link(element, ctx))
        elif "person" in element:
            parts.append(render_person(element))
        elif "dateElement" in element:
            parts.append(render_date_element(element))
        elif "inlineObjectElement" in element:
            parts.append(render_inline_object(element, ctx))
        elif "horizontalRule" in element:
            parts.append("---")
        # autoText, pageBreak, columnBreak, footnoteReference, equation: dropped
        index += 1
    return "".join(parts).rstrip()


# ----- block rendering -----

def is_ordered_list(lists, list_id, level):
    levels = lists.get(list_id, {}).get("listProperties", {}).get("nestingLevels", [])
    if level >= len(levels):
        return False
    return levels[level].get("glyphType", "") in ORDERED_GLYPHS


def render_list_item(text, bullet, lists):
    level = bullet.get("nestingLevel", 0)
    indent = "  " * level
    marker = "1." if is_ordered_list(lists, bullet.get("listId", ""), level) else "-"
    return f"{indent}{marker} {text}"


def render_paragraph(paragraph, ctx):
    text = render_elements(paragraph.get("elements", []), ctx)
    bullet = paragraph.get("bullet")
    if bullet is not None:
        return render_list_item(text, bullet, ctx.lists)
    if not text:
        return ""
    named_style = paragraph.get("paragraphStyle", {}).get("namedStyleType", "NORMAL_TEXT")
    if named_style in HEADING_PREFIX:
        return HEADING_PREFIX[named_style] + text
    return text


def render_cell(cell, ctx):
    pieces = []
    for element in cell.get("content", []):
        if "paragraph" in element:
            rendered = render_paragraph(element["paragraph"], ctx)
            if rendered:
                pieces.append(rendered)
        elif "table" in element:
            log_warn("nested table inside a cell omitted | reason='markdown has no nested-table form'")
            pieces.append("[nested table omitted]")
    return " ".join(pieces).replace("|", "\\|").replace("\n", " ").strip()


def render_table(table, ctx):
    rows = table.get("tableRows", [])
    if not rows:
        return ""
    column_count = max((len(row.get("tableCells", [])) for row in rows), default=0)
    if column_count == 0:
        return ""
    md_rows = []
    for row in rows:
        cells = [render_cell(c, ctx) for c in row.get("tableCells", [])]
        cells += [""] * (column_count - len(cells))
        md_rows.append("| " + " | ".join(cells) + " |")
    separator = "| " + " | ".join(["---"] * column_count) + " |"
    return "\n".join([md_rows[0], separator, *md_rows[1:]])


# ----- document assembly -----

def join_blocks(blocks):
    """Tight newline between adjacent list items; blank line between everything else."""
    if not blocks:
        return ""
    out = blocks[0][0]
    for index in range(1, len(blocks)):
        text, is_list = blocks[index]
        prev_is_list = blocks[index - 1][1]
        separator = "\n" if (is_list and prev_is_list) else "\n\n"
        out += separator + text
    return out + "\n"


def convert_content(content, publish):
    """Render one body's worth of content. `content` carries body/inlineObjects/lists
    — from a single tab (documentTab) or the legacy top-level document."""
    ctx = RenderContext(
        inline_objects=content.get("inlineObjects", {}),
        lists=content.get("lists", {}),
        publish=publish,
    )
    blocks = []
    for element in content.get("body", {}).get("content", []):
        if "paragraph" in element:
            rendered = render_paragraph(element["paragraph"], ctx)
            if rendered:
                blocks.append((rendered, element["paragraph"].get("bullet") is not None))
        elif "table" in element:
            rendered = render_table(element["table"], ctx)
            if rendered:
                blocks.append((rendered, False))
        # sectionBreak, tableOfContents: dropped
    return join_blocks(blocks)


# ----- tab selection -----

def collect_tabs(doc):
    """Flatten doc.tabs depth-first into [{id, title, content}, ...], where content
    is the {body, inlineObjects, lists} dict for that tab."""
    tabs = []

    def walk(tab_list):
        for tab in tab_list:
            props = tab.get("tabProperties", {})
            document_tab = tab.get("documentTab", {})
            tabs.append({
                "id": props.get("tabId", ""),
                "title": props.get("title", ""),
                "content": {
                    "body": document_tab.get("body", {}),
                    "inlineObjects": document_tab.get("inlineObjects", {}),
                    "lists": document_tab.get("lists", {}),
                },
            })
            walk(tab.get("childTabs", []))

    walk(doc.get("tabs", []))
    return tabs


def render_doc(doc, requested_tab_id, publish):
    """Return (markdown, tab_title) for exactly one tab: the requested tab, or the
    sole tab, or a tabless doc's body. A multi-tab doc with no tab selected is an
    error — use /ari-gsw-read to expand it into one file per tab."""
    tabs = collect_tabs(doc)
    if not tabs:
        legacy = {
            "body": doc.get("body", {}),
            "inlineObjects": doc.get("inlineObjects", {}),
            "lists": doc.get("lists", {}),
        }
        return convert_content(legacy, publish), None
    if requested_tab_id:
        for tab in tabs:
            if tab["id"] == requested_tab_id:
                log_info(f"rendering tab | tab_id='{tab['id']}' title='{tab['title']}'")
                # Only suffix the filename when there's more than one tab to disambiguate.
                tab_title = tab["title"] if len(tabs) > 1 else None
                return convert_content(tab["content"], publish), tab_title
        available = ", ".join(t["id"] for t in tabs)
        die(f"tab not found | tab_id='{requested_tab_id}' available='{available}'")
    if len(tabs) == 1:
        return convert_content(tabs[0]["content"], publish), None
    summary = "; ".join(f"{t['id']}={t['title']}" for t in tabs)
    die(f"doc has multiple tabs, select one | tabs='{len(tabs)}' available='{summary}' hint='pass --tab <id> or a ?tab= URL, or use /ari-gsw-read for one file per tab'")


def with_title_line(markdown, title, publish):
    """Publish dialect: the Doc title, plain text, is the draft's first line —
    /ari-hemingway--share-gdoc reads it back as the document title."""
    if not publish:
        return markdown
    if not title:
        log_warn("doc has no title, publish dialect gets none | hint='set one in Docs before publishing'")
        return markdown
    return f"{title}\n\n{markdown}"


def slugify(title):
    slug = re.sub(r"[^a-z0-9]+", "-", title.strip().lower()).strip("-")
    return slug[:60] or "google-doc"


def default_filename(title, tab_title):
    base = slugify(title)
    if tab_title:
        return f"{base}__{slugify(tab_title)}.md"
    return f"{base}.md"


# ----- entrypoint: parse -> validate -> load -> convert -> emit -----

def parse_args():
    parser = argparse.ArgumentParser(description="Convert a Google Doc (or one tab of it) to markdown.")
    parser.add_argument("source", nargs="?", help="Google Doc URL or document ID (a ?tab=<id> selects one tab)")
    parser.add_argument("--tab", help="tab id to render (overrides any tab= in the source URL)")
    parser.add_argument("--out", help="write markdown to PATH, or into PATH/ when it is a directory (default: <title-slug>[__<tab-slug>].md in CWD)")
    parser.add_argument("--stdout", action="store_true", help="print markdown to stdout instead of a file")
    parser.add_argument("--force", action="store_true", help="overwrite the output file if it already exists")
    parser.add_argument("--publish", action="store_true",
                        help="emit the /ari-hemingway--format-gdoc dialect: Doc title as the first line, Drive URLs raw, linked images via mermaid.ink (feeds /ari-hemingway--share-gdoc)")
    parser.add_argument("--json-file", dest="json_file", help="convert a saved Docs JSON instead of fetching")
    return parser.parse_args()


def load_doc(args):
    if args.json_file:
        path = Path(args.json_file)
        if not path.is_file():
            die(f"json file not found | json_file='{args.json_file}'")
        return parse_json_or_die(path.read_text(encoding="utf-8"), "json file")
    return fetch_doc(resolve_doc_id(args.source))


def resolve_out_path(out_arg, title, tab_title):
    """Where to write. No --out → default name in CWD. --out a directory (or a
    trailing-slash path) → default name inside it, so a doc's tabs share the
    <doc-slug>__ prefix there. Otherwise --out is the literal file path."""
    if not out_arg:
        return Path(default_filename(title, tab_title))
    out_path = Path(out_arg)
    if out_arg.endswith("/") or out_path.is_dir():
        return out_path / default_filename(title, tab_title)
    return out_path


def write_output(markdown, args, title, tab_title):
    if args.stdout:
        sys.stdout.write(markdown)
        return
    out_path = resolve_out_path(args.out, title, tab_title)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists() and not args.force:
        die(f"output exists | path='{out_path}' hint='pass --force to overwrite, --out PATH for another location, or --stdout'")
    try:
        out_path.write_text(markdown, encoding="utf-8")
    except OSError as err:
        die(f"cannot write output | path='{out_path}' err='{err}'")
    log_info(f"wrote markdown | path='{out_path}' bytes='{len(markdown)}'")
    print(str(out_path))


def main():
    args = parse_args()
    if not args.source and not args.json_file:
        die("nothing to convert | hint='pass a doc URL/ID, or --json-file PATH'")

    requested_tab_id = resolve_requested_tab_id(args)
    doc = load_doc(args)
    markdown, tab_title = render_doc(doc, requested_tab_id, args.publish)
    if not markdown.strip():
        die(f"document produced no content | title='{doc.get('title', '')}'")
    markdown = with_title_line(markdown, doc.get("title", ""), args.publish)

    write_output(markdown, args, doc.get("title", "google-doc"), tab_title)


if __name__ == "__main__":
    main()
