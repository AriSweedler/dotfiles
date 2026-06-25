// Bake-time, BIDIRECTIONAL cross-check between the Claude Code leader chords
// declared in actions.ts and the ones actually present in ~/.claude/keybindings.json.
// Drift in either direction fails the bake:
//
//   validateActionsToKeybindings — every claudeActions entry must exist (right action) in keybindings.json
//   validateKeybindingsToActions — every "alt+l …" leader chord in keybindings.json must have a claudeActions entry
//
// Failures are collected LAZILY (full report in one pass) and printed as a single
// console.error block with paste-ready repair output. Exits non-zero unless
// KARABINER_SKIP_CLAUDE_CHECK is set. CC owns the alt+l chords; we never bind them here.

import fs from "fs"
import os from "os"
import path from "path"
import { fileURLToPath } from "url"
import { LEADER, claudeActions, chordFor, type ClaudeAction } from "./actions.ts"

const KEYBINDINGS_PATH =
  process.env.CLAUDE_KEYBINDINGS_PATH ?? path.join(os.homedir(), ".claude", "keybindings.json")
const SKIP_ENV = "KARABINER_SKIP_CLAUDE_CHECK"
const CHORD_PREFIX = `${LEADER} ` // a leader chord key looks like "alt+l j"

type KbEntry = { context?: string; bindings?: Record<string, string | null> }

type Missing = { kind: "missing"; action: ClaudeAction }
type Wrong = { kind: "wrong"; action: ClaudeAction; found: string }
type Orphan = { kind: "orphan"; ccContext: string; chord: string; ccAction: string }
type Failure = Missing | Wrong | Orphan

function loadEntries(): KbEntry[] {
  const parsed = JSON.parse(fs.readFileSync(KEYBINDINGS_PATH, "utf8")) as { bindings?: unknown }
  if (!Array.isArray(parsed.bindings)) throw new Error(`expected a top-level "bindings" array`)
  return parsed.bindings as KbEntry[]
}

// A chord maps to the right action if it appears in ANY block of its context.
function lookup(entries: KbEntry[], a: ClaudeAction): string | undefined {
  const chord = chordFor(a)
  for (const entry of entries) {
    if (entry.context !== a.ccContext) continue
    const found = entry.bindings?.[chord]
    if (typeof found === "string") return found
  }
  return undefined
}

// forward: every declared action must exist (with the right action) in keybindings.json.
function validateActionsToKeybindings(entries: KbEntry[]): Failure[] {
  const failures: Failure[] = []
  for (const action of claudeActions) {
    const found = lookup(entries, action)
    if (found === undefined) failures.push({ kind: "missing", action })
    else if (found !== action.ccAction) failures.push({ kind: "wrong", action, found })
  }
  return failures
}

// reverse: every "alt+l …" leader chord in keybindings.json must have a declared action.
function validateKeybindingsToActions(entries: KbEntry[]): Failure[] {
  const declared = new Set(claudeActions.map((a) => `${a.ccContext} ${chordFor(a)}`))
  const failures: Failure[] = []
  for (const entry of entries) {
    if (!entry.context || !entry.bindings) continue
    for (const [chord, ccAction] of Object.entries(entry.bindings)) {
      if (!chord.startsWith(CHORD_PREFIX) || typeof ccAction !== "string") continue
      if (declared.has(`${entry.context} ${chord}`)) continue // covered (a mismatch is caught as "wrong")
      failures.push({ kind: "orphan", ccContext: entry.context, chord, ccAction })
    }
  }
  return failures
}

function collectFailures(entries: KbEntry[]): Failure[] {
  return [...validateActionsToKeybindings(entries), ...validateKeybindingsToActions(entries)]
}

function buildReport(failures: Failure[], preamble?: string): string {
  const out: string[] = ["", `✗ claude leader-chord check FAILED (leader = "${LEADER}")`]
  if (preamble) out.push(`  ${preamble}`)
  out.push("")

  for (const f of failures) {
    if (f.kind === "orphan") {
      out.push(`  • ${JSON.stringify(f.chord)} → ${JSON.stringify(f.ccAction)}  [context ${f.ccContext}]  ORPHAN — no claudeActions entry`)
    } else {
      const status = f.kind === "wrong" ? `WRONG — currently ${JSON.stringify(f.found)}` : "MISSING"
      out.push(`  • ${JSON.stringify(chordFor(f.action))} → ${JSON.stringify(f.action.ccAction)}  [${f.action.desc}]  ${status}`)
    }
  }

  // Fix 1: missing/wrong -> paste valid JSON into keybindings.json, grouped by context.
  const kbFixes = failures.filter((f): f is Missing | Wrong => f.kind !== "orphan")
  const byContext = new Map<string, (Missing | Wrong)[]>()
  for (const f of kbFixes) byContext.set(f.action.ccContext, [...(byContext.get(f.action.ccContext) ?? []), f])
  for (const [ctx, fs] of byContext) {
    const bindings = fs.map((f) => `      ${JSON.stringify(chordFor(f.action))}: ${JSON.stringify(f.action.ccAction)}`).join(",\n")
    out.push("", `  Add/fix in ${KEYBINDINGS_PATH} (context "${ctx}"):`, "  {", `    "context": ${JSON.stringify(ctx)},`, `    "bindings": {`, bindings, "    }", "  }")
  }

  // Fix 2: orphans -> add a ClaudeAction to actions.ts.
  const orphans = failures.filter((f): f is Orphan => f.kind === "orphan")
  if (orphans.length) {
    out.push("", `  Add to src/claude/actions.ts (claudeActions[]):`)
    for (const o of orphans) {
      const suffix = o.chord.slice(CHORD_PREFIX.length).replace(/^alt\+/, "")
      out.push(`    { suffix: ${JSON.stringify(suffix)}, ccContext: ${JSON.stringify(o.ccContext)}, ccAction: ${JSON.stringify(o.ccAction)}, desc: "TODO" },`)
    }
  }

  const count = (k: Failure["kind"]) => failures.filter((f) => f.kind === k).length
  out.push("", `  ${count("missing")} missing, ${count("wrong")} mismatched, ${count("orphan")} orphaned. Set ${SKIP_ENV}=1 to bypass.`, "")
  return out.join("\n")
}

function reportAndExit(failures: Failure[], preamble?: string): never {
  console.error(buildReport(failures, preamble))
  return process.exit(1)
}

export function validateClaudeKeybindings(): void {
  if (process.env[SKIP_ENV]) {
    console.warn(`[claude-check] skipped via ${SKIP_ENV}`)
    return
  }

  let entries: KbEntry[]
  try {
    entries = loadEntries()
  } catch (e) {
    reportAndExit(
      claudeActions.map((action) => ({ kind: "missing" as const, action })),
      `Could not read ${KEYBINDINGS_PATH}: ${(e as Error).message} — create it and add every chord below.`,
    )
  }

  const failures = collectFailures(entries)
  if (failures.length === 0) {
    console.log(`[claude-check] OK — ${claudeActions.length} leader chords match both ways with ${KEYBINDINGS_PATH}`)
    return
  }
  reportAndExit(failures)
}

// Allow standalone read-only runs: `tsx src/claude/validate.ts`
if (process.argv[1] && process.argv[1] === fileURLToPath(import.meta.url)) {
  validateClaudeKeybindings()
}
