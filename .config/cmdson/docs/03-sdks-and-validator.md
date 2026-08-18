# cmdson — SDKs & Validator Plan

Plan only. Part 1 is the validator plan; Parts 2–5 are the SDK plan, the shared test
strategy, and sequencing. Everything here consumes the synthesized data model in
`docs/01-spec.md` as normative; nothing below adds fields to it.

One framing sentence that governs both parts: **the spec's executable form is a fixture set, not prose.** The validator, every SDK, and both frontend adapters are judged against the same golden files, so "conforms to cmdson" is a test run, never an argument.

---

## Part 1 — `cmdson-lint`, the validator

### 1.1 Purpose and shape

`cmdson-lint` answers one question: *is this document a valid cmdson document, and which frontends can actually serve it?* It is deliberately simpler than either frontend — a thin CLI over the reference SDK's loader, so it contains **no parsing or rendering logic of its own**. The requirement "simpler than either frontend" is met structurally: lint = loader + a rule table + a report formatter.

It runs as a pipeline of layers; each layer only sees input the previous layer accepted:

| Layer | Name | What it does |
|---|---|---|
| L0 | Parse | Read JSON (or YAML via one loader call). A database file (JSON array) fans out into per-document runs. |
| L1 | Canonicalize | Apply the loader's canonicalizations — bare-string choice shorthand `"s"` → `{"value": "s"}`, defaulted fields made explicit. All later layers (and all SDKs) see only canonical documents. |
| L2 | Structural | Validate against the published JSON Schema meta-schema (`cmdson.schema.json`, draft 2020-12). Shapes, required fields, closed enums (`type`, `join`, `effect`, `openPolicy`, `bind.at`), field types. |
| L3 | Semantic | Rules JSON Schema cannot express (below). |
| L4 | Profiles | Opt-in per-frontend degradation analysis (below). |

The meta-schema is itself a deliverable: authors who put `$schema` in their documents get editor validation and completion for free, before lint ever runs.

### 1.2 Semantic rules (L3)

Every rule has a stable ID (`CMD###`), a severity, and a one-line rationale printable via `--explain`. The v1 rule set, grouped:

**Identity and uniqueness**
- `CMD001` (error) — sibling `Command.name`s unique.
- `CMD002` (error) — `Param.name`s unique along any root→leaf path.
- `CMD003` (error) — `Choice.value`s unique within one `Value`.
- `CMD004` (error) — key surface unique per node: all `Choice.key`s of that node's params plus its subcommand `key`s share one namespace. This mirrors the check the karabiner argbuilder already enforces at bake time ("option keys must be unique across groups"); lint catches it before bake does.

**Defaults and values**
- `CMD010` (error) — `default` and `initial` type-check against `Value.type` and satisfy `pattern`/`min`/`max`.
- `CMD011` (error) — `default` ∈ `choices` when `open: false`; same for `initial`.
- `CMD012` (error) — every `Choice.value` parses as the declared `type`.
- `CMD013` (warning) — `required: true` together with `default`: dead for parsers (defaults inject only on absence, and required forbids absence) but live for finite frontends, where it is exactly what rescues the param via fixed-constant pre-emission — flagged so authors confirm the combination is deliberate.
- `CMD014` (info) — `initial` present with no `default`: legal and sometimes exactly right (the typing-test `--words` case), flagged at info level so authors confirm it was deliberate.

**Structural exclusivity**
- `CMD020` (error) — positional-bound params and `subcommands` never coexist on one node.
- `CMD021` (error) — `cwd` on the document root only.
- `CMD022` (error) — value-less params (switches) only on `bind.at: "flag"`.
- `CMD023` (error) — `join` only on flag binds; `var` only on env binds.
- `CMD024` (error) — `open: false` requires a non-empty `choices`; `openPolicy` requires `open: true`.
- `CMD025` (error) — env `var` matches `[A-Z_][A-Z0-9_]*`.
- `CMD026` (error) — `cmdson` version field on the root only, and a known version.
- `CMD027` (error) — a required positional may not follow an optional positional (parse ambiguity).

**References (dangling-pointer class)**
- `CMD030` (error) — known `meta` namespaces that reference spec elements must resolve: `meta.karabiner.omitChoices` values must name existing `Choice.value`s on that param. Each frontend namespace ships a small hint schema; unknown namespaces are ignored with an info note (`CMD031`), per the model's opaque-bag contract.
- `CMD032` (error) — curation must leave a servable group: after `omitChoices`, the surviving choice set is non-empty and still contains the preselection (`initial ?? default`).
- `CMD033` (error, database scope) — root identity keys (`meta.<frontend>.menuName ?? name`) unique across a database file; menu names must not contain `" | "`.

