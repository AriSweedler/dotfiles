# notif-center — click any macOS notification

Status: Layer 1 built, perf-tuned. Layer 2 (Karabiner binding) pending.
Author: Ari (with Claude)
Date: 2026-05-28

## Problem

`Hyper+N` today runs `claude-notification-click-simulator`, which only sees
notifications **terminal-notifier itself posted**. It works by asking
terminal-notifier for its own delivery list (`-list ALL`), dismissing one of
its own groups (`-remove`), and re-running the click action it baked into
`-execute` at fire time. It is blind to Slack, Calendar, Messages, or any
notification it didn't create.

Goal: a `Hyper+N` that clicks the *real* macOS notification — whatever is on
screen, from any app — and triggers that notification's native action. Plus a
small CLI to `list`, `click` (first or Nth), and `filter`.

## Why this needs a new mechanism

terminal-notifier operates entirely inside its own bookkeeping. The real
Notification Center tray is owned by the `NotificationCenter` process and is
only reachable through the macOS Accessibility (AX) API. So the new tool drives
`NotificationCenter` via System Events UI scripting — a different domain from
the existing pipeline, sharing none of its primitives.

## Feasibility findings (validated this session)

All of the following was probed live against the running `NotificationCenter`
on this machine (Darwin 25.x / macOS Tahoe).

1. **The process is AX-scriptable.** `tell process "NotificationCenter"` works;
   whatever runs `osascript` needs Accessibility permission (already granted to
   the controlling terminal here).

2. **Where notifications live.** `window 1` is an `AXSystemDialog` named
   "Notification Center". Notifications are descendants with a distinguishing
   **subrole**:
   - `AXNotificationCenterAlert` — a single notification.
   - `AXNotificationCenterAlertStack` — a collapsed group of one app's
     notifications.

3. **Enumeration.** Walk `entire contents of window 1` and keep elements whose
   subrole is one of the two above. Subrole *is* readable on these refs;
   indexing is stable between two calls made close in time.

4. **Plural *reference* access is dead; plural *value* access is live.** The
   single most important — and most expensive to learn — rule, refined twice:
   - `UI element i of X` (singular, indexed) → **live** ref; properties and
     `count of UI elements of` it read correctly.
   - `entire contents of X`, `UI elements of X` (plural collections of
     *references*) → **dead** refs whose properties read back as `missing value`
     (the body is a SwiftUI `AXHostingView`). Passing a container ref into a
     handler degrades it the same way.
   - `value of every static text of X` (a plural collection of *values*) →
     **live and correct** — it returns a list of strings, not refs, so the
     dead-ref trap doesn't apply. This is both safe and ~20× faster than a
     per-element walk (see Performance). It captures the direct `AXStaticText`
     children, which is where a notification's **title, subtitle, body** live,
     in that order.

5. **Actions.** Without hovering, an alert offers `AXPress` (the default
   "open / activate" click) and `Show Details`. Hovering / stacks additionally
   expose `Show`, `Close`, `Reply`, `Clear All`. So the reliable "click" is
   **`AXPress`**, not the named `Show`.

6. **AppleScript gotchas that cost real time.**
   - **Child enumeration must stay inline in the live `tell process` scope.**
     Passing a container ref into a handler degrades it — `count of UI elements
     of el` then returns 0, so the walk silently collects nothing. `using terms
     from` fixes *compilation* of the System Events vocabulary but does **not**
     re-establish the runtime target, so it doesn't help here. Recursion (which
     needs enumeration inside the recursive handler) is therefore out; bounded
     inline nested loops are the only correct form. Leaf reads (`role`/`value`)
     *do* survive a handler boundary — only enumeration breaks.
   - `set x to contents of a` derefs too. Keep the live loop reference.
   - **Keep emitted records newline-free.** `name of every action of a` is a
     plural enumeration whose coercion emits multi-line action dumps
     (`Name:Show⏎Target:0x0⏎Selector:(null)`). That broke the zsh field split
     (line-based `read` truncates at the first newline, dropping the real text
     two lines down). Dropped the actions column; every field is now single-line
     by construction (text is newline-scrubbed in AppleScript).
   - A top-level handler called inside `tell process …` needs `my`
     (`my clean(...)`), else "process doesn't understand the message".
   - `container` is a reserved System Events property name — don't use it as a
     variable.

