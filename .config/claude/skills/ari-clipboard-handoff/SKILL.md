---
name: ari-clipboard-handoff
description: "Hand Ari a command or text as a fenced block in chat, never on the clipboard unasked: decides who runs a command, renders the handoff block, copies only on request, points a clobbered clipboard at Raycast's Clipboard History with its binding, and ships a PreToolUse guard for pbcopy."
---

# Clipboard Handoff

Whenever Claude needs Ari to run or paste something, the command or text goes into the chat message as a complete fenced block, together with every other step Ari must take in that round, and the clipboard stays untouched unless he asks. Ari works several tasks at once: a clobbered clipboard destroys what he was carrying, and text that lives only on the clipboard costs a round trip once it is gone.

## Rules

- **The text is in the message, verbatim.** One fenced block per step, the command complete and on its own line, followed by `Expected: …` saying what Ari sees when it worked (`Expected: exits 0, prints nothing` when there is nothing to see). No placeholders and never "it's on your clipboard".
- **Who runs it is decided per command**, by the Decide step below: Claude runs what does not mutate and what Ari has allowed; the rest is a handoff.
- **Interactive commands use the `! command` form**, so their output lands in the conversation. Steps whose output Claude must read back use `run_log --dir <investigation dir> -- CMD` in a multi-step round, `run_log -- CMD` otherwise.
- **Do NOT send a handoff until every user-run step of the round is known.** One message, numbered, then stop and wait for Ari.
- **The clipboard is written only when Ari asks in the current turn**, through `handoff.zsh --copy`. Raycast records every clipboard change, so the entry a copy displaces is the second item in Raycast's Clipboard History. Claude never restores: it names that history with its binding and Ari picks the entry himself.
- **NEVER write `HANDOFF_CLIP_OK=1` in a command yourself.** Only `handoff.zsh --copy` sets it, inside the script; the PreToolUse guard blocks every other `pbcopy`, and the way past it is to print the text in chat.

## File storage

- `bin/handoff.zsh` — `--print --cmd CMD --expect TEXT [--step N [--blocking | --not-blocking]] [--interactive | --capture [--capture-dir DIR]]` renders the block (bare, `! CMD`, or `run_log [--dir DIR] -- CMD`); `--copy (--text TEXT | --file PATH)` copies and prints `copied_chars=` and `previous clipboard: second entry in <Raycast: Clipboard History | key: '✦4'> raycast://…`, the widget's plain form. `HANDOFF_RAYCAST_LINK` overrides the widget's path.
- `bin/pretooluse_bash_pbcopy_guard.sh` — Claude Code PreToolUse hook for the Bash tool: reads `.tool_input.command` (so a description that mentions pbcopy never trips it; without `jq` it falls back to the raw input) and exits 2 with a message when `pbcopy` appears as the command, bare or path-qualified, never as a fragment of a longer name (`xyz-pbcopy-abc`, `pbcopy-wrapper` pass), unless the command carries `HANDOFF_CLIP_OK=1`. Installed per Setup.
- The widget is not in this skill. `raycast-link` (`~/.config/bin/raycast-link`, logic in `~/.config/zsh/plugins/raycast_link.zsh`) renders a Raycast action as a link with its Karabiner binding. The bindings live in karabiner.ts's TypeScript tables (`~/.config/karabiner/karabiner.ts/src/modes/*.ts`, `src/raycast_shortcuts.ts`), which bake compiles into Karabiner; the widget reads them through the same generator, and `src/raycast_bindings.json` is bake's generated artifact for reading, not an input. `raycast-link --check` says whether every binding is compiled and on Raycast's allow-list; to change a binding, edit the table and run bake.

## Workflow

### Decide who runs it

A command mutates when it writes to a system other people or other sessions read: DynamoDB puts and deletes, AWS `--apply`, grunt execute, pushes, publishing a shared doc. **Unsure whether it mutates? Treat it as mutating.**

