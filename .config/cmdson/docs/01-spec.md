# cmdson v1 — data model (synthesized)

Ground truth verified against source: `argbuilder.ts` (static bake, cartesian product of `ArgGroup`s, mandatory `defaultKey`, keys unique across groups, fire returns an `Action`), `actions.ts` (`script(name, args)` — the karabiner fire target is an **argv token list**, not a shell string), `typing.ts` (3×4 builder, `status` deliberately outside the builder as a direct `s` binding), `karabiner-typing-test` (accepts `--words` with any action including `status`, and when `--words` is absent the downstream `passage` CLI picks its own default — `words_requested=""`), `tmux-oneshot` (recursive cmd/flags/subcommands, four kv styles, options-or-free-text, top-level-only `pwd`, `autodismiss`, `menu` override, shell-string `eval`), `commands.json` (ACTION rendered as a dash-less `equals` kv token **after** `irun`: `irun ACTION=login cxt`).

---

## 1. Scoring

| Criterion | P1 (minimal-composable) | P2 (expressiveness-first) | P3 (constraint-first) |
|---|---|---|---|
| (a) Both frontends expressible | **8** — covers both examples cleanly, but its karabiner profile refuses optional-no-default params instead of synthesizing a skip option, and it under-specifies flattening | **9** — everything reachable, `initial` and degradation contract §3.3 are the sharpest frontend modeling | **9** — most precise about karabiner mechanics (argv-list fire, product budgets, skip synthesis, bare-branch flattening) |
| (b) SDK-readiness | **8** — clean argv→typed contract, but a single `default` field can't express "builder pre-emits 50, parser must not inject 50" | **10** — provenance, result-shape table, precedence chain, structured errors: the most complete parse contract | **7** — parse sketch works, but string-typed defaults and no env-as-input weaken the typed-object story |
| (c) Simplicity & evolvability | **10** — 4 nouns, 1 discriminator, ~24 fields; quoting correctly expelled from the data model | **6** — kind-conditional field blocks, repeat/arity/relations/parsing directives/persistent/hidden: real accretion risk before any consumer needs them | **7** — moderate core, but the capability algebra is a second spec, and the `-quoted` join styles smuggle serialization into data |
| (d) Prior-art reuse | **9** — Fig value-presence, name/exec split, join reduction, namespaced meta: each steal correctly *reduced*, not copied | **9** — broadest and best-argued adopt/reject ledger; enum-vs-suggestions (clap ValueEnum vs ValueHint) is the single best steal in any proposal | **8** — good steals (`effect`, structured choices), but string `default` and Fig's acknowledged name-overloading footgun re-adopted |
| **Total** | **35** | **34** | **31** |

**Winner and base: Proposal 1.** Its skeleton (four nouns, `bind` discriminator, quoting-as-emission, namespaced `meta`) is the only one small enough that the validator stays "simpler than either frontend." P2 contributes the two ideas P1 demonstrably gets wrong (`initial`/`default`, `effect`, provenance); P3 contributes the karabiner projection machinery P1 hand-waves (token-list assembly, skip synthesis, flattening, emit≡omit contract, `openPolicy`).

---

## 2. Synthesized final data model

A cmdson **document** is a template for the invocation triple `(env, argv, cwd)` plus the typed choice space that fills its holes. Five shapes: `Command`, `Param`, `Bind`, `Value`, `Choice`. A database file is a JSON array of documents. Only JSON scalars/arrays/objects — no string micro-DSLs, no code — so YAML is 1:1 free.

