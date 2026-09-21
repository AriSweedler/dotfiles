---
name: ari-code-trace
description: "Trace a call graph from a root function down to leaf nodes, producing an artifact folder with annotated source files and a Mermaid diagram."
user_invocable: true
---

# Code Trace

Trace a function's call graph top-down, producing a self-contained artifact folder.

## Usage

```
/ari-code-trace <function-name-or-file:line>
```

The user provides a starting point — a function name, a `file:line` reference, or a description. If the user provides a description, locate the function first (using Grep/Read), then begin.

The starting point can be any callable: named function, arrow function assigned to a variable, class method, exported handler, or higher-order function. For higher-order functions that return closures, trace into the returned function's body as the root — the factory wrapper is just scaffolding.

## Output

An artifact folder at `/tmp/ari-code-trace-<name>-<YYYYMMDD-HHmmss>/` (UTC) containing:

- One file per function in the call graph (in the function's source language)
- `_edges.md` — edge list maintained during exploration
- `mermaid/call-graph.mmd` — Mermaid diagram of the call graph
- `mermaid/call-graph.ink_url.url` — mermaid.ink PNG URL (cat-friendly)
- `mermaid/call-graph.live_url.url` — mermaid.live fullscreen view URL (cat-friendly)

For functions over 300 lines, both an unabridged file (full source) and an `.abridged` file (pseudocode summary) are produced.

## Phase 1: Explore

**Step 0**: Create the artifact folder and initialize `_edges.md` with the root function name and source location.

Then, symbol-to-symbol:

1. Read the full function.
2. Identify every function/method it calls.
3. For each called symbol, jump to its definition:
   - **Imported symbol**: follow the import path to the file, then to the definition. If it resolves to a barrel/index re-export, follow through to the actual definition.
   - **Same-file symbol**: find the definition in the current file (no import to follow).
   - **Method call** (`this.foo()`, `instance.foo()`): resolve the type, navigate to the class, read the method.
4. Record the edge in `_edges.md`.
5. Repeat from the new function.

Update `_edges.md` periodically during exploration. The file must be complete before starting Phase 2+3.

**Phase 1 is complete** when every function name that appears as a call target in `_edges.md` either (a) has its own section with calls listed, or (b) is marked as a leaf.

### Parallelization

When a function fans out to multiple independent callees, explore branches in parallel using background agents. Each agent traces one subtree and returns its edges. Merge results into `_edges.md` when they complete. This is most valuable when the root fans out to 3+ branches at the same depth.

### Progress updates

After every ~10 functions explored, or at the halfway point (whichever comes first), emit a brief update: `Explored N functions so far. Current branch: <functionName>.`

### `_edges.md` format

Every edge line includes the file location or `(external)`. List each unique callee once per function, even if called in multiple branches.

```
# Edges
root: retryImportRunAsync
source: server/imports/retry.tsx:15

## retryImportRunAsync
- -> getImportRunRecordAsync (server/imports/records.tsx:42)
- -> updateImportRunStatusAsync (server/imports/status.tsx:88)
- -> enqueueRetryTaskAsync (server/tasks/enqueue.tsx:12)

## getImportRunRecordAsync
- -> queryShard (server/db/shard.tsx:201) [leaf: stdlib wrapper]

## enqueueRetryTaskAsync
- -> sqsClient.send (external) [leaf: AWS SDK]
- -> getImportRunRecordAsync [cycle]
- -> updateStatus [already traced]
```

Edge annotations:
- `[leaf: reason]` — recursion stops here, with explanation
- `[cycle]` — actual recursive/mutual recursion back to an ancestor in the call chain
- `[already traced]` — callee already has its own section in `_edges.md` (e.g., sibling closures calling each other). Not a true cycle, just a back-reference.

### Leaves

A function is a leaf when you should stop recursing. Use judgment based on this principle: **a leaf is a function that doesn't contain business logic relevant to understanding this call graph.** It's infrastructure, utility, external, or already visited.

Common leaf patterns:
- Functions that only call stdlib, external libraries, or runtime APIs
- Infrastructure wrappers (DB accessors, task queue enqueue methods, HTTP clients)
- Logging, metrics, assertions, ID generation, generic utilities
- Mixin-generated or dynamically dispatched methods with no static definition
- Functions already visited (cycles — mark with `[cycle]`)

You don't need a checklist — read the function and decide: "does tracing deeper add insight into the business logic flow?" If not, it's a leaf.

Note: `makeStubbable(fn)` is a test wrapper. Trace the wrapped function, not the wrapper.

### Depth and size limits

- **Default max depth**: 5 levels from root.
- **Default max nodes**: 40 functions.
- If either limit is hit, pause, show the current `_edges.md`, and ask the user which branches to continue or whether to stop.

### Class methods and singleton methods

When you see `this.someMethod()` or `instance.doThing()`:
1. Determine the object's type from its declaration or type annotation.
2. Navigate to the class definition and read the method.
3. For inherited methods, follow the class hierarchy to the actual implementation.
4. Name as `ClassName.methodName` (e.g., `ImportRunner.retryAsync`).

For methods on singleton/plain-object exports (not classes), use `objectName.methodName` (e.g., `appJsonToDbSerializer.loadDisconnectedWorkflowIdsAsync`).

### Inline closures

When a function defines closures or local functions internally (e.g., `useCallback`, inner arrow functions, locally scoped `function` or `async function` declarations):
- Create a separate node for each one that calls project functions. Use the variable/function name (e.g., `validateCodeAsync`, `onSubmit`, `renderFilePicker`).
- If the closure has no name, give it one based on its purpose and prefix with `unnamed.` (e.g., `unnamed.fetchAndRetryHandler`).
- Record an edge from the parent function to the closure (parent defines it), AND edges from the closure to its callees.
- Trivial memoized values (`useMemo` returning simple expressions with no project function calls) are not nodes — skip them.
- In the artifact, include the closure's body as the function content.

### Callbacks and higher-order functions

- If a project-defined function is passed as a callback, trace into it. Record the edge from the **caller that provides** the callback.
- If a function accepts a callback parameter and you need to know what's passed, look at the call sites (the caller's code) to find the concrete implementation.
- For event handler registrations (`.on()`, `.addEventListener()`), treat as a leaf unless the user asks to trace event flows.