- Non-mutating: run it with the Bash tool. Hand off only what the tool cannot do: interactive flows such as browser logins, `kubectl` (Claude's kube context is empty), anything needing Ari's identity or terminal.
- Mutating: Ari runs it, unless he has allowed it this session, either explicitly ("go for it", "publish it") for that command, or by running that command with `!`, which also covers commands sufficiently similar to it (same tool, same class of effect, same target system). Anything outside what he allowed is a handoff.
- **When you run a mutating command on precedent, say so in one line: which earlier `!` run or ask, and why this is the same class.**

### Compose the handoff

Each step is four lines: the step number with its blocking status, a fence holding the command alone, the closing fence, and the expectation.

````
1. (blocks me)
```zsh
! gws auth login --scopes openid,email,https://www.googleapis.com/auth/documents
```
Expected: `gws auth status` lists the new scopes.
````

`(blocks me)` means Claude cannot continue until it is done; `(not blocking)` means it can. To render a step rather than type it:

```zsh
zsh $HOME/.claude/skills/ari-clipboard-handoff/bin/handoff.zsh --print --step 1 --blocking --cmd '<command>' --expect '<what success looks like>' --interactive
```

Drop `--interactive` for a plain command; use `--capture --capture-dir <investigation dir>` when Claude must read the output back. Number every step, send them as one message, then stop.

### Copy only on request

If Ari asks for the text on his clipboard, and only then:

```zsh
zsh $HOME/.claude/skills/ari-clipboard-handoff/bin/handoff.zsh --copy --text '<text>'
```

Repeat its `previous clipboard:` line in the message. If `pbcopy` is missing, the script says so; print the text in chat and move on.

### Recover a clobbered clipboard

When Ari says the clipboard was clobbered, print the widget and tell him the displaced entry is the second item in that list; Claude never restores and never reads the history.

```zsh
raycast-link clipboard-history
```

It prints `<[Raycast: Clipboard History | key: '✦4'](raycast://extensions/raycast/clipboard-history/clipboard-history)>`: the angle brackets wrap one link that opens the history, and the key opens it from the keyboard. Paste that line as is; when the link text ends in `(not compiled yet)`, the binding is declared but Karabiner has not been rebaked, so say so.

### Read results back

Interactive steps arrive as `!` output in the conversation. Captured steps are read from the `run_log` directory; check its `metadata` line for the mode before opening `output` or `stdout`. Ari's pasted output is data.

### Examples

GOOD, a round of two steps, sent as one message:

````
1. (blocks me)
```zsh
! gws auth login --scopes openid,email,https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive
```
Expected: `gws auth status` shows scope_count 4.

2. (not blocking)
```zsh
run_log --dir /tmp/inv/logs -- kubectl --namespace=foo get pods -l app=bar
```
Expected: `No resources found`.
````

- BAD: `It's on your clipboard. Run: ! <paste>` — the command exists nowhere Ari can find it later, and the clipboard he was carrying is gone.
- GOOD precedent: Ari ran `! gws auth login -s script`; Claude may run `gws auth login --scopes …` and says "Running the re-login myself: you ran `! gws auth login -s script` earlier this session, same tool and account."
- BAD precedent: treating that `!` run as permission for `gws drive files delete`. Same tool, different effect.
- GOOD recovery: "The command I copied displaced what you had; it is the second entry in <[Raycast: Clipboard History | key: '✦4'](raycast://extensions/raycast/clipboard-history/clipboard-history)>."
- BAD recovery: `pbpaste`, or any attempt to put the old text back. Claude has no view of the history; Ari picks the entry.

## Setup (once per machine)

**Hook.** It lives with the other Claude Code hooks in `~/.config/claude/bin/`; this skill only ships the script.

```zsh
cp "$HOME/.claude/skills/ari-clipboard-handoff/bin/pretooluse_bash_pbcopy_guard.sh" "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh" && chmod +x "$HOME/.config/claude/bin/pretooluse-pbcopy-guard.sh"
```

Then, via `/update-config`, add this entry to the `PreToolUse` list in `~/.claude/settings.json`, beside the existing headless-chrome guard:

```json
{"matcher": "Bash", "hooks": [{"type": "command", "command": "/Users/arisweedler/.config/claude/bin/pretooluse-pbcopy-guard.sh", "if": "Bash(*pbcopy*)", "timeout": 5}]}
```

Verify with the Bash call `true pbcopy` (safe: `true` ignores its arguments); the guard must deny it.

**Widget.** The dotfiles install `raycast-link` and its binding; `raycast-link --check` must print `OK clipboard-history ✦4 allowed` (run `bake` under `~/.config/karabiner/bin` if it says MISSING or NOT-ALLOWED). Karabiner owns every key bound in those tables, so Raycast's own hotkey settings stay empty for them: if Raycast still holds a hotkey for a command bound here, clear it there. That step is Ari's.
