---
name: ari-spotify
description: Read Ari's Spotify Liked Songs and create, fill or rename playlists from a Claude session through one JSON-out CLI (bin/spotify.zsh, a wrapper over concert-mcp's Spotify client). The OpenClaw concert bot does not run this skill; it calls concert-mcp's MCP server. Use when a task needs the songs Ari liked by an artist, his playlist names, a concert's teaser playlist, or a new playlist; never call the Spotify API by hand.
---

# Spotify

A Claude session makes every Spotify call through `bin/spotify.zsh`; the model picks the command and reads the JSON. The script runs concert-mcp's own Spotify client from the homelab checkout (`~/homelab/apps/concert-mcp`, or `$CONCERT_MCP_HOME`). The OpenClaw concert bot does not run this script: it runs `concert-mcp serve`, an MCP server whose `concert_add` tool makes the teaser playlist with the same client. Both read the same credentials file, so one `auth` serves both.

## Rules

- **NEVER reach Spotify except through `bin/spotify.zsh`:** no `curl`, no Python, no import of concert-mcp's client, no token taken from a file. If no command does the job, stop and tell Ari which operation is missing.
- **A teaser playlist is made for a concert only. NEVER create or fill a playlist for a movie.** A ticket for a screening (a cinema, a film title) is a movie, even a music documentary; a live show is a concert. If you cannot tell which, ask Ari before any write. The bot follows the same rule: `movie_add` makes no Spotify call, and `concert_add` hands a movie ticket to the movie flow.
- **Make a concert's teaser with `teaser`, never by hand.** It names the playlist `<YYYY-MM-DD> | <artist>`, the name the bot uses, so a second run finds the first playlist and does not make another.
- **A write is a dry run unless `--execute` is on its command line.** The writes are `playlist-create`, `playlist-add`, `playlist-unfollow`, `rename` and `teaser`. Run each without `--execute` first and read the dry-run record. When Ari asked for the playlist in this request, run `--execute` next. When you picked the name or the tracks, show him the plan (name, numbered tracks) and wait for his yes. Confirm the act from the JSON (`created`, `added`, `dry_run`), never from exit 0.
- **`playlist-unfollow` is a delete, and the CLI cannot undo it.** Run it only on a playlist Ari named in this conversation. Show him its name, owner and url from `playlists`, keep the url in your reply, and add `--execute` only after his yes.
- **`auth` and `setlist-auth` are Ari's to run, never from the Bash tool.** `auth` waits for a browser callback and `--manual` reads hidden input, so hand the command to Ari's pane through /ari-driving and read the result back. Run `me` first: if it answers, auth is done.
- **NEVER print, `cat` or Read a credentials file** (`~/.config/concert-mcp/spotify.json`, the old `~/.config/ari-spotify/credentials.json`) or the 1Password item. To test the credentials, run `me`.

## Commands

Reads:

```zsh
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh me
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh liked --artist "Jai Wolf"          # --refresh refetches the 6 h cache
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlists
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-tracks --playlist <id>
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh search-artist --name "Jai Wolf"
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh setlist-find --artist "Jai Wolf" --date 2026-11-14 --venue "The Quarry" --songs
```

Writes, each a dry run first, then the same line with `--execute`:

```zsh
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh teaser --artist "Jai Wolf" --date 2026-11-14
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh teaser --artist "Jai Wolf" --date 2026-11-14 --execute
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-create --name "<name>" --description "<text>"
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-add --playlist <id> --uri spotify:track:<id> --uri spotify:track:<id>
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh rename --playlist <id> --name "<name>"
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-unfollow --playlist <id>
```

Ari's terminal only, through /ari-driving:

```zsh
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh auth --execute            # --manual when 1Password does not answer; --force after a dead token
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh setlist-auth --execute    # the setlist.fm key that setlist-find needs
```

- `<id>` is the bare playlist id. From `open.spotify.com/playlist/<id>?si=…` or `spotify:playlist:<id>`, pass only `<id>`.
- `--uri` takes a track's `uri` field (`spotify:track:<id>`), never its `url`. Give one `--uri` per track, each uri once, in the order `liked` returned them (oldest first). Do not sort them; `playlist-add` skips uris already in the playlist.
- The Web API cannot put a playlist in a folder. Make the playlist, then tell Ari to move it into the folder in the app.

## Output

- **Exit 0:** stdout is one JSON object (the wrapper always passes `--json`).
- **Exit 1, stdout `{"ok": false, "fix": …, "error": …}`:** the input was wrong. Apply `fix` and run once more.
- **Exit 1, empty stdout:** one `[ERROR] … | key='value'` line on stderr, from Spotify, 1Password, the network, or a missing `uv` or checkout. See **When a command fails**.
- `teaser` and `setlist-find` always run with `--no-send`, so they never post to Telegram.

