"""Bookmarks in a published Google Doc: a link to a sentence, not a section.

Draft dialect (/ari-hemingway--structure-bookmark): `[text](#bm-<slug>)` in the main body puts a bookmark
on that text (the link style is removed once the bookmark exists, so the text renders plain) and
`[text](#goto-<slug>)`, anywhere, links to it. Every `#aside-n` marker (/ari-hemingway--structure-aside)
is an implicit target: its tab's return links move from the heading above the marker onto the marker.

The Docs REST API cannot create bookmarks; Apps Script can. --apply runs addBookmarks in the Apps Script
project under bin/gas through scripts.run, then sends one batchUpdate that points every #goto- link and
aside return link at link.bookmark and strips the #bm- link style. Bookmarks die on republish like tabs,
so gdoc_publish.zsh runs --check-setup and then --apply --execute after every publish.

Modes: --check-setup (one line per prerequisite in dependency order: scopes, api, project, content,
deployment, run; OK or the exact next command or click path; exit 1 if anything is missing), --configure
(record the script and deployment ids), --apply. --configure and --apply are dry runs unless the
entrypoint hands them --execute, which it does only when lib/dry_run.zsh resolved this run to act.
"""
import argparse
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

from skill_log import die, log_info, log_warn
from gdoc_api import (
    FIRST_TAB,
    GWS_TIMEOUT_S,
    RETURN_TEXT,
    all_tabs,
    batch_update,
    check_gws,
    doc_id_from,
    fetch_doc,
    first_tab,
    gws_json,
    marker_text,
    paragraphs,
    run_link,
    runs_in,
    text_runs,
)

CONFIG_PATH = Path.home() / ".local" / "share" / "ari-hemingway" / "gdoc_bookmarks.json"
GAS_DIR = Path(__file__).resolve().parent / "gas"
SELF = "zsh $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gdoc_bookmarks.zsh"
# gws rejects an absolute --dir ("--dir must be a relative path"), so the push runs from inside bin/gas.
PUSH_COMMAND = "(cd $HOME/.claude/skills/ari-hemingway--structure-bookmark/bin/gas && gws script +push --script {script_id} --dir .)"
API_DISABLED_MARKER = "has not enabled the Apps Script API"
SCOPES_NEEDED = ("https://www.googleapis.com/auth/script.projects", "https://www.googleapis.com/auth/script.deployments")
# Publishing itself needs these; a re-login must carry them too, because `gws auth login` replaces the
# token's whole scope set (a login with `-s script` dropped documents and drive on 2026-09-23).
PUBLISH_SCOPES = ("https://www.googleapis.com/auth/documents", "https://www.googleapis.com/auth/drive")
USER_SETTINGS_URL = "https://script.google.com/home/usersettings"
GWS_CLIENT_SECRET = Path.home() / ".config" / "gws" / "client_secret.json"
ASIDE_TAB_RE = re.compile(r"^Aside (\d+):")
SECTION_RE = re.compile(r"^# Aside (\d+):")
H1_RE = re.compile(r"^# ")
FOOTER_PREFIX = "🤖🌸"
ANCHOR_RE = re.compile(r"\[([^\]]+)\]\(#(bm|goto|aside)-([a-z0-9][a-z0-9-]*)\)")
LOOSE_ANCHOR_RE = re.compile(r"\]\(#(?:bm|goto)-[^)]*\)")
MARKUP_RE = re.compile(r"`|\*")
PING_FUNCTION = "ping"
ADD_FUNCTION = "addBookmarks"
OK, MISSING, SKIPPED = "OK", "MISSING", "SKIPPED"


# --- Setup probes ---


def gws_gcp_project():
    """The GCP project of the OAuth client gws signs in with; scripts.run needs the script on the same one."""
    try:
        return json.loads(GWS_CLIENT_SECRET.read_text(encoding="utf-8"))["installed"]["project_id"]
    except (OSError, json.JSONDecodeError, KeyError) as err:
        log_warn(f"cannot read the gws GCP project | path='{GWS_CLIENT_SECRET}' err='{type(err).__name__}: {err}'")
        return "<the project_id in ~/.config/gws/client_secret.json>"


