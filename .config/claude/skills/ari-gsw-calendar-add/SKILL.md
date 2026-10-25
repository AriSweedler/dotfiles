---
name: ari-gsw-calendar-add
description: Add an event to Ari's Google Calendar via the gws CLI. Titles carry a [Type] prefix from the event-type taxonomy; title, time, and location are required. Use when asked to put something on the calendar from a Slack post, receipt paste, or verbal ask; a chat bot drives the same insert through bin/cal-add.py.
---

# Calendar Add

Turn source material — a Slack post, a pasted receipt/confirmation, a verbal ask — into a Google Calendar event via `gws calendar +insert`. Every event title carries a `[<Type>]` prefix from the **Event types** taxonomy. Input is typically a messy blob (order receipts, channel posts); extract only the event fields and ignore the noise.

## Rules

- **Title, time, and location are required. Notes (description) are optional.** If any required field is missing from the source material, ask the user for the missing field(s) — NEVER create an event without all three. The same applies to a type's required fields (see its section).
- **Every title is `[<Type>] <Title>`, unless the type has its own calendar.** A type with a **Calendar** line in its section goes on that calendar with no prefix: the calendar already says what it is. Pick the type from the **Event types** sections. If no section fits, ask the user what prefix to use and offer to add a section for it via `/ari-skill-update` (a work-only type goes in the local file named under **Event types**).
- **Calendar:** `primary` unless the type's section names one. Resolve a named calendar by listing, never from memory:
  ```zsh
  gws calendar calendarList list 2>/dev/null | jq -r '.items[] | select(.summary | test("<name>"; "i")) | .id'
  ```
- **Times are RFC3339 with an explicit offset** (e.g. `2026-08-15T21:00:00-07:00`), using the event location's timezone.
- **End time:** if the source gives none, use start + 2 hours and show the assumed end in the confirmation.
- **Each description element goes on its own line** (doors time, ticket link, purchase record, playlist, …) — newline-separated, never a run-on sentence.
- **Never `2>&1` a gws call you'll parse** — gws prints `Using keyring backend: keyring` on stderr, which corrupts the JSON on stdout.
- **Headless gws (ssh, a bot) needs the file keyring.** Without a login keychain, gws's decrypt fails and it DELETES `credentials.enc` and `token_cache.json`. Copy the `gws-cli` keychain item's 44-char key into `~/.config/gws/.encryption_key` (mode 600) once, then run with `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file`; `bin/cal-add.py` sets it itself when the key file exists.
- **Confirm before inserting.** Show the assembled event (title, time, location, description) and wait for a yes.

## Event types

One section per type: its prefix plus type-specific rules. When a new type appears, add a section for it.

**Also read `~/.local/share/gsw-calendar-add/event-types.md` when it exists**: work and machine-specific types live there, in the same section format, in the local dotfiles tier. A new work-only type goes in that file, not here.

### [Concert]

- **Calendar: the one whose name contains "concert"** (resolve its id per the Calendar rule), passed as `--calendar <id>`. Never `primary`.
- **Artist: required — and IS the title**, with no prefix: the title is just `<artist>` (the Concerts calendar makes `[Concert]` redundant).
- **Times:** the event start is ALWAYS the showtime; the doors time ALWAYS goes in the description.
- **Ticket-purchase link: required.** Goes in the description. Strip ALL query params from the link; exceptions where a param is load-bearing will be listed here as we learn them (currently none).
- **Ticket purchase record: required.** When/how tickets were bought — date, ticket count, platform, dollar amount (e.g. `6/24/26: 1 ticket on Ticketweb, $31.55`). Goes in the description alongside the ticket link; derivable from a receipt blob.
- **Spotify playlist link: optional.** Goes in the description when supplied. No querying if absent.
- **Opener(s): optional.** When known, each opening act goes in the description on its own line as `Opener: <name>` (e.g. `Opener: Pink Skies`). No querying if absent.
- **Invitees: optional.** "invite Sam", "invited Alex" → add each as an attendee (`--attendee <email>`, repeatable); use the address the user uses for that person when confidently known, otherwise ask for the email. No querying if absent.
- **The description holds ONLY** the doors time, opener(s), ticket link, purchase record, and optional Spotify link/notes. No incidental receipt text ("All ages", venue policies), and no processing notes like "(all query params stripped)" — just the cleaned content.
- Missing artist, ticket link, or purchase record → ask the user, per the required-field rule.

