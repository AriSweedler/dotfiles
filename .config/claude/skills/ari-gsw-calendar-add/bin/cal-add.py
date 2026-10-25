#!/usr/bin/env python3
"""Add one Google Calendar event from a JSON object, via the gws CLI. The script does the checking; the caller only
extracts fields. It prints ONE JSON line and never a traceback.

Usage (JSON on stdin, or flags):
  python3 cal-add.py [--concert] [--dry-run] <<'JSON'
  {"title": "...", "start": "...", "location": "...", "source": "<the text the fields were read from>"}
  JSON
  python3 cal-add.py --concert --title "..." --start "2026-11-14 20:30" --location "..." --description "Doors: 7:30 PM" --source "..."

Fields (aliases in parentheses are accepted and renamed):
  title (artist, summary)  required  event title; bare artist on the Concerts calendar
  start (datetime)         required  "YYYY-MM-DD HH:MM", "YYYY-MM-DD 8:00 PM" or RFC3339; "date" + "time" also accepted
  end                      optional  same formats; default start + 2 hours
  tz (timezone)            optional  IANA zone of the venue, default America/Los_Angeles
  calendar                 optional  calendar NAME or id; default primary; forced to Concerts by --concert
  location (venue)         required  venue (and address when known)
  description (notes)      optional  list of lines, one fact per line
  attendees                optional  list of email addresses
  source (text)            optional  the text the fields were read from. The script adds what it can see itself: the last
                                     OCR output (~/.openclaw/media/ocr-last.txt) and the user messages of the last 15 min
                                     from OpenClaw's transcript store. Every URL, dollar amount and clock time in the
                                     description must appear in that text, else the line is dropped; a start equal to the
                                     doors time is refused. With no text at all, every such line is dropped.
  allowPast                optional  true to accept a start more than 12 hours ago

Output (default): when a chat spoke in the last 15 min the script delivers the reply itself through `openclaw message
send` (3 tries) and prints only "SENT to telegram <chat> [topic n]. ... Reply with exactly: NO_REPLY"; otherwise the
reply text plus a "NOT SENT: <why>" line (--no-send forces this); "FIX: <what to change>" when the caller's input was wrong. The Doors and Purchased lines are derived from the source text, not the caller.
With --json, one JSON line instead:
  {"ok": true, "id", "htmlLink", "calendar", "summary", "start", "end", "dropped": [...], "reply": "<text to send>"}
  {"ok": true, "duplicate": true, ...}                     an identical event existed; nothing created
  {"ok": false, "error", "reply": "<text to send>"}         the user must supply something
  {"ok": false, "error", "retry": true, "fix": "<what to change>"}   the caller's JSON was wrong; fix it, run once more
"""
import json, os, pathlib, re, shutil, sqlite3, subprocess, sys, time
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

GWS = shutil.which("gws") or "/opt/homebrew/bin/gws"
HOME = pathlib.Path.home()
GWS_KEY_FILE = HOME / ".config/gws/.encryption_key"   # file keyring backend: works headless, never touches the keychain
OCR_LAST = HOME / ".openclaw/media/ocr-last.txt"       # written by the ocr-image wrapper OpenClaw runs on each image
TRANSCRIPT_DB = HOME / ".openclaw/agents/main/agent/openclaw-agent.sqlite"
CONTEXT_WINDOW_S = 15 * 60
SENT_LOG = HOME / ".openclaw/media/cal-add-last-sent.json"   # dedupe: the same reply is not sent twice within 10 min
OPENCLAW = shutil.which("openclaw") or "/opt/homebrew/bin/openclaw"
PLATFORMS = ("Ticketweb", "Ticketmaster", "AXS", "Eventbrite", "DICE", "Dothebay", "See Tickets", "Etix", "Tixr", "Shotgun", "RA")
SPOTIFY = HOME / ".claude/skills/ari-spotify/bin/spotify.zsh"   # the teaser playlist (ari-spotify skill); concerts only
TEASER_TIMEOUT_S = 150   # a cold Liked Songs fetch (~4000 songs) takes ~40 s
ALIASES = {"artist": "title", "summary": "title", "datetime": "start", "timezone": "tz", "venue": "location",
           "notes": "description", "text": "source"}
