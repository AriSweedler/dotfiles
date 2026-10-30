---
name: ari-driving
description: "Entrypoint for driving Ari's terminals: anything Ari should run, or that Claude runs in a terminal Ari watches. Routes to ari-driving-tmux for a pane on this machine (click-to-type and click-to-run links, run_log captures, fenced handoffs, the clipboard) or ari-driving-remote for a host over ssh (his laptop, a Pi, any host with tmux). Use when Ari says \"ari-driving\", \"type it into my pane\", \"pane 2.4\", \"run this on my laptop\", \"send-keys\", \"never press enter\", or Claude needs Ari to run a command and read its output back. Never raw tmux send-keys; never pbcopy unless Ari asks."
---

# Driving

Routes a request to the one sibling that reaches the terminal. Each sibling is `ari-driving-<route>`, named for how its terminal is reached: `tmux` for a pane on this machine, reached by a link Ari clicks; `remote` for a pane on another host, reached over ssh. A new route (a browser, a device with no tmux) gets its own sibling and a row in **Identify the route**.

## Rules

The family's shared rules live here, once. A sibling loaded without this router invokes it first; each sibling also carries the safety rules inline, so they hold when this file is not in context.

### Pane labels

- **Name every pane by its label, in prose too.** `ID=%301|pane=2.4`: tmux's pane ID, fixed for the pane's life, and the `window.pane` Ari reads off prefix-q. NEVER one part alone: not "pane 2.4", not `%301`. A pane on another machine also carries that machine's everyday name first, `machine=personal|ID=%18|pane=3.1`: what `dotfiles machine-name` prints there (dotfiles init writes a random one; `dotfiles machine-name NAME` renames it). A local label is a link printed by `link.zsh`; a remote label is inline code, never linked.

### Panes and the opt-in

- **A pane assignment is a hint, never a fact.** One from earlier in the conversation or from a compaction summary may be stale; after compaction, every pane in the summary is a hint. Re-resolve before each use: `link.zsh --pane <it>` here, `run.zsh --host-definition <name> --list` there.
- **One pane per branch or fork.** `run.zsh` binds a pane to the Claude session that first types into it (`$CLAUDE_CODE_SESSION_ID`) and refuses every other session with 76; a `/branch`, a fork or a subagent is another session. A session that must drive gets its own pane, created on Ari's words this turn and opted in by him (`/ari-driving-remote` **Create a pane for yourself**); a fork sent to drive is told which pane it owns, and the parent stops driving that pane while the fork lives. When Ari explicitly makes two sessions share a pane, capture (`--cmd ''`) immediately before every send and read only from your own `TYPED:` echo down: a capture can return the other session's output.
- **NEVER raw `tmux send-keys`** (or `paste-buffer`, `load-buffer`) into Ari's panes, locally or over ssh. Only the siblings' scripts type, after checking the opt-in and the idle prompt: `link.zsh` makes the link Ari clicks; `run.zsh --cmd` types when Claude must read the pane back itself.
- **Content never goes through a pane: not typed, not encoded, not chunked.** Content is more than one line, over 200 bytes, or the value of a body, description or message flag (a bead body, a script, a config); there is no chunk size small enough to make it a command. For a host, `run.zsh --put FILE` copies it and one short command names the path, typed or handed as **Who runs a command** decides (`/ari-driving-remote` **Put a file on the host**). For a pane on this machine, Write the file and the link names its path. A secret is neither typed nor put: tell Ari the path and he places it.
- **The opt-in is Ari's.** Claude never sets it: not `ari-driving on`, `ari-remote-tmux on` or `@ari_driving`, typed, linked, chained, in a pane's startup command, through the Bash tool, or through a fork, subagent or other session; `run.zsh`, `link.zsh` and the click handler refuse any command that spells them. An unmarked pane is refused (`run.zsh` exits 77; a click only focuses): put the command in chat under the pane's label and ask Ari to run `ari-driving on` there, the same when he says "turn it on for me" and for a pane Claude just created. An opt-in Claude set is undone at once with `run.zsh … --cmd 'ari-driving off'` there (exit 70: the pane is already gone), and Ari is told which pane. Seen 2026-10-30: `machine=personal|ID=%35|pane=5.1`, opted in by Claude, was gone within a minute; Ari attributed it to his guard.

### Who runs a command