```jsonc
// ── Command ── the one recursive node ─────────────────────────────
{
  "cmdson": "1",                 // REQUIRED on the document root only.
  "name": "typing-test",         // REQUIRED. Parse identity: what an SDK matches in
                                 //   argv; what menus display. Unique among siblings.
  "exec": ["karabiner-typing-test"],
                                 // optional argv TOKENS to emit, default [name].
                                 //   An array, never an opaque string, because the
                                 //   canonical assembly output is a token list
                                 //   (karabiner fires script(name, args)).
  "key": "t",                    // optional single keycap when offered as a
                                 //   subcommand choice in one-key frontends.
  "description": "…",            // optional, on every noun.
  "effect": "write",             // "read" | "write" (default) | "destructive".
                                 //   Max along the chosen path wins. Auto-firing
                                 //   frontends (karabiner ⏎) refuse "destructive"
                                 //   unless operator config opts in.
  "cwd": "~/src",                // optional, document ROOT only — the third slot of
                                 //   the triple. Template context, not a param.
  "params": [ /* Param */ ],     // optional, ORDERED. One list for flags,
                                 //   positionals, and env vars; `bind` discriminates.
                                 //   Emission order = document order.
  "subcommands": [ /* Command */ ],
                                 // optional, recursive. If present, exactly one MUST
                                 //   be chosen (this is the alternatives / mutual-
                                 //   exclusion operator). MUTUALLY EXCLUSIVE with
                                 //   positional-bound params on the same node.
                                 //   Finite frontends default to the FIRST entry.
  "meta": { "tmux-oneshot": { "autodismiss": true, "menuName": "Set CONTEXT" } }
                                 // optional on EVERY noun: opaque bags namespaced by
                                 //   frontend id (OpenAPI x- convention). The single
                                 //   escape hatch for frontend-private hints —
                                 //   autodismiss, menu overrides, karabiner choice
                                 //   curation. Unknown namespaces are ignored.
}

// ── Param ── one value slot in the invocation ─────────────────────
{
  "name": "words",               // REQUIRED. The typed-result key (argparse `dest`),
                                 //   never rendered. Unique along any root→leaf path.
                                 //   Also the generated-usage placeholder (<words>).
  "bind": /* Bind */,            // REQUIRED. WHERE the value lands.
  "description": "…",
  "required": false,             // optional bool. Asymmetric defaults, matching CLI
                                 //   reality (Fig): flag=false, env=false,
                                 //   positional=true.
  "value": /* Value */,          // ABSENT = presence-only switch (legal only on
                                 //   bind.at=="flag"; SDK result: boolean).
                                 //   PRESENT (even {}) = takes one value.
                                 //   This one presence bit replaces any flag-type
                                 //   enum and any boolean type (Fig's args trick;
                                 //   exactly tmux-oneshot's bool/kv split).
  "meta": { }
}

// ── Bind ── the discriminator over (env, argv) slots ──────────────
{ "at": "flag", "token": "--words", "join": "space" }
                                 // token: exact spelling, dashes included — never
                                 //   implied. Dash-less tokens are legal ("ACTION"),
                                 //   which is how wrapper-consumed VAR=value TOKENS
                                 //   are expressed when they must sit mid-argv.
                                 // join: "space" | "equals", default "space". A
                                 //   SEMANTIC property of the target CLI, not a UI
                                 //   style. Quoting is NOT here — argv has no
                                 //   quotes; see render semantics.
{ "at": "positional" }           // order among positionals = document order.
{ "at": "env", "var": "ACTION" } // the value travels via the ENVIRONMENT. Frontends
                                 //   WRITE it as a VAR=value prefix hoisted to the
                                 //   front of the line; SDKs READ it via getenv (the
                                 //   shell consumed the prefix). One declaration,
                                 //   both directions.

// ── Value ── the legal-value space ────────────────────────────────
{
  "type": "int",                 // "string" (default) | "int" | "float". Closed
                                 //   list. Booleans are switch-absence; enums are
                                 //   choices; everything else is `format`.
  "format": "path",              // optional free annotation ("path","url","duration",
                                 //   "email"). Hint for pickers/docs; unknown
                                 //   formats degrade to the base type (oclif lesson:
                                 //   annotation, never code; keeps the type list closed).
  "pattern": "^[a-z]+$",         // optional, strings: anchored regex.
  "min": 1, "max": 300,          // optional, int/float bounds.
  "choices": [ /* Choice */ ],   // optional enumeration. Bare-string shorthand:
                                 //   "s" ≡ {"value":"s"}; loaders canonicalize.
  "open": true,                  // default = (choices absent). true: values outside
                                 //   choices are legal (choices are suggestions).
                                 //   false requires choices. One list + one bit
                                 //   replaces a separate enum/suggestions pair.
  "openPolicy": "close",         // "close" (default) | "exclude". Consulted ONLY by
                                 //   no-free-text frontends when open=true:
                                 //   "close"  = the listed choices become the whole
                                 //              set there (the list is representative);
                                 //   "exclude"= the list is mere examples; a frontend
                                 //              without free text must not offer this
                                 //              param (bubbling per degradation rules).
  "default": "next",             // optional, typed per `type`. PARSE-TIME: an SDK
                                 //   injects it when the param is absent. CONTRACT:
                                 //   emitting the default explicitly MUST be
                                 //   semantically identical to omitting the param —
                                 //   this is what licenses finite frontends to
                                 //   pre-emit it. Must satisfy constraints and be
                                 //   ∈ choices when open=false.
  "initial": 50,                 // optional, typed per `type`. BUILD-TIME ONLY:
                                 //   interactive preselection. Parsers NEVER inject
                                 //   it. Use when the downstream tool owns the true
                                 //   default (typing test: --words absent ⇒ passage
                                 //   decides; the UI still preselects 50).
  "meta": { }
}

// ── Choice ── one enumerated value ────────────────────────────────
{
  "value": 50,                   // REQUIRED, typed per the owning Value.type. What
                                 //   is emitted (canonical string form) and what the
                                 //   SDK returns.
  "label": "50 words",           // optional display text.
  "key": "1",                    // optional single keycap for one-key frontends.
  "description": "…",
  "meta": { }
}
```