**Contract notes lint cannot check**
- The emit≡omit contract on `default` is a claim about the *target program's* behavior; it is statically unverifiable. Lint documents this in `--explain CMD010` and the conformance suite covers it only by convention (fixture authors attest it). This is stated explicitly so nobody expects the validator to prove it.

### 1.3 Frontend profiles (L4) — enumerability analysis

`--profile <name>` runs the degradation contract from the data model as a checkable analysis. Profiles are named capability sets shipped with lint:

- `karabiner`: capabilities `{}` (no FREE_TEXT, no RECURSION, no CWD), budgets `{maxCombinations: 64, maxChoicesPerGroup: 10, keyAlphabet: [a-z0-9…]}` (budgets configurable via `--profile-config <json>`).
- `tmux-oneshot`: all capabilities, unbounded; checks reduce to `cwd` honored at top level only and menu-name uniqueness from `meta.tmux-oneshot.menuName`.

Per document, the profile layer replays the degradation rules and emits one **verdict** per command — the same bake-time verdicts the model requires, produced ahead of bake:

- `OK` — fully renderable; for karabiner, reports the manipulator count (e.g. `typing-test: 3 action × 4 words = 12 combinations`).
- `DEGRADED` — renderable after named degradations, each listed: `flattened bare subcommands into one 10-choice group`, `synthesized "(skip)" option for optional param X`, `pre-emitting default for param Y`, `closed open choices for param Z (openPolicy: close)`.
- `EXCLUDED` — with the reason: required param unrenderable (`openPolicy: exclude` and no FREE_TEXT), `cwd` without CWD, `effect: destructive` in an auto-firing frontend, combination budget exceeded, key alphabet exhausted.

