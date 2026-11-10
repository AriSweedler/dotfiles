---
name: ari-gsw-calendar-add
description: Add an event to Ari's Google Calendar via the gws CLI. Titles carry a [Type] prefix from the event-type taxonomy; title, time, and location are required. Use when asked to put something on the calendar from a Slack post, receipt paste, or verbal ask; a chat bot drives the same insert through concert-mcp's MCP tools.
---

# Calendar Add

Turn source material — a Slack post, a pasted receipt/confirmation, a verbal ask — into a Google Calendar event via `gws calendar +insert`. Every event title carries a `[<Type>]` prefix from the **Event types** taxonomy. Input is typically a messy blob (order receipts, channel posts); extract only the event fields and ignore the noise.

## Rules

- **Title, time, and location are required. Notes (description) are optional.** If any required field is missing from the source material, ask Ari for the missing field(s) — NEVER create an event without all three. The same applies to a type's required fields (see its section).
- **Every title is `[<Type>] <Title>`, unless the type has its own calendar.** A type with a **Calendar** line in its section goes on that calendar with no prefix: the calendar already says what it is. Pick the type from the **Event types** sections. If no section fits, ask Ari what prefix and rules the type takes, then add its section with `/ari-skill-update`; **a new section MUST land with its own concert-mcp module, tool and golden test** (**Event types**).
- **Calendar:** `primary` unless the type's section names one. Resolve a named calendar by listing, never from memory; exactly one id → use it, none or several → show the names and ask, never fall back to `primary`:
  ```zsh
  gws calendar calendarList list 2>/dev/null | jq -r '.items[] | select(.summary | test("<name>"; "i")) | .id'
  ```
