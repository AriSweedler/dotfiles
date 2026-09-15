#!/usr/bin/env python3
"""Classify a Drive folder or Google Doc (URL or bare id) and print one tab URL
per line to stdout. Folder -> docs x tabs; doc -> tabs (depth-first). Discovery,
skips, and per-doc failures are logged to stderr.
"""
import argparse
import json
import re

from at_log import log_info, log_warn, log_err, die
from at_subprocess import run_capture

GWS_TIMEOUT_S = 90
TAB_URL = "https://docs.google.com/document/d/{doc_id}/edit?tab={tab_id}"
EDIT_URL = "https://docs.google.com/document/d/{doc_id}/edit"
DOC_MIME = "application/vnd.google-apps.document"
FOLDER_MIME = "application/vnd.google-apps.folder"

FOLDER_ID_RE = re.compile(r"/folders/([a-zA-Z0-9_-]+)")
DOC_ID_RE = re.compile(r"/(?:document|file)/d/([a-zA-Z0-9_-]+)")
OPEN_ID_RE = re.compile(r"[?&]id=([a-zA-Z0-9_-]+)")
BARE_ID_RE = re.compile(r"^[a-zA-Z0-9_-]{20,}$")


def parse_json_or_die(text, where):
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        die(f"{where} is not JSON | head='{text[:200]!r}'")
    if not isinstance(value, dict):
        die(f"{where} is not a JSON object | type='{type(value).__name__}'")
    return value


def gws_json(cmd, what):
    """Run a gws command under a timeout and parse its JSON stdout."""
    result = run_capture(cmd, GWS_TIMEOUT_S, what=what)
    return parse_json_or_die(result.stdout, f"{what} output")


# ----- source classification -----

def get_mime_type(resource_id):
    data = gws_json(
        ["gws", "drive", "files", "get", "--params",
         json.dumps({"fileId": resource_id, "fields": "mimeType", "supportsAllDrives": True}),
         "--format", "json"],
        what="gws drive files get",
    )
    return data.get("mimeType", "")


def classify_source(source):
    """Return ('folder', id) or ('doc', id). A /folders/ URL is a folder and a
    /document//file/ URL is a doc (unambiguous); an `?id=` URL or a bare id is
    ambiguous, so resolve it by Drive mimeType rather than assuming a doc."""
    folder_match = FOLDER_ID_RE.search(source)
    if folder_match:
        return ("folder", folder_match.group(1))
    doc_match = DOC_ID_RE.search(source)
    if doc_match:
        return ("doc", doc_match.group(1))
    open_match = OPEN_ID_RE.search(source)
    resource_id = open_match.group(1) if open_match else (source if BARE_ID_RE.match(source) else None)
    if resource_id is None:
        die(f"not a Drive folder or Google Doc | source='{source}' accepts='.../folders/<id>, .../document/d/<id>, ?id=<id>, or a bare id'")
    mime = get_mime_type(resource_id)
    if mime == FOLDER_MIME:
        return ("folder", resource_id)
    if mime == DOC_MIME:
        return ("doc", resource_id)
    die(f"unsupported Drive type | id='{resource_id}' mimeType='{mime}' supported='Google Doc or folder'")


# ----- gws fetches -----

def list_folder_contents(folder_id):
    """Return (docs, skipped_by_mime) for items directly in folder_id (non-recursive).
    docs = [(id, name)]; skipped_by_mime = {mimeType: count} for everything else."""
    docs = []
    skipped = {}
    page_token = None
    while True:
        params = {
            "q": f"'{folder_id}' in parents and trashed=false",
            "fields": "nextPageToken,files(id,name,mimeType)",
            "pageSize": 200,
            "orderBy": "name",
            "supportsAllDrives": True,
            "includeItemsFromAllDrives": True,
        }
        if page_token:
            params["pageToken"] = page_token
        data = gws_json(
            ["gws", "drive", "files", "list", "--params", json.dumps(params), "--format", "json"],
            what="gws drive files list",
        )
        for entry in data.get("files", []):
            if entry.get("mimeType") == DOC_MIME:
                docs.append((entry["id"], entry.get("name", "")))
            else:
                mime = entry.get("mimeType", "unknown")
                skipped[mime] = skipped.get(mime, 0) + 1
        page_token = data.get("nextPageToken")
        log_info(f"listed page | running_docs='{len(docs)}'")
        if not page_token:
            return docs, skipped


def fetch_tabs(doc_id):
    """Return [(tab_id, title), ...] for doc_id, depth-first over child tabs."""
    doc = gws_json(
        ["gws", "docs", "documents", "get", "--params",
         json.dumps({"documentId": doc_id, "includeTabsContent": True}), "--format", "json"],
        what="gws docs documents get",
    )
    tabs = []

    def walk(tab_list):
        for tab in tab_list:
            props = tab.get("tabProperties", {})
            tab_id = props.get("tabId")
            if tab_id:
                tabs.append((tab_id, props.get("title", "")))
            walk(tab.get("childTabs", []))

    walk(doc.get("tabs", []))
    return tabs


# ----- expansion -----

def emit_tab_links(doc_id, name):
    """Print one tab URL per tab of doc_id to stdout; log the doc to stderr.
    A doc with no enumerable tabs emits a single plain /edit URL — itself a valid
    unit to convert (the converter renders its body)."""
    tabs = fetch_tabs(doc_id)
    if not tabs:
        log_warn(f"no tabs returned, emitting plain edit url | doc_id='{doc_id}' name='{name}'")
        print(EDIT_URL.format(doc_id=doc_id), flush=True)
        return
    log_info(f"expanded doc | doc_id='{doc_id}' name='{name}' tabs='{len(tabs)}'")
    for tab_id, title in tabs:
        log_info(f"  tab | tab_id='{tab_id}' title='{title}'")
        print(TAB_URL.format(doc_id=doc_id, tab_id=tab_id), flush=True)


def expand_folder(folder_id):
    docs, skipped = list_folder_contents(folder_id)
    if not docs:
        breakdown = ", ".join(f"{mime}={count}" for mime, count in skipped.items()) or "none"
        die(f"no Google Docs in folder | folder_id='{folder_id}' other_items='{breakdown}' note='expands Google Docs only, non-recursively'")
    log_info(f"expanded folder | folder_id='{folder_id}' docs='{len(docs)}' skipped_non_docs='{sum(skipped.values())}'")
    failures = []
    for doc_id, name in docs:
        try:
            emit_tab_links(doc_id, name)
        except SystemExit:
            # One unreadable doc (un-shared, trashed, transient) must not abort the
            # rest of the fan-out; record it and keep going.
            log_err(f"skipped doc, expansion failed | doc_id='{doc_id}' name='{name}'")
            failures.append(doc_id)
    if failures:
        die(f"folder expansion incomplete | failed='{len(failures)}' of='{len(docs)}' note='links printed above are partial'")


# ----- entrypoint -----

def parse_args():
    parser = argparse.ArgumentParser(description="Expand a Drive folder or Google Doc into per-tab doc links.")
    parser.add_argument("source", nargs="?", help="Drive folder URL/id or Google Doc URL/id")
    return parser.parse_args()


def main():
    args = parse_args()
    if not args.source:
        die("nothing to expand | hint='pass a Drive folder or Google Doc URL/id'")
    kind, resource_id = classify_source(args.source)
    if kind == "folder":
        expand_folder(resource_id)
        return
    emit_tab_links(resource_id, "")


if __name__ == "__main__":
    main()