KNOWN = {"title", "start", "end", "tz", "calendar", "location", "description", "attendees", "source", "allowPast",
         "date", "time"}
URL_RE = re.compile(r"https?://\S+", re.I)
MONEY_RE = re.compile(r"\$\s?\d[\d,]*(?:\.\d{2})?")
CLOCK_RE = re.compile(r"\b\d{1,2}(?::\d{2})?\s*(?:am|pm)\b", re.I)
PLAIN_RE = re.compile(r"\b\d{1,2}:\d{2}\b")
NEED_USER = "I could not read the {what} from that. Reply with it and I will add the event."


JSON_MODE = False
SEND = True


def current_chat():
    """The chat whose user spoke most recently (within the window): OpenClaw's session store keeps each channel session's
    delivery route. Returns (session_id, route) or (None, None) for a CLI run with no live chat."""
    try:
        con = sqlite3.connect(f"file:{TRANSCRIPT_DB}?mode=ro", uri=True, timeout=2)
        rows = con.execute("select current_session_id, entry_json from session_nodes").fetchall()
        con.close()
    except Exception:
        return None, None
    best, best_t = None, (time.time() - CONTEXT_WINDOW_S) * 1000
    for sid, raw in rows:
        try:
            e = json.loads(raw)
        except Exception:
            continue
        route = ((e.get("delivery") or {}).get("route") or {})
        t = e.get("lastInteractionAt") or 0
        if route.get("channel") and t > best_t:
            best, best_t = (sid, route), t
    return best or (None, None)


def rename_topic(route, name):
    """Rename the Telegram forum topic the request came from to the house form 'YYYY-MM-DD | Artist | Venue'. The bot
    is a group admin with the manage-topics right; Bot API editForumTopic. Returns a status string, never raises."""
    thread = str((route or {}).get("thread", {}).get("id") or "") if isinstance((route or {}).get("thread"), dict) else ""
    chat = str(((route or {}).get("target") or {}).get("to") or "")
    if (route or {}).get("channel") != "telegram" or not thread or thread == "1" or not chat.startswith("-100"):
        return "topic not renamed: not a Telegram forum topic"
    try:
        token = json.loads((HOME / ".openclaw/openclaw.json").read_text(encoding="utf-8"))["channels"]["telegram"]["botToken"]
    except Exception as e:
        return f"topic not renamed: no bot token ({type(e).__name__})"
    import urllib.request, urllib.parse, urllib.error
    data = urllib.parse.urlencode({"chat_id": chat, "message_thread_id": thread, "name": name[:128]}).encode()
    try:
        with urllib.request.urlopen(f"https://api.telegram.org/bot{token}/editForumTopic", data=data, timeout=20) as r:
            ok = json.loads(r.read().decode()).get("ok")
        return f"topic renamed to {name[:128]}" if ok else "topic not renamed: Telegram said no"
    except urllib.error.HTTPError as e:
        return f"topic not renamed: HTTP {e.code} {e.read().decode('utf-8', 'replace')[:120]}"
    except Exception as e:
        return f"topic not renamed: {type(e).__name__}"


def send_reply(text, route):
    """Deliver the reply to the chat ourselves, so no model has to copy it. Returns a status line."""
    to = str((route.get("target") or {}).get("to") or "")
    chat = re.sub(r"^telegram:", "", to).split(":topic:")[0]
    thread = (route.get("thread") or {}).get("id")
    if not chat:
        return "NOT SENT: no chat target in the route"
    try:
        last = json.loads(SENT_LOG.read_text())
        if last.get("text") == text and time.time() - last.get("at", 0) < 600:
            return "NOT SENT: identical reply was sent less than 10 minutes ago"
    except Exception:
        pass
    cmd = [OPENCLAW, "message", "send", "--channel", str(route["channel"]), "--target", chat, "-m", text]
    if route.get("accountId"):
        cmd += ["--account", str(route["accountId"])]
    if thread is not None:
        cmd += ["--thread-id", str(thread)]
    err = ""
    for attempt in range(3):   # Telegram's API drops a request now and then; three tries a few seconds apart
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        except Exception as e:
            return f"NOT SENT: openclaw message send did not run: {e}"
        if p.returncode == 0:
            break
        err = (p.stderr or p.stdout).strip()[-200:]
        time.sleep(4)
    else:
        return f"NOT SENT: openclaw message send failed 3 times: {err}"
    try:
        SENT_LOG.parent.mkdir(parents=True, exist_ok=True)
        SENT_LOG.write_text(json.dumps({"text": text, "at": time.time()}))
    except OSError:
        pass
    return f"SENT to {route['channel']} {chat}" + (f" topic {thread}" if thread is not None else "")


