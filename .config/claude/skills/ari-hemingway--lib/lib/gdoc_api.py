"""Docs API helpers shared by the hemingway publish scripts (share-gdoc's gdoc_asides.py and
structure-bookmark's gdoc_bookmarks.py).

On PYTHONPATH through each script's zsh entrypoint, beside at_log and at_subprocess. Everything here
either calls the gws CLI or walks a documents.get reply. The two literals both scripts must agree on
(the return-link text an aside tab carries, the marker text an aside puts in the body) live here too.
"""
import json
import shutil

from at_log import die, log_info
from at_subprocess import run_capture

GWS_TIMEOUT_S = 90
FIRST_TAB = "t.0"
RETURN_TEXT = "← Return to main article"


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


def gws_json(args, what):
    """A gws call that must succeed; dies with the gws stderr otherwise."""
    result = run_capture(["gws", *args, "--format", "json"], timeout_s=GWS_TIMEOUT_S, what=what)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        die(f"{what}: reply is not JSON | error='{exc}' head='{result.stdout[:200]}'")


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
