#!/usr/bin/env python3
"""Spotify for Ari's bots and skills. Run: zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh <command> ...

JSON in (flags), JSON out (stdout). Standard library only. The app's client id and secret
and the user's refresh token live in 1Password ("Spotify - OpenClaw app", vault Private);
`auth` copies them into ~/.config/ari-spotify/credentials.json (mode 600) once, and every
other command runs from that file without touching 1Password, so a chat bot can call it.

Commands:
  auth              one-time browser login; writes the credentials file, stores the refresh token
  me                the signed-in user
  liked             Liked Songs, oldest first; --artist NAME keeps the tracks by that artist
  playlists         the user's playlists (name, id, url, tracks)
  playlist-tracks   the tracks of --playlist ID
  playlist-create   --name NAME [--description TEXT] [--public]; refuses a name that already exists
  playlist-add      --playlist ID --uri spotify:track:... (repeatable); skips uris already in it
  search-artist     --name NAME: the best artist matches
"""
import argparse
import base64
import http.server
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from pathlib import Path

from skill_log import log_info, log_warn, die
from skill_subprocess import run_capture

ACCOUNTS = "https://accounts.spotify.com"
API = "https://api.spotify.com/v1"
REDIRECT_URI = "http://127.0.0.1:8888/callback"
SCOPES = "user-library-read playlist-read-private playlist-modify-private playlist-modify-public"
OP_ITEM = "Spotify - OpenClaw app"
OP_VAULT = "Private"
OP_PLACEHOLDER = "FILL_THIS_OUT"
CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "ari-spotify"
CREDENTIALS = CONFIG_DIR / "credentials.json"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "ari-spotify"
LIKED_CACHE = CACHE_DIR / "liked.json"
LIKED_CACHE_TTL_S = 6 * 3600
HTTP_TIMEOUT_S = 30
PAGE = 50


# ---------- credentials ----------

def read_credentials():
    if not CREDENTIALS.exists():
        die(f"not authorized yet | path='{CREDENTIALS}' hint='run: spotify.zsh auth'")
    return json.loads(CREDENTIALS.read_text(encoding="utf-8"))


def write_credentials(creds):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CREDENTIALS.write_text(json.dumps(creds, indent=2) + "\n", encoding="utf-8")
    CREDENTIALS.chmod(0o600)


def basic_auth(creds):
    raw = f"{creds['client_id']}:{creds['client_secret']}".encode("utf-8")
    return "Basic " + base64.b64encode(raw).decode("ascii")


def token_request(creds, form):
    data = urllib.parse.urlencode(form).encode("utf-8")
    req = urllib.request.Request(f"{ACCOUNTS}/api/token", data=data, method="POST")
    req.add_header("Authorization", basic_auth(creds))
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:300]
        die(f"token request refused | grant='{form.get('grant_type')}' status='{e.code}' body='{body}'")
    except urllib.error.URLError as e:
        die(f"token request failed | reason='{e.reason}'")


def access_token(creds):
    """A valid access token, refreshing (and persisting) when the cached one is stale."""
    if creds.get("access_token") and creds.get("expires_at", 0) > time.time() + 60:
        return creds["access_token"]
    tok = token_request(creds, {"grant_type": "refresh_token", "refresh_token": creds["refresh_token"]})
    creds["access_token"] = tok["access_token"]
    creds["expires_at"] = time.time() + int(tok.get("expires_in", 3600))
    if tok.get("refresh_token"):
        creds["refresh_token"] = tok["refresh_token"]
    write_credentials(creds)
    return creds["access_token"]


# ---------- Web API ----------

def api(creds, method, path, *, params=None, body=None, retries=3):
    """One Web API call. Retries 429 per Retry-After, dies on other errors. Returns parsed JSON or None."""
    url = path if path.startswith("http") else f"{API}{path}"
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    data = json.dumps(body).encode("utf-8") if body is not None else None
    for attempt in range(retries + 1):
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {access_token(creds)}")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as resp:
                raw = resp.read()
                return json.loads(raw.decode("utf-8")) if raw else None
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries:
                wait = min(int(e.headers.get("Retry-After", "2")), 30)
                log_warn(f"rate limited, waiting | retry_after_s='{wait}'")
                time.sleep(wait)
                continue
            if e.code == 401 and attempt < retries:
                creds["expires_at"] = 0  # force a refresh and retry once
                continue
            body_text = e.read().decode("utf-8", "replace")[:300]
            die(f"Spotify API refused | method='{method}' path='{path}' status='{e.code}' body='{body_text}'")
        except urllib.error.URLError as e:
            die(f"Spotify API unreachable | path='{path}' reason='{e.reason}'")
    die(f"Spotify API kept rate-limiting | path='{path}' retries='{retries}'")