def gws_probe(args, json_flag=True):
    """A setup probe that must tolerate an API error: returns (ok, reply_or_message). Bounded like
    run_capture, but a non-zero exit is data here, not a reason to die. `gws auth status` prints JSON
    on its own and rejects --format, hence json_flag."""
    command = ["gws", *args, "--format", "json"] if json_flag else ["gws", *args]
    try:
        result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", timeout=GWS_TIMEOUT_S)
    except FileNotFoundError:
        return False, "gws binary not found"
    except subprocess.TimeoutExpired:
        return False, f"gws timed out after {GWS_TIMEOUT_S}s"
    try:
        reply = json.loads(result.stdout)
    except json.JSONDecodeError:
        return False, (result.stderr.strip() or result.stdout.strip())[:300]
    if isinstance(reply, dict) and "error" in reply:
        return False, reply["error"]
    return result.returncode == 0, reply


def error_text(error):
    if isinstance(error, dict):
        return f"{error.get('code', '')} {error.get('status', '')} {error.get('message', '')}".strip()
    return str(error)


def load_config():
    if not CONFIG_PATH.exists():
        return {}
    try:
        return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as err:
        die(f"bookmark config is not JSON | path='{CONFIG_PATH}' err='{err}' fix='delete it, then re-run {SELF} --check-setup'")


def save_config(config):
    CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_PATH.write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")


# --- Dry run ---


def is_dry_run(args):
    """lib/dry_run.zsh decides in the entrypoint, which hands on --execute only when this run acts and
    exports DRY_RUN=0 then. Missing either, the run is a dry run."""
    return not (args.execute and os.environ.get("DRY_RUN") == "0")


def outcome(dry_run, done, planned):
    """A dry run logs what it would do: a past-tense line there reads as if the Doc already changed."""
    if dry_run:
        return planned
    return done


def report_dry_run(dry_run, changes):
    """The closing log line, worded as lib/dry_run.zsh's report_dry_run words it."""
    if changes == 0:
        log_info("Nothing to change | changes='0'")
        return
    if not dry_run:
        log_info(f"Executed | changes='{changes}'")
        return
    rerun = f"{SELF} {shlex.join(sys.argv[1:])} --execute"
    log_info(f"Dry run; nothing changed | changes='{changes}' rerun='{rerun}'")


def check_scopes():
    ok, reply = gws_probe(["auth", "status"], json_flag=False)
    if not ok:
        return MISSING, f"gws auth status failed: {error_text(reply)}"
    have = list(reply.get("scopes", []))
    lacking = [scope for scope in SCOPES_NEEDED if scope not in have]
    lacking_publish = [scope for scope in PUBLISH_SCOPES if scope not in have]
    if lacking or lacking_publish:
        wanted = list(dict.fromkeys([*have, *PUBLISH_SCOPES, *SCOPES_NEEDED]))
        names = ", ".join(s.rsplit("/", 1)[1] for s in [*lacking_publish, *lacking])
        publish_note = " (publishing needs documents and drive too, and they are missing now)" if lacking_publish else ""
        return MISSING, (
            f"token lacks {names}{publish_note}; a login replaces the whole scope set, so run: "
            f"gws auth login --scopes {','.join(wanted)}"
        )
    return OK, "token carries script.projects and script.deployments (and documents, drive)"


def check_api(config):
    """The per-user Apps Script API toggle. projects.get on the recorded id, or on a placeholder when
    none is recorded, answers 403 'User has not enabled the Apps Script API' while it is off; any
    other answer (the project, or a 404 for the placeholder) means the API is reachable."""
    script_id = config.get("scriptId") or "api-probe"
    ok, reply = gws_probe(["script", "projects", "get", "--params", json.dumps({"scriptId": script_id})])
    if ok:
        return OK, "Apps Script API enabled for this user"
    message = error_text(reply)
    if API_DISABLED_MARKER in message:
        return MISSING, f"Apps Script API is off for this user: open {USER_SETTINGS_URL} and turn on 'Google Apps Script API'"
    return OK, f"Apps Script API reachable (probe answered: {message[:80]})"


def check_config(config):
    if config.get("scriptId"):
        return OK, f"scriptId={config['scriptId']} in {CONFIG_PATH}"
    return MISSING, f"no script project recorded; run: gws script projects create --json '{{\"title\":\"gdoc bookmarks\"}}'  then: {SELF} --configure --script-id <scriptId from the reply> --execute"


def local_gas_files():
    return {path.stem: path.read_text(encoding="utf-8").strip() for path in sorted(GAS_DIR.iterdir()) if path.suffix in (".gs", ".json")}