### Unresolved imports

If an import cannot be resolved after checking path aliases, index files, and extensions (.tsx, .ts, .js), mark the symbol as a leaf with `[leaf: unresolved import at <path>]`. If 3+ unresolved imports accumulate, pause and ask the user about path aliases or build steps.

### Tool selection

- **Read**: Open files by known path — the primary tool during tracing.
- **Grep** (`output_mode: "content"`): Find a symbol definition when following a barrel export or when resolving a method on a typed object. Use patterns like `export function symbolName` or `export const symbolName`.
- **Glob**: Resolve import paths that omit file extensions.
- Prefer following imports over searching. If you must search, verify the result matches the expected type from the call site.

## Phase 2+3: Document and Contextualize

For each function in the call graph, create a file in the artifact folder. You may write the `generic` and `specific` fields in a single pass since `_edges.md` provides full graph context.

If Phase 2 reveals a call site not in `_edges.md`, add the edge and trace the new function before continuing. Treat this as a Phase 1 extension.

At the start, tell the user: `Writing N function files...`

Write files in parallel where possible — batch independent Write calls together.

### File naming

All files in one flat directory. Preserve the function's original casing.

- **Leaf functions** (functions where you stopped recursing — `leaf: true` in frontmatter): `leaf.` prefix: `leaf.queryShard.tsx`, `leaf._getCommonHeaders.tsx`
- **Non-leaf functions**: just the name: `validateCard.tsx`, `_requestAsync.tsx`
- **Class methods**: `ClassName.methodName.tsx` (e.g., `ImportRunner.retryAsync.tsx`)
- **Singleton methods**: `objectName.methodName.tsx` (e.g., `appJsonToDbSerializer.loadAsync.tsx`)
- **Inline closures**: use the variable name: `validateCodeAsync.tsx`, or `unnamed.fetchHandler.tsx`
- **Name collisions**: shortest unique directory suffix with `--` separator. Compare full paths of colliding functions, find the first directory segment (from the end) that differs. Example: `domestic--validateCard.tsx` vs `international--validateCard.tsx`.
- Extension matches the source file's actual extension.

External leaf calls (SDK methods, DB accessors called but not traced into) appear in `_edges.md` but do NOT get artifact files. Only functions you read and traced get files.

### File contents

Each file contains:

1. **Markdown frontmatter** (plain YAML between `---` fences)
2. **The full function** (signature + body), verbatim from source

### Abridged files for long functions

When a function exceeds **300 lines**, produce two files:

1. **`functionName.tsx`** — the full unabridged source, verbatim. Add `lines: N` to frontmatter.
2. **`functionName.abridged.tsx`** — a pseudocode summary that captures the function's logic flow in ~30-80 lines of readable pseudo-TypeScript/English. Same frontmatter, plus `abridged: true`.

The abridged version should:
- Preserve the function signature exactly
- Replace implementation details with English descriptions in comments
- Keep control flow structure (if/else, switch, try/catch, for loops) but summarize bodies
- Preserve all function calls that appear in the call graph (these are the edges). Include leaf/infrastructure calls as comments (e.g., `// emit metrics via taskStats.onError(...)`) so the reader sees the full picture.
- Omit variable declarations, type assertions, and boilerplate that don't affect control flow
- Target ~10-15% of the original line count, clamped to 30-80 lines

Example abridged file:

