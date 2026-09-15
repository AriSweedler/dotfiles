---
name: ari-gsw-calendar-add
description: Add an event to Ari's Google Calendar via the gws CLI. Titles carry a [Type] prefix from the event-type taxonomy; title, time, and location are required. Use when asked to put something on the calendar from a Slack post, receipt paste, or verbal ask.
---

# Calendar Add

Turn source material — a Slack post, a pasted receipt/confirmation, a verbal ask — into a Google Calendar event via `gws calendar +insert`. Every event title carries a `[<Type>]` prefix from the **Event types** taxonomy. Input is typically a messy blob (order receipts, channel posts); extract only the event fields and ignore the noise.

## Rules

- **Title, time, and location are required. Notes (description) are optional.** If any required field is missing from the source material, ask the user for the missing field(s) — NEVER create an event without all three. The same applies to a type's required fields (see its section).
- **Every title is `[<Type>] <Title>`.** Pick the type from the **Event types** sections. If no section fits, ask the user what prefix to use and offer to add a section for it via `/ari-skill-update`.
- **Times are RFC3339 with an explicit offset** (e.g. `2026-08-15T21:00:00-07:00`), using the event location's timezone.
- **End time:** if the source gives none, use start + 2 hours and show the assumed end in the confirmation.
- **Each description element goes on its own line** (doors time, ticket link, purchase record, playlist, …) — newline-separated, never a run-on sentence.
- **Never `2>&1` a gws call you'll parse** — gws prints `Using keyring backend: keyring` on stderr, which corrupts the JSON on stdout.
- **Confirm before inserting.** Show the assembled event (title, time, location, description) and wait for a yes.

## Event types

One section per type: its prefix plus type-specific rules. When a new type appears, add a section for it.

### [Airtable Culture Club]

Events coordinated in the Airtable Culture Club (Slack channel posts about movie nights, outings, etc.). Example: a post announcing movie night Thursday — dinner at Super Duper at the office, walking out at 6:30pm, showtime 7pm at the Metreon — becomes `[Airtable Culture Club] Movie night`, start 6:30pm (the walk-out time), location Metreon, with the dinner/logistics detail in the description.

### [Concert]

- **Artist: required — and IS the title**, so the title is `[Concert] <artist>`.
- **Times:** the event start is ALWAYS the showtime; the doors time ALWAYS goes in the description.
- **Ticket-purchase link: required.** Goes in the description. Strip ALL query params from the link; exceptions where a param is load-bearing will be listed here as we learn them (currently none).
- **Ticket purchase record: required.** When/how tickets were bought — date, ticket count, platform, dollar amount (e.g. `6/24/26: 1 ticket on Ticketweb, $31.55`). Goes in the description alongside the ticket link; derivable from a receipt blob.
- **Spotify playlist link: optional.** Goes in the description when supplied. No querying if absent.
- **Opener(s): optional.** When known, each opening act goes in the description on its own line as `Opener: <name>` (e.g. `Opener: Pink Skies`). No querying if absent.
- **Invitees: optional.** "invite Lavi", "invited Sabrina" → add each as an attendee (`--attendee <email>`, repeatable); use the @airtable.com address when confidently known, otherwise ask for the email. No querying if absent.
- **The description holds ONLY** the doors time, opener(s), ticket link, purchase record, and optional Spotify link/notes. No incidental receipt text ("All ages", venue policies), and no processing notes like "(all query params stripped)" — just the cleaned content.
- Missing artist, ticket link, or purchase record → ask the user, per the required-field rule.

Worked example — a Ticketweb order receipt paste:

| Field | Extracted |
| --- | --- |
| Title | `[Concert] Krooked Kings` |
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
[Concert] Krooked Kings
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
gws calendar +insert --summary '[<Type>] <Title>' --start '<RFC3339>' --end '<RFC3339>' --location '<where>' --description '<notes>' 2>/dev/null
```

Useful extras: `--attendee <email>` (repeatable), `--meet` (adds a Meet link). Report the `htmlLink` and `id` from the response, then open the event with the dotfiles opener (`~/.config/bin/open-link`, work-profile Chrome first):

```zsh
open-link '<htmlLink>'
```

If the insert fails (non-zero exit), show gws's stderr and offer retry / debug — expired auth or a locked keyring is the common cause.

### Edit or undo

For a small fix (add an attendee, tweak a field), patch the existing event. `--params` carries only URL/query parameters — body fields passed there are silently dropped (unchanged resource, same etag, no error); the request body goes in `--json`. `attendees` replaces the whole list, so include existing attendees when adding one:

```zsh
gws calendar events patch --params '{"calendarId": "primary", "eventId": "<id>", "sendUpdates": "all"}' --json '{"attendees": [{"email": "<email>"}]}' 2>/dev/null
```

If the event is wholesale wrong, delete it and re-insert. `events delete` writes its empty-body response to a file in cwd (`download.html` by default) and `-o` must resolve inside cwd — so run it from `/tmp`:

```zsh
cd /tmp && gws calendar events delete -o gws-delete-response.out --params '{"calendarId": "primary", "eventId": "<id>"}' 2>/dev/null && rm -f gws-delete-response.out
```

Verify with `gws calendar events get --params '{"calendarId": "primary", "eventId": "<id>"}' 2>/dev/null | jq -r '.status'` — `cancelled` means deleted.
