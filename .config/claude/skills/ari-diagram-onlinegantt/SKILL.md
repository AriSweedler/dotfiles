---
name: ari-diagram-onlinegantt
description: Build and validate Gantt charts in onlinegantt.com's native .gantt JSON format. Turns a list of tasks (estimates, dependencies, completion dates) into a phase-grouped, schema-valid .gantt file the user imports via Open. Use when the user wants a Gantt chart, a project timeline, or to convert a task queue / roadmap into a schedule.
---

# ari-diagram-onlinegantt

Build and validate Gantt charts in the native JSON format used by [onlinegantt.com](https://www.onlinegantt.com/#/gantt). The validated `.gantt` file *is* the deliverable — the tool is client-side and has no live-render URL.

## Reference

Read this before building. The workflow below references it.

### .gantt JSON format

Top-level object with exactly these keys:

```json
{
  "data": [ <parent task>, ... ],
  "resources": [ {"resourceId": "Name", "resourceName": "Name"}, ... ],
  "projectStartDate": null,
  "projectEndDate": null,
  "advanced": { ... }
}
```

Every task — parent **and** subtask — has this exact shape:

```json
{
  "TaskID": 1,
  "TaskName": "Human label",
  "StartDate": "2026-06-05T15:00:00.000Z",
  "EndDate": "2026-06-10T00:00:00.000Z",
  "Duration": 3,
  "Predecessor": "3FS",
  "resources": [],
  "Progress": 0,
  "color": "121",
  "info": "<p>HTML notes; use &amp; for ampersands.</p>",
  "DurationUnit": "day"
}
```

- Parent tasks additionally carry `"subtasks": [ ... ]` and use `"Predecessor": null`.
- Subtasks with no dependency use `"Predecessor": ""` (empty string, **not** `null`).
- `TaskID` is a unique integer across the whole file (parents and subtasks share one namespace).
- `Progress` is `0`–`100`. `color` is an opaque 3-digit palette index (`"121"`, `"211"`, `"301"`, `"112"`, `"203"`) or `""` — pick any; it only affects bar color.
- `info` is HTML — wrap notes in `<p>...</p>`, escape `&` as `&amp;`. Empty is `"<p><br></p>"`.

**Copy the `advanced` block verbatim from `reference/template.gantt`.** The only fields you ever change are `timezone`/`timezoneOffset` (see **Date conventions**) and column `show`/order. The column-name set is fixed and validated — do not rename, add, or drop columns: `Task ID`, `Task Name`, `Start Date`, `End Date`, `Duration`, `Progress %`, `Dependency`, `Resources`, `Color`.

### Date conventions

`StartDate`/`EndDate` are absolute UTC instants; onlinegantt renders them in `advanced.timezone`. **Default to `America/Los_Angeles` unless the user states a timezone.** If they do, set `advanced.timezone` and `advanced.timezoneOffset` (offset is **minutes** west of UTC) and convert with the rule below.

Rule, for any timezone:
- **StartDate** = first working day at **08:00 local**, converted to UTC.
- **EndDate** = last working day at **17:00 local**, converted to UTC.
- **Milestone** (`Duration: 0`): `StartDate == EndDate`.

Worked, `America/Los_Angeles` (UTC-7, `timezoneOffset: 420`): 08:00 → `T15:00:00.000Z`; 17:00 → `T00:00:00.000Z` the **next** calendar day (17:00 + 7h = 24:00).

Worked, `America/New_York` (UTC-4 EDT, `timezoneOffset: 240`): 08:00 → `T12:00:00.000Z`; 17:00 → `T21:00:00.000Z` the **same** day.

Scheduling honors `workWeek` (weekends skipped) and `holidays`.

### Duration conversion

`Duration` is in **working days** (`DurationUnit: "day"`), counting only `workWeek` days. Convert an estimate in weeks with **`ceil(weeks × 5)`**:

| Estimate | Working days |
| -------- | ------------ |
| 0 wk     | 0 (milestone) |
| 0.5 wk   | 3 (`ceil(2.5)`) |
| 1 wk     | 5 |
| 2 wk     | 10 |

**Back-counting `StartDate` from a completion date.** When the user gives a completion date, treat it as the **last working day** and step back `Duration` working days, **counting the last day itself** and skipping weekends/holidays.

Example: completion **Tue Jun 9 2026**, Duration **3**. Step back inclusively:

| Step | Day | |
| --- | --- | --- |
| 1 | Tue Jun 9 | last working day |
| 2 | Mon Jun 8 | |
| — | Sun Jun 7 | skipped (weekend) |
| — | Sat Jun 6 | skipped (weekend) |
| 3 | Fri Jun 5 | first working day → `StartDate` |

So `StartDate` = Jun 5, last working day = Jun 9. In LA: `StartDate: "2026-06-05T15:00:00.000Z"`, `EndDate: "2026-06-10T00:00:00.000Z"`.

### Predecessors

Format: `"<TaskID><type>"`, e.g. `"3FS"`. Types: `FS` (finish-to-start), `SS`, `FF`, `SF`. References may point to any TaskID (cross-phase is fine).

**Add a finish-to-start link from B to A only if `B.StartDate >= A.EndDate`.** That is the test — run it.

- If it holds: set B's `Predecessor` to `"<A's TaskID>FS"`.
- If it does NOT hold (the tasks overlap): you **MUST NOT** add the link. `advanced.dependencyConflict` is `"Add Offset to Dependency"`, so a conflicting link silently reschedules B and drifts off the user's dates. Leave `Predecessor: ""` and note the intended-but-omitted dependency in B's `info`.
- **NEVER** add a link just because tasks are listed in sequence or read as dependent. Dates decide, not narrative order.

## Workflow

1. **Choose where to write.** If the user named a file/location, use it (if it already exists, confirm before overwriting). Otherwise make a temp dir:
   ```bash
   ts=$(date +%s%3N)
   TMPDIR=$(mktemp -d "/tmp/gantt-${ts}-XXXXXXX")
   ```
2. **Build** `<name>.gantt`. Copy `reference/template.gantt` as the scaffold, then:
   - Group tasks into logical phases — one parent task per phase, real tasks as `subtasks`.
   - Convert each estimate to working days (**Duration conversion**); compute `StartDate`/`EndDate` (**Date conventions**, back-counting from completion dates when given).
   - Subtask with no dependency → `Predecessor: ""`; parent → `Predecessor: null`. Apply the predecessor test (**Predecessors**) before adding any link.
   - Set each parent's `StartDate`/`EndDate`/`Duration` to span its children.
3. **Validate — MANDATORY GATE. Do not skip; do not substitute eyeballing.**
   ```
   zsh $HOME/.claude/skills/ari-diagram-onlinegantt/bin/validate --file <name>.gantt
   ```
   **Done means exit code 0 and the `Valid .gantt file` line.** If it reports problems, fix the JSON and re-run — repeat until it exits 0. Show the passing output as proof before presenting.
4. **Present.** Always print the `.gantt` file path. The **first** time you hand a chart to a user in a conversation, give the open instructions once: "go to https://www.onlinegantt.com/#/gantt and click **Open .gantt file**, then select this file." After that, just print the path.

## Worked example

Input (what the user might say):

> Phase "Setup": "Design schema" (1 wk), then "Build API" (1 wk). Then a "Launch" milestone. Start Mon Jun 1 2026.

Result (LA timezone; this mirrors `reference/template.gantt`). Design runs Jun 1–5 (5 working days). Build's start (Jun 8) ≥ Design's end (Jun 6 stored) → safe to link `"2FS"`. Launch is a 0-day milestone after Build.

```json
{
  "data": [{
    "TaskID": 1, "TaskName": "Setup",
    "StartDate": "2026-06-01T15:00:00.000Z", "EndDate": "2026-06-13T00:00:00.000Z",
    "Duration": 10, "Predecessor": null, "resources": [], "Progress": 0,
    "color": "", "info": "<p><br></p>", "DurationUnit": "day",
    "subtasks": [
      {"TaskID": 2, "TaskName": "Design schema",
       "StartDate": "2026-06-01T15:00:00.000Z", "EndDate": "2026-06-06T00:00:00.000Z",
       "Duration": 5, "Predecessor": "", "resources": [], "Progress": 0,
       "color": "121", "info": "<p><br></p>", "DurationUnit": "day"},
      {"TaskID": 3, "TaskName": "Build API",
       "StartDate": "2026-06-08T15:00:00.000Z", "EndDate": "2026-06-13T00:00:00.000Z",
       "Duration": 5, "Predecessor": "2FS", "resources": [], "Progress": 0,
       "color": "211", "info": "<p><br></p>", "DurationUnit": "day"},
      {"TaskID": 4, "TaskName": "Launch",
       "StartDate": "2026-06-13T00:00:00.000Z", "EndDate": "2026-06-13T00:00:00.000Z",
       "Duration": 0, "Predecessor": "3FS", "resources": [], "Progress": 0,
       "color": "", "info": "<p><br></p>", "DurationUnit": "day"}
    ]
  }],
  "resources": [], "projectStartDate": null, "projectEndDate": null,
  "advanced": { "...": "copied verbatim from reference/template.gantt" }
}
```

## Syncing edits back

The user opens the `.gantt` file in onlinegantt, edits it (drags dates, sets progress, renames, adds tasks), exports, and shares it back. Diff the returned file against the one you produced:

```
zsh $HOME/.claude/skills/ari-diagram-onlinegantt/bin/diff --base <yours>.gantt --new <theirs>.gantt
```

The differ is **schema-agnostic** — it knows nothing about `.gantt`. It emits `{"changes": [{op, path, old/new|value}]}`, matching array objects by identity (`TaskID`, `resourceId`, … auto-detected) so reordering and mid-list insert/remove don't cascade, and writes **no prose**. *You* translate the paths, because you know the schema:

| Path / field change | Means |
| --- | --- |
| `op:add` at `$.data[TaskID=N]` | added a phase |
| `op:add` at `…subtasks[TaskID=N]` | added a task (see `value.TaskName`; parent = phase) |
| `op:remove` at those paths | deleted that phase / task |
| `…TaskName` change | renamed it |
| `…StartDate` / `…EndDate` change | moved start/end (compare dates → "pushed out N days") |
| `…Duration` change | re-estimated (working days) |
| `…Progress` change | progress update (`0→100` = marked done; `→0` = reset) |
| `…Predecessor` change | dependency added/removed/changed (`"3FS"` = finish-to-start on task 3) |
| `…resources[...]` add/remove | (un)assigned an owner |
| `…color` change | recolored (cosmetic) |
| `…info` change | edited the task's notes |

Narrate in the conversation's context ("you pushed the migration out a week", "you marked the DDB tables done", "you added a buffer task"), then update your understanding of the schedule (and any notes) before continuing. Parent (phase) `StartDate`/`EndDate`/`Progress` are auto-derived from children — mention them only if no child change explains them.

## Tools

`zsh $HOME/.claude/skills/ari-diagram-onlinegantt/bin/validate --file <file.gantt>` — checks the full `.gantt` schema (top-level + `advanced` keys, the fixed column set, every task's field types, unique `TaskID`s, `Predecessor` format and targets, `Progress` range, `Duration >= 0`, `StartDate <= EndDate`, and that `Duration` fits the calendar span). Exit 0 + OK line when clean; one problem per line and non-zero otherwise. `--help` for usage.

- `--sort start|end` — after a passing validation, print leaf tasks sorted by start or end date, one per line as `<start>  <end>  <task>  (<phase>)` to stdout, e.g. `2026-06-01  2026-06-06  Design schema  (Setup)`. Requires `jq`.

`zsh $HOME/.claude/skills/ari-diagram-onlinegantt/bin/diff --base <a.json> --new <b.json> [--id-key NAME ...]` — schema-agnostic structural JSON differ (any JSON). See **Syncing edits back**.

## Notes

- The format round-trips: re-importing an exported file reproduces it. When unsure of a field, export a tiny chart from the tool and `bin/diff` it against yours.
- For a throwaway diagram in chat or a Doc (not an editable schedule), Mermaid's `gantt` grammar may suffice — but `/ari-diagram-mermaid` provides no Gantt-specific guidance, so you'd be hand-writing the syntax.