def paged(creds, path, params=None):
    """Every item of a paginated endpoint."""
    params = dict(params or {}, limit=PAGE)
    page = api(creds, "GET", path, params=params)
    while True:
        for item in page.get("items", []):
            yield item
        if not page.get("next"):
            return
        page = api(creds, "GET", page["next"])


def track_row(track, added_at=None):
    row = {
        "name": track.get("name"),
        "artists": [a.get("name") for a in track.get("artists", [])],
        "artist_ids": [a.get("id") for a in track.get("artists", [])],
        "album": (track.get("album") or {}).get("name"),
        "uri": track.get("uri"),
        "url": (track.get("external_urls") or {}).get("spotify"),
        "duration_ms": track.get("duration_ms"),
    }
    if added_at is not None:
        row["added_at"] = added_at
    return row


def playlist_row(pl):
    # The 2025 Web API renamed a playlist's `tracks` to `items`; accept both.
    return {
        "name": pl.get("name"),
        "id": pl.get("id"),
        "url": (pl.get("external_urls") or {}).get("spotify"),
        "public": pl.get("public"),
        "tracks": (pl.get("items") or pl.get("tracks") or {}).get("total"),
        "owner": (pl.get("owner") or {}).get("display_name") or (pl.get("owner") or {}).get("id"),
        "owner_id": (pl.get("owner") or {}).get("id"),
        "description": pl.get("description"),
    }


def playlist_entries(creds, playlist_id):
    """The tracks in a playlist, oldest-added first. Entries carry `item` (new API) or `track` (old)."""
    for entry in paged(creds, f"/playlists/{playlist_id}/items"):
        track = entry.get("item") or entry.get("track")
        if track and track.get("type", "track") == "track":
            yield track_row(track, entry.get("added_at"))


# ---------- commands ----------

def app_credentials_from_op():
    if shutil.which("op") is None:
        die("missing prerequisite | missing='op' hint='or pass --manual'")
    log_info(f"reading the app's client id and secret from 1Password | item='{OP_ITEM}' vault='{OP_VAULT}' hint='approve the 1Password dialog; --manual types them instead'")
    client_id = run_capture(["op", "read", f"op://{OP_VAULT}/{OP_ITEM}/username"], 120, what="op read client id").stdout.strip()
    client_secret = run_capture(["op", "read", f"op://{OP_VAULT}/{OP_ITEM}/credential"], 120, what="op read client secret").stdout.strip()
    if OP_PLACEHOLDER in (client_id, client_secret) or not client_id or not client_secret:
        die(f"the 1Password item still holds the placeholder | item='{OP_ITEM}' fields='username, credential' hint='paste the Client ID and Client Secret from the Spotify dashboard'")
    return client_id, client_secret


def app_credentials_from_terminal():
    """Typed into the terminal, hidden; for when 1Password's CLI integration is not answering."""
    import getpass
    if not sys.stdin.isatty():
        die("--manual needs a terminal to type into | stdin='not a tty'")
    client_id = getpass.getpass("Spotify Client ID (hidden): ").strip()
    client_secret = getpass.getpass("Spotify Client Secret (hidden): ").strip()
    if len(client_id) != 32 or len(client_secret) != 32:
        die(f"Spotify ids are 32 hex characters | client_id_len='{len(client_id)}' client_secret_len='{len(client_secret)}'")
    return client_id, client_secret


def store_refresh_token_in_op(refresh_token):
    """Best effort: the credentials file is the runtime copy; 1Password is the backup."""
    if shutil.which("op") is None:
        log_warn("op not installed; refresh token kept only in the credentials file")
        return
    log_info(f"storing the refresh token in 1Password | item='{OP_ITEM}' hint='approve the dialog; 60 s'")
    try:
        subprocess.run(["op", "item", "edit", OP_ITEM, "--vault", OP_VAULT, f"refresh token[password]={refresh_token}"],
                       capture_output=True, text=True, encoding="utf-8", timeout=90, check=True)
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as e:
        log_warn(f"could not store the refresh token in 1Password; it is in the credentials file | reason='{str(e)[:160]}'")


