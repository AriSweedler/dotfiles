#!/usr/bin/env python3
"""cal-del.py: delete a calendar event the way a chat bot can drive it. The caller names the event; this script finds it
on the Concerts and Personal calendars, deletes it when the match is unique, lists the candidates when it is not, and
sends the reply itself (same contract as cal-add.py: FIX / NO_REPLY / NOT SENT).

  python3 cal-del.py <<'JSON'
  {"title": "ZZZ Test Band", "date": "2026-11-20"}
  JSON
  python3 cal-del.py --pick 2            # after a numbered list: delete candidate 2
  flags: --title --date --calendar --id --pick --dry-run --json --no-send

Fields: title (artist/summary, required unless --pick/--id), date (YYYY-MM-DD, optional: narrows to that day ±1),
calendar (name, optional: default searches Concerts and Personal), id (an event id from a previous listing).
Output: one match -> "**Removed from <calendar>**" with Artist / When / Where bullets; several -> a numbered list
(candidates kept in ~/.openclaw/media/cal-del-candidates.json for --pick); none -> "nothing deleted".
"""
import importlib.util
import json
import pathlib
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

# Reuse cal-add.py's plumbing (gws, live chat, reply delivery, bullets, link) instead of a second copy.
_SPEC = importlib.util.spec_from_file_location("caladd", pathlib.Path(__file__).resolve().parent / "cal-add.py")
C = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(C)

CANDIDATES = C.HOME / ".openclaw/media/cal-del-candidates.json"
ALIASES = {"artist": "title", "summary": "title", "event": "title", "name": "title", "venue": "location", "when": "date",
           "day": "date", "cal": "calendar", "eventId": "id", "pick": "pick", "number": "pick", "choice": "pick"}
KNOWN = {"title", "date", "calendar", "id", "pick", "location", "tz"}
FLAGS = ("--dry-run", "--json", "--no-send")