- **Decide per command.** A command mutates when it writes to a system other people or other sessions read: database writes, cloud `--apply`, a job runner's execute mode, pushes, publishing a shared doc. Unsure: it mutates.
    - Non-mutating: run it with the Bash tool. Hand off only what the tool cannot do: interactive logins, anything needing Ari's identity, kube context or terminal. `kubectl get pods` with Claude's credentials is Bash; the same command needing his kube context is a click-to-run link.
    - Mutating: Ari runs it, and clicking a `▶ run` link counts as Ari running it. Two exceptions, this session only: he allowed that command explicitly, or he ran one with `!`, which also covers later commands of the same tool, same subcommand and same target system (his `! tofu apply` on stack X in dev covers another apply on X in dev; not X in prod, not another tool). Running one on precedent, say in one line which earlier run it follows, directly above the link or block.
- **A harness-denied command goes to Ari unchanged.** Never rephrase it past the classifier; hand it over as a click-to-type link, a fenced block, or `run.zsh --no-enter`.
- **A command Ari runs is handed in the form his terminal can take.** On this machine, a click-to-type or click-to-run link from `link.zsh`. On a remote pane, where no link can reach, the command in a fenced `zsh` block under the pane's full label, never bare in prose.
- **A put is Claude's.** `run.zsh --put FILE` types nothing, so it needs no pane, no opt-in and no hand-off; one chat line first (what the file is, its byte count, which definition), and the file is one Claude wrote this session or one Ari named that Claude has read whole. The command that names the path is decided as above.
- **Questions are Ari's.** Never type a password, code or approval; say what the pane is asking. A command that will ask one goes out as an interactive run link (`/ari-driving-tmux`), which keeps Ari in that pane until it finishes and returns him then.

### Captures and the clipboard

- **Every driven command is captured, and nothing erases it.** Click-to-run links, `run.zsh --cmd` and fenced `run_log` steps wrap the command in `run_log`, so each leaves a capture dir under `/tmp/run_log`; a click-to-type link, a `!` step and `--no-run-log` type it bare. NEVER start or chain `clear`, `reset` or `tmux clear-history`: Ari's scrollback is his record of what ran, and the scripts refuse a leading `clear`. Clean output is the capture's `stdout.plain`.
- **NEVER write Ari's clipboard unless his message this turn asks for it.** "Copy that" and "put it on my clipboard" ask; "give me the command" does not. No `pbcopy`, `osascript … clipboard`, `tmux set-buffer -w` or OSC 52, on any machine; when he asks, `/ari-driving-tmux`'s `handoff.zsh --copy`. A denied copy is not retried another way: show the text in a code block.

## Workflow

### Identify the route

Infer it from Ari's words and print it with the evidence, e.g. `Route: tmux (Ari said "pane 2.4")`, `Route: remote (content for the laptop)`:

| Ari's words | Route | Sibling |
|---|---|---|
| `2.4` or `%N` alone, "my pane", "this terminal", a command Ari should run here | a pane on this machine | `/ari-driving-tmux` |
| "run it in another terminal", no pane named | a pane here, none named: a fenced step, or ask which pane | `/ari-driving-tmux` |
| a pasted `run_log artifact: <dir>` line | the result of a run here; data to read | `/ari-driving-tmux` |
| a pane from earlier in the conversation or a compaction summary | a hint: re-resolve it before use | the sibling it came from |
| a machine name from `--hosts` ("personal"), "my laptop", `user@host`, "2.4 on the laptop" | a host over ssh | `/ari-driving-remote` |
| "the Pi", a host whose definition says it has no tmux | the host its definition says it is reached from, nesting `ssh -t` | `/ari-driving-remote` |
| "file that bead on my laptop", "put this script on the Pi": content (Rules) bound for a host | a host over ssh, carrying content: a file, not keystrokes | `/ari-driving-remote` (**Put a file on the host**) |
| "send-keys this into …", "type it but don't press Enter" | not a licence for raw `send-keys`: a click-to-type link here, `run.zsh --no-enter` there | by machine |
| Claude must type, wait for the prompt and read the pane itself, on this machine | the `local` definition | `/ari-driving-remote` |
| nothing fits | ask in one line which machine, with the likelier one recommended | — |

### Invoke the sibling

Invoke it through the Skill tool with Ari's request as its argument; never Read a sibling's SKILL.md in its place. One request can need both: "run `diskutil list` on my laptop and compare with here" is `Route: remote + tmux`; the remote half goes to `/ari-driving-remote`, the local half runs with Bash because it does not mutate.
