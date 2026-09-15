---
name: ari-use-config
description: Keep Claude inside the commands the Claude Code settings already permit. Load the effective allow/ask/deny rules merged across every settings file, prefer allowlisted commands, and when something isn't covered pick the cheapest acceptable path — manual approval, a reusable script, or a structured permission request. Use when you want command execution scoped to the configured permissions.
---

# Use Config

Keep command execution inside the Claude Code settings' permissions. Run `bin/effective-permissions.zsh` to load the merged allow/ask/deny rules, classify every command against them before running it, and take the cheapest acceptable path when a command isn't allowlisted.

## How to match a command against a rule

A rule is `Tool(pattern)` (`Bash(npm test:*)`, `Read(~/.ssh/**)`) or a bare tool name (`mcp__chrome-devtools__take_screenshot`, which matches every call to that tool). For `Bash(...)` patterns:

- **`Bash(npm test:*)`** — prefix: matches any command starting with `npm test` (`:*` covers the rest, including args).
- **`Bash(npm test)`** — exact: matches only the literal `npm test`, nothing more.
- **`Bash(sudo *)`** — glob: `*` matches any run of characters.

Match the command against ALLOW, ASK, and DENY, then assign a bucket (DENY wins over ALLOW):

| Command | Matches | Bucket |
|---|---|---|
| `npm test` | `Bash(npm test:*)` in ALLOW | allowed |
| `npm test -- --watch` | `Bash(npm test:*)` (prefix) | allowed |
| `npm run dev` | nothing | uncovered |
| `git status -sb` | only an exact `Bash(git status)` rule | uncovered |
| `sudo rm x` | `Bash(sudo *)` in DENY | denied |

**Compound commands count as uncovered unless every part is allowed.** `npm test 2>&1 | tail` pipes an allowed command into an unallowed one, so the whole thing is uncovered and prompts — this is why allowed commands run bare.

## Workflow

### Load the effective config

Run the loader — emit exactly this one Bash call:

```zsh
zsh $HOME/.claude/skills/ari-use-config/bin/effective-permissions.zsh
```

It prints `status`, `managed_only`, counts, and `SOURCES` / `ALLOW` / `ASK` / `DENY` sections. Pass `--dir <repo>` to resolve project settings for another directory. **If `status` is `partial` or `failed`, or ALLOW is empty, do not trust the list** — tell the user the load was degraded and treat every command as uncovered (see Rules).

### Classify every command before running it

**Before each Bash/tool call, state the bucket in one line, then act:**

- **allowed** → run the command **bare** (the literal string; no pipe/redirect that breaks the match).
- **ask** (matches ASK) → run it and take the approval prompt.
- **uncovered** (matches nothing) → run it and take the approval prompt. Escalate (next step) only if it's a 3+ command series or a recurring need.
- **denied** (matches DENY) → do NOT run it. Name the deny rule you matched and its source, propose an alternative that reaches the goal through a different, non-denied capability, and wait for the user. Never re-request an un-deny.

If you can no longer recall the loaded rules, re-run the loader.

### Escalate an uncovered command

Manual approval handles one-off uncovered commands. Escalate when it doesn't:

- **Write a script** — a 3+ command series, a loop, or a pipeline. Wrap it in a skill `bin/` script per `/ari-skill-shellscripts`; the single `zsh $HOME/.claude/skills/<skill>/bin/<script>` invocation becomes one allowlistable unit (N approvals → 1 rule).
- **Request a new permission** — a command you expect to run again in future sessions. Present the request template and wait for the verdict.

### Request a new permission

Present exactly this shape, filled in:

```
Permission request
  Rule:   Bash(gh pr view:*)
  Why:    read PR metadata to summarize review state
  How:    gh pr view <n> --json title,state,reviews
  Effect: read-only          # or: mutating
  Target: $HOME/.claude/settings.json (user global — applies to all projects)
```

The user answers **`allow`** (write the rule), **`deny`** (record it; never ask again), or **`skip`** (one-off, no rule). An ambiguous answer → ask again; never assume `allow`.

### Apply the verdict

On `allow`, delegate to `/update-config` to write the rule. Default target is user global `$HOME/.claude/settings.json`; use a project `.claude/settings.local.json` only when the user explicitly asks. The rule takes effect immediately — no reload needed; treat the new rule as active.

## Rules

- **DENY wins, always.** Never run or re-request a denied command.
- **Run allowed commands bare.** WRONG: `npm test 2>&1 | tail -50` (compound → prompt). RIGHT: `npm test > /tmp/test.out`, then Read the file.
- **Invoke scripts via `$HOME`, never `~`.** Allow rules carry absolute paths; the matcher expands `$HOME` (not `~`), so `zsh $HOME/.claude/skills/...` matches the absolute rule.
- **On a degraded load** (`status` `partial`/`failed`, or empty ALLOW): treat every command as uncovered → manual approval. NEVER run bare on a degraded load.
- **Never edit settings files directly** — always go through `/update-config`.

## Scope

The loader reflects **file-based** allow/ask/deny rules only. It cannot see CLI `--allowedTools`, `permissions.defaultMode` (`bypassPermissions` / `acceptEdits` / `plan`), or the session's prompt mode — so an "uncovered → expect a prompt" expectation can differ under those modes.