### Render semantics (normative)

Assembly produces the triple, at the **token** level:

```
render(doc, selection) -> (env, argv, cwd):
  env  := { var: canonical(value) } for every env-bound param on the chosen
          root→leaf path (path order, then document order)
  argv := per node from root to leaf:
            node.exec tokens
            then non-env params in document order:
              switch present        -> [token]
              flag + value, space   -> [token, value]
              flag + value, equals  -> [token + "=" + value]
              positional            -> [value]
            then the chosen subcommand's tokens
  cwd  := root cwd, if any
```

An optional param that resolves to nothing contributes no tokens. **Serialization is a frontend duty, not data**: a shell-string frontend (tmux-oneshot) prefixes `VAR=value` assignments, joins tokens, and MUST shell-quote any token that needs it (MAY quote always) — tmux's four styles are exactly 2 joins × this emission policy. An argv frontend (karabiner `script(name, args)`) passes tokens directly; if it must carry `env`, its wrapper prepends the assignments to the shell command it builds.

Whether a frontend emits pre-filled values is frontend policy: karabiner emits `initial ?? default` for every group (it must — groups are total, and the user sees the preselection); fzf may skip; SDKs inject `default` (never `initial`) on the read side.

A **Selection** — `render`'s second argument and the payload of a frontend's fire — is
`{path: [command names, root→leaf], values: {paramName: typedValue}}`: switches are booleans,
omitted optionals are absent keys. Deliberately symmetric with the SDK's ParseOutcome.

### Degradation contract (computed, never guessed)

A frontend ships a static profile: capabilities ⊆ {FREE_TEXT, RECURSION, DYNAMIC (reserved), CWD} plus budgets (karabiner: `{maxCombinations, maxChoicesPerGroup, keyAlphabet}`; tmux: all capabilities, unbounded). Per-node rules, applied before reachability:

| Node in an incapable frontend | Rule |
|---|---|
| `open:true` choices, no FREE_TEXT | `openPolicy:"close"` → the choices become the set; `"exclude"` → param unrenderable |
| unrenderable param with a `default` | pre-emit the default as a fixed constant, required or not — invisible emission is licensed by the emit≡omit contract, which covers `default` ONLY; a bare `initial` never licenses it (omission then means the downstream tool's own default) |
| unrenderable **optional** param, no `default` | synthesize a "(skip)" option rendering zero tokens as the group default; `initial`, if any, is ignored — it is a visible-preselection hint only |
| unrenderable **required** param, no `default` | command excluded from this frontend — a bake-time verdict with a logged reason, never a runtime surprise |
| `subcommands` where every branch is bare (no params, no children) | **flatten** to one synthetic choice group over branch names/keys (the ctx family's shape) |
| non-flattenable subcommands, no RECURSION | branch-level exclusion; surviving branches still offered |
| `cwd` without CWD | command excluded (wrong-cwd execution is worse than absence) |
| `effect:"destructive"` in an auto-firing frontend | excluded unless operator opt-in |

The validator makes these rules checkable as named **profiles** (e.g. `karabiner`: every surviving group has ≤ budget choices, a preselection, and unique keys across the node's whole surface; product ≤ `maxCombinations`).

Two deliberate asymmetries, stated as decisions: flattened subcommand groups default to their
FIRST branch (a subcommand choice is required, so any default is legal), while param choice
groups need an explicit `initial`/`default` — invisible pre-emission must be licensed.
Synthesized options ("(skip)", "(off)"/"(on)") take the reserved keycap `-` (override:
`meta.karabiner.skipKey`), which must then be free in the node's key surface.

### SDK parse contract

1. Parse input is argv AFTER the invoking program (shell `$@`); `exec` tokens are render-only and never parsed. Walk argv against the tree: subcommand `name` descends; flag `token` consumes — parsers accept **both** `--f v` and `--f=v` regardless of `join` (join is a render preference; input is liberal); flag tokens match before positional fill; remaining tokens fill positionals in order. A repeated flag is an error; no `--` end-of-options convention in v1.
2. Env-bound params come from `getenv(var)` — never argv.
3. Apply `default`s (never `initial`s), then validate: type conversion, `pattern`/`min`/`max`, choice membership when `open:false`; unknown `format`s degrade to the base type.
4. Return `{path: [...names], values: {name: typed}, provenance: {name: "argv"|"env"|"default"}}`; result types: switch → bool, int/float → number, else string. Errors are data: `{param, raw, message, choices?}`.
5. Usage/help is **generated, never authored** — `[--t <n>]` optional, `<p>` positional, `VAR=<n>` env prefix, subcommand table — and round-trip-tested by the validator so help can never drift.

### Validator invariants

Schema shapes; sibling-name and per-path param-name uniqueness; `default`/`initial` satisfy constraints (and choices when closed); choice values parse as `type`; `positionals ⊕ subcommands`; `cwd` and `cwd`-root-only; switches only on flag binds; `join` only on flag binds; `open:false` ⇒ choices present; `openPolicy` only with `open:true`; env `var` matches `[A-Z_][A-Z0-9_]*`; plus the named frontend profiles above.

Database-file rules: root identity keys (`meta.<frontend>.menuName ?? name`) are unique
across the array, and menu names must not contain `" | "` (the tmux menu separator). YAML is
supported 1:1 through the canonicalizer with one stated rule: scalars map per the JSON field
types — quote anything YAML would retype (`cmdson: "1"`, choice values like `"no"`); the
conformance suite carries one YAML case.

---

## 3. Worked examples

### 3a. The `ctx` context-picker family

`ACTION` is semantically an environment variable the ctx functions read, so it is env-bound; render hoists it to the line front (`ACTION=login irun cXt`), behavior-equivalent to today's `irun ACTION=login cXt` because the eval'd inner command inherits the environment. The emit≡omit contract holds: the ctx functions default ACTION to `copy_env`.

```json
{
  "cmdson": "1",
  "name": "ctx",
  "exec": ["irun"],
  "description": "context picker (ctx family)",
  "effect": "read",
  "params": [
    {
      "name": "action",
      "bind": { "at": "env", "var": "ACTION" },
      "description": "what to do with the picked context",
      "value": {
        "default": "copy_env",
        "choices": [
          { "value": "copy_env",  "key": "e", "description": "copy exported variables" },
          { "value": "copy_flag", "key": "p", "description": "copy a --pick flag" },
          { "value": "login",     "key": "l", "description": "sign in" }
        ]
      }
    }
  ],
  "subcommands": [
    { "name": "cx",  "key": "1", "description": "main contexts, all stages" },
    { "name": "cX",  "key": "2", "description": "ALL contexts, all stages" },
    { "name": "cxd", "key": "3", "description": "main, dev" },
    { "name": "cxt", "key": "4", "description": "main, test" },
    { "name": "cxp", "key": "5", "description": "main, prod" },
    { "name": "cxl", "key": "6", "description": "main, lab" },
    { "name": "cXd", "key": "7", "description": "all contexts, dev" },
    { "name": "cXt", "key": "8", "description": "all contexts, test" },
    { "name": "cXp", "key": "9", "description": "all contexts, prod" },
    { "name": "cXl", "key": "0", "description": "all contexts, lab" }
  ],
  "meta": {
    "tmux-oneshot": {
      "menuName": "Set CONTEXT",
      "menuText": "irun ctx… — context picker (dev/test/prod/lab; ACTION=copy_env/copy_flag/login)"
    }
  }
}
```

Selection `{action:"login", subcommand:"cXt"}` → `(env: {ACTION:"login"}, argv: ["irun","cXt"], cwd: ∅)`; tmux serializes `ACTION=login irun cXt`. Karabiner: all subcommand branches are bare → flatten to one 10-choice group; with the action group, 3 × 10 = 30 static bindings, every choice keyed. Generated usage: `[ACTION=<action>] irun <subcommand>`.

### 3b. The hyper+t typing test

The decisive modeling: `--words` is an **int with representative choices** (`open:true, openPolicy:"close"`) and an **`initial` of 50 with no `default`** — the karabiner UI preselects and emits 50, tmux lets you type 37, and an SDK parsing a bare `karabiner-typing-test next` injects nothing, leaving the `passage` CLI's own default intact. The action enum carries all four values including `status`; karabiner's omission of `status` from the builder is frontend curation, expressed in `meta`, because the script genuinely accepts (and ignores) `--words` with `status` — the spec models the contract, not the curated keyboard surface.

```json
{
  "cmdson": "1",
  "name": "typing-test",
  "exec": ["karabiner-typing-test"],
  "description": "Open a Monkeytype test seeded by the passage CLI",
  "effect": "write",
  "params": [
    {
      "name": "action",
      "bind": { "at": "positional" },
      "required": false,
      "value": {
        "default": "next",
        "choices": [
          { "value": "next",     "key": "n", "description": "next unread passage, advancing the bookmark" },
          { "value": "current",  "key": "c", "description": "retype the last passage (--words re-anchors)" },
          { "value": "previous", "key": "p", "description": "rewind one passage and retype it (--words re-anchors)" },
          { "value": "status",   "key": "s", "description": "notify progress; no test opened" }
        ],
        "meta": { "karabiner": { "omitChoices": ["status"] } }
      }
    },
    {
      "name": "words",
      "bind": { "at": "flag", "token": "--words", "join": "space" },
      "description": "passage length; re-anchors the bookmark for current/previous",
      "value": {
        "type": "int",
        "min": 1,
        "open": true,
        "openPolicy": "close",
        "initial": 50,
        "choices": [
          { "value": 5,   "key": "0", "label": "5 words" },
          { "value": 50,  "key": "1", "label": "50 words" },
          { "value": 100, "key": "2", "label": "100 words" },
          { "value": 300, "key": "3", "label": "300 words" }
        ]
      }
    }
  ]
}
```

Karabiner projection: action group next/current/previous (status curated out), words group 0/1/2/3 preselecting `1` from `initial:50` → 3 × 4 = 12 manipulators, firing e.g. `script("karabiner-typing-test", ["previous","--words","100"])` — byte-identical to today's `typing.ts` builder. tmux offers all four actions and free-typed word counts. Generated usage: `karabiner-typing-test [<action>] [--words <words>]` — matching the script's hand-written usage comment.

---

## 4. Decisions log

1. **Base skeleton = P1's four nouns + `bind` discriminator.** Losing alternative: P2's kind-discriminated Param with per-kind field blocks. P1's shape carries identical information with fewer mechanisms, and the "validator simpler than either frontend" requirement is only met by the small core.
2. **Canonical assembly output is a token list (P3), not a rendered line (P1's implicit framing).** Ground truth: karabiner fires `script(name, args)` — an argv array. Defining assembly at the token level makes quoting provably a serialization concern and makes the karabiner projection exact. `exec` becomes `[string]` accordingly.
3. **`initial` vs `default` split (P2) over a single `default` (P1, P3).** The typing test proves a single field is wrong: the builder must preselect-and-emit 50 while a parser must not inject 50 (the `passage` CLI owns the true default). Losing alternative — P1's "defaults applied on the read side" — silently shadows downstream defaults.
4. **The emit≡omit contract on `default` (P3), stated normatively.** It is the sole license for finite frontends to pre-emit defaults (which karabiner's total groups require). Without it, P1's "frontend policy" hand-wave is unsound.
5. **One `choices` list + `open` + `openPolicy` (P1 + P3) over a separate `suggestions` concept (P2).** Same expressiveness, one noun fewer; `openPolicy` gives the author the exact degradation dial P2's enum/suggestions split existed to provide ("close" = representative set, "exclude" = mere examples).
6. **`join` reduced to `space | equals`; quoted styles (P3) and `accept` lists (P2) rejected.** Argv has no quotes — tmux's four styles are 2 joins × emitter escaping. And the SDK *is* the target parser, so it can simply be liberal (`--f v` and `--f=v` both accepted); a configurable accept-list guards against nothing real here.
7. **Env bind hoists to line front; P2's `placement: "before-leaf"` rejected.** `ACTION=login irun cxt` and `irun ACTION=login cxt` are behavior-equivalent under process-env inheritance (the eval'd inner command sees the variable either way). For the rare wrapper where token position genuinely matters, the model already expresses it with zero new fields: a dash-less flag token + `join:"equals"` (P3's ctx modeling survives as the escape hatch, not the canonical form — env bind is canonical because it gives SDKs the `getenv` read side for free).
8. **`effect: read|write|destructive` adopted (P2/P3, from usage-KDL).** One field, and it answers the only safety question a one-keystroke auto-firing frontend must ask. P1's omission was its clearest gap.
9. **Relations rejected entirely (P1's stance); P2's `requires`/`conflictsWith`/groups and P3's choice-level `conflictsWith` lose.** Subcommand branching is the exclusion operator the finite UIs need; a constraint graph is a second validation language. Decisive test case: `status` vs `--words` — the script *accepts and ignores* the combination, so encoding it models incidental leniency as law; and the karabiner builder's status omission is frontend curation (`meta.karabiner.omitChoices`), not command semantics. A future `constraints` block remains the reserved extension point.
10. **Skip-option synthesis, default-fixing, and bare-branch flattening (P3) adopted into the karabiner profile**, replacing P1's coarse "refuse the document." Keeps strictly more documents reachable with zero new core fields, and every exclusion is a logged bake-time verdict.
11. **Type list closed at `string|int|float` + `format` annotation (P1); P2's `path`/`duration`/`datetime`/`map` and its symbolic `parser` registry rejected for v1.** Neither frontend nor either example needs them; `format` carries the hint today, and promoting a format to a type later is additive. The `parser` registry reintroduces host-dependence the oclif lesson warns about.
12. **Repeat/arity/count, `envFrom` fallbacks, `defaultMissing`, `persistent`, `hidden`, `deprecated`, parsing directives (all P2) deferred.** No current consumer can render or needs any of them; each has a known additive design (repeat ⇒ list result per docopt shapes) when a consumer arrives.
13. **Usage strings generated, never authored; P2's `usageLines` override rejected.** An override field reintroduces drift — the disease docopt inverted itself to avoid. Prose lives in `description`; the round-trip test is a validator conformance check.
14. **Subcommands are a required choice, mutually exclusive with positionals (P1); P2/P3's optional-parent policies rejected for v1.** Both frontends today treat subcommand pick as mandatory (tmux esc aborts); "(none)" rows and runnable parents are additive later via one field.
15. **Namespaced `meta` bags (P1/P2's `x-` convention) carry `autodismiss`, tmux menu overrides, and karabiner choice curation.** Losing alternative: promoting any of them to core (P2 promoted `cwd` only — kept, since every dispatcher needs cwd; the rest is presentation/curation policy).
16. **Provenance (`argv|env|default`) in SDK results (P2).** Costless in the model, and it is what makes the env read-side and default injection debuggable.
17. **Document = one root Command + version; database file = array of documents (P1); P3's `commands` array inside one document rejected.** One command per document keeps identity, versioning, and validation per-command; the database concept stays a trivial container.