def check_content(config):
    ok, reply = gws_probe(["script", "projects", "getContent", "--params", json.dumps({"scriptId": config["scriptId"]})])
    if not ok:
        return MISSING, f"projects.getContent failed: {error_text(reply)[:200]}"
    remote = {f["name"]: (f.get("source") or "").strip() for f in reply.get("files", [])}
    local = local_gas_files()
    stale = [name for name, source in local.items() if remote.get(name) != source]
    if stale:
        return MISSING, f"project files differ from bin/gas ({', '.join(stale)}); run: {PUSH_COMMAND.format(script_id=config['scriptId'])}"
    return OK, f"project files match bin/gas ({', '.join(sorted(local))})"


def check_deployment(config):
    ok, reply = gws_probe(["script", "projects", "deployments", "list", "--params", json.dumps({"scriptId": config["scriptId"]})])
    if not ok:
        return MISSING, f"deployments.list failed: {error_text(reply)[:200]}"
    # Apps Script creates a HEAD deployment (no versionNumber) by itself; only a deployment of a
    # numbered version with an EXECUTION_API entry point counts.
    deployments = reply.get("deployments", [])
    executable = [
        d["deploymentId"]
        for d in deployments
        if d.get("deploymentConfig", {}).get("versionNumber") is not None
        and any(e.get("entryPointType") == "EXECUTION_API" for e in d.get("entryPoints", []))
    ]
    head = [d["deploymentId"] for d in deployments if d.get("deploymentConfig", {}).get("versionNumber") is None]
    ignored = f" (ignoring the automatic HEAD deployment {', '.join(head)})" if head else ""
    wanted = config.get("deploymentId")
    if wanted and wanted in executable:
        return OK, f"API-executable deployment {wanted}{ignored}"
    if wanted:
        return MISSING, f"deploymentId {wanted} is not a versioned API-executable deployment of this project (found: {executable or 'none'}{ignored}); re-run: {SELF} --configure --script-id {config['scriptId']} --deployment-id <id> --execute"
    if executable:
        return MISSING, f"deployment(s) exist but none is recorded ({', '.join(executable)}{ignored}); run: {SELF} --configure --script-id {config['scriptId']} --deployment-id {executable[-1]} --execute"
    create_version = f"gws script projects versions create --params '{{\"scriptId\":\"{config['scriptId']}\"}}' --json '{{\"description\":\"gdoc bookmarks\"}}'"
    create_deployment = f"gws script projects deployments create --params '{{\"scriptId\":\"{config['scriptId']}\"}}' --json '{{\"versionNumber\":<versionNumber from the reply>,\"manifestFileName\":\"appsscript\",\"description\":\"gdoc bookmarks\"}}'"
    return MISSING, f"no versioned API-executable deployment{ignored}; run: {create_version}  then: {create_deployment}  then: {SELF} --configure --script-id {config['scriptId']} --deployment-id <deploymentId from the reply> --execute"


def check_run_probe(config):
    body = json.dumps({"function": PING_FUNCTION, "devMode": True})
    ok, reply = gws_probe(["script", "scripts", "run", "--params", json.dumps({"scriptId": config["deploymentId"]}), "--json", body])
    if not ok:
        message = error_text(reply)
        if "PERMISSION_DENIED" in message or "403" in message:
            project = gws_gcp_project()
            return MISSING, (
                f"scripts.run is refused: the script must share the caller's GCP project. Open https://script.google.com/home/projects/{config['scriptId']}/settings, "
                f"under 'Google Cloud Platform (GCP) Project' click 'Change project' and enter the project number of {project} (gcloud projects describe {project} --format='value(projectNumber)')  ({message[:120]})"
            )
        if "404" in message or "NOT_FOUND" in message:
            return MISSING, f"deployment {config['deploymentId']} not found by scripts.run; re-run the deployment step  ({message[:120]})"
        return MISSING, f"scripts.run failed: {message[:200]}"
    result = reply.get("response", {}).get("result")
    if result != "ok":
        return MISSING, f"ping returned {result!r}; push bin/gas again: {PUSH_COMMAND.format(script_id=config['scriptId'])}"
    return OK, "scripts.run reaches the project (ping returned ok)"


def run_check_setup():
    """Print one line per prerequisite. A MISSING prerequisite skips the ones that depend on it."""
    config = load_config()
    steps = [
        ("scopes", lambda: check_scopes()),
        ("api", lambda: check_api(config)),
        ("project", lambda: check_config(config)),
        ("content", lambda: check_content(config)),
        ("deployment", lambda: check_deployment(config)),
        ("run", lambda: check_run_probe(config)),
    ]
    blocked_by = None
    for name, step in steps:
        if blocked_by is not None:
            print(f"{SKIPPED:<8} {name}: blocked by {blocked_by}")
            continue
        if name == "run" and not config.get("deploymentId"):
            print(f"{SKIPPED:<8} {name}: blocked by deployment")
            continue
        status, detail = step()
        print(f"{status:<8} {name}: {detail}")
        if status == MISSING:
            blocked_by = name
    if blocked_by is not None:
        raise SystemExit(1)