def out(obj, code=0):
    """Default output: the reply text, then a SENT/NOT SENT line when a live chat exists (the script delivers the reply
    itself); "FIX: ..." when the caller's input was wrong. --json prints the record instead."""
    if obj.get("reply") and SEND and not obj.get("dryRun"):
        _, route = current_chat()
        obj["sent"] = send_reply(obj["reply"], route) if route else "NOT SENT: no live chat (CLI run)"
    if JSON_MODE:
        print(json.dumps(obj, ensure_ascii=False))
    elif obj.get("retry"):
        print("FIX: " + obj["fix"])
    elif obj.get("reply"):
        if str(obj.get("sent", "")).startswith("SENT"):
            # The chat already has the full reply. Give the caller nothing to paraphrase: just what to answer.
            print("NO_REPLY")   # the chat already has the reply; this is the whole answer the caller should give
        else:
            print(obj["reply"])
            if obj.get("sent"):
                print(obj["sent"])
    else:
        print(json.dumps(obj, ensure_ascii=False))
    sys.exit(code)


def gws_env():
    """Prefer the file backend whenever its key file exists: gws then needs no keychain, so plain ssh and the gateway
    both work and nothing can trip the credential deletion."""
    env = dict(os.environ)
    if GWS_KEY_FILE.exists():
        env["GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND"] = "file"
    return env


def keychain_reachable():
    """gws keeps its encryption key in the login keychain and DELETES credentials.enc when decryption fails, which is
    what happens in a session without keychain access (plain ssh). Refuse to call gws from such a session."""
    if sys.platform != "darwin":
        return True
    p = subprocess.run(["security", "show-keychain-info", pathlib.Path.home() / "Library/Keychains/login.keychain-db"],
                       capture_output=True, text=True)
    return p.returncode == 0


def need(what):
    out({"ok": False, "error": f"{what} is required", "reply": NEED_USER.format(what=what)}, 1)


def bad(error, fix):
    out({"ok": False, "error": error, "retry": True, "fix": fix}, 1)


def gws(*args):
    # stdout only: gws prints keyring chatter on stderr, which would corrupt the JSON.
    env = gws_env()
    if env.get("GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND") != "file" and not keychain_reachable():
        out({"ok": False, "error": "login keychain not reachable from this session; gws would delete its credentials",
             "reply": "The laptop keychain is locked in this session, so I did not touch Google Calendar. Ari: run this from the tmux pane, not plain ssh."}, 1)
    try:
        p = subprocess.run([GWS, *args], capture_output=True, text=True, timeout=60, env=env)
    except Exception as e:
        out({"ok": False, "error": f"gws did not run: {e}", "reply": "The calendar tool is not reachable right now. Try again in a minute."}, 1)
    if p.returncode != 0:
        tail = (p.stderr or p.stdout).strip()[-300:]
        out({"ok": False, "error": f"gws {' '.join(args[:2])} exited {p.returncode}: {tail}",
             "reply": "Google Calendar refused the request. Ari: check `gws auth` on the laptop."}, 1)
    return p.stdout


