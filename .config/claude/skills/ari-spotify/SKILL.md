---
name: ari-spotify
description: Read Ari's Spotify Liked Songs and create or fill playlists through one JSON-out CLI (bin/spotify.zsh), from a Claude session or the OpenClaw concert bot. Use when a task needs the songs Ari liked by an artist, his playlist names, or a new playlist; never call the Spotify API by hand.
---

# Spotify

One stdlib-Python CLI does every Spotify call; the model only picks the command and reads the JSON. Credentials come from 1Password once (`auth`) and then from `~/.config/ari-spotify/credentials.json` (mode 600), so a bot runs it with no prompts.

## Rules

- **Only the CLI talks to Spotify.** No `curl`, no raw tokens in a prompt or a chat.
- **Every command prints one JSON object on stdout**; logs go to stderr. Parse stdout.
- **Liked Songs come back oldest-first** (`added_at`), which is the order the teaser playlist wants. The list is cached 6 h; `--refresh` forces a fetch.
- **Writes are idempotent:** `playlist-create` returns the existing playlist instead of a second one with the same name; `playlist-add` skips uris already in the playlist. Both take `--dry-run`.
- **The Web API cannot create or move playlists into folders**, and cannot delete one: `playlist-unfollow` removes it from the library, which for the owner is the same thing. Say so and leave a folder move to Ari in the app.
- **Playlists Ari only follows (another user's, e.g. the setlist.fm ones) answer 403** to `playlist-tracks` under a development-mode app. Only his own and public-API-readable ones list.
- **Secrets:** the app's Client ID, Client Secret and the refresh token live in the 1Password item `Spotify - OpenClaw app` (vault Private). `auth` reads the first two with `op read` and writes the third back with `op item edit`; nothing else touches 1Password. When the 1Password CLI integration does not answer (`authorization timeout`, `couldn't connect to the desktop app`), `auth --manual` takes the two values typed hidden into the terminal. Never print the credentials file.

## Commands

```zsh
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh auth                     # one time, opens a browser; --force to redo; --manual to type the app ids
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh me
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh liked --artist "Jai Wolf"
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlists
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-tracks --playlist <id>
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-create --name "<name>" --description "<text>"
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-add --playlist <id> --uri spotify:track:<id> --uri spotify:track:<id>
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh playlist-unfollow --playlist <id>
zsh $HOME/.claude/skills/ari-spotify/bin/spotify.zsh search-artist --name "Jai Wolf"
```

The script speaks the 2025 Web API: a playlist's contents are `items` (each entry's track under `item`), at `/playlists/<id>/items`; the old `tracks` names return 403.

`liked` output: `{"artist", "count", "tracks": [{"name", "artists", "album", "uri", "url", "duration_ms", "added_at"}]}`. `playlists`: `{"count", "playlists": [{"name", "id", "url", "public", "tracks", "owner", "description"}]}`. Errors exit 1 with one `[ERROR] … | key='value'` line on stderr.

## Setup (once per machine)

1. Spotify developer dashboard: an app with Redirect URI `http://127.0.0.1:8888/callback` and the Web API enabled. Copy its Client ID and Client Secret into the 1Password item's `username` and `credential` fields.
2. `auth` (above) in a terminal on that machine: it reads the item, opens the consent page, catches the callback on 127.0.0.1:8888, and writes the credentials file and the refresh token.
3. The OpenClaw gateway's exec needs `~/.claude/skills` linked on that machine (`dotfiles init --group repo`).

## File storage

- `bin/spotify.zsh` — a thin wrapper over `concert-mcp spotify` (and `concert-mcp teaser` / `setlist-find`), the Spotify code having moved into the homelab's `apps/concert-mcp` submodule; the CLI. Stdlib only; shared logging from `/ari-skill-pythonscripts`.
