---
name: ari-hemingway--structure-playbook
description: "Produce operational playbook/runbook drafts — step-by-step procedures an oncall or engineer follows to perform an operation safely. Three modes: research (from scratch), distill (from session knowledge), update (existing doc)."
---

# Operational Playbook

Produce operational playbooks/runbooks for oncalls and engineers performing a risky or multi-phase operation. Targets gdoc.

Formatting rules: see `/ari-hemingway--format-gdoc`. Workflow patterns (investigation folder, restore context, drafting, permalink resolution, fact-check, present/output): see `/ari-hemingway--lib`. If any rule here appears to contradict `/ari-hemingway--format-gdoc`, the format skill wins.

## Document structure

Follows the service-orchestration house format (exemplar: "[Playbook] Use MCR to emergency shutdown a service"). Required sections, in order:

1. **Title** — H1, `[Playbook] <imperative phrase>`, matching the doc filename.
2. **Contact line** — immediately under the title: the owning team's linked Slack channel (e.g. `#help-service-orchestration-and-deploy`).
3. **Summary** — the happy path in 2–3 numbered steps before any detail ("If X: 1. do A, 2. do B"). When multiple sources of truth exist, rank them here.
4. **When to use** — trigger conditions: the alerts, requests, or situations that route a reader here. Also state when NOT to use it, linking the sibling playbook that covers the near-miss case ("If you need X instead, see [Playbook Y]").
5. **Preconditions & access** — roles, CLIs, auth, and safety checks the reader must have or perform before step 1. A reader who fails a precondition stops here.
6. **Procedure** — phases as `# Step N: <verb phrase>` H1s, each with exact commands, expected output, and blocking gate language ("Do not proceed until X") in the step text.
7. **Failure & recovery branches** — what to do when a gate fails, keyed to the step it recovers from.
8. **Rollback / abort** — how to return to a safe state from any phase, and when aborting is the right call.
9. **Verification** — trailing consolidated section: the checks, dashboards, and expected values that prove the operation completed (e.g. a status script, `kubectl` state, a Datadog metric with the pass value spelled out).
10. **Useful links** — tail, split into **Code and PRs** (GitHub permalinks pinned to a SHA, each with a one-line annotation), **Docs** (RFCs), and **Dashboards and playbooks** (go/ links, sibling playbooks).

Optional sections:

- **Background** — how the system works, links to explainers. Keep short; link out rather than explain in place. Use info callouts (`**ℹ️ Info ℹ️**`) for system behavior that changes how the reader acts, with a permalink to the enforcing code.
- **FAQ**

## Rules

### Content scope — word count

600–2500 words. A playbook the oncall can't finish reading during the incident is a design doc wearing the wrong hat.

### Commands

- Every command goes in a fenced code block, copy-pasteable exactly as written. One command per block — never chain commands the reader must mentally split. Never put code in gdoc tables — it converts to mush.
- Parameterize via env vars set once up front (`export STAGE=…`, `export SERVICE_NAME=…`); long grunt invocations use `\` continuations.
- Each step states its expected output or observable effect. A step whose success the reader can't recognize is not a step.
- Commands that mutate state must be labeled as mutating so the reader — not an agent — runs them deliberately.
- Use full resource names (full cluster names, full table names, full pipeline names) — never abbreviations or placeholders the reader must expand from memory.

### One method per step; permissions

- Prescribe exactly ONE method per step (KISS) — the most automated blessed path, naming the exact pipeline (e.g. **Emergency Shutdown Pipeline `<serviceName>` `<stage>`**). Never present a menu of alternatives; if another method exists, it belongs in a failure branch or a one-line aside, not the procedure.
- Route permissions explicitly: when a command needs elevated permissions, say so and link the per-stage admin-grunt-task Spinnaker pipelines (alpha/staging/production) and go/production-access for prod.
- Call out reversibility at decision points ("use `disable-image` (reversible), not `deregister-image` (irreversible)").

### Verification gates

- Gates are explicit and blocking: "Do not proceed until X." State what to look at (command output, dashboard, k8s state) and what value/state means pass.
- Every phase boundary gets a gate. If two consecutive steps have no gate between them, they are one phase.
- Gate language lives in the step text; the trailing **Verification** section consolidates the end-to-end checks with expected values spelled out.

### Failure branches

- Each failure branch names the step or gate it recovers from ("If the gate after step 4 fails: …").
- A branch either rejoins the procedure at a named step or exits to Rollback / abort — never dead-ends.

## Investigation folder

Root path: `/tmp/hemingway/playbook/{topic-slug}/{timestamp}/`. Structure, schemas, derivation rules, and cadence all follow `/ari-hemingway--lib`.

## Workflow

### Determine mode

- **research** — build the playbook from scratch: read the code paths, grunt tasks, pipelines, and monitors that the operation touches; verify each command against the source before writing it down.
- **distill** — the session (or a linked thread/investigation) already contains the operation's steps and evidence; extract, order, and gate them. Fact-check commands against code rather than trusting session memory.
- **update** — an existing playbook (gdoc URL or file) needs revision; diff its claims against current code/infra, preserve its structure unless wrong, and mark stale commands.

If the user didn't state a mode, infer it (existing doc URL → update; rich session context on the operation → distill; otherwise research) and confirm.

### Gather pointers

Follow `Gather pointers` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Restore context

Follow `Restore context` in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Investigate

Verify every command, flag, task name, pipeline name, and table name against the code or live system — a playbook's commands must run as written. Record evidence per `/ari-hemingway--lib` cadence. For distill mode, treat session claims as leads, not facts.

### Draft

Follow the `Drafting` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md` and all `/ari-hemingway--format-gdoc` rules.

### Fact-check

Follow the `Fact-check gate` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`. Commands get the strictest treatment: each fenced command must trace to a source (code permalink, grunt task registration, pipeline definition) in the sources file.

### Present

Follow the `Present` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.

### Output

Follow the `Output` procedure in `$HOME/.claude/skills/ari-hemingway--lib/SKILL.md`.
