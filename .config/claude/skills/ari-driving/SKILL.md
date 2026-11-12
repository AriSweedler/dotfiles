---
name: ari-driving
description: "Entrypoint for driving Ari's terminals: anything Ari should run, or that Claude runs in a terminal Ari watches. Routes to ari-driving-tmux for a pane on this machine (click-to-type and click-to-run links, run_log captures, fenced handoffs, the clipboard) or ari-driving-remote for a host over ssh (his laptop, a Pi, any host with tmux). Use when Ari says \"ari-driving\", \"type it into my pane\", \"pane 2.4\", \"run this on my laptop\", \"send-keys\", \"never press enter\", or Claude needs Ari to run a command and read its output back. Never raw tmux send-keys; never pbcopy unless Ari asks."
---

# Driving

Routes a request to the one sibling that reaches the terminal. Each sibling is `ari-driving-<route>`: `tmux` for a pane on this machine, by a link Ari clicks; `remote` for a pane on another host, over ssh.

## Rules

A sibling loaded alone invokes this router first; the NEVER rules below are also inline in each sibling, so they hold when this file is not in context.

### Pane labels

- **Name every pane by its label, in prose too.** `ID=%301|pane=2.4`: tmux's pane ID, fixed for the pane's life, and the `window.pane` Ari reads off prefix-q. NEVER one part alone: not "pane 2.4", not `%301`. A pane on another machine carries that machine's everyday name first, `machine=ozone|ID=%18|pane=3.1`, what `dotfiles machine-name` prints there (`/ari-driving-remote` **Run a command**); no `machine=` means this machine, whatever route drives it. "Typed into `machine=ozone|ID=%18|pane=3.1`; it printed four ready beads", never "typed into pane 3.1 on the laptop".
- **A label Ari pastes is placed by its `machine=`.** His own `ari-driving on` and `off` put the full label on his clipboard, `machine=<dotfiles machine-name>|ID=%N|pane=W.P`. MUST run `dotfiles machine-name` here (Bash) before deciding, and compare the whole name: equal → this machine, drop `machine=…|` and name the pane `ID=%N|pane=W.P`, `Route: tmux (pasted label is this machine)`; another name → remote, the definition whose `--hosts` `windows=` lists that label, kept whole, `Route: remote (pasted label names ozone)`; no definition lists it → `Route: ? (machine=X is not this machine and no definition has listed it; which definition?)`, never a new definition from a label alone. Here `dotfiles machine-name` prints `studio`: `machine=studio|ID=%301|pane=2.4` is `ID=%301|pane=2.4`; `machine=ozone|ID=%18|pane=3.1` stays whole.
- **A local label is the link `link.zsh` prints; a remote label is inline code, never linked.**
- **A pane Ari names casually keeps the full label and appends its nickname**, `machine=ozone|ID=%18|pane=3.1|nickname=homelab`, the window name from `--list`; a branch or fork never reuses a nickname.

### Panes and the opt-in

- **MUST re-resolve a pane before every send or link**: `link.zsh --pane %N` (or `W.P`) here, `run.zsh --host-definition <name> --list` there. A pane from earlier in the conversation or a compaction summary is a hint, never a fact, and so is the route. A hint that resolves to nothing is dropped, never replaced by a neighbour: `Route: ? (ID=%301|pane=2.4 from the summary no longer exists; which pane?)`.
- **One pane per session.** `run.zsh` binds a pane to the Claude session that first types into it and refuses every other with 76 (`/ari-driving-remote` **The gate**); a `/branch`, a fork or a subagent is another session.
    - A session that must drive gets its own pane, created only when Ari asked for one in this turn's message and opted in by him (`/ari-driving-remote` **Create a pane for yourself**).
    - A fork sent to drive is told its pane; the parent stops driving that pane while the fork lives.
    - When Ari has two sessions share a pane, capture (`--cmd ''`) immediately before every send and read only from your own `TYPED:` echo down.