def parse_input(args):
    """Flags or one JSON object, aliases folded, unknown keys refused (the caller fixes its JSON once)."""
    ev, i, positional = {}, 0, []
    while i < len(args):
        a = args[i]
        if a.startswith("--"):
            key = a[2:]
            if key not in KNOWN and key not in ALIASES:
                C.bad(f"unknown flag --{key}", f"allowed flags: {', '.join('--' + k for k in sorted(KNOWN))}")
            if i + 1 >= len(args):
                C.bad(f"--{key} needs a value", f"pass a value after --{key}")
            ev[ALIASES.get(key, key)] = args[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1
    if not ev:
        raw = positional[0] if positional else sys.stdin.read()
        try:
            ev = json.loads(raw)
        except Exception as e:
            C.bad(f"input is not valid JSON: {e}", 'send exactly one JSON object, e.g. {"title": "Jai Wolf", "date": "2026-10-24"}')
        if not isinstance(ev, dict):
            C.bad("input must be a JSON object", "send one {...} object")
        ev = {ALIASES.get(k, k): v for k, v in ev.items()}
    unknown = sorted(set(ev) - KNOWN)
    if unknown:
        C.bad(f"unknown keys: {', '.join(unknown)}", f"use only: {', '.join(sorted(KNOWN))}")
    return ev


def norm_title(s):
    return " ".join(str(s or "").lower().replace("&", "and").split())


def when_of(e, tz):
    st, en = e.get("start") or {}, e.get("end") or {}
    if st.get("dateTime"):
        a = datetime.fromisoformat(st["dateTime"].replace("Z", "+00:00")).astimezone(tz)
        b = datetime.fromisoformat((en.get("dateTime") or st["dateTime"]).replace("Z", "+00:00")).astimezone(tz)
        return C.fmt_range(a, b), a
    day = datetime.fromisoformat(st.get("date")).replace(tzinfo=tz)
    return day.strftime("%a %b %-d (all day)"), day


def find_candidates(ev, tz, dry):
    """Events whose title contains the words asked for, on the named calendar or on Concerts + Personal."""
    title = norm_title(ev.get("title"))
    if ev.get("date"):
        try:
            day = datetime.strptime(str(ev["date"])[:10], "%Y-%m-%d").replace(tzinfo=tz)
        except ValueError:
            C.bad(f"date {ev['date']!r} is not YYYY-MM-DD", 'send the day as "2026-10-24"')
        t_min, t_max = day - timedelta(days=1), day + timedelta(days=2)
    else:
        now = datetime.now(tz)
        t_min, t_max = now - timedelta(days=30), now + timedelta(days=365)
    cals = [C.resolve_calendar(ev["calendar"], dry)] if ev.get("calendar") else [C.resolve_calendar("Concerts", dry), ("primary", "Personal")]
    if dry and not ev.get("calendar"):
        cals = [("<id of Concerts>", "Concerts"), ("primary", "Personal")]
    found = []
    for cal_id, cal_name in cals:
        if dry:
            continue
        params = {"calendarId": cal_id, "timeMin": t_min.isoformat(), "timeMax": t_max.isoformat(), "singleEvents": True,
                  "maxResults": 50, "q": ev.get("title") or ""}
        items = json.loads(C.gws("calendar", "events", "list", "--params", json.dumps(params))).get("items", [])
        for e in items:
            if e.get("status") == "cancelled":
                continue
            have = norm_title(e.get("summary"))
            words = [w for w in title.split() if len(w) > 1]
            if title and not (title in have or all(w in have for w in words)):
                continue
            when, start = when_of(e, tz)
            found.append({"id": e.get("id"), "calendarId": cal_id, "calendar": cal_name, "summary": e.get("summary") or "(no title)",
                          "when": when, "start": start.isoformat(), "location": e.get("location") or "", "htmlLink": e.get("htmlLink"),
                          "description": e.get("description") or ""})
    found.sort(key=lambda c: c["start"])
    return found


def delete_event(c, dry):
    """gws events delete writes its empty response to a file in cwd, so it runs from /tmp."""
    if dry:
        return
    env = C.gws_env()
    p = subprocess.run([C.GWS, "calendar", "events", "delete", "-o", "gws-del.out", "--params",
                        json.dumps({"calendarId": c["calendarId"], "eventId": c["id"]})],
                       capture_output=True, text=True, timeout=60, env=env, cwd="/tmp")
    pathlib.Path("/tmp/gws-del.out").unlink(missing_ok=True)
    if p.returncode != 0:
        C.out({"ok": False, "error": f"gws delete exited {p.returncode}: {(p.stderr or p.stdout).strip()[-300:]}",
               "reply": "Google Calendar refused the delete. Ari: check `gws auth` on the laptop."}, 1)
    # The weekly setlist poller must forget the show too.
    try:
        q = json.loads(C.SETLIST_QUEUE.read_text(encoding="utf-8")) if C.SETLIST_QUEUE.exists() else []
        kept = [e for e in q if e.get("event_id") != c["id"]]
        if len(kept) != len(q):
            C.SETLIST_QUEUE.write_text(json.dumps(kept, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    except Exception:
        pass


def removed_reply(c, dry):
    head = f"**Would remove from {c['calendar']}**" if dry else f"**Removed from {c['calendar']}**"
    rows = [C.bullet("Artist", c["summary"]), C.bullet("When", c["when"])]
    if c["location"]:
        rows.append(C.bullet("Where", c["location"]))
    for ln in c["description"].splitlines():
        if ln.startswith("Teaser playlist: "):
            rows.append(C.bullet("Teaser", f"[playlist]({ln.split(': ', 1)[1]}) left in place; say \"delete the teaser playlist\" to remove it"))
    return head + "\n" + "\n".join(rows)


def main():
    args = sys.argv[1:]
    dry, C.JSON_MODE, C.SEND = "--dry-run" in args, "--json" in args, "--no-send" not in args
    ev = parse_input([a for a in args if a not in FLAGS])
    tz = ZoneInfo(str(ev.get("tz") or "America/Los_Angeles"))

    if ev.get("pick"):
        try:
            n = int(str(ev["pick"]).strip().rstrip("."))
            cands = json.loads(CANDIDATES.read_text(encoding="utf-8"))
            c = cands[n - 1]
        except (ValueError, IndexError, FileNotFoundError, json.JSONDecodeError):
            C.out({"ok": False, "error": "no such candidate", "reply": "I do not have a list to pick from any more. Tell me the event name and date and I will look again."}, 1)
        delete_event(c, dry)
        CANDIDATES.unlink(missing_ok=True)
        C.out({"ok": True, "deleted": not dry, "dryRun": dry, **c, "reply": removed_reply(c, dry)})

    if ev.get("id"):
        cal_id, cal_name = C.resolve_calendar(ev.get("calendar") or "Concerts", dry)
        e = json.loads(C.gws("calendar", "events", "get", "--params", json.dumps({"calendarId": cal_id, "eventId": ev["id"]})))
        when, start = when_of(e, tz)
        c = {"id": ev["id"], "calendarId": cal_id, "calendar": cal_name, "summary": e.get("summary") or "(no title)", "when": when,
             "start": start.isoformat(), "location": e.get("location") or "", "htmlLink": e.get("htmlLink"), "description": e.get("description") or ""}
        delete_event(c, dry)
        C.out({"ok": True, "deleted": not dry, "dryRun": dry, **c, "reply": removed_reply(c, dry)})

    if not str(ev.get("title") or "").strip():
        C.out({"ok": False, "error": "title is required", "reply": "Which event? Tell me the artist or title (and the date if you know it) and I will remove it."}, 1)
    found = find_candidates(ev, tz, dry)
    if dry and not found:
        C.out({"ok": True, "dryRun": True, "reply": f"**Would look for** {ev['title']}" + (f" around {ev['date']}" if ev.get("date") else "") + " on Concerts and Personal, then remove the one match."})
    if not found:
        where = f" around {ev['date']}" if ev.get("date") else ""
        C.out({"ok": True, "deleted": False, "reply": f"I found no event like **{ev['title']}**{where} on Concerts or Personal. Nothing deleted."})
    if len(found) == 1:
        c = found[0]
        delete_event(c, dry)
        C.out({"ok": True, "deleted": not dry, "dryRun": dry, **c, "reply": removed_reply(c, dry)})
    CANDIDATES.parent.mkdir(parents=True, exist_ok=True)
    CANDIDATES.write_text(json.dumps(found, ensure_ascii=False), encoding="utf-8")
    rows = [f"{i}. **{c['summary']}** on {c['calendar']}: {c['when']}" + (f", {c['location']}" if c['location'] else "") for i, c in enumerate(found, 1)]
    C.out({"ok": True, "deleted": False, "candidates": found,
           "reply": f"I found {len(found)} events like **{ev['title']}**. Reply with the number to delete:\n" + "\n".join(rows)})


if __name__ == "__main__":
    main()