def cmd_auth(args):
    if CREDENTIALS.exists() and not args.force:
        die(f"credentials already exist | path='{CREDENTIALS}' hint='pass --force to log in again'")
    client_id, client_secret = app_credentials_from_terminal() if args.manual else app_credentials_from_op()
    creds = {"client_id": client_id, "client_secret": client_secret}

    state = secrets.token_urlsafe(16)
    auth_url = f"{ACCOUNTS}/authorize?" + urllib.parse.urlencode({
        "client_id": client_id, "response_type": "code", "redirect_uri": REDIRECT_URI,
        "scope": SCOPES, "state": state, "show_dialog": "true" if args.force else "false",
    })
    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            ok = q.get("state", [""])[0] == state and "code" in q
            result["code"] = q["code"][0] if ok else None
            result["error"] = q.get("error", ["state mismatch"])[0] if not ok else None
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(("Spotify linked. You can close this tab." if ok else f"Login failed: {result['error']}").encode("utf-8"))

        def log_message(self, *_):
            return

    host, port = urllib.parse.urlparse(REDIRECT_URI).hostname, urllib.parse.urlparse(REDIRECT_URI).port
    try:
        server = http.server.HTTPServer((host, port), Handler)
    except OSError as e:
        die(f"cannot listen for the callback | addr='{host}:{port}' reason='{e}'")
    server.timeout = 300
    log_info(f"opening the Spotify consent page; log in as the account that owns the playlists | url='{auth_url}'")
    print(auth_url, file=sys.stderr)
    webbrowser.open(auth_url)
    server.handle_request()
    server.server_close()
    if not result.get("code"):
        die(f"no authorization code received | error='{result.get('error', 'timeout after 300 s')}'")

    tok = token_request(creds, {"grant_type": "authorization_code", "code": result["code"], "redirect_uri": REDIRECT_URI})
    if not tok.get("refresh_token"):
        die(f"token response carries no refresh token | keys='{', '.join(sorted(tok))}'")
    creds.update({
        "refresh_token": tok["refresh_token"],
        "access_token": tok["access_token"],
        "expires_at": time.time() + int(tok.get("expires_in", 3600)),
        "scope": tok.get("scope", SCOPES),
    })
    write_credentials(creds)
    me = api(creds, "GET", "/me")
    creds["user_id"] = me["id"]
    write_credentials(creds)
    log_info(f"credentials written | path='{CREDENTIALS}' user='{me.get('display_name')}' id='{me['id']}'")
    store_refresh_token_in_op(tok["refresh_token"])
    print(json.dumps({"ok": True, "user": me.get("display_name"), "user_id": me["id"], "scope": creds["scope"], "credentials": str(CREDENTIALS)}))


def cmd_me(args):
    creds = read_credentials()
    me = api(creds, "GET", "/me")
    print(json.dumps({"id": me.get("id"), "display_name": me.get("display_name"), "url": (me.get("external_urls") or {}).get("spotify"), "product": me.get("product")}))


def load_liked(creds, refresh):
    if not refresh and LIKED_CACHE.exists() and time.time() - LIKED_CACHE.stat().st_mtime < LIKED_CACHE_TTL_S:
        rows = json.loads(LIKED_CACHE.read_text(encoding="utf-8"))
        if rows and "artist_ids" in rows[0]:  # an older cache lacks the ids the artist filter needs
            return rows
    log_info("fetching Liked Songs (50 per page)")
    rows = [track_row(item["track"], item.get("added_at")) for item in paged(creds, "/me/tracks") if item.get("track")]
    rows.sort(key=lambda r: r.get("added_at") or "")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    LIKED_CACHE.write_text(json.dumps(rows), encoding="utf-8")
    log_info(f"liked songs cached | count='{len(rows)}' path='{LIKED_CACHE}'")
    return rows


def normalize(name):
    return " ".join((name or "").lower().replace("&", "and").split())