| Command | Record |
|---|---|
| `me` | `{"id", "display_name", "url", "product"}` |
| `liked` | `{"artist", "count", "tracks": [{"name", "artists", "album", "uri", "url", "duration_ms", "added_at"}]}` |
| `playlists` | `{"count", "playlists": [{"name", "id", "url", "public", "tracks", "owner", "owner_id", "description"}]}`; here `tracks` is a count |
| `playlist-tracks` | `{"playlist", "count", "tracks": [<the liked row>]}` |
| `search-artist` | `{"query", "artists": [{"name", "id", "url", "followers", "genres"}]}` |
| `playlist-create` | `{"created": true, <playlist row>}` new; `{"created": false, <playlist row>}` the name already exists (any case): use its `id`; `{"created": false, "dry_run": true, "name"}` would create, no `id` yet |
| `playlist-add` | `{"added", "skipped", "playlist"}`; dry run `{"added": 0, "would_add", "skipped", "dry_run": true}` |
| `rename` | `{"renamed", "id", "from", "to"}` (`dry_run` on a dry run) |
| `playlist-unfollow` | `{"unfollowed", "playlist"}` (`dry_run` on a dry run) |
| `teaser` | `{"ok", "name", "liked_count", "tracks", "created", "exists", "dry_run", …}` |

## Workflow

### Fill a playlist from an artist's Liked Songs

1. `liked --artist "<name>"`. The match is exact with case ignored; with no exact match, the command refetches and matches on a substring instead. Keep only tracks whose `artists` holds the name, and show any other hits to Ari as near misses.
2. `count: 0` → run `search-artist`, rerun `liked` with the top `name` it returns, and if that is still 0, say there are no liked songs and make no playlist. Add `--refresh` when Ari says he just liked songs or a track he named is missing.
3. For a concert, run `teaser` and stop. Otherwise run `playlist-create`, dry run then `--execute`, and take `id` from the record.
4. If `created` is `false` and `owner_id` is not `me`'s `id`, the name belongs to a playlist Ari only follows. Stop and tell him; adding to it answers 403.
5. `playlist-add --playlist <id>` with the uris, dry run then `--execute`. Report the playlist url and `added`/`skipped`.

```zsh
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh liked --artist "Jai Wolf"
# {"artist": "Jai Wolf", "count": 2, "tracks": [{"name": "Indian Summer", "uri": "spotify:track:AAA", …}, {"name": "Starlight", "uri": "spotify:track:BBB", …}]}
# (each write's dry run, the same line without --execute, comes first and is not shown)
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-create --name "Jai Wolf, liked" --execute
# {"created": true, "name": "Jai Wolf, liked", "id": "PLID", "url": "https://open.spotify.com/playlist/PLID", …}
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-add --playlist PLID --uri spotify:track:AAA --uri spotify:track:BBB --execute
# {"added": 2, "skipped": 0, "playlist": "PLID"}
```

```
BAD:  "Add Dune Part Three on Friday and make a playlist" → search-artist "Hans Zimmer", playlist-create
GOOD: no Spotify call; "teaser playlists are for concerts only" (the calendar add is /ari-gsw-calendar-add)
```

### When a command fails

| stderr | Cause | Do |
|---|---|---|
| `not authorized yet` | no credentials file | Hand Ari `auth --execute` through /ari-driving, then rerun once |
| `token request refused` … `invalid_grant` (or a 400/401 on the token) | the refresh token is dead; the bot's teasers fail too | Hand Ari `auth --force --execute`; retrying will not help |
| `credentials already exist` | `auth` already ran | Nothing to do: auth is done |
| `authorization timeout`, `couldn't connect to the desktop app` | 1Password's CLI integration did not answer | Hand Ari `auth --manual --execute` |
| 403 on `playlist-tracks`, `owner_id` not `me`'s `id` | a playlist Ari only follows (e.g. a setlist.fm one) under a development-mode app | Tell Ari; do not retry or re-auth |
| `uv not found`, `concert-mcp checkout missing` | setup is incomplete | Point Ari to **Setup** step 2 |

Any other `[ERROR]`: show the line and ask Ari whether to retry, skip, or rerun with `--log-level debug`.

## Setup (once per machine)

1. Spotify developer dashboard: an app with Redirect URI `http://127.0.0.1:8888/callback` and the Web API enabled. Copy its Client ID and Client Secret into the `username` and `credential` fields of the 1Password item `Spotify - concert-mcp` (vault Private).
2. Check out the homelab with its `apps/concert-mcp` submodule, and install `uv` (/ari-dotfiles-nix).
3. Ari runs `auth --execute` in his terminal. It reads the two ids with `op read`, opens the consent page, catches the callback on 127.0.0.1:8888, writes `~/.config/concert-mcp/spotify.json` (mode 600), and stores the refresh token back in the item with `op item edit`. Every other command reads only that file, falling back to the old `~/.config/ari-spotify/credentials.json` when it is absent.

## File storage

- `bin/spotify.zsh` — the CLI. It takes the uv lookup and the checkout check from the concert-mcp launcher `/ari-gsw-calendar-add` keeps in `lib/concert_mcp.zsh`, the one launcher both skills use. It runs `teaser` and `setlist-find` as top-level `concert-mcp` subcommands and the rest as `concert-mcp spotify <command>`, with `uv run`. It always adds `--json` (and `--no-send` for the two top-level commands), and it adds concert-mcp's `--dry-run` to a write without `--execute`. The client is concert-mcp's `src/concert_mcp/adapters/spotify_http.py`, which speaks the 2025 Web API (`/playlists/<id>/items`); its flags are in that repo's `docs/cli.md`.