Profile findings are warnings by default (the document is valid cmdson even if karabiner can't serve it); `--strict` promotes them. This gives authors the "enumerability warning" the project brief asks for: *this document is legal but will silently vanish from your keyboard UI* becomes a lint line, not a surprise.

### 1.4 CLI shape

v1 is deliberately small — schema check + semantic errors + profile verdicts, plain-text
output (this is personal tooling; the validator must stay simpler than either frontend):

```
cmdson-lint [--profile <name>]... [--strict] <file>...
                                       # each file: one document or a database array; "-" = stdin
```

Deferred to v1.1 (rule IDs are stable from day one, so nothing renumbers): `--format json`,
`--explain <RULE_ID>`, `--rules`, `--profile-config <json>`, `--schema`.

Text findings are one line each: `commands.json#/2/params/0 CMD011 error: default "copy_envv" not in choices (copy_env, copy_flag, login)` — a JSON Pointer locates the node, the doc path (`ctx → action`) is appended for humans. JSON format: `{findings: [{rule, severity, pointer, path, message}], verdicts: [{command, profile, verdict, reasons}]}`.

### 1.5 Exit codes

| Code | Meaning |
|---|---|
| 0 | Clean (warnings may exist unless `--strict`) |
| 1 | Findings at error severity, including L0 parse failures of the input document |
| 2 | CLI misuse or I/O failure: unknown flag, unreadable file, bad `--profile-config` |
| 3 | Internal error (a bug in lint itself) |

This is the shellcheck-family convention: 1 means "your file", 2+ means "your invocation or my bug", so CI pipelines can distinguish them.

### 1.6 Implementation language: TypeScript on Node

Recommendation: **TypeScript**, published as an npm bin (`cmdson-lint`) bundled to a single file with esbuild so it runs on bare `node` with no runtime deps.

Why:
1. **One canonicalizer.** Lint's L1–L2 are exactly the reference SDK's loader. Implementing lint in any other language forks canonicalization on day one — the highest-risk drift in the whole ecosystem. Lint-as-thin-CLI-over-SDK makes "the validator and the parser agree" true by construction.
2. **JSON Schema maturity.** `ajv` gives draft-2020-12 validation with pointer-accurate errors; no other candidate language beats it enough to justify point 1's cost.
3. **The operators already have Node.** The karabiner bake toolchain and the monkeytype URL encoder both require node on the machines where cmdson documents live; tmux-oneshot machines have it too. Zero new toolchain.
4. Cold-start (~50–80 ms) is irrelevant for a lint tool.

Explicitly considered and deferred: a Rust or Go static binary (nice for editor LSP integration and no-node shell hosts). Revisit only after the Rust SDK exists (Part 2.6), at which point the binary comes free rather than as a fork.

---

## Part 2 — Language SDKs

### 2.1 Shared architecture

Every SDK is the same five deterministic stages, in the docopt direction (spec drives parser — no SDK ever contains per-command logic):

```
load/canonicalize → match (argv walk) → resolve (source precedence) → validate (types/constraints) → report (result | errors, usage/help)
```

The stages are normative because the conformance fixtures (Part 4) exercise each seam. An SDK is "done" when the fixture runner passes, not when its author says so.

### 2.2 TypeScript SDK (reference implementation)

API surface, in full — everything else is internal:

```ts
import {loadSpec, type Spec, type ParseOutcome} from "cmdson";

const spec: Spec = loadSpec(text);          // JSON or YAML; throws SpecError[] on invalid
                                            // documents — the same L1–L3 rules as lint

const outcome: ParseOutcome = spec.parse(argv, {env: process.env});
// ParseOutcome is a discriminated union:
//   { ok: true,  path: string[],                        // ["ctx", "cXt"]
//     values: Record<string, string | number | boolean>,
//     provenance: Record<string, "argv" | "env" | "default"> }
//   { ok: false, errors: ParseError[], usage: string }
// ParseError = { param?: string, raw?: string, message: string,
//                choices?: string[], path: string[] }

spec.usage(path?: string[]): string          // one-line synopsis for a node
spec.help(path?: string[]): string           // synopsis + param/choice/subcommand tables
formatErrors(outcome): string                // canonical stderr rendering, usage-first
```

**Parse semantics** (restating the model's contract as implementation duties):
- Parse input is argv after the invoking program (shell `$@`); `exec` tokens are render-only and never parsed.
- Subcommand `name` descends the tree; unknown first token at a subcommand node is an error listing the branches.
- Flag `token` matches exactly as spelled (dashes included; dash-less tokens like `ACTION` are legal flags). Input is liberal: `--f v` and `--f=v` are both accepted regardless of declared `join` — `join` is a render preference only.
- Flag tokens match before positional fill; remaining tokens fill positionals in document order; extras are an error. A repeated flag is an error. No `--` end-of-options convention in v1.
- Env-bound params read `getenv(var)` — never argv (the shell consumed the prefix).
- Unknown flags error; a did-you-mean suggestion by edit distance is a nice-to-have, not conformance-tested.

**Validation-as-parsing.** There is no separate "validate" call a caller can forget: `parse` returns either a fully typed object or errors, never a half-checked bag of strings. Conversion grammar is pinned by fixtures: `int` = optional sign + decimal digits; `float` = finite decimal; `pattern` is anchored; `min`/`max` inclusive; choice membership compares typed values when `open: false`; unknown `format`s degrade to the base type. Switch → `boolean`, int/float → `number`, else `string`.

**Precedence.** In the v1 model each param has exactly one bind, so per-param resolution is *bound source, else `default`* — and `initial` is **never** injected (the typing-test acid case). Internally the resolver is still written as an ordered source list `[argv, env, default]` with the winner recorded in `provenance`: when the deferred `envFrom` fallback extension lands (a flag that falls back to an env var), the classic **flag > env > default** chain is a one-line change and `provenance` already names the winner. That is why provenance exists: it makes both the env read side and default injection debuggable today, and it future-proofs the precedence chain.

**Usage/help generation** — generated, never authored; drift is impossible because the round-trip is a lint conformance check:
- Synopsis grammar: env params render first as `VAR=<name>` (bracketed when optional), then exec tokens, then params in document order — switch `[--flag]`, kv flag `[--flag <name>]` (or `--flag=<name>` under `join: "equals"`), positional `<name>`, brackets iff optional — then `<subcommand>` when branches exist. The two worked examples pin it: `[ACTION=<action>] irun <subcommand>` and `karabiner-typing-test [<action>] [--words <words>]` (the latter matching the hand-written usage comment in today's script, which the generated string replaces).
- Help adds description lines, a choice table (`value — description`), and `(default: X)` for `default`. `initial` deliberately does **not** render in help — it is a UI preselection, not part of the command's contract; presenting it as a default would misstate ownership of the true default.

**Error reporting.** Errors are data (`{param, raw, message, choices?}` plus the command path), so frontends can render them natively; `formatErrors` provides the canonical text form. Recommended CLI wrapper behavior: usage + errors to stderr, exit 64 (`EX_USAGE`) — recommended, not normative.

### 2.3 zsh helper

Not a reimplementation — zsh must never contain a second parser. The TS package ships a CLI mode designed for `eval`:

```zsh
# replaces the hand-written PARSE and VALIDATE blocks in scripts like karabiner-typing-test
eval "$(cmdson parse "${SPEC_PATH}" -- "$@")" || exit 64
# on success, emits shell-quoted assignments: typeset action=next; typeset words=100
# absent optional params emit nothing (so ${words-} distinguishes absent from empty)
# on failure, emits `exit 64` after printing generated usage + errors to stderr
```

Companions: `cmdson parse --emit json … | jq` when a script wants provenance, and `cmdson usage <spec>` so a script's `--help` is the generated string. Node cold start (~50 ms) is acceptable for keyboard-fired scripts; if it ever isn't, the Rust binary (2.6) replaces the runtime without changing the interface.

### 2.4 Python SDK

Gated behind a named consumer (none exists today). A port, not a design: written only after the fixtures freeze, so its API mirrors the TS surface (`cmdson.load_spec(...).parse(argv, env=os.environ)` returning a dataclass with `path` / `values` / `provenance`, errors as data). Target audience is tooling and test harnesses. It carries zero new decisions by construction — every behavioral question is answered by a fixture.

### 2.5 Rust SDK (sketch only)

`serde` derive over the canonical model; `Spec::parse(&[String], &impl Env) -> Result<Parse, Vec<ParseError>>`. Its purpose is a single static `cmdson` binary subsuming lint + the zsh helper on hosts without node. Relationship to clap: cmdson inverts clap-derive — clap generates a parser from Rust types; cmdson generates the typed result (and optionally types, Part 3) from the spec, docopt's direction with structured data instead of usage-string parsing. Not scheduled until the fixture suite proves the contract twice (TS + Python).

### 2.6 SDK non-goals (v1)

No plugin hooks, no custom parser callbacks, no runtime spec mutation. The `parser`-registry idea was rejected in the data model for host-dependence; SDKs honor that by having no extension surface beyond `meta` passthrough.

---

## Part 3 — Type generation

Gated behind a named consumer, exactly like the Rust SDK — nothing today imports generated
types (`typing.ts` loads docs directly; the zsh helper needs none). When one arrives:
`cmdson gen ts spec.json > ctx.gen.ts` consumes the **canonical** model and emits:

- A literal union per closed choice set: `type CtxAction = "copy_env" | "copy_flag" | "login"`.
- `number` for int/float; for `open: true` with representative choices, optionally the autocomplete-preserving widening `5 | 50 | 100 | 300 | (number & {})`.
- `boolean` for switches; optional params without a `default` are `name?: T` (absent from `values` when unset); params with a `default` are non-optional (injection guarantees presence).
- A discriminated union over subcommand paths, discriminated on a `path` tuple literal, values accumulated along the path:

```ts
type CtxResult =
  | {path: ["ctx", "cxt"], values: {action: CtxAction}, provenance: …}
  | {path: ["ctx", "cXt"], values: {action: CtxAction}, provenance: …}
  // … one arm per leaf
```

- An embedded canonical spec constant plus a typed `parse` wrapper (`parse(argv, opts): CtxResult | ParseFailure`), so a CLI author imports one generated module and gets compile-time exhaustiveness over subcommand branches via `switch (result.path[1])`.

Mechanics: deterministic output (document order everywhere), a header comment carrying the spec's content hash so CI catches drift between spec and generated file, regeneration idempotent. Inspiration credit where due: clap-derive (inverted), docopt (spec-drives-parser), and openapi-typescript as the spec→`.d.ts` precedent proving the workflow. Same walk later yields zsh/fish completions — noted as future, out of v1.

---

## Part 4 — Test strategy: shared golden fixtures

One conformance tree, consumed by every SDK via a ~100-line per-language runner. Adding an SDK means writing a runner, never writing tests.

```
conformance/
  cases/<name>/
    spec.json            # document under test (ctx and typing-test are cases 001/002)
    parse/<case>.json    # {argv, env, expect: {path, values, provenance} | {errors}}
    usage.txt            # expected generated usage/help per node path
    render/<sel>.json    # selection → expected (env, argv, cwd) token triple
                         # + shell-serialization vectors (values needing quoting)
  lint/<rule>/
    spec.json            # minimal document violating exactly one rule
    findings.json        # expected rule IDs, severities, pointers (+ profile verdicts)
```

**The acid fixtures** — each pins a decision from the data-model synthesis:
1. **initial-vs-default** (typing-test): `[]` → `values` contains `action: "next"` (provenance `default`) and **no** `words` key; `["previous", "--words", "100"]` → `words: 100` typed, provenance `argv`. This is the single most important fixture in the suite.
2. **env read side** (ctx): env `ACTION=login` → provenance `env`; unset → `copy_env` injected, provenance `default`.
3. **join liberality**: `--words 100` ≡ `--words=100`.
4. **closed-choice rejection**: error carries the `choices` array.
5. **type conversion errors**: `--words banana`, `--words 1.5` against `int`.
6. **open int free value**: `--words 37` accepted.
7. **missing required positional**, **unknown flag**, **extra positional**.
8. **render triples**: `{path: ["ctx", "cXt"], values: {action: "login"}}` → `({ACTION: "login"}, ["irun", "cXt"], ∅)`; typing selection → `["karabiner-typing-test", "previous", "--words", "100"]` (render argv always starts with the `exec` tokens; the karabiner projection maps argv[0]→script name, rest→args); quoting vectors for the tmux serializer (a value containing a space and a single quote).
9. **usage round-trip**: generated strings byte-match `usage.txt` for both worked examples.

**Cross-cutting property test** (reference SDK only, others inherit via fixtures): for every enumerable selection of a spec, `parse(render(selection))` returns the selection's `values`. Provenance may differ by design — a pre-emitted default parses as `argv` — the invariant is value equality, which is exactly the emit≡omit contract exercised end-to-end.

Golden files are regenerated only by a blessed `cmdson conformance --bless` in the reference SDK; ports never regenerate. Lint fixtures double as rule documentation: `--explain CMD027` prints `lint/CMD027/spec.json`.

---

## Part 5 — Sequencing: what to build first, and what proves the spec

Ordered so each step has a named proof against an artifact that already exists today. The spec is *proven* at step 6, when one document drives all three consumer kinds (SDK parse, free-text frontend, finite frontend) with no per-frontend forks.

| # | Build | Proof |
|---|---|---|
| 1 | Meta-schema (`cmdson.schema.json`) + the two worked-example documents checked in as conformance cases | Both examples validate; the schema rejects a seeded set of malformed mutants |
| 2 | TS core: loader + canonicalizer (the shared kernel lint and SDK both sit on) | Canonicalization goldens (bare-string choices, defaulted fields) |
| 3 | `cmdson-lint` L1–L3 (no profiles yet) | Both examples lint clean; the `lint/` fixture suite passes red and green |
| 4 | TS parse + usage + errors, conformance runner, fixture families 1–7 + 9 | The initial-vs-default acid test: parsing bare `karabiner-typing-test next` injects nothing, leaving the `passage` CLI's own default intact |
| 5 | Render module + native cmdson reading in tmux-oneshot (a rewrite of `_assemble` per the frontend plan §3.2 — no cmdson→legacy adapter) | The ctx document reproduces today's `commands.json` behavior, including the serialized `ACTION=login irun cXt` line; quoting proven by the serializer's quote-iff-needed vectors, not byte-parity with the four legacy styles |
| 6 | Karabiner profile in lint + bake-time projection in `karabiner.ts` (cmdson doc → `argBuilder(...)` call) | Byte-identical manipulator JSON versus today's hand-written `typingBuilder`: 12 combinations, same keycaps, `status` curated out via `meta.karabiner.omitChoices`, firing `script("karabiner-typing-test", ["previous", "--words", "100"])` |
| 7 | zsh helper (`cmdson parse` eval mode, `cmdson usage`); migrate `karabiner-typing-test`'s PARSE/VALIDATE blocks | Script behavior unchanged, including `words_requested=""` passthrough when `--words` is absent |
| 8 | `cmdson gen ts` type generation | Generated module compiles; an ctx wrapper type-checks with literal unions and exhaustive path switching |
| 9 | Python SDK (port from fixtures); Rust SDK + static binary only when a no-node host demands it | Python: fixture suite green with zero new decisions. Rust: same, plus the single-binary lint/parse replacing the node runtime behind an unchanged interface |

Two deliberate omissions close the plan: nothing in this sequence implements any deferred model feature (repeat/arity, `envFrom`, `persistent`, …) — each stays deferred until a step in this table needs it and a fixture can pin it; and no step ships without its proof line, because the proof lines are what keep cmdson a spec that gets obeyed rather than a spec that gets interpreted.