def resolve_artist(creds, name):
    """The Spotify artist a (possibly misspelled) name means: an exact match first, else the most-followed
    result whose name shares the query's words, else the top result when the query is one word of it."""
    res = api(creds, "GET", "/search", params={"q": name, "type": "artist", "limit": 10})
    items = (res.get("artists") or {}).get("items", [])
    if not items:
        die(f"no Spotify artist matches | artist='{name}'")
    want = normalize(name)
    exact = [a for a in items if normalize(a.get("name")) == want]
    if exact:
        pick = max(exact, key=lambda a: (a.get("followers") or {}).get("total", 0))
    else:
        want_words = set(want.split())
        close = [a for a in items if want_words & set(normalize(a.get("name")).split())]
        if not close:
            die(f"no close Spotify artist match | artist='{name}' top_results='{', '.join(a.get('name', '') for a in items[:5])}'")
        pick = max(close, key=lambda a: (a.get("followers") or {}).get("total", 0))
        log_warn(f"artist name corrected | asked='{name}' spotify='{pick.get('name')}'")
    return {"name": pick.get("name"), "id": pick.get("id"), "url": (pick.get("external_urls") or {}).get("spotify")}


def liked_by_artist(creds, artist, refresh=False):
    """Liked tracks credited to the artist (by id; name fallback for old caches), oldest first."""
    rows = load_liked(creds, refresh)
    hits = [r for r in rows if artist["id"] in (r.get("artist_ids") or []) or normalize(artist["name"]) in [normalize(a) for a in r["artists"]]]
    if not hits and not refresh:
        return liked_by_artist(creds, artist, refresh=True)
    return hits


# Ari's naming for the Concerts folders (Teasers and Setlists alike), decided 2026-10-25: "YYYY-MM-DD | Artist".
CONCERT_NAME = "{date} | {artist}"
OLD_CONCERT_NAME = re.compile(r"^\s*(\d{4})[/-](\d{2})[/-](\d{2})\s*(?:[-|]\s*)?(.+?)\s*$")