- **NEVER raw `tmux send-keys`** (or `paste-buffer`, `load-buffer`) into Ari's panes, locally or over ssh. Only the siblings' scripts type, after checking the opt-in and the idle prompt: `link.zsh` makes the link Ari clicks; `run.zsh --cmd` types when Claude must read the pane back itself.
- **Content never goes through a pane: not typed, not encoded, not chunked.** A string is content when any holds: more than one line; over 200 bytes; the value of a body, description or message flag (a bead body, a script, a config). For a host, `run.zsh --host-definition <name> --put FILE --project DIR` copies it and prints the landing path after `PUT:` (the `PUT:` path; the project and name rule, the path shape and the exit codes are `/ari-driving-remote` **Put a file on the host**), then one short command names the `PUT:` path, typed or handed as **Who runs a command** decides. For a pane on this machine, Write the file to the scratchpad and the link's command names that path. `bd create "Retry on 503" --body "…three paragraphs…"` is content: the body is put, the command is `bd create "Retry on 503" --body-file <the PUT: path>`.
- **A secret is NEVER typed and NEVER put.** Tell Ari the destination path on the host; he places it.
- **The opt-in is Ari's.** Claude never sets or clears it: not `ari-driving on`, `ari-remote-tmux on`, `@ari_driving` or `ari-driving release`, typed, linked, chained, in a pane's startup command, through the Bash tool, or through a fork, subagent or other session; `run.zsh`, `link.zsh` and the click handler refuse any command that spells the first three. Exception: Ari's own `tmux-restart` types `ari-driving on`, without Enter, into panes opted in before the restart; Claude never runs it. `on` installs `release` as a window hook, so the window's ✦ (the status-bar mark of an opted-in pane) comes down by itself when its last marked pane closes; a ✦ that stays is reported to Ari with the window, and he runs `ari-driving release` there. An unmarked pane is refused (`run.zsh` exits 77; a click only focuses): the command goes in chat under the pane's label, in his terminal's form, with the one-line ask:

    ````
    `machine=ozone|ID=%18|pane=3.1` is not opted in. Run `ari-driving on` there, then:
    ```zsh
    bd ready
    ```
    ````

- **"Turn it on for me", "opt it in", a pane Claude just created: the answer is the same.** The label and the literal `ari-driving on` go to Ari; NEVER type, link, chain or Bash it. An opt-in Claude set is undone at once with `run.zsh … --cmd 'ari-driving off'` there (exit 70: the pane is already gone, as on 2026-10-30), Ari is told which pane, and the skill update follows (`/ari-skill-update`, **A mistake is a skill update**).

### Who runs a command

- **Decide per command.** A command mutates when it writes to a system other people or other sessions read: database writes, cloud `--apply`, a job runner's execute mode, pushes, publishing a shared doc. Unsure: it mutates. A terminal Ari names wins over the Bash default.
    - Non-mutating: run it with the Bash tool; on a host, that is `run.zsh --cmd` into an opted-in pane. Hand off only what the tool cannot do: interactive logins, anything needing Ari's identity, kube context or terminal. `kubectl get pods` with Claude's credentials is Bash; the same command needing his kube context is a click-to-run link; `tofu plan` needs his cloud identity, so a link; `git log` is Bash, `git push` is his.
    - Mutating: Ari runs it, and clicking a `▶ run` link counts as Ari running it, so the full command is readable in chat beside the link, never only inside it. Two exceptions, this session only: he allowed that command explicitly, or he ran one with `!`, which also covers later commands of the same tool, same subcommand and same target system (his `! tofu apply` on stack X in dev covers another apply on X in dev; not X in prod, not another tool). A run on precedent prints the earlier run it follows, one line directly above the link or block: "Follows your `! tofu apply` on stack X in dev earlier this session." No line, no precedent.
- **A command the Bash tool refused (permission, classifier, sandbox) goes to Ari unchanged.** NEVER reword it past the refusal: a denied `rm -rf /tmp/run_log/old` is never `find … -delete`. The exact text goes out as a click-to-type link, a fenced block, or `run.zsh --no-enter`, and the hand-off says the harness refused it.
- **Hand Ari a command in the form his terminal takes.** Here, a click-to-type or click-to-run link from `link.zsh`. On a remote pane, where no link reaches, the command in a fenced `zsh` block under the pane's full label (the block above), never bare in prose ("run bd ready on your laptop").
- **A put is Claude's.** `run.zsh --put` types nothing, so it needs no pane, no opt-in and no hand-off: one chat line (what the file is, which definition, which project), then run it; no yes is waited for. The file is one Claude wrote this session or one Ari named that Claude has read whole; anything else is read whole first or not put. **Decide per command** covers the command that names the `PUT:` path.
- **Questions are Ari's.** Never type a password, code or approval; say what the pane is asking. A command that will ask one (`sudo`, `ssh` to a new host, `gh auth`, a login, `-i`, a tool that prompted earlier this session) goes out as an interactive run link (`/ari-driving-tmux`), which keeps Ari in that pane until it finishes, then returns him.

### Captures and the clipboard