def parse_time(s, tz, what):
    s = re.sub(r"\s+", " ", str(s).strip())
    for fmt in ("%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %I:%M %p", "%Y-%m-%d %I %p", "%Y-%m-%dT%H:%M",
                "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(s.upper() if "%p" in fmt else s, fmt).replace(tzinfo=ZoneInfo(tz))
        except ValueError:
            pass
    try:
        dt = datetime.fromisoformat(s.replace(" ", "T", 1).replace("Z", "+00:00"))
        return dt if dt.tzinfo else dt.replace(tzinfo=ZoneInfo(tz))
    except ValueError:
        bad(f"{what} {s!r} is not a date", f'{what} must look like "2026-11-03 20:00" (24h) or "2026-11-03 8:00 PM"')


def recent_context():
    """The text the caller was looking at, fetched by the script itself rather than trusted from the caller: the last
    OCR output and the user messages of the last 15 minutes from OpenClaw's transcript store (the live chat's session
    first, else any). Best effort, read-only."""
    parts, cutoff = [], time.time() - CONTEXT_WINDOW_S
    sid, _ = current_chat()
    try:
        if OCR_LAST.stat().st_mtime > cutoff:
            parts.append(OCR_LAST.read_text(errors="replace"))
    except OSError:
        pass
    try:
        con = sqlite3.connect(f"file:{TRANSCRIPT_DB}?mode=ro", uri=True, timeout=2)
        q = "select event_json from transcript_events where created_at > ? and event_json is not null"
        args = [int(cutoff * 1000)]
        if sid:
            q += " and session_id = ?"
            args.append(sid)
        rows = con.execute(q + " order by created_at desc limit 40", args).fetchall()
        con.close()
        for (raw,) in rows:
            m = (json.loads(raw).get("message") or {})
            if m.get("role") != "user":
                continue
            c = m.get("content")
            if isinstance(c, str):
                parts.append(c)
            elif isinstance(c, list):
                parts.extend(x.get("text", "") for x in c if isinstance(x, dict) and x.get("type") == "text")
    except Exception:
        pass
    return "\n".join(p for p in parts if p)


def derived_lines(text):
    """Description lines built from the source text itself, so the doors time and the purchase record never pass
    through a model (or a shell that eats "$42")."""
    lines = []
    d = re.search(r"doors?\s*(?:open|at|:|@)?\s*(\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?)", text, re.I)
    if d:
        lines.append("Doors: " + re.sub(r"\s*([ap])\.?m\.?", lambda m: " " + m.group(1).upper() + "M", d.group(1), flags=re.I).strip())
    n = re.search(r"\b(\d{1,2})\s*(?:x\s*)?tickets?\b", text, re.I)
    amt = re.search(r"\$\s?(\d[\d,]*(?:\.\d{2})?)", text)
    plat = next((pl for pl in PLATFORMS if re.search(r"\b" + re.escape(pl) + r"\b", text, re.I)), None)
    if amt or n:
        parts = []
        if n:
            parts.append(f"{n.group(1)} ticket" + ("" if n.group(1) == "1" else "s"))
        if amt:
            parts.append("$" + amt.group(1))
        lines.append("Purchased: " + ", ".join(parts) + (f" on {plat}" if plat else ""))
    return lines


def clock(txt):
    """'7:30 PM' / '7pm' / '7.30 p.m.' -> time"""
    t = re.sub(r"[\s.]", "", txt).upper().replace("PM", " PM").replace("AM", " AM")
    return datetime.strptime(t, "%I:%M %p" if ":" in t else "%I %p").time()


def show_time(text):
    """(time, certain): the show time the text states. Certain when it says 'show/showtime/music/starts <t>'; inferred
    when there is a doors time and exactly one other clock time; else (None, False)."""
    m = re.search(r"\b(?:show(?:time)?|music|starts?|performance)\s*(?:at|:|@|starts?|begins?)?\s*(\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?)", text, re.I)
    if m:
        return clock(m.group(1)), True
    d = re.search(r"doors?\s*(?:open|at|:|@)?\s*(\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?)", text, re.I)
    if d:
        others = {clock(t) for t in CLOCK_RE.findall(text)} - {clock(d.group(1))}
        if len(others) == 1:
            return others.pop(), False
    return None, False


def norm(s):
    return re.sub(r"\s+", "", str(s)).lower().rstrip("/.,)")


def verify_line(line, source):
    """A description line is kept only when every URL, dollar amount and clock time in it appears in the source."""
    claims = URL_RE.findall(line) + MONEY_RE.findall(line) + CLOCK_RE.findall(line) + PLAIN_RE.findall(line)
    if not claims:
        return True
    if source is None:
        return False
    return all(norm(c) in source for c in claims)


def resolve_calendar(name, dry):
    if not name or str(name).lower() == "primary":
        return "primary", "Personal"
    if "@" in str(name):
        return name, name
    if dry:
        return f"<id of {name}>", str(name)
    items = json.loads(gws("calendar", "calendarList", "list")).get("items", [])
    hits = [c for c in items if str(name).lower() in (c.get("summary") or "").lower()]
    if len(hits) != 1:
        names = ", ".join(sorted(c.get("summary", "") for c in items))
        bad(f"calendar {name!r} matched {len(hits)} calendars", f"use one of: {names}")
    return hits[0]["id"], hits[0]["summary"]


def bullet(key, value):
    return f"• **{key}:** {value}"


def bullets(title, when, location, lines):
    """Keys bold, values plain, one bullet each. A 'Key: value' line keeps its key; anything else is a plain bullet."""
    rows = [bullet("Artist", title), bullet("When", when), bullet("Where", location)]
    for ln in lines:
        k, sep, v = ln.partition(": ")
        rows.append(bullet(k, v) if sep and len(k) <= 24 else f"• {ln}")
    return "\n".join(rows)


def account_email():
    """The signed-in account's primary calendar id is its email; pinning links to it (authuser=) keeps a phone with
    several Google accounts from opening the wrong one."""
    try:
        items = json.loads(gws("calendar", "calendarList", "list")).get("items", [])
        return next((c["id"] for c in items if c.get("primary")), None)
    except SystemExit:
        return None


def event_link(html_link):
    email = account_email()
    return f"{html_link}&authuser={email}" if html_link and email else html_link


def fmt_range(start, end):
    same_day = start.date() == end.date()
    a = start.strftime("%a %b %-d, %-I:%M %p")
    b = end.strftime("%-I:%M %p" if same_day else "%a %b %-d, %-I:%M %p")
    return f"{a} – {b} {start.tzname()}"


def teaser_playlist(artist, start, dry):
    """The concert teaser playlist via the ari-spotify skill: every liked song by the artist, oldest first, named
    'YYYY-MM-DD | Artist'. Returns {"bullet": reply line, "line": description line or None, "result": raw}. Never fatal:
    the event matters more than the playlist, so any failure becomes a reply line Ari can act on."""
    if not SPOTIFY.exists():
        return {"bullet": bullet("Teaser", "not made (ari-spotify skill is not on this machine)"), "line": None, "result": None}
    cmd = ["zsh", str(SPOTIFY), "teaser", "--artist", artist, "--date", start.strftime("%Y-%m-%d")] + (["--dry-run"] if dry else [])
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TEASER_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        return {"bullet": bullet("Teaser", f"not made (Spotify took longer than {TEASER_TIMEOUT_S} s)"), "line": None, "result": None}
    except OSError as e:
        return {"bullet": bullet("Teaser", f"not made ({e})"), "line": None, "result": None}
    if p.returncode != 0:
        why = (p.stderr.strip().splitlines() or ["unknown error"])[-1]
        why = re.sub(r"\x1b\[[0-9;]*m", "", why).replace("[ERROR] ", "")[:160]
        return {"bullet": bullet("Teaser", f"not made ({why})"), "line": None, "result": None}
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"bullet": bullet("Teaser", "not made (Spotify tool gave an unreadable answer)"), "line": None, "result": None}
    name, n = res.get("name"), res.get("liked_count", 0)
    if not n:
        return {"bullet": bullet("Teaser", f"none, no liked songs by {res.get('artist', {}).get('name', artist)} yet"), "line": None, "result": res}
    if dry or not res.get("url"):
        return {"bullet": bullet("Teaser", f"would make {name} ({n} liked songs)"), "line": None, "result": res}
    verb = "" if res.get("created") else " (already existed, topped up)"
    return {"bullet": bullet("Teaser", f"[{name}]({res['url']}) {n} liked songs{verb}. Move it to Concerts › Teasers in Spotify."),
            "line": f"Teaser playlist: {res['url']}", "result": res}


