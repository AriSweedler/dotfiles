---
name: ari-driving
description: "Entrypoint for driving Ari's terminals: anything Ari should run, or that Claude runs in a terminal Ari watches. Routes to ari-driving-tmux for a pane on this machine (click-to-type and click-to-run links, run_log captures, fenced handoffs, the clipboard) or ari-driving-remote for a host over ssh (his laptop, a Pi, any host with tmux). Use when Ari says \"ari-driving\", \"type it into my pane\", \"pane 2.4\", \"run this on my laptop\", \"send-keys\", \"never press enter\", or Claude needs Ari to run a command and read its output back."
---

# Driving

Dispatcher for the `ari-driving-*` family. Turns "this needs running over there" into one sibling invocation: a pane on this machine and a pane on another host both run tmux, but they are reached differently and handed over differently.

## Naming grammar

Every skill in the family is `ari-driving-<target>`, where the target is how the terminal is reached:

- `tmux` — a pane on this machine: Claude hands Ari a link he clicks (focus, type, or run and return), reads `run_log` captures, and owns every fenced handoff and clipboard rule.
- `remote` — a pane on a host reached over ssh: host definitions, typing with a gate, waiting for the prompt, capturing the pane.

A new target (a browser, a device with no tmux) gets its own `ari-driving-<target>` sibling and a line in **Identify the target**.

## Preconditions

- `/ari-driving-tmux` and `/ari-driving-remote` are installed.
- tmux on each machine; Ari marks each pane Claude may touch with `ari-driving on` in that pane.

## Rules

- **Name every pane by its label.** `ID=%301|pane=2.4`: tmux's pane ID, fixed for the pane's life, and the `window.pane` Ari reads off prefix-q. Never one alone. A local pane's label is linked (`/ari-driving-tmux`).
- **A pane assignment is a hint, never a fact.** One Ari gave earlier in the conversation, or one carried in a compaction summary, may be stale: he repurposes panes, often because Claude asked him to run something "in another terminal". The siblings re-check every time.
- **Never raw `tmux send-keys` into Ari's panes**, locally or over ssh. Only the siblings' scripts check the opt-in and the idle prompt first.
- **The opt-in is Ari's.** A pane not marked `ari-driving on` is refused; tell Ari to run it there himself, never type it.
- **Decide who runs it, per command.** A command mutates when it writes to a system other people or other sessions read: database writes, cloud `--apply`, a job runner's execute mode, pushes, publishing a shared doc. Unsure: it mutates.
    - Non-mutating: run it with the Bash tool. Hand off only what the tool cannot do: interactive logins, anything needing Ari's identity, kube context or terminal.
    - Mutating: Ari runs it, unless he allowed it this session, explicitly for that command, or by running it with `!`, which also covers commands of the same tool, class of effect and target system. Running one on precedent, say so in one line: which earlier run or ask, and why it is the same class.
- **Questions are Ari's.** Never type a password, code or approval; say what the pane is asking.
- **Every driven command is captured, and nothing erases it.** Commands go through `run_log` (the siblings wrap them), so each leaves a capture dir under `/tmp/run_log`. Never start one with `clear`: it wipes the typed command from Ari's scrollback, his record of what ran; the scripts refuse it.

## Workflow

### Identify the target

Infer it from Ari's words and print it with the evidence, e.g. `Target: tmux (Ari said "pane 2.4")`:

| Ari's words | Target | Sibling |
|---|---|---|
| a `2.4` or `%N`, "my pane", "this terminal", a command Ari should run here, a `run_log artifact:` line | a pane on this machine | `/ari-driving-tmux` |
| a host or definition name, "my laptop", "the Pi", `user@host`, a window on another machine | a host over ssh | `/ari-driving-remote` |

Ambiguous: "2.4 on the laptop" is remote; "2.4" alone is local. Neither fits: ask in one line which machine, with the likelier one recommended.

### Hand off

Invoke the sibling through the Skill tool with Ari's request as its argument; never Read a sibling's SKILL.md in its place. One request can need both (run on the laptop, read the result here): invoke each for its part.
