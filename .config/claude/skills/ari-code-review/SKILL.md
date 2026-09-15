---
name: ari-code-review
description: Review a TypeScript diff against Ari's clean/functional conventions — consistent naming, parse-early, functional pipelines, no non-null assertions, early-exit, colocation, block ordering, named pure helpers, a test section per pure function, and comments per /ari-code-comments — and report each finding as file:line with a paste-able rewrite. Use when reviewing a TS diff/PR/branch for style and altitude; complements /code-review (correctness bugs) and /simplify (general cleanups it applies for you).
---

# Ari Code Review

Review a TypeScript diff against the principles below; report each finding as `file:line` with a paste-able rewrite. **Altitude** = the right level of abstraction (a loop where a pipeline belongs, a raw string where a parsed type belongs) — not correctness. A finding that would change runtime behavior is a bug: defer it to `/code-review`. General reuse/altitude cleanups you want *applied* are `/simplify`'s job; this skill enforces these specific named conventions.

## Input

A diff to review (default resolved in Gather the diff). `--fix` additionally applies the mechanical findings — see Report.

## Principles

Each principle is **NEVER** (always flag) or **PREFER** (flag only when it materially helps), and lists its passing case so you don't over-flag. One hunk yields at most one finding; when two principles apply, the one earlier in this list wins.

### No non-null assertions — NEVER
Flag `!`, `arr[0]!`, `obj![key]!`. Narrow instead: destructure (`const [x] = arr; if (x !== undefined)`) or gate through a `flatMap` that proves existence. Precompute an optional once and gate on it rather than asserting twice.
Fine: a value the compiler already knows is defined (no `!` token).

### Parse early, drop information late — NEVER
Parse a key or string to its structured type immediately; never thread the raw string past the parse. Keep the rich parsed value and project it (`getPurpose(parsedKey)`) only where you switch on the projection. Don't add a type when an existing dimension already orders the data.
Fine: the raw string is used only to parse, then discarded.

### Functional pipelines, not loops — NEVER
Every `continue` is a `filter`. Build with `filter`/`map`/`flatMap`/`groupBy`/`reduce`. Fuse a filter-then-map into one `flatMap` returning `[]` or `[value]`, removing the intermediate.
```ts
// BAD — loop + continue + push
const names: string[] = [];
for (const u of users) {
    if (u.role !== 'admin') continue;
    names.push(u.name);
}
// BAD — two passes, intermediate array
const names = users.filter((u) => u.role === 'admin').map((u) => u.name);
// GOOD
const names = users.flatMap((u) => (u.role === 'admin' ? [u.name] : []));
```
Fine: a `for…of` with genuine cross-iteration accumulation, an early `return`, or side effects that don't fit a pipeline.

### Exit early, no compound predicates — NEVER
Guard-clause out; don't gate a block on `a && b && c`.
```ts
// BAD
if (user && user.isActive && user.hasAccess(resource)) return grant();
return deny();
// GOOD
if (user === undefined) return deny();
if (!user.isActive) return deny();
if (!user.hasAccess(resource)) return deny();
return grant();
```
Fine: a single two-term `&&` in a boolean expression.

### Name for what it is, consistently — PREFER
Collections are `entries: Array<XxxSpec>` using the full `Spec` (not `…WithoutManagedFields`). The same concept keeps the same name and argument position across functions. Rename a value when its identity changes — a row merged with other data is no longer an `entry`. Spell out domain nouns; stop short of restating the type in the name.
Fine: a clear domain name already used consistently.

### Colocate with use — PREFER
Declare each value at its point of use, as late as possible — never hoist a computation to the top of a function when it's consumed near the bottom. Put an assert next to the code that produces what it checks; define a local helper next to the return that uses it.
Fine: definition and sole use are adjacent, or separated only by related setup.