SETLIST_QUEUE = pathlib.Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "ari-spotify/setlist-queue.json"


def setlist_lookup(artist, start, venue):
    """The setlist.fm page for the show, looked up the day the ticket is bought (ari-spotify `setlist-find`). Returns
    {"bullet", "line", "result", "queue": bool}; queue is True when the page is missing or still empty, so the weekly
    poller (beads-7q9.2) re-checks it. Never fatal."""
    if not SPOTIFY.exists():
        return None
    cmd = ["zsh", str(SPOTIFY), "setlist-find", "--artist", artist, "--date", start.strftime("%Y-%m-%d"), "--venue", venue]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    except (subprocess.TimeoutExpired, OSError) as e:
        return {"bullet": bullet("Setlist", f"lookup failed ({str(e)[:80]})"), "line": None, "result": None, "queue": True}
    if p.returncode != 0:
        why = re.sub(r"\x1b\[[0-9;]*m", "", (p.stderr.strip().splitlines() or ["unknown error"])[-1]).replace("[ERROR] ", "")[:160]
        return {"bullet": bullet("Setlist", f"lookup failed ({why})"), "line": None, "result": None, "queue": True}
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"bullet": bullet("Setlist", "lookup gave an unreadable answer"), "line": None, "result": None, "queue": True}
    # Every concert is queued (Ari, 2026-10-25): a page fills in over weeks, so the poller keeps checking until two
    # months after the show even when songs are already there.
    if not res.get("found"):
        return {"bullet": bullet("Setlist", "not on setlist.fm yet; checking weekly for 2 months"), "line": None, "result": res, "queue": True}
    n = res.get("song_count", 0)
    what = f"{n} songs so far" if n else "no songs yet"
    return {"bullet": bullet("Setlist", f"[setlist.fm]({res['url']}) {what}; checking weekly for 2 months"),
            "line": f"Setlist: {res['url']}", "result": res, "queue": True}