def record_config(config, previous, dry_run):
    """Write the config when it changed. Returns the writes this run makes: 0 or 1."""
    record = f"path='{CONFIG_PATH}' scriptId='{config.get('scriptId')}' deploymentId='{config.get('deploymentId', '')}' previous='{json.dumps(previous)}'"
    if config == previous:
        log_info(f"bookmark setup already recorded | {record}")
        return 0
    if dry_run:
        log_info(f"would record bookmark setup | {record}")
        return 1
    save_config(config)
    log_info(f"bookmark setup recorded | {record}")
    return 1


def run_configure(args, dry_run):
    config = load_config()
    previous = dict(config)
    if args.script_id and args.script_id != config.get("scriptId") and not args.deployment_id and "deploymentId" in config:
        log_warn(f"new script project; dropping the old project's deployment | scriptId='{args.script_id}' dropped_deploymentId='{config['deploymentId']}'")
        del config["deploymentId"]
    if args.script_id:
        config["scriptId"] = args.script_id
    if args.deployment_id:
        config["deploymentId"] = args.deployment_id
    if not config.get("scriptId"):
        die("--configure needs --script-id at least once")
    changes = record_config(config, previous, dry_run)
    report_dry_run(dry_run, changes)
    print(json.dumps({"config": str(CONFIG_PATH), "changes": changes, "dry_run": int(dry_run)}))


# --- Draft parsing ---


def plain_text(label):
    """The label as the Doc renders it: the import drops code-span and emphasis delimiters, and a
    re-apply finds the target by this text."""
    return MARKUP_RE.sub("", label)


def check_anchor_forms(line):
    """A #bm-/#goto- link ANCHOR_RE cannot read would otherwise be skipped silently and fail verify
    only after the Doc was written."""
    readable = {m.end() for m in ANCHOR_RE.finditer(line)}
    for loose in LOOSE_ANCHOR_RE.finditer(line):
        if loose.end() not in readable:
            die(f"malformed #bm-/#goto- link | link='{loose.group(0)}' expected='[text](#bm-<slug>) with a kebab-case slug ([a-z0-9-], starting with a letter or digit) and text on one line with no ]'")


def parse_draft(path):
    """Return (targets {key: {url, text}}, gotos [(slug, text)]). Aside markers are implicit targets;
    a #bm- inside an aside section is rejected, since bookmarks are created in the first tab only."""
    if not Path(path).is_file():
        die(f"draft not found | file='{path}' expected='the full draft the Doc was published from'")
    lines = Path(path).read_text(encoding="utf-8").split("\n")
    targets, gotos = {}, []
    in_aside = None
    for line in lines:
        section = SECTION_RE.match(line)
        if section:
            in_aside = int(section.group(1))
        elif in_aside is not None and (H1_RE.match(line) or line.startswith(FOOTER_PREFIX)):
            in_aside = None
        check_anchor_forms(line)
        for match in ANCHOR_RE.finditer(line):
            label, kind, slug = plain_text(match.group(1)), match.group(2), match.group(3)
            if kind == "bm":
                if in_aside is not None:
                    die(f"#bm- inside an aside body; bookmarks live in the main body, #goto- may point here | aside='{in_aside}' slug='{slug}' text='{label}'")
                key = f"bm-{slug}"
                if key in targets:
                    die(f"bookmark slug used twice | slug='{slug}' text='{label}'")
                targets[key] = {"url": f"#bm-{slug}", "text": label}
            elif kind == "goto":
                gotos.append((slug, label))
            elif in_aside is None and label == marker_text(slug):
                targets[f"aside-{slug}"] = {"url": f"#aside-{slug}", "text": label}
    dangling = sorted({slug for slug, _ in gotos if f"bm-{slug}" not in targets})
    if dangling:
        die(f"#goto- links with no #bm- target | slugs='{dangling}' hint='to point at an aside, use a reference by title instead'")
    return targets, gotos


# --- Apply ---