Worked example — a Ticketweb order receipt paste:

| Field | Extracted |
| --- | --- |
| Calendar | Concerts (id from `calendarList list`) |
| Title | `Krooked Kings` |
| Time | Sat Aug 15, 9:00 PM PDT (`2026-08-15T21:00:00-07:00`) |
| Location | The Independent, 628 Divisadero St, San Francisco, CA 94117 |
| Description | Four lines: `Doors: 8:30 PM PDT` / `Opener: Pink Skies` / `Tickets: https://www.ticketweb.com/event/krooked-kings-the-independent-tickets/14902833` / `Purchased 6/24/26: 1 ticket on Ticketweb, $31.55` |
| Opener | Pink Skies (known from the lineup, not the receipt) |
| Spotify playlist | Not in the blob → omitted |
| Invitees | Not mentioned → none |
| Ignored | Order number, payment method, "All ages", venue policy text |

### [Movie]

- **Film: required — and IS the title**, so the title is `[Movie] <film>`; keep the format when the ticket names one (e.g. `[Movie] The Odyssey — IMAX 70MM`).
- **Runtime: required.** Goes in the description as `Runtime: <Xh Ymin>`, and the end time is start + runtime (overrides the generic start + 2h default).
- **Ticket purchase record: required.** Platform, ticket count, dollar amount — date when known (e.g. `Purchased on Fandango: 2 tickets, $63.36`). Goes in the description; derivable from a receipt blob.
- **Letterboxd link: required — look it up, never via API keys** (Letterboxd's API is partner-gated; IMDb's is paid). Guess the film slug (kebab-case title, year-suffixed when ambiguous, e.g. `the-odyssey-2026`) and validate with `curl -sI 'https://letterboxd.com/film/<slug>/'` — 200 means good. On a miss, `curl -sI 'https://letterboxd.com/imdb/<tt-id>/'` (or `/tmdb/<id>/`) 302s to the canonical `/film/<slug>/`, or fall back to a web search. The description carries the canonical `https://letterboxd.com/film/<slug>/` URL — verify it's the right film, no query params.
- **Auditorium/seats: optional.** When known, on their own description line (e.g. `Auditorium 16, seats F9 + F10`).
- Missing runtime or purchase record → ask the user, per the required-field rule.

Worked example — a Fandango confirmation paste:

| Field | Extracted |
| --- | --- |
| Title | `[Movie] The Odyssey — IMAX 70MM` |
| Time | Fri Aug 21, 10:00 PM – 12:52 AM PDT (end = start + 2h 52min runtime) |
| Location | AMC Metreon 16, 135 4th St, San Francisco, CA 94103 |
| Description | Four lines: `Auditorium 16, seats F9 + F10` / `Runtime: 2h 52min` / `Letterboxd: https://letterboxd.com/film/the-odyssey-2026/` / `Purchased on Fandango: 2 tickets, $63.36` |
| Letterboxd link | Looked up by the agent, never in the blob |
| Ignored | Order number, convenience fees, payment method |

## Workflow

### Parse the source

Extract title, start/end time, location, and description material from the blob; ignore receipt noise. Match the event to a type section and apply its rules.

### Fill gaps