```tsx
---
generic: Validates task eligibility and executes the task function.
abridged: true
source: server_shared/task_queue/task_executor.tsx:399
lines: 496
calls:
  - getTaskDefinitionIfExists
  - runTaskQueueFunctionWithNewMainConnectionAsync
  - _callTaskFunctionAsync
called_by:
  - executeTaskRecordAndUpdateDbTableAsync
---

async _executeTaskRecordAsync({taskRecord, ...}): Promise<TaskResult | null> {
    // Check retry limit — return null if exhausted
    if (taskRecord.retryCount > taskRecord.retryLimit) { return null; }

    // Check deny lists (functionKey, applicationId) — return null if denied

    // Look up the task definition
    const taskDefinition = getTaskDefinitionIfExists(taskRecord.functionKey);
    if (!taskDefinition) { return null; }

    // Validate scope, disabled application, shard assignment — return null on mismatch

    // Execute the task function in a fresh DB connection context
    const result = await runTaskQueueFunctionWithNewMainConnectionAsync(async () => {
        return await _callTaskFunctionAsync(taskDefinition, taskRecord, ...);
    });

    // Classify result: cancel / postpone / error / success
    // Record stats for each outcome
    return result;
}
```

**During Phase 1 exploration**, when you encounter a function over 300 lines:
- Read it fully to identify all call edges
- Write the abridged version first (this is what you'll reference during the rest of Phase 1)
- Write the unabridged version in Phase 2+3

**During Phase 2+3**, when re-reading long functions for `specific` context, start with the `.abridged` file. If you need to reference a subtle detail (e.g., a specific condition check or error handling nuance), fall back to the unabridged file.

#### Example: non-leaf function

Filename: `validateCard.tsx`

```tsx
---
generic: |
  Validates a credit card number and expiry date.
  Returns true only if the card number is 16 digits and not expired.
specific: |
  Called by processPayment as the first gate before charging.
  If validation fails, processPayment returns early with an error.
source: server/payments/card.tsx:42
calls:
  - isExpired
  - formatCardNumber
called_by:
  - processPayment
---

function validateCard(card: CardInfo): boolean {
    if (card.number.length !== 16) {
        return false;
    }
    return !isExpired(card) && formatCardNumber(card.number) !== null;
}
```

#### Example: leaf function

Filename: `leaf.isExpired.tsx`

```tsx
---
generic: Checks whether a card's expiry date is in the past.
source: server/payments/card.tsx:58
calls: []
called_by:
  - validateCard
leaf: true
leaf_reason: No further project function calls.
---

function isExpired(card: CardInfo): boolean {
    return new Date(card.expiryYear, card.expiryMonth) < new Date();
}
```

### Frontmatter fields

- `generic`: What the function does in general. Prefer a concise paraphrase (1-3 sentences). If an existing doc comment is already concise and accurate, use it verbatim. If no doc comment exists, write one.
- `specific`: How this function is used **in this call graph**. Should answer: (1) Who calls this and why, (2) What the caller does with the return value or side effect, (3) Any preconditions enforced at the call site not obvious from `generic`. If identical to `generic`, write "See generic" or omit.
- `source`: `file_path:line_number`.
- `calls`: functions this calls (in the artifact). `[]` for leaves. Use prefixed name on collisions.
- `called_by`: functions that call this (in the artifact). Same collision rule.
- `leaf`: `true` for leaf nodes. Omit for non-leaves.
- `leaf_reason`: Why recursion stopped. Omit for non-leaves.
- `lines`: function body line count. Only include when > 300 lines.
- `abridged`: `true` on abridged files. Omit otherwise.

## Phase 4: Diagram

1. Create `mermaid/` subfolder in the artifact folder.
2. Write `mermaid/call-graph.mmd`. Line 1 is the `%%{init: …}%%` directive that opens `/ari-diagram-mermaid`'s color theme block, copied verbatim, and every `classDef` or `style` that sets `fill` also sets `color`; bake refuses the file otherwise, and that palette block satisfies both.
3. Bake URLs with `/ari-diagram-mermaid`'s `bin/bake` script, passing the artifact's absolute path:

```zsh
MERMAID_FORMAT=ink_url  zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/bake /tmp/ari-code-trace-<name>-<YYYYMMDD-HHmmss>/mermaid/call-graph.mmd
MERMAID_FORMAT=live_url zsh $HOME/.claude/skills/ari-diagram-mermaid/bin/bake /tmp/ari-code-trace-<name>-<YYYYMMDD-HHmmss>/mermaid/call-graph.mmd
```

The bake script gates the theme directive and text contrast, confirms mermaid.ink renders the source, prints the URL to stdout, and writes sidecar files next to the `.mmd`: `call-graph.ink_url.url` and `call-graph.live_url.url` (the fullscreen `mermaid.live/view#` link). A failed gate lists each offending line; fix the `.mmd` and re-run.

Diagram rules:
- `graph TD` (top-down) layout
- Root function at the top
- Group by source module using `subgraph` when it aids readability
- Leaf nodes: stadium shape, defined once: `leafName([leafName])`, then referenced by ID
- Cycles: dotted edge with label: `A -.->|cycle| B`
- Labels: function name only, no signatures

## Final report

Present the user with:

1. **Artifact path**: the `/tmp/ari-code-trace-...` folder path.
2. **Summary table**: each function — source path, leaf status, one-line description.
3. **Diagram**: rendered inline.
4. **Stats**: total functions, depth reached, number of leaves.