def add_bookmarks(doc, targets, config, dry_run):
    """Run addBookmarks; in a dry run, placeholder ids stand in for the ids it would return."""
    payload = [{"key": key, "url": t["url"], "text": t["text"]} for key, t in targets.items()]
    body = json.dumps({"function": ADD_FUNCTION, "parameters": [doc, payload], "devMode": True}, ensure_ascii=False)
    if dry_run:
        log_info(f"would run scripts.run addBookmarks | doc='{doc}' deployment='{config['deploymentId']}' targets='{len(payload)}'")
        return {key: f"BOOKMARK_{key}" for key in targets}
    log_info(f"running scripts.run addBookmarks | doc='{doc}' targets='{len(payload)}'")
    reply = gws_json(["script", "scripts", "run", "--params", json.dumps({"scriptId": config["deploymentId"]}), "--json", body], what="scripts.run addBookmarks")
    if "error" in reply:
        die(f"addBookmarks failed | error='{json.dumps(reply['error'])[:300]}'")
    result = reply.get("response", {}).get("result") or {}
    missing = sorted(set(targets) - set(result))
    if missing:
        die(f"addBookmarks returned no id for some targets | missing='{missing}'")
    log_info(f"bookmarks added | count='{len(result)}'")
    return result


def link_style(tab_id, run, style):
    return {"updateTextStyle": {"range": {"tabId": tab_id, "startIndex": run["startIndex"], "endIndex": run["endIndex"]}, "textStyle": style, "fields": "link"}}


def bookmark_link(bookmark_id):
    return {"link": {"bookmark": {"id": bookmark_id, "tabId": FIRST_TAB}}}


def build_relink_requests(doc_json, gotos, bookmarks):
    """Point every #goto- run and aside return run at its bookmark; strip the link from every #bm- run."""
    requests = []
    # Every #goto- label, so a re-apply (the #goto- URLs already relinked) finds each one by its text.
    key_by_goto_text = {text: f"bm-{slug}" for slug, text in gotos}
    for props, tab in all_tabs(doc_json):
        tab_id = props["tabId"]
        aside = ASIDE_TAB_RE.match(props.get("title", ""))
        aside_key = f"aside-{aside.group(1)}" if aside else None
        for run in runs_in(tab):
            link, content = run_link(run), run["textRun"]["content"]
            url = link.get("url", "")
            if url.startswith("#goto-"):
                key = f"bm-{url[len('#goto-'):]}"
                if key not in bookmarks:
                    die(f"the Doc links to a slug the draft does not bookmark | url='{url}' fix='pass --file the draft this Doc was published from'")
                requests.append(link_style(tab_id, run, bookmark_link(bookmarks[key])))
            elif "bookmark" in link and content in key_by_goto_text:
                requests.append(link_style(tab_id, run, bookmark_link(bookmarks[key_by_goto_text[content]])))
            elif url.startswith("#bm-") and tab_id == FIRST_TAB:
                requests.append(link_style(tab_id, run, {}))
            elif aside_key in bookmarks and content == RETURN_TEXT and link:
                requests.append(link_style(tab_id, run, bookmark_link(bookmarks[aside_key])))
    return requests


def anchor_runs(doc_json):
    """[(tabId, startIndex, url)] of every run still linked to #bm- or #goto-."""
    return [
        (props["tabId"], run["startIndex"], run_link(run).get("url", ""))
        for props, tab in all_tabs(doc_json)
        for run in runs_in(tab)
        if run_link(run).get("url", "").startswith(("#bm-", "#goto-"))
    ]


def verify(doc_json, bookmarks):
    leftovers = [url for _, _, url in anchor_runs(doc_json)]
    if leftovers:
        die(f"anchor links left after apply | urls='{leftovers}'")
    links = [run_link(run)["bookmark"] for _, tab in all_tabs(doc_json) for run in runs_in(tab) if "bookmark" in run_link(run)]
    # addBookmarks removed every first-tab bookmark, so a link to any id it did not return goes nowhere.
    stale = sorted({b.get("id") for b in links if b.get("tabId", FIRST_TAB) == FIRST_TAB} - set(bookmarks.values()))
    if stale:
        die(f"links to bookmarks this apply removed | ids='{stale}' fix='a #goto- label the draft no longer has; edit the link in the Doc or republish'")
    return len(links)


def paragraph_texts(tab):
    return ["".join(run["textRun"]["content"] for run in text_runs(p)) for p in paragraphs(tab)]