def concert_date(text):
    """YYYY-MM-DD, YYYY/MM/DD or an RFC3339 prefix -> YYYY-MM-DD."""
    import datetime
    for fmt in ("%Y-%m-%d", "%Y/%m/%d"):
        try:
            return datetime.datetime.strptime(text.strip()[:10], fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    die(f"unreadable concert date | date='{text}' expected='YYYY-MM-DD'")


def canonical_concert_name(name):
    """The house form of a dated concert playlist name, or None when the name carries no leading date."""
    m = OLD_CONCERT_NAME.match(name or "")
    if not m:
        return None
    return CONCERT_NAME.format(date=f"{m.group(1)}-{m.group(2)}-{m.group(3)}", artist=m.group(4))


def cmd_liked(args):
    creds = read_credentials()
    rows = load_liked(creds, args.refresh)
    if args.artist:
        want = args.artist.strip().lower()
        rows = [r for r in rows if any((a or "").lower() == want for a in r["artists"])]
        if not rows:
            # second chance: a substring match (e.g. "Jai Wolf" vs "JAI WOLF feat. ...") on a fresh fetch
            rows = [r for r in load_liked(creds, True) if any(want in (a or "").lower() for a in r["artists"])]
    print(json.dumps({"artist": args.artist, "count": len(rows), "tracks": rows}, ensure_ascii=False))


def cmd_playlists(args):
    creds = read_credentials()
    rows = [playlist_row(pl) for pl in paged(creds, "/me/playlists")]
    print(json.dumps({"count": len(rows), "playlists": rows}, ensure_ascii=False))


def cmd_playlist_tracks(args):
    creds = read_credentials()
    rows = list(playlist_entries(creds, args.playlist))
    print(json.dumps({"playlist": args.playlist, "count": len(rows), "tracks": rows}, ensure_ascii=False))


def cmd_playlist_create(args):
    creds = read_credentials()
    name = args.name.strip()
    if not name:
        die("empty playlist name | flag='--name'")
    existing = next((pl for pl in paged(creds, "/me/playlists") if (pl.get("name") or "").strip().lower() == name.lower()), None)
    if existing:
        log_warn(f"a playlist with that name exists; not creating another | name='{name}' id='{existing['id']}'")
        print(json.dumps({"created": False, **playlist_row(existing)}, ensure_ascii=False))
        return
    if args.dry_run:
        log_info(f"dry-run: would create | name='{name}' public='{args.public}'")
        print(json.dumps({"created": False, "dry_run": True, "name": name}))
        return
    # 2025 Web API: POST /me/playlists (the older /users/<id>/playlists answers 403).
    pl = api(creds, "POST", "/me/playlists", body={"name": name, "description": args.description or "", "public": bool(args.public)})
    log_info(f"playlist created | name='{name}' id='{pl['id']}'")
    print(json.dumps({"created": True, **playlist_row(pl)}, ensure_ascii=False))


def cmd_playlist_add(args):
    creds = read_credentials()
    uris = [u.strip() for u in args.uri if u.strip()]
    bad = [u for u in uris if not u.startswith("spotify:track:")]
    if bad:
        die(f"not track uris | bad='{', '.join(bad)}' expected='spotify:track:<id>'")
    have = {row["uri"] for row in playlist_entries(creds, args.playlist)}
    new = [u for u in uris if u not in have]
    skipped = len(uris) - len(new)
    if args.dry_run:
        log_info(f"dry-run: would add | playlist='{args.playlist}' add='{len(new)}' skipped='{skipped}'")
        print(json.dumps({"added": 0, "would_add": len(new), "skipped": skipped, "dry_run": True}))
        return
    for i in range(0, len(new), 100):
        api(creds, "POST", f"/playlists/{args.playlist}/items", body={"uris": new[i:i + 100]})
    log_info(f"tracks added | playlist='{args.playlist}' added='{len(new)}' skipped_existing='{skipped}'")
    print(json.dumps({"added": len(new), "skipped": skipped, "playlist": args.playlist}))


def cmd_teaser(args):
    """The concert teaser playlist: every liked song by the artist, oldest-liked first, named like the Teasers folder."""
    creds = read_credentials()
    date = concert_date(args.date)
    artist = resolve_artist(creds, args.artist)
    tracks = liked_by_artist(creds, artist)
    name = CONCERT_NAME.format(date=date, artist=artist["name"])
    description = args.description or f"Teaser for {artist['name']} on {date}: every song Ari liked by them, in the order he liked them."
    existing = next((pl for pl in paged(creds, "/me/playlists") if normalize(pl.get("name")) == normalize(name)), None)
    result = {"artist": artist, "date": date, "name": name, "liked_count": len(tracks), "tracks": [t["name"] for t in tracks]}
    if not tracks:
        result.update({"created": False, "reply": f"No teaser: you have not liked any songs by {artist['name']} yet."})
        print(json.dumps(result, ensure_ascii=False))
        return
    if args.dry_run:
        result.update({"created": False, "dry_run": True, "exists": bool(existing)})
        log_info(f"dry-run: would {'fill' if existing else 'create'} | name='{name}' tracks='{len(tracks)}'")
        print(json.dumps(result, ensure_ascii=False))
        return
    if existing:
        pl = existing
        log_info(f"teaser exists; topping it up | name='{name}' id='{pl['id']}'")
    else:
        pl = api(creds, "POST", "/me/playlists", body={"name": name, "description": description, "public": False})
        log_info(f"teaser created | name='{name}' id='{pl['id']}'")
    have = {row["uri"] for row in playlist_entries(creds, pl["id"])}
    new = [t["uri"] for t in tracks if t["uri"] not in have]
    for i in range(0, len(new), 100):
        api(creds, "POST", f"/playlists/{pl['id']}/items", body={"uris": new[i:i + 100]})
    url = (pl.get("external_urls") or {}).get("spotify")
    result.update({
        "created": existing is None, "id": pl["id"], "url": url, "added": len(new), "already_there": len(tracks) - len(new),
        "folder": "Concerts / Teasers (move it there in the Spotify app; the API cannot)",
        "reply": f"Teaser playlist {'created' if existing is None else 'updated'}: {name} ({len(tracks)} liked songs) {url}",
    })
    print(json.dumps(result, ensure_ascii=False))


def cmd_rename(args):
    """Rename one playlist (only the owner can). Idempotent: an unchanged name is a no-op."""
    creds = read_credentials()
    pl = api(creds, "GET", f"/playlists/{args.playlist}", params={"fields": "id,name,owner(id)"})
    new = args.name.strip()
    if not new:
        die("empty name | flag='--name'")
    if pl.get("name") == new:
        print(json.dumps({"renamed": False, "id": pl["id"], "name": new, "reason": "already that name"}, ensure_ascii=False))
        return
    if (pl.get("owner") or {}).get("id") != creds.get("user_id"):
        die(f"not the owner; Spotify only lets the owner rename | playlist='{pl.get('name')}' owner='{(pl.get('owner') or {}).get('id')}'")
    if args.dry_run:
        log_info(f"dry-run: would rename | from='{pl.get('name')}' to='{new}'")
        print(json.dumps({"renamed": False, "dry_run": True, "id": pl["id"], "from": pl.get("name"), "to": new}, ensure_ascii=False))
        return
    api(creds, "PUT", f"/playlists/{args.playlist}", body={"name": new})
    log_info(f"renamed | from='{pl.get('name')}' to='{new}'")
    print(json.dumps({"renamed": True, "id": pl["id"], "from": pl.get("name"), "to": new}, ensure_ascii=False))


def cmd_playlist_unfollow(args):
    """Remove a playlist from the library (the API cannot delete one; for the owner this is the same thing)."""
    creds = read_credentials()
    if args.dry_run:
        log_info(f"dry-run: would unfollow | playlist='{args.playlist}'")
        print(json.dumps({"unfollowed": False, "dry_run": True, "playlist": args.playlist}))
        return
    api(creds, "DELETE", f"/playlists/{args.playlist}/followers")
    log_info(f"playlist unfollowed | playlist='{args.playlist}'")
    print(json.dumps({"unfollowed": True, "playlist": args.playlist}))


def cmd_search_artist(args):
    creds = read_credentials()
    res = api(creds, "GET", "/search", params={"q": args.name, "type": "artist", "limit": 5})
    rows = [{"name": a.get("name"), "id": a.get("id"), "url": (a.get("external_urls") or {}).get("spotify"), "followers": (a.get("followers") or {}).get("total"), "genres": a.get("genres")} for a in (res.get("artists") or {}).get("items", [])]
    print(json.dumps({"query": args.name, "artists": rows}, ensure_ascii=False))


# ---------- main ----------

def parse_args():
    parser = argparse.ArgumentParser(description="Spotify for Ari's bots: JSON out, credentials from ~/.config/ari-spotify.")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("auth", help="one-time browser login")
    p.add_argument("--force", action="store_true", help="log in again even if credentials exist")
    p.add_argument("--manual", action="store_true", help="type the Client ID and Secret into the terminal instead of reading 1Password")
    p.set_defaults(func=cmd_auth)
    sub.add_parser("me", help="the signed-in user").set_defaults(func=cmd_me)
    p = sub.add_parser("liked", help="Liked Songs, oldest first")
    p.add_argument("--artist", help="keep only tracks by this artist (exact name, case-insensitive)")
    p.add_argument("--refresh", action="store_true", help="ignore the 6 h cache")
    p.set_defaults(func=cmd_liked)
    sub.add_parser("playlists", help="the user's playlists").set_defaults(func=cmd_playlists)
    p = sub.add_parser("playlist-tracks", help="tracks of a playlist")
    p.add_argument("--playlist", required=True, help="playlist id")
    p.set_defaults(func=cmd_playlist_tracks)
    p = sub.add_parser("playlist-create", help="create a private playlist")
    p.add_argument("--name", required=True)
    p.add_argument("--description", default="")
    p.add_argument("--public", action="store_true")
    p.add_argument("--dry-run", dest="dry_run", action="store_true")
    p.set_defaults(func=cmd_playlist_create)
    p = sub.add_parser("playlist-add", help="add tracks to a playlist")
    p.add_argument("--playlist", required=True, help="playlist id")
    p.add_argument("--uri", action="append", required=True, help="spotify:track:<id>, repeatable")
    p.add_argument("--dry-run", dest="dry_run", action="store_true")
    p.set_defaults(func=cmd_playlist_add)
    p = sub.add_parser("teaser", help="create the concert teaser playlist for an artist: liked songs, oldest first")
    p.add_argument("--artist", required=True, help="artist name as read from the ticket; resolved against Spotify search")
    p.add_argument("--date", required=True, help="concert date, YYYY-MM-DD")
    p.add_argument("--description", default="", help="override the default description")
    p.add_argument("--dry-run", dest="dry_run", action="store_true")
    p.set_defaults(func=cmd_teaser)
    p = sub.add_parser("rename", help="rename a playlist you own")
    p.add_argument("--playlist", required=True, help="playlist id")
    p.add_argument("--name", required=True)
    p.add_argument("--dry-run", dest="dry_run", action="store_true")
    p.set_defaults(func=cmd_rename)
    p = sub.add_parser("playlist-unfollow", help="remove a playlist from the library (the API cannot delete)")
    p.add_argument("--playlist", required=True, help="playlist id")
    p.add_argument("--dry-run", dest="dry_run", action="store_true")
    p.set_defaults(func=cmd_playlist_unfollow)
    p = sub.add_parser("search-artist", help="find an artist")
    p.add_argument("--name", required=True)
    p.set_defaults(func=cmd_search_artist)
    return parser.parse_args()


def main():
    args = parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