- **Times are RFC3339 with an explicit offset** (e.g. `2026-08-15T21:00:00-07:00`), using the event location's timezone.
- **End time:** if the source gives none, use start + 2 hours and show the assumed end in the confirmation.
- **Each description element goes on its own line** (doors time, ticket link, purchase record, playlist, …) — newline-separated, never a run-on sentence.
- **Never `2>&1` a gws call you'll parse** — gws prints `Using keyring backend: keyring` on stderr, which corrupts the JSON on stdout.
- **Headless gws (ssh, a bot) needs the file keyring.** Without a login keychain, gws's decrypt fails and it DELETES `credentials.enc` and `token_cache.json`. Copy the `gws-cli` keychain item's 44-char key into `~/.config/gws/.encryption_key` (mode 600) once, then run with `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND=file`; concert-mcp (behind `bin/cal-add.zsh` and the bot's tools) sets it itself when the key file exists.
- **MUST confirm before ANY calendar write**: an insert, a patch, a delete, `cal-add.zsh --execute`, `cal-del.zsh --execute`. Show the event (or its dry-run reply) and the change, and wait for Ari's yes.

## Event types

One section per type: its prefix plus type-specific rules. Each section is the spec for one concert-mcp tool in its own module with a golden test (homelab `apps/concert-mcp`): [Concert] is `concert_add` (`src/concert_mcp/flows/concert_add.py`, `tests/test_flow_concert_add.py`), [Movie] is `movie_add` (`src/concert_mcp/flows/movie_add.py` and `text/movie.py`, `tests/test_flow_movie_add.py` against `tests/goldens/fandango-movie.json`). A change to a section lands with the same change to its module and golden test; a new section gets its own module and tool there.

Known undefined type: a massage booking (the bot failed one on 2026-10-28). Ari defines its section; until then it takes the no-section path in the Rules.

**Also read `~/.local/share/gsw-calendar-add/event-types.md` when it exists**: work and machine-specific types live there, in the same section format, in the local dotfiles tier. A new work-only type goes in that file, not here.

### [Concert]

- **Calendar: the one whose name contains "concert"** (resolve its id per the Calendar rule), passed as `--calendar <id>`. Never `primary`.
- **Artist: required — and IS the title**, with no prefix: the title is just `<artist>` (the Concerts calendar makes `[Concert]` redundant).
- **Times:** the event start is ALWAYS the showtime; the doors time ALWAYS goes in the description.
- **Ticket-purchase link: required.** Goes in the description with every query param stripped.
- **Ticket purchase record: required.** When/how tickets were bought — date, ticket count, platform, dollar amount (e.g. `Purchased 6/24/26: 1 ticket on Ticketweb, $31.55`). Goes in the description alongside the ticket link; derivable from a receipt blob.
- **Spotify playlist link: optional.** Goes in the description when supplied; when none is, `bin/cal-add.zsh` makes the teaser playlist and writes its line. Never search for one yourself.
- **Opener(s): optional.** When known, each opening act goes in the description on its own line as `Opener: <name>` (e.g. `Opener: Pink Skies`). No querying if absent.
- **Invitees: optional.** "invite Sam", "invited Alex" → add each as an attendee (`--attendee <email>`, repeatable); use an address only when it appears in the source or this conversation, otherwise ask Ari for it. No querying if absent.
- **The description holds ONLY** the doors time, opener(s), ticket link, purchase record, and optional Spotify link/notes. No incidental receipt text ("All ages", venue policies), and no processing notes like "(all query params stripped)" — just the cleaned content.
- Missing artist, ticket link, or purchase record → ask Ari, per the required-field rule.

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
- **Ticket purchase record: required.** Platform and ticket count, the date when known, and the dollar amount when the source shows one (e.g. `Purchased on Fandango: 2 tickets, $63.36`). Goes in the description; derivable from a receipt blob. A source with no price (a Fandango confirmation screen) → **ask Ari for the amount**; the bot, with no one to ask, writes the record without it (`Purchased on Fandango: 2 tickets`).
- **Letterboxd link: required — look it up, never via API keys** (Letterboxd's API is partner-gated; IMDb's is paid). The slug is the kebab-case title: try `https://letterboxd.com/film/<slug>-<year>/` first, then `https://letterboxd.com/film/<slug>/`, and keep the page whose `og:title` names the film and year. On a miss, `curl -sI 'https://letterboxd.com/imdb/<tt-id>/'` (or `/tmdb/<id>/`) 302s to the canonical `/film/<slug>/`, or fall back to a web search. The description carries the canonical `https://letterboxd.com/film/<slug>/` URL, no query params.
- **Auditorium/seats: optional.** When known, one description line: the auditorium, then the seats joined with ` + ` (e.g. `Auditorium 16, seats F9 + F10`).
- Missing runtime or purchase record → ask Ari, per the required-field rule.

Worked example — a Fandango confirmation paste:

| Field | Extracted |
| --- | --- |
| Title | `[Movie] The Odyssey — IMAX 70MM` |
| Time | Fri Aug 21, 10:00 PM – 12:52 AM PDT (end = start + 2h 52min runtime: `2026-08-22T00:52:00-07:00`, the next day) |
| Location | AMC Metreon 16, 135 4th St, San Francisco, CA 94103 |
| Description | Four lines: `Auditorium 16, seats F9 + F10` / `Runtime: 2h 52min` / `Letterboxd: https://letterboxd.com/film/the-odyssey-2026/` / `Purchased on Fandango: 2 tickets, $63.36` |
| Letterboxd link | Looked up by the agent, never in the blob |
| Ignored | Order number, convenience fees, payment method |

Worked example — a Fandango confirmation screenshot, which shows no price (the bot's golden test; this skill asks Ari for the amount instead):

| Field | Extracted |
| --- | --- |
| Title | `[Movie] Godzilla Minus Zero` |
| Time | Wed Nov 11, 2:30 PM – 4:45 PM PST (end = start + 2h 15min runtime) |
| Location | Alamo Drafthouse Cinema New Mission, 2550 Mission Street, San Francisco, CA 94110 |
| Description | Four lines: `Auditorium 1, seats 515 + 516` / `Runtime: 2h 15min` / `Letterboxd: https://letterboxd.com/film/godzilla-minus-zero/` / `Purchased on Fandango: 2 tickets` |
| Letterboxd link | `godzilla-minus-zero-2026` is a 404; the bare `godzilla-minus-zero` is the 2026 film |
| Ignored | Confirmation number, rating, pickup instructions, the email address |

## Workflow

### Parse the source

Extract title, start/end time, location, and description material from the blob; ignore receipt noise. Match the event to a type section and apply its rules. No year in the source → the next date on or after today; a weekday that does not match the date → ask.

### Fill gaps

Ask Ari for any missing required field (title, time, location, plus the type's required fields). Do not guess.

### Confirm and insert

**Pick the path by type.** [Concert] → `bin/cal-add.zsh` (**File storage**): run its dry run, show the reply verbatim as the confirmation, then `--execute` after Ari's yes; NEVER hand-build a gws insert for a concert. Every other type → the gws steps below.

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

Before the insert, and before any retry, list the events at that start (`gws calendar events list --params '{"calendarId": "<id>", "timeMin": "<start>", "timeMax": "<end>", "q": "<title>"}' 2>/dev/null`): a non-cancelled match is already on the calendar; report its `htmlLink` and insert nothing. Then, the description in `$'…'` so each `\n` is a real newline (inside plain single quotes it stays the two characters `\n`):

```zsh
gws calendar +insert --calendar '<id or primary>' --summary '<title>' --start '<RFC3339>' --end '<RFC3339>' --location '<where>' --description $'Runtime: 2h 15min\nPurchased on Fandango: 2 tickets' 2>/tmp/gws-insert.err
```

`--summary` is `[<Type>] <Title>` on `primary` and the bare title on a type's own calendar.

Useful extras: `--attendee <email>` (repeatable), `--meet` (adds a Meet link). Report the `htmlLink` and `id` from the response, then open the event with the dotfiles opener (`~/.config/bin/open-link`, work-profile Chrome first):

```zsh
open-link '<htmlLink>'
```

If the insert fails (non-zero exit), show `/tmp/gws-insert.err` and offer retry / debug — expired auth or a locked keyring is the common cause.

### Edit or undo

For a small fix (add an attendee, tweak a field), patch the existing event. `--params` carries only URL/query parameters — body fields passed there are silently dropped (unchanged resource, same etag, no error); the request body goes in `--json`. `attendees` replaces the whole list: read it first, append, and patch with the whole array (`sendUpdates: all` emails every attendee; say so at the confirmation):

```zsh
gws calendar events get --params '{"calendarId": "<the event's calendar id>", "eventId": "<id>"}' 2>/dev/null | jq -c '{attendees: ((.attendees // []) + [{email: "<email>"}])}'
gws calendar events patch --params '{"calendarId": "<the event's calendar id>", "eventId": "<id>", "sendUpdates": "all"}' --json '<the object jq printed>' 2>/dev/null
```

If the event is wholesale wrong, insert the corrected one first, then delete the old one: a failed re-insert then loses nothing. A Concerts or Personal event goes through `bin/cal-del.zsh --title '<name>' --calendar '<id>' --id '<eventId>'` (dry run, then `--execute`), which also drops a show from the setlist poller's queue. Any other calendar: `events delete` writes its empty-body response to a file in cwd (`download.html` by default) and `-o` must resolve inside cwd — so run it in a subshell in a fresh temp dir:

```zsh
(cd "$(mktemp -d)" && gws calendar events delete -o gws-delete-response.out --params '{"calendarId": "<calendar id>", "eventId": "<id>"}' 2>/dev/null)
```

Verify with `gws calendar events get --params '{"calendarId": "<calendar id>", "eventId": "<id>"}' 2>/dev/null | jq -r '.status'` — `cancelled` means deleted.

## File storage

- `bin/cal-add.zsh` — the deterministic half of this skill: `concert-mcp add --concert` (the homelab's `apps/concert-mcp` submodule holds the policy) behind the shared launcher. Takes the event as flags, or one JSON object as the argument or on stdin; validates the required fields and dates, resolves the calendar, applies the [Concert] rules, skips an event already on the calendar, makes the teaser playlist (`--no-teaser` skips it; a Spotify failure is one reply line, never a failed event), inserts via gws, and prints the reply. A dry run unless `--execute`; run the dry run, show it per **Confirm and insert**, then `--execute` after Ari's yes:
  ```zsh
  zsh $HOME/.claude/skills/ari-gsw-calendar-add/bin/cal-add.zsh --title 'Jai Wolf' --start '2026-10-24 20:00' --location 'The Regency Ballroom, San Francisco'
  zsh $HOME/.claude/skills/ari-gsw-calendar-add/bin/cal-add.zsh --title 'Jai Wolf' --start '2026-10-24 20:00' --location 'The Regency Ballroom, San Francisco' --execute
  ```
  Output: `FIX: <why>` means the input was wrong (fix it, run once more); `NO_REPLY` means the reply went to the live chat; anything else is the reply text, ending in `NOT SENT: <why>` when no chat was live.
- `bin/cal-del.zsh` — `concert-mcp del`, the same launcher and the same `--execute` gate: `--title <artist>` and an optional `--date YYYY-MM-DD`; it searches Concerts and Personal, deletes a unique match (and drops the show from the setlist poller's queue), replies with a numbered list when several match (rerun with `--pick N`), and says "nothing deleted" when none does.
- `lib/concert_mcp.zsh` — the launcher both scripts source: finds uv (PATH, then `/opt/homebrew/bin`, `~/.local/bin`), refuses a missing checkout (`CONCERT_MCP_HOME` overrides `~/homelab/apps/concert-mcp`), and passes concert-mcp's own `--dry-run` unless `--execute`.

## From a chat bot (OpenClaw)

The bot runs neither script: it calls concert-mcp's MCP tools (`concert__concert_add`, `concert__calendar_add`, `concert__event_delete`; a ticket that parses as a movie goes to the `movie_add` flow), per the workspace rule `~/.openclaw/workspace/AGENTS.md` on the gateway machine. The tools own the reply and its delivery; the output contract is the one above.
