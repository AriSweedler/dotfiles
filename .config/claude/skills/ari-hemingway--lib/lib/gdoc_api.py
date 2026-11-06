"""Docs API helpers shared by the hemingway publish scripts (share-gdoc's gdoc_asides.py and
structure-bookmark's gdoc_bookmarks.py).

On PYTHONPATH through each script's zsh entrypoint, beside skill_log and skill_subprocess. Everything here
either calls the gws CLI or walks a documents.get reply. The two literals both scripts must agree on
(the return-link text an aside tab carries, the marker text an aside puts in the body) live here too.
"""
import json
import re
import shutil
import subprocess

from skill_log import die, log_info

GWS_TIMEOUT_S = 90
GWS_ERROR_HEAD_CHARS = 600
FIRST_TAB = "t.0"
RETURN_TEXT = "← Return to main article"
# A diagram image opens its source fullscreen (/view, not /edit: the reader gets the diagram, not the editor).
IMAGE_LINK_PREFIX = "https://mermaid.live/view#"
# insertRichLink accepts Drive file and folder URLs only, so this is the whole chip allowlist; group 3 is the file id.
DRIVE_LINK_PATTERN = r"^https://(docs|drive)\.google\.com/(.*/d/|drive/folders/)([A-Za-z0-9_-]+)"
DRIVE_LINK_RE = re.compile(DRIVE_LINK_PATTERN)


def marker_text(n):
    return f"aside {n} ℹ️"


def doc_id_from(value):
    """Reduce a Docs URL (…/d/<id>/edit?tab=…) or bare id to the id."""
    if "/d/" in value:
        value = value.split("/d/", 1)[1].split("/", 1)[0]
    return value.split("?", 1)[0].split("#", 1)[0]


def check_gws():
    if shutil.which("gws") is None:
        die("missing prerequisites | missing='gws'")


def gws_error_body(stdout):
    """The API's error object from a failed gws call's stdout (code, message, reason, details), compact;
    the head of stdout when it is not JSON, '' when empty."""
    text = stdout.strip()
    if not text:
        return ""
    try:
        error = json.loads(text).get("error", text)
    except (json.JSONDecodeError, AttributeError):
        error = text
    return json.dumps(error, ensure_ascii=False)[:GWS_ERROR_HEAD_CHARS]


def gws_json(args, what):
    """A gws call that must succeed; dies with the exit code, the stderr and the API's error body from
    stdout (gws prints the code, reason and details there, not on stderr)."""
    cmd = ["gws", *args, "--format", "json"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=GWS_TIMEOUT_S)
    except FileNotFoundError:
        die(f"{what}: binary not found | bin='gws'")
    except subprocess.TimeoutExpired:
        die(f"{what}: timed out | timeout_s='{GWS_TIMEOUT_S}'")
    if result.returncode != 0:
        die(f"{what}: failed | rc='{result.returncode}' stderr='{result.stderr.strip()[-300:]}' api_error='{gws_error_body(result.stdout)}'")
    try:
        reply = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        die(f"{what}: reply is not JSON | error='{exc}' head='{result.stdout[:200]}'")
    return reply


def fetch_doc(doc):
    params = json.dumps({"documentId": doc, "includeTabsContent": True})
    return gws_json(["docs", "documents", "get", "--params", params], what="documents.get")


def batch_update(doc, requests, revision, dry_run, what):
    """One batchUpdate pinned to the revision the requests were built from. Under dry_run the body is
    printed to stdout (data) and nothing is sent. Returns the reply, or {} when nothing was sent."""
    if not requests:
        log_info(f"nothing to send | what='{what}'")
        return {}
    body = json.dumps({"requests": requests, "writeControl": {"requiredRevisionId": revision}}, ensure_ascii=False)
    if dry_run:
        log_info(f"dry-run: would send batch | what='{what}' requests='{len(requests)}'")
        print(body)
        return {}
    return gws_json(["docs", "documents", "batchUpdate", "--params", json.dumps({"documentId": doc}), "--json", body], what=what)


def all_tabs(doc_json):
    """[(tabProperties, documentTab)] in document order."""
    return [(tab["tabProperties"], tab["documentTab"]) for tab in doc_json["tabs"]]


def first_tab(doc_json):
    return doc_json["tabs"][0]["documentTab"]


def tab_by_id(doc_json, tab_id):
    for props, tab in all_tabs(doc_json):
        if props["tabId"] == tab_id:
            return tab
    die(f"tab missing | tab='{tab_id}'")


def paragraphs(tab):
    return [element for element in tab["body"]["content"] if "paragraph" in element]


def text_runs(paragraph_element):
    return [element for element in paragraph_element["paragraph"]["elements"] if "textRun" in element]


def runs_in(tab):
    for paragraph_element in paragraphs(tab):
        yield from text_runs(paragraph_element)


def run_link(run):
    return run["textRun"].get("textStyle", {}).get("link", {})


def content_box(document_style):
    """The page's text area in points (width, height) from a documentStyle."""
    page = document_style.get("pageSize")
    if not page:
        die("documentStyle has no pageSize; image fit unknown")
    def margin(side):
        return document_style.get(side, {}).get("magnitude", 0)  # the API omits a zero-valued field
    return (
        page["width"]["magnitude"] - margin("marginLeft") - margin("marginRight"),
        page["height"]["magnitude"] - margin("marginTop") - margin("marginBottom"),
    )


def inline_image_elements(node):
    """Every inlineObjectElement under node (a body, a table cell, any nested dict or list), in document order."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "inlineObjectElement":
                yield value
            else:
                yield from inline_image_elements(value)
    elif isinstance(node, list):
        for item in node:
            yield from inline_image_elements(item)


def image_findings(container):
    """One finding per inline image in container, a documents.get reply (main tab) or a documentTab (an
    aside tab): {id, url, width, height, max_width, max_height, fits, links_to_view}. A missing size is
    fits=False. The checks the finish step and the aside verify read share."""
    if "tabs" in container and "body" not in container:
        die("image_findings needs a documentTab or a first-tab documents.get reply, not an includeTabsContent reply")
    elements = list(inline_image_elements(container.get("body", {})))
    if not elements:
        return []
    if "documentStyle" not in container:
        die("document has images but no documentStyle; image fit unknown")
    max_width, max_height = content_box(container["documentStyle"])
    findings = []
    for element in elements:
        image_id = element["inlineObjectId"]
        url = element.get("textStyle", {}).get("link", {}).get("url", "")
        size = container.get("inlineObjects", {}).get(image_id, {}).get("inlineObjectProperties", {}).get("embeddedObject", {}).get("size")
        width = size["width"].get("magnitude", 0) if size else None
        height = size["height"].get("magnitude", 0) if size else None
        fits = size is not None and width <= max_width and height <= max_height
        findings.append({
            "id": image_id, "url": url, "width": width, "height": height,
            "max_width": max_width, "max_height": max_height,
            "fits": fits, "links_to_view": url.startswith(IMAGE_LINK_PREFIX),
        })
    return findings