def check_targets(doc_json, targets):
    """What addBookmarks does first, read from the Doc: each target by its link URL in the first tab, else
    by text that occurs exactly once there. It runs before any write, in a dry run too: Bookmarks.gs
    removes every bookmark before it looks a target up."""
    tab = first_tab(doc_json)
    urls = {run_link(run).get("url", "") for run in runs_in(tab)}
    texts = paragraph_texts(tab)
    for key, target in targets.items():
        if target["url"] in urls:
            continue
        hits = sum(text.count(target["text"]) for text in texts)
        if hits == 0:
            die(f"target not found in the first tab | key='{key}' text='{target['text']}' fix='pass --file the draft this Doc was published from'")
        if hits > 1:
            die(f"target text occurs more than once | key='{key}' text='{target['text']}' hits='{hits}' fix='bookmark a longer, unique phrase and republish'")


def verify_plan(doc_json, requests):
    """The dry run's verify: every #bm- and #goto- run has a request in the relink batch, else the
    real run would leave it and fail verify."""
    planned = {(r["updateTextStyle"]["range"]["tabId"], r["updateTextStyle"]["range"]["startIndex"]) for r in requests}
    leftovers = [url for tab_id, start, url in anchor_runs(doc_json) if (tab_id, start) not in planned]
    if leftovers:
        die(f"anchor links the relink batch would leave | urls='{leftovers}'")


def run_apply(args, dry_run):
    doc = doc_id_from(args.doc)
    targets, gotos = parse_draft(args.file)
    if not targets:
        log_info(f"nothing to bookmark | file='{args.file}'")
        report_dry_run(dry_run, 0)
        print(json.dumps({"doc": doc, "bookmarks": {}, "relinked_runs": 0, "dry_run": int(dry_run)}))
        return
    config = load_config()
    if not config.get("deploymentId"):
        die(f"bookmark setup incomplete; run: {SELF} --check-setup")
    doc_json = fetch_doc(doc)
    log_info(f"{outcome(dry_run, 'applying bookmarks', 'would apply bookmarks')} | doc='{doc}' title='{doc_json.get('title', '')}' targets='{len(targets)}' goto_links='{len(gotos)}'")
    check_targets(doc_json, targets)
    if dry_run:
        print(json.dumps({"targets": targets, "gotos": gotos}, ensure_ascii=False))
    bookmarks = add_bookmarks(doc, targets, config, dry_run)
    doc_json = fetch_doc(doc)
    requests = build_relink_requests(doc_json, gotos, bookmarks)
    for key in sorted(targets):
        log_info(f"{outcome(dry_run, 'bookmark target', 'would bookmark target')} | key='{key}' text='{targets[key]['text']}' bookmark='{bookmarks[key]}'")
    batch_update(doc, requests, doc_json["revisionId"], dry_run, what="relink batch")
    changes = 1 + (1 if requests else 0)
    summary = {"doc": doc, "bookmarks": bookmarks, "relinked_runs": len(requests), "dry_run": int(dry_run)}
    if dry_run:
        verify_plan(doc_json, requests)
        report_dry_run(dry_run, changes)
        print(json.dumps(summary, ensure_ascii=False))
        return
    count = verify(fetch_doc(doc), bookmarks)
    log_info(f"bookmarks applied | targets='{len(targets)}' relinked_runs='{len(requests)}' bookmark_links='{count}'")
    report_dry_run(dry_run, changes)
    print(json.dumps(summary, ensure_ascii=False))


def parse_args():
    parser = argparse.ArgumentParser(description="Bookmarks in a published Google Doc: check the Apps Script setup, record it, or apply the draft's bookmarks.")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check-setup", dest="check_setup", action="store_true", help="one line per prerequisite: OK, or the next command or click path")
    mode.add_argument("--configure", action="store_true", help="record --script-id and --deployment-id")
    mode.add_argument("--apply", action="store_true", help="add the draft's bookmarks to --doc and relink")
    parser.add_argument("--script-id", dest="script_id", help="--configure: Apps Script project id")
    parser.add_argument("--deployment-id", dest="deployment_id", help="--configure: API-executable deployment id")
    parser.add_argument("--doc", help="--apply: Google Doc id or URL")
    parser.add_argument("--file", help="--apply: the markdown draft")
    parser.add_argument("--execute", action="store_true", help="--configure, --apply: write; the entrypoint passes it only when lib/dry_run.zsh resolved this run to act")
    return parser.parse_args()


def main():
    args = parse_args()
    check_gws()
    if args.check_setup:
        run_check_setup()
        return
    dry_run = is_dry_run(args)
    if args.configure:
        run_configure(args, dry_run)
        return
    if not args.doc or not args.file:
        die("--apply needs --doc and --file")
    run_apply(args, dry_run)


if __name__ == "__main__":
    main()