## Known limitations / open questions

- **Collapsed stacks hide their members.** When several notifications from one
  app collapse into an `AXNotificationCenterAlertStack`, the member alerts and
  their text are *not* in the AX tree until the stack is expanded. The stack
  itself exposes only `AXPress` + `Show Details` and no text.
  - Consequence for testing: **terminal-notifier is a poor test harness** — all
    its notifications share one app identity and self-collapse into a single
    stack within ~1s. A lone notification reads perfectly; a second one makes
    both unreadable.
  - Decision needed: does `click` on a stack (a) `AXPress` it to expand, then
    click the top member, or (b) treat the stack as one clickable unit?

- **Text reads direct children only.** `value of every static text of a` returns
  the alert's direct `AXStaticText` children. Every notification observed
  (terminal-notifier, Slack, Calendar) keeps title/subtitle/body as direct
  children, so this is complete in practice; a notification that nested text
  inside a sub-group would lose it. Revisit only if such a case appears.

- **No posting-app identity (decided: won't fix).** The posting app's name
  ("Slack") is not in the AX tree at all — not as text, not as an image
  description, nowhere in window 1 (verified by sweeping every element's
  value/description). `--app` therefore matches the notification's first text
  line — the title/sender, e.g. the Slack *workspace* "Airtable", not the app.
  The only source of true app/bundle identity is the usernoted SQLite DB, whose
  schema is per-macOS-version — rejected as too much maintenance. Closed.

- **macOS-version fragility.** The AX hierarchy and subrole names are
  undocumented and have shifted across releases. Pin behavior to subrole
  matching (robust) rather than fixed index paths (brittle).

- **Replace or coexist with the claude simulator?** Clicking the *real* claude
  banner triggers terminal-notifier's `-execute` (the tmux-jump) anyway, so a
  general clicker **subsumes** the claude one. Recommendation: replace.

## Alternatives considered

- **usernoted SQLite DB**
  (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`) holds every
  delivered notification (app bundle id, title, body, date) as binary plists.
  It is the *only* source of true app/bundle identity (which AX omits). But:
  (a) includes already-dismissed rows, (b) needs plist decoding, (c) still needs
  AX to actually *click*, and (d) the schema is per-macOS-version. **Rejected**
  — AX text-reading turned out reliable, and per-version DB maintenance isn't
  worth the one thing it adds (the posting-app name).

## Proposed architecture

### Layer 1 — the CLI: `~/.config/bin/notif-center`

Single zsh script (matches the `claude-session-from-focus` /
`claude-pr-from-session` neighbors: zsh + `log.zsh`, stderr for logs, stdout
for data). The user asked to keep it simple — no bin/lib split, since there's
no fire/click duality to share; this tool only reads + acts on live OS state.

```
notif-center list  [--app PAT] [--match PAT]
notif-center click [N] [--app PAT] [--match PAT] [--action NAME]
notif-center dump            # raw enumeration (debug)
notif-center tree [N]        # full AX descendant dump of the Nth alert (debug)
```

- **list** → `IDX \t TEXT` for each (filtered) notification. (An actions column
  was dropped — `name of every action` emits multi-line garbage that broke
  field parsing, and it added no value; see finding #6.)
- **click [N]** → perform the action on the Nth filtered notification
  (default: 1st). Default action **AXPress**; `--action` selects
  `show|close|details|reply|clearall` when present.
- **filters** apply identically to `list` and `click`. `--app` matches the
  first text line; `--match` matches any text. Both substring,
  case-insensitive, AND-combined.

Internals (built + proven):
- **One** embedded AppleScript engine (`AS_ENGINE`), dispatched by `argv[1]`,
  run via `osascript - <<<`. The shared parts — `isAlert`, the
  `entire contents of window 1` walk filtered by subrole, the idx counter, the
  process/window guards — live once; each mode (`list` / `click` / `tree`)
  branches inside the per-alert loop. (An earlier draft had three near-identical
  engines; collapsing them was the main DRY win.)
  - `list` → records `idx ⟨US⟩ subrole ⟨US⟩ text`, `⟨RS⟩`-separated (US=0x1f,
    RS=0x1e — chosen so notification text can't collide with the delimiters).
    Text via one `value of every static text of a` per alert (a plural *value*
    fetch — see finding #4 and Performance).
  - `click <idx> <ax-action>` → re-walk to the absolute index, `perform
    action`, AXPress fallback, status (`ok` / `axpress-fallback` / `fail: …`).
  - `tree <idx>` → indexed AX dump (debug). `dump` reuses `list`.
- zsh splits records on RS then US, applies `--app`/`--match`, maps the filtered
  Nth back to its absolute alert index, and calls `click`. **With no filters it
  skips the list build entirely** — the filtered index already equals the
  absolute index, so the Hyper+N path never pays the text-reading cost.
- Default action is `AXPress` (`open`); the named `Show` isn't present without
  hover. `--action` exposes `show|close|details|reply|clearall` for when they
  are.

### Layer 2 — the Karabiner binding (copy the existing pipeline)

Mirror the current `Hyper+P` / `Hyper+Q` / `Hyper+N` structure exactly:

1. **Wrapper** `karabiner.ts/src/scripts/bin/karabiner-notification-click` —
   thin orchestrator living in the karabiner repo so the conditional UX stays
   next to the binding (same rationale as the existing wrappers). It calls
   `notif-center click`, then:
   - exit 0 → fire the Raycast confetti (matches current "caught one" UX), and
   - exit ≠0 → transient terminal-notifier alert "no notification to click".

2. **Rule** — repoint `Hyper+N` in `karabiner.ts/src/claude-notifications.ts`
   (or a renamed `src/notifications.ts`) from
   `claude-notification-click-simulator` to `karabiner-notification-click`.

3. **Bake** — `~/.config/karabiner/bin/bake` regenerates + sorts
   `karabiner.json` and `git df add`s it. Then `git df commit`; user runs
   `git_df_push`.

## Performance

Profiled against ~9 notifications (Darwin 25.x). The compile-cost hypothesis was
**wrong**: `osascript` startup is 54ms and a precompiled `.scpt` saves only
~17ms. The real cost is Apple-events round-trips — each AX property read is
~20ms, so a per-element walk over hundreds of reads dominates.

| operation | before | after |
|---|---|---|
| `list` (~9 alerts) | 3.65s | ~1.3s |
| `click 1`, no filter (the Hyper+N path) | ~5s | **0.30s** |
| `click 1 --match …` (filtered) | ~5s | ~1.6s |

Two fixes:

1. **Batched text fetch.** Per-alert text was a depth-3 indexed walk — hundreds
   of singular round-trips (~2.4s). Replaced with one
   `value of every static text of a` per alert (finding #4): ~20× faster, and
   correct because it returns values, not refs.
2. **`click` hot-path skip.** `click` used to build the full `list` (reading
   every alert's text) just to map the filtered Nth to an absolute index, then
   re-walk — so unfiltered `click 1` paid the entire `list` cost (~5s). With no
   filters the filtered index *is* the absolute index, so `click` now skips the
   list build. Filtered `click` still reads text (it must, to match).

Remaining cost (`list` at scale): the subrole scan — one round-trip per element
of `entire contents` (~1s for ~47 elements at 9 alerts). Left as-is on purpose:
bulk `subrole of (entire contents …)` is rejected by System Events (`-1728`,
verified), and the only faster route is a hard-coded structural path — the
per-macOS-version fragility this design explicitly avoids.

## Sequencing

1. ~~Finalize Layer 1 (`notif-center`)~~ **done**: default action is AXPress;
   text validated against real Slack/Calendar notifications; perf-tuned (above).
   Open: stack-click behavior (expand vs treat-as-unit) — see Known limitations.
2. Write the Karabiner wrapper; repoint `Hyper+N`; `bake`.
3. Commit script + karabiner.json + this doc via `git df`.

## Out of scope (for now)

- Reading the usernoted DB for bundle-id-accurate `--app`.
- Expanding/among multiple stacks and addressing individual members within a
  collapsed stack.
- Dismiss-all / reply-inline flows beyond exposing the `--action` names.
```