def queue_setlist(event_id, cal_id, artist, start, venue, setlist):
    """Remember the show for the weekly setlist poller (beads-7q9.2), which re-checks setlist.fm until `until`
    (two months after the show) and builds or tops up the setlist playlist. Idempotent per event."""
    if not setlist or not setlist.get("queue") or not event_id:
        return
    try:
        entries = json.loads(SETLIST_QUEUE.read_text(encoding="utf-8")) if SETLIST_QUEUE.exists() else []
    except ValueError:
        entries = []
    if any(e.get("event_id") == event_id for e in entries):
        return
    entries.append({"event_id": event_id, "calendar_id": cal_id, "artist": artist, "date": start.strftime("%Y-%m-%d"),
                    "venue": venue, "setlistfm_url": (setlist.get("result") or {}).get("url"),
                    "song_count": (setlist.get("result") or {}).get("song_count", 0),
                    "until": (start + timedelta(days=61)).strftime("%Y-%m-%d"),
                    "added": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    SETLIST_QUEUE.parent.mkdir(parents=True, exist_ok=True)
    SETLIST_QUEUE.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main():
    args = sys.argv[1:]
    global JSON_MODE, SEND
    dry, concert, JSON_MODE, SEND = "--dry-run" in args, "--concert" in args, "--json" in args, "--no-send" not in args
    want_teaser = concert and "--no-teaser" not in args
    args = [a for a in args if a not in ("--dry-run", "--concert", "--json", "--no-send", "--no-teaser")]
    # Flag form: --title X --start Y --location Z [--description L]... [--source T]. Else one JSON object (arg or stdin).
    ev, i, positional = {}, 0, []
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            key = a[2:]
            if key not in KNOWN and key not in ALIASES:
                bad(f"unknown flag --{key}", f"allowed flags: {', '.join('--' + k for k in sorted(KNOWN - {'date', 'time'}))}")
            if i + 1 >= len(args):
                bad(f"--{key} needs a value", f"pass a value after --{key}")
            val = args[i + 1]
            key = ALIASES.get(key, key)
            if key == "description":
                ev.setdefault("description", []).append(val)
            elif key == "attendees":
                ev.setdefault("attendees", []).append(val)
            else:
                ev[key] = val
            i += 2
        else:
            positional.append(a)
            i += 1
    if not ev:
        raw = positional[0] if positional else sys.stdin.read()
        try:
            ev = json.loads(raw)
        except Exception as e:
            bad(f"input is not valid JSON: {e}", "send exactly one JSON object, keys and strings in double quotes")
    if not isinstance(ev, dict):
        bad("input must be a JSON object", "send one {...} object")
    ev = {ALIASES.get(k, k): v for k, v in ev.items()}
    unknown = sorted(set(ev) - KNOWN)
    if unknown:
        bad(f"unknown keys: {', '.join(unknown)}", f"allowed keys: {', '.join(sorted(KNOWN - {'date', 'time'}))}")
    if "date" in ev and "time" in ev and not ev.get("start"):
        ev["start"] = f"{ev['date']} {ev['time']}"

    raw_source = "\n".join(x for x in (str(ev.get("source") or ""), recent_context()) if x)
    source = norm(raw_source) if raw_source.strip() else None
    tz = str(ev.get("tz") or "America/Los_Angeles")
    try:
        ZoneInfo(tz)
    except Exception:
        bad(f"unknown tz {tz!r}", "use an IANA name like America/Los_Angeles, or omit it")

    title = re.sub(r"\s+", " ", str(ev.get("title") or "")).strip()
    if concert:
        title = re.sub(r"^\[concert\]\s*", "", title, flags=re.I)
    if not title:
        need("artist" if concert else "title")
    if not ev.get("start"):
        need("date and time")
    start = parse_time(ev["start"], tz, "start")
    end = parse_time(ev["end"], tz, "end") if ev.get("end") else start + timedelta(hours=2)
    end_assumed = not ev.get("end")
    if end <= start or end - start > timedelta(hours=12):
        bad("end must be after start and within 12 hours", "fix end, or omit it for start + 2 hours")
    now = datetime.now(timezone.utc)
    if start < now - timedelta(hours=12) and not ev.get("allowPast"):
        out({"ok": False, "error": f"start {start.isoformat()} is in the past",
             "reply": f"That reads as {start.strftime('%a %b %-d %Y, %-I:%M %p')}, which is in the past. Reply with the right date (include the year) and I will add it."}, 1)
    if start > now + timedelta(days=730):
        out({"ok": False, "error": f"start {start.isoformat()} is over two years out",
             "reply": f"That reads as {start.strftime('%a %b %-d %Y')}, over two years from now. Reply with the right date and I will add it."}, 1)
    location = re.sub(r"\s+", " ", str(ev.get("location") or "")).strip()
    if not location:
        need("venue")
    # The show time comes from the text when the text states it; the caller only supplies the date.
    notes = []
    st, certain = show_time(raw_source)
    if st and start.time() != st:
        fixed = start.replace(hour=st.hour, minute=st.minute)
        if certain:
            notes.append(f"Start corrected to {fixed.strftime('%-I:%M %p')}, the show time in the text.")
            end = end + (fixed - start) if end_assumed else end
            start = fixed
        else:
            bad(f"start {start.strftime('%-I:%M %p')} is not the show time", f"the text puts the show at {st.strftime('%-I:%M %p')} (doors are earlier); use that")

    desc = ev.get("description") or []
    if isinstance(desc, str):
        desc = desc.replace("\\n", "\n").split("\n")
    if not isinstance(desc, list):
        bad("description must be a list of lines", 'use ["Doors: 7:00 PM", "Purchased: 1 ticket, $45"]')
    lines, dropped = derived_lines(raw_source), []
    for ln in desc:
        ln = re.sub(r"\s+", " ", str(ln)).strip()
        if not ln or any(ln.split(":")[0].lower() == d.split(":")[0].lower() for d in lines):
            continue   # the script's own Doors/Purchased lines win over the caller's
        (lines if verify_line(ln, source) else dropped).append(ln)
    attendees = ev.get("attendees") or []
    if not isinstance(attendees, list) or any("@" not in str(a) for a in attendees):
        bad("attendees must be a list of email addresses", 'use ["name@example.com"]')
    cal_id, cal_name = resolve_calendar("Concerts" if concert else ev.get("calendar"), dry)

    # The teaser playlist (concerts only) runs before the insert so one insert carries its link; it is never fatal.
    teaser = teaser_playlist(title, start, dry) if want_teaser else None
    if teaser and teaser["line"]:
        lines.append(teaser["line"])
    # The setlist.fm page, looked up the day the ticket is bought; the show is queued for the weekly poller either way.
    setlist = setlist_lookup(title, start, location) if concert else None
    if setlist and setlist["line"]:
        lines.append(setlist["line"])

    # Telegram renders **bold** and [text](url); link previews are off in channels.telegram.linkPreview.
    body = bullets(title, fmt_range(start, end) + (" (end assumed)" if end_assumed else ""), location,
                   [ln for ln in lines if not ln.startswith(("Teaser playlist: ", "Setlist: "))])
    for extra in (teaser, setlist):
        if extra:
            body += "\n" + extra["bullet"]
    topic_name = f"{start.strftime('%Y-%m-%d')} | {title} | {location.split(',')[0].strip()}"
    if dropped:
        notes.append(f"Left out (not in the text I was given): {'; '.join(dropped)}")
    note = "".join("\n" + n for n in notes)
    common = {"calendar": cal_name, "summary": title, "start": start.isoformat(), "end": end.isoformat(),
              "location": location, "description": lines, "dropped": dropped, "teaser": teaser and teaser["result"],
              "setlist": setlist and setlist["result"], "topic": topic_name}
    if dry:
        out({"ok": True, "dryRun": True, **common, "reply": f"**Would add to {cal_name}**\n{body}{note}"})

    def finish(event_id, html_link, duplicate):
        """Queue the show for the setlist poller, rename the Telegram topic, deliver the reply."""
        queue_setlist(event_id, cal_id, title, start, location, setlist)
        _, route = current_chat()
        topic = rename_topic(route, topic_name) if (concert and route and SEND) else "topic not renamed: no live chat"
        head = f"**Already on {cal_name}** (nothing new created)" if duplicate else f"**Added to {cal_name}**"
        out({"ok": True, "duplicate": duplicate, "id": event_id, "htmlLink": html_link, "topic_status": topic, **common,
             "reply": f"{head}\n{body}{note}\n[Open in Google Calendar]({event_link(html_link)})"})

    # Duplicate guard: a retried insert must not create a second event.
    existing = json.loads(gws("calendar", "events", "list", "--params", json.dumps({
        "calendarId": cal_id, "timeMin": start.isoformat(), "timeMax": (start + timedelta(minutes=1)).isoformat(),
        "singleEvents": True, "q": title}))).get("items", [])
    for e in existing:
        if (e.get("summary") or "").strip().lower() == title.lower() and e.get("status") != "cancelled":
            # The event predates the playlist or the setlist page: add the missing link lines to its description.
            missing = [x["line"] for x in (teaser, setlist) if x and x["line"] and x["line"] not in (e.get("description") or "")]
            if missing:
                gws("calendar", "events", "patch", "--params", json.dumps({"calendarId": cal_id, "eventId": e.get("id")}),
                    "--json", json.dumps({"description": "\n".join([(e.get("description") or "").rstrip()] + missing).strip()}))
            finish(e.get("id"), e.get("htmlLink"), True)
    cmd = ["calendar", "+insert", "--calendar", cal_id, "--summary", title, "--start", start.isoformat(),
           "--end", end.isoformat(), "--location", location]
    if lines:
        cmd += ["--description", "\n".join(lines)]
    for a in attendees:
        cmd += ["--attendee", str(a)]
    try:
        r = json.loads(gws(*cmd))
    except ValueError:
        out({"ok": False, "error": "gws returned no JSON", "reply": "Google Calendar gave an unreadable answer. Ari: check the laptop."}, 1)
    finish(r.get("id"), r.get("htmlLink") or "", False)


if __name__ == "__main__":
    main()