Ask the user for any missing required field (title, time, location, plus the type's required fields). Do not guess.

### Confirm and insert

Show the assembled event and wait for approval. Mark any assumed value (defaulted end time, resolved attendee email):

```
Krooked Kings  (calendar: Concerts)
Sat Aug 15, 9:00 PM – 11:00 PM PDT (end assumed: start + 2h)
The Independent, 628 Divisadero St, San Francisco, CA 94117
---
Doors: 8:30 PM PDT
Opener: Pink Skies
Tickets: https://www.ticketweb.com/event/krooked-kings-the-independent-tickets/14902833
Purchased 6/24/26: 1 ticket on Ticketweb, $31.55
```

Then:

```zsh
gws calendar +insert --calendar '<id or primary>' --summary '<title>' --start '<RFC3339>' --end '<RFC3339>' --location '<where>' --description '<notes>' 2>/dev/null
```

`--summary` is `[<Type>] <Title>` on `primary` and the bare title on a type's own calendar.

Useful extras: `--attendee <email>` (repeatable), `--meet` (adds a Meet link). Report the `htmlLink` and `id` from the response, then open the event with the dotfiles opener (`~/.config/bin/open-link`, work-profile Chrome first):

```zsh
open-link '<htmlLink>'
```

If the insert fails (non-zero exit), show gws's stderr and offer retry / debug — expired auth or a locked keyring is the common cause.

### Edit or undo

For a small fix (add an attendee, tweak a field), patch the existing event. `--params` carries only URL/query parameters — body fields passed there are silently dropped (unchanged resource, same etag, no error); the request body goes in `--json`. `attendees` replaces the whole list, so include existing attendees when adding one:

```zsh
gws calendar events patch --params '{"calendarId": "<the event's calendar id>", "eventId": "<id>", "sendUpdates": "all"}' --json '{"attendees": [{"email": "<email>"}]}' 2>/dev/null
```

If the event is wholesale wrong, delete it and re-insert. `events delete` writes its empty-body response to a file in cwd (`download.html` by default) and `-o` must resolve inside cwd — so run it from `/tmp`:

```zsh
cd /tmp && gws calendar events delete -o gws-delete-response.out --params '{"calendarId": "<calendar id>", "eventId": "<id>"}' 2>/dev/null && rm -f gws-delete-response.out
```

Verify with `gws calendar events get --params '{"calendarId": "<calendar id>", "eventId": "<id>"}' 2>/dev/null | jq -r '.status'` — `cancelled` means deleted.

## File storage

- `bin/cal-add.py` — the deterministic half of this skill. Takes the event as JSON (stdin or arg) or flags, validates the required fields and the date formats, resolves the calendar by name, applies the Concert rules it knows (show time as the start, doors in the description, purchase record and doors derived from the source text, invented URLs and prices dropped), skips an event already on the calendar, inserts via gws, and prints the exact reply. With `--concert` it also makes the teaser playlist through `/ari-spotify` (`spotify.zsh teaser`, liked songs by the artist oldest first, named `YYYY-MM-DD | Artist`), writes `Teaser playlist: <url>` into the event description and a `• **Teaser:**` bullet into the reply; a Spotify failure is one reply line, never a failed event. `--no-teaser` skips it. `--dry-run` never calls gws; `--help` lists the fields.

## From a chat bot (OpenClaw)

A small model does not follow the prose above. Its one job is a JSON of the fields it read; the script owns the rest, including sending the reply into the chat that spoke last:

```zsh
python3 $HOME/.claude/skills/ari-gsw-calendar-add/bin/cal-add.py --concert <<'JSON'
{"title": "Jai Wolf", "start": "2026-10-24 20:00", "location": "The Regency Ballroom, San Francisco"}
JSON
```

Output contract: `FIX: <why>` means the JSON was wrong (fix it, run once more); `NO_REPLY` means the script already delivered the reply; anything else is the reply text to relay, ending in `NOT SENT: <why>` when no chat was live (a CLI run). The workspace rule that drives the bot (`~/.openclaw/workspace/AGENTS.md` on the gateway machine) must name this path and nothing under `/tmp`, which macOS clears on reboot.