- **Default to a captured form, and nothing erases it.** Click-to-run links, `run.zsh --cmd` and fenced `run_log` steps wrap the command in `run_log`, leaving a capture dir under `/tmp/run_log`. A click-to-type link, a `!` step (a fenced hand-off step Ari runs himself), a paste step (the bare command laid out as the link's code block, for Ari to paste into a pane himself, under the link's blockquote when the pane is opted in; both `/ari-driving-tmux`) and `--no-run-log` type it bare: only when Ari names one, says he will paste it himself, or the harness refused the command. NEVER start or chain `clear`, `reset` or `tmux clear-history`: Ari's scrollback is his record of what ran, and the scripts refuse a leading `clear`.
- **Read results from the capture's `stdout.plain`** when one exists, never from the pane scrape.
- **NEVER write Ari's clipboard unless his message this turn asks for it.** "Copy that" and "put it on my clipboard" ask; "give me the command" does not, and an earlier turn's ask does not carry forward. No `pbcopy`, `osascript … clipboard`, `tmux set-buffer -w` or OSC 52, on any machine; when he asks, `/ari-driving-tmux`'s `handoff.zsh --copy`. Never retry a denied copy another way: show the text in a code block.

## Workflow

### Identify the route

The first line of the reply is the route with its evidence: `Route: tmux (Ari said "pane 2.4")`, `Route: remote (content for the laptop)`, `Route: remote + bash (laptop half to the sibling; the local half does not mutate)`, `Route: ? (here or the laptop? likelier the laptop: you said "over there")`. A machine named this turn beats a pane named alone; a pane from earlier never overrides a machine named now; two rows at equal weight are "nothing fits".

| Ari's words | Route | Sibling | Note |
|---|---|---|---|
| `2.4` or `%N` alone, "my pane", "this terminal", a command Ari should run here | tmux | `/ari-driving-tmux` | Ari clicks and pastes the `run_log artifact:` line back; no machine named means this machine, said in the evidence |
| "run it in another terminal", no pane named | tmux | `/ari-driving-tmux` | a fenced step when Ari only needs to run it; ask which pane when Claude needs the capture or a pane's state |
| a pasted `run_log artifact: <dir>` line | tmux | `/ari-driving-tmux` | data to read; a dir absent on this machine is asked about, never reported empty |
| a pasted `machine=…\|ID=%N\|pane=W.P` label | by machine | by machine | **Pane labels**: equal to `dotfiles machine-name` here → tmux, prefix dropped; another name → remote, kept whole; no definition lists it → ask |
| a machine name from `--hosts` ("ozone"), "my laptop", `user@host`, "2.4 on the laptop", a machine not yet in `--hosts` | remote | `/ari-driving-remote` | the sibling owns definitions and asks for `user@host` when none exists; several plausible definitions: ask, likelier first |
| "the Pi", a host whose definition says it has no tmux | remote | `/ari-driving-remote` | the host its definition says it is reached from, nesting `ssh -t` |
| "file that bead on my laptop", "put this script on the Pi": content (Rules) bound for a host | remote | `/ari-driving-remote` | **Put a file on the host**: a file, not keystrokes |
| "send-keys this into …", "type it but don't press Enter" | by machine | by machine | a click-to-type link here, `run.zsh --no-enter` there |
| Claude needs the output without Ari clicking anything (a loop, a wait for the prompt, "watch the TUI in 2.4 and tell me when hashing finishes") and the pane is on this machine | remote, the `local` definition | `/ari-driving-remote` | not tmux although the pane is local; `--hosts` must list `local` |
| "copy that", "my clipboard got overwritten" | tmux | `/ari-driving-tmux` | **Copy only on request**, **Recover a clobbered clipboard** |
| "make yourself a pane"; a fact about a host ("the Pi is on .102 now") | remote | `/ari-driving-remote` | **Create a pane for yourself**; **Add or describe a host** |
| no command to run; nothing fits, or two rows fit | ask | — | one line, the likelier answer recommended; no sibling is invoked |

### Invoke the sibling

**Invoke it through the Skill tool, argument = Ari's request verbatim plus the Route line; NEVER Read a sibling's SKILL.md in its place.** One sibling per request, and a sibling never re-invokes the router; a consumer that already knows its route may invoke the sibling directly. If the Skill tool is missing or the sibling unknown, stop: name the sibling and that `/ari-dotfiles-skill-registry` relinks it; a fork without the Skill tool hands the driving back to its parent. A route that fails is reported with the sibling's reason, never retried through the other sibling. One request can need both: "run `diskutil list` on my laptop and compare with here" is `Route: remote + bash`: the remote half goes to `/ari-driving-remote`; the local half does not mutate, so it runs with Bash and no sibling. A local half that mutates is tmux.

## Adding a route

A new route (a browser, a device with no tmux) gets its own sibling, `ari-driving-<route>`, and a row in **Identify the route**.