### Order each block: comment, operation, metric, check, log — PREFER
Separate each logical block with a blank line and order it leading-comment → operation → metric → check → log (metric/check/log only when present). The comment heads the block; a computation never trails its explanation.
```ts
// Flatten entries with this node group's state so the type narrows.
const statesWithEntry = entries.flatMap(...);    // operation
h.stats.increment('node_group.candidates');      // metric (if any)
h.assert(statesWithEntry.length > 0, '...');     // check (if any)
this.logger.info('selected candidates', {...});  // log (if any)
```
Fine: a single-line block needs no comment.

### Extract and name pure helpers — PREFER
Pull reused logic, or a named transform/predicate/derivation worth seeing at the call site, into a standalone pure function — favor the shape that is easiest to unit-test in isolation: inputs and outputs only, no I/O or hidden state. Each gets its own test section (below).
Fine: a single field access or one comparison left inline.

### A test section per pure function — PREFER
Each exported pure function gets its own `describe` block (or labeled `[fnName] …` cases) that exercises it directly. If the diff adds a new exported pure helper with no matching test section, flag it — no code rewrite, the gap itself is the finding.

<!-- TODO(ari): flesh out fuller testing conventions. Exemplar: admin/custom_domain_provisioner/provisioning_operation.test.tsx
Patterns: table-driven typed cases + `for (const testCase of ...) it(testCase.name, ...)`; one section per function; behavior-spec case names; edge cases as rows; error paths via shouldThrow + h.assert.throwsAsync; private logic via a TestableXxx subclass; log assertions via expectedWarnings: RegExp[] + errorLogSpy.
Still open (from PR review): mocked vs unmocked contracts, property-based invariants, sharding over lowering numRuns. -->

### Comments follow /ari-code-comments — NEVER
Judge every comment in the diff against `/ari-code-comments` — read that skill first; it owns the conventions (restating code, JSDoc, block syntax, wording). The paste-able rewrite is the corrected comment, or its deletion.
Fine: a comment that passes that skill's rules.

## Workflow

### Gather the diff

Resolve the base ref: `origin/main`, else `main`, else `origin/HEAD`; if none resolve, ask for it. Then:
- On a feature branch: `git diff <base>...HEAD -- '*.ts' '*.tsx'`. If the working tree is dirty, also review `git diff HEAD -- '*.ts' '*.tsx'` and say you're including uncommitted changes.
- On the base branch itself: `git diff HEAD -- '*.ts' '*.tsx'`.

(Or the range and paths the user named — always pass paths after `--`.) Skip pure deletions and generated/vendored files (`*.pb.ts`, `*/generated/*`, `node_modules/`, `linguist-generated`); on renames review only the changed lines; note anything skipped. Review only changed lines; for a naming/consistency finding, read the full enclosing file first. Never flag unchanged lines.

If the diff is empty, STOP and report `No TS/TSX changes to review` plus the range used. Above ~50 files, report the size and review file-by-file ("files A–K of N") rather than truncating silently.

### Review against the principles

Check each changed hunk against every principle. **Every finding MUST include the literal, paste-able replacement code.** If you can't write it, DROP the finding — never downgrade to "consider…".

### Report

One finding per block, ordered by file then line. The principle name is the exact `###` heading:
```
admin/eks/foo.tsx:42 — No non-null assertions
  config.entries[0]! → const [first] = config.entries; if (first === undefined) return;

admin/eks/foo.tsx:88 — Functional pipelines, not loops
  for-loop with continue → users.flatMap((u) => (u.role === 'admin' ? [u.name] : []))

2 findings.
```
End with `N findings.` (`0 findings.` for a clean diff).

**Default mode never touches files** — report only.

**`--fix`:** after reporting, apply ONLY the mechanical NEVER findings (removing a `!`, splitting a compound predicate); comment findings and every PREFER / judgment finding stay "manual" — `/ari-code-comments` gates inline comments on the user, and `--fix` must not bypass that. Apply non-overlapping rewrites only — if two touch the same lines, apply one and re-report the rest as manual. Apply a rewrite only if its original text still matches, so a re-run is a no-op. Then run `bazel run //testing/lint_prepush:cli` on the touched files and show `git diff`. If lint fails, report the error and the applied rewrites; don't claim success.
