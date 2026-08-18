# Frontend Integration Plan

> `docs/02-frontends.md` — how the two existing frontends realize, dispatch, and migrate to cmdson.
> The data model this plan projects from is `docs/01-data-model.md`. Ground truth for frontend
> behavior is the source: `karabiner.ts/src/utils/argbuilder.ts`, `karabiner.ts/src/utils/actions.ts`,
> `karabiner.ts/src/modes/typing.ts`, `karabiner.ts/src/scripts/bin/karabiner-typing-test`,
> `~/.config/bin/tmux-oneshot`, and the live db `~/.local/share/tmux_oneshot/commands.json`.

cmdson defines the full command; each frontend consumes what it can. This document pins down
exactly what "what it can" means for the two frontends that exist today:

| | karabiner argbuilder | tmux-oneshot |
|---|---|---|
| Interaction | one keycap per option, ⏎ fires, esc cancels | fzf pickers in a tmux popup, esc skips/aborts |
| Assembly time | **bake time** — every combination is a static manipulator | **run time** — assembled per invocation |
| Free text | never | yes (`read` from tty) |
| Recursion | no (flattening only) | yes |
| Execution | `script(name, args)` — an **argv token list** through the `karabiner_script` wrapper | one shell **string**, `eval`'d in the popup zsh |
| Capability profile | `{}` + budgets `{maxCombinations, maxChoicesPerGroup, keyAlphabet}` | `{FREE_TEXT, RECURSION, CWD}`, unbounded |

---

## 1. Concept mapping

Every noun and field in the data model, mapped to its realization in each frontend. "Verdict"
means a logged bake/load-time exclusion per §4 — never a runtime surprise.

### 1.1 Command

| cmdson concept | karabiner argbuilder | tmux-oneshot |
|---|---|---|
| `name` | builder `id`; rule name (`argbuilder: <name>`); notification title | fzfdb key (unless `meta.tmux-oneshot.menuName` overrides); menu row lead |
| `exec` (argv tokens) | fire target: `script(exec[0], exec[1:] + assembled tokens)`. **Constraint:** `exec[0]` must resolve to a `karabiner_script`-known script; otherwise verdict: command excluded from this profile | leading tokens of the serialized shell string (today's `cmd` fragment) |
| `key` | keycap for this branch when it appears as a choice in a flattened subcommand group | unused (fzf is fuzzy-search); may be shown in menu text |
| `description` | folded into the builder title notification (`(<title>) — ⏎ to run`) | `  # <description>` suffix in menu rows |
| `effect` | `"destructive"` in an auto-firing (⏎) frontend → verdict: excluded unless operator opt-in in the profile config. `read`/`write` pass | no exclusion (firing is multi-step and deliberate). Policy hook: a destructive entry should never `autodismiss`, and may get a confirm prompt (open question §5.7) |
| `cwd` (root only) | **unsupported** → verdict: command excluded (the wrapper runs with no meaningful cwd; wrong-cwd execution is worse than absence). Unlockable later — §5.11 | direct: `cd` (tilde-expanded) before `eval`, exactly today's top-level `pwd` |
| `params` (ordered) | one `ArgGroup` per surviving param, in document order (see 1.2) | flag-bound optionals → the flags multiselect; required params, positionals, env params → unconditional prompts, in document order |
| `subcommands` (required choice) | all branches bare (no params/children) → **flatten** to one synthetic choice group over branch `name`/`key`; any non-bare branch → verdict: that branch excluded (no RECURSION), survivors still offered; zero survivors → command excluded | recursive fzf pick (today's `subcommands`); esc aborts the whole entry, matching "exactly one MUST be chosen" |
| `meta.karabiner` | consumed: `omitChoices` (curation), and proposed homes for key auto-assignment overrides and quick-fire bindings (§5) | ignored |
| `meta.tmux-oneshot` | ignored | consumed: `autodismiss`, `menuName`, `menuText` — byte-for-byte today's `autodismiss` and `menu.{name,text}` |
| `cmdson` version | loader rejects unknown major | loader rejects unknown major |

### 1.2 Param + Bind

| cmdson concept | karabiner argbuilder | tmux-oneshot |
|---|---|---|
| `name` | `ArgGroup.name` and `ArgGroup.label` (the notification line lead) | prompt label (`<name>> ` / `<name> value: `) |
| `bind {at:"flag", token, join:"space"}` | baked into fire tokens: option contributes `[token, value]` | rendered `token value`; serializer quotes the value when needed (today's `space` / `space-quoted` collapse into join=`space` + emitter quoting policy) |
| `bind {at:"flag", join:"equals"}` | option contributes one fused token `token=value` | rendered `token=value` (+ quoting policy; subsumes `equals` / `equals-quoted`) |
| `bind {at:"positional"}` | option contributes bare `[value]` at its document-order slot | **new in the migrated assembler** (no legacy equivalent): value resolved via choices-fzf or free-typed prompt, emitted as a bare token in document order |
| `bind {at:"env", var}` | selection lands in the env map; the `karabiner_script` wrapper prepends `VAR=value` assignments to the shell command it builds — a **required wrapper extension**, §2.1 / §5.2 | `VAR=value` assignments hoisted to the front of the serialized line (replaces today's mid-line `ACTION=…` kv-flag trick; behavior-equivalent under process-env inheritance) |
| `required` (asymmetric defaults) | groups are total, so every param always resolves; `required` matters only via the degradation ladder — a **required** param that cannot be rendered is a command-level exclusion verdict | required params cannot be esc-skipped: esc re-prompts or aborts the entry. Optional flag-bound params keep today's esc-= -no-flags multiselect semantics |
| value **absent** (switch) | synthesized two-option group: "(off)" → zero tokens (default) and "(on)" → `[token]`. Keys for the pair come from `meta.karabiner` or auto-assignment (§5.3) | `type:"bool"` flag in the multiselect — today's behavior unchanged |
| value **present** | choice group per 1.3 | kv resolution per 1.3 |

### 1.3 Value

| cmdson concept | karabiner argbuilder | tmux-oneshot |
|---|---|---|
| `type` (`string`/`int`/`float`) | erased at bake: choice values canonicalize to strings inside static commands; type correctness is a validator/bake check, never runtime | free-typed input is parsed/validated as the type; failure re-prompts with the error |
| `format` | ignored (annotation only) | picker hint only (e.g. a future path-completion mode); unknown formats degrade to the base type |
| `pattern`, `min`, `max` | bake-time check on every baked choice value (there is no free input to check at runtime) | runtime validation of free-typed input, with re-prompt |
| `choices` | `ArgGroup.options` — one keycap each, subject to budgets (§4) | fzf list (labels + descriptions as rows) |
| `open: true` + `openPolicy: "close"` | the listed choices become the whole set here (list is representative) | fzf list **plus** free text (`--print-query` or a sentinel row — §5.6) |
| `open: true` + `openPolicy: "exclude"` | param unrenderable (list is mere examples) → degradation ladder: pre-emit its `default` as a fixed constant; else synthesize "(skip)" if optional; else exclude the command | same as `"close"` for tmux — it has FREE_TEXT, so `openPolicy` is never consulted |
| `open: false` (closed enum) | choices are the group, directly | fzf list only; no free-text path |
| `default` | preselection **and** pre-emission — total groups must emit something, and the emit≡omit contract licenses emitting the default | cursor preselection in the picker; an optional param left untouched emits nothing (the SDK/downstream default applies) |
| `initial` | preselection winner: groups preselect `initial ?? default` (the typing test preselects-and-emits 50 from `initial` with no `default`) | same preselection; never treated as a parse default |

### 1.4 Choice

| cmdson concept | karabiner argbuilder | tmux-oneshot |
|---|---|---|
| `value` | `ArgOption.value` (canonical string form) | the emitted token / row identity |
| `label` | `ArgOption.label`; falls back to the canonical value string | row display text; same fallback |
| `key` | `ArgOption.key` — the keycap. Profile requires every surviving choice to have one, unique across the node's whole surface (missing keys: §5.3) | unused |
| `description` | dropped — no room in the one-line group notification | appended to the fzf row (`  # …`) |
| `meta` | curation hooks (e.g. the choice a `meta.karabiner.omitChoices` entry names is removed from the group before budgets are checked) | reserved |

---

## 2. Dispatch contract

Canonical assembly output is the triple `(env, argv, cwd)` at the **token** level. Serialization
— quoting included — is a frontend duty; cmdson documents never contain shell quoting as data.

### 2.1 karabiner: bake-time projection → static manipulators → `karabiner_script` wrapper

The pipeline runs entirely at config-compile ("bake") time:

1. **Load + verdict.** The cmdson loader parses the doc, canonicalizes choices, and runs the
   karabiner profile (§4). Survivors project to an `ArgBuilder`.
2. **Project.** Each surviving param becomes an `ArgGroup`; `defaultKey` is the key of the
   `initial ?? default` choice (or the synthesized "(off)"/"(skip)" option). The `fire`
   callback implements the render semantics: for a selection it produces
   `script(exec[0], exec[1:] + tokens)` — tokens assembled per the normative order (exec,
   then non-env params in document order, then the flattened subcommand's tokens).
3. **Bake.** `argBuilderRules` expands the cartesian product of all groups into static ⏎
   manipulators, one per combination, each conditioned on its group variables. This is why
   budgets exist: the product is materialized in `karabiner.json`.

Execution path at fire time: the manipulator's to-event is the output of
`actionToTos(script(...))` → `karabiner_script(name, {args})` (from `macros.ts`). Contract with
the wrapper, as observed from `karabiner-typing-test`'s header and the `script` action shape:

- **argv, not a string.** `script.args` is a token array. The wrapper owns flattening it into
  the `shell_command` string and MUST shell-quote each token individually. cmdson-side
  projection never pre-quotes.
- **Environment.** The wrapper sets `REPO_LIB` and redirects output to
  `/tmp/karabiner.<script>/log.txt`. Karabiner's console-user-server spawns the command with a
  minimal environment and no meaningful cwd — hence the profile lacks CWD.
- **Env-bound params** require a wrapper extension: the projector hands the wrapper an env map
  per combination, and the wrapper prepends `VAR=value` assignments (each value quoted) to the
  command string it builds. Until that extension lands (§5.2), a doc with env-bound params gets
  an exclusion verdict on the karabiner profile.
- **Fire is one keystroke** (⏎, no confirmation) — this is what makes `effect: "destructive"` a
  bake-time gate rather than a UX prompt.

### 2.2 tmux-oneshot: run-time assembly → serialize → popup `eval`

The pipeline runs per invocation, inside a tmux popup (`<Prefix>C-k`):

1. **Pick.** fzfdb lists documents by `name` / `meta.tmux-oneshot.menuName`; preview shows the
   raw doc. A key argument skips the top-level menu (unchanged from today).
2. **cwd.** The doc's root `cwd` is tilde-expanded and `cd`'d before anything else — exactly
   today's `pwd` handling. A failed `cd` aborts.
3. **Assemble.** Interactive resolution walks the doc: optional flag-bound params through the
   multiselect (esc = none, today's semantics); required params, positionals, and env params
   prompt unconditionally; values come from a choices-fzf, free text, or both (`open: true`);
   typed input is validated with re-prompt; subcommand pick recurses (esc = abort). Output is
   the `(env, argv)` pair.
4. **Serialize.** `VAR=value` assignments first (values quoted as needed), then argv tokens
   joined with spaces, each token shell-quoted **iff it needs it** (the emitter MAY quote
   always). This single policy replaces the four legacy kv styles: they were exactly
   2 joins × quote-or-not, and the quote half is now emitter policy, not data.
5. **Execute.** `eval` the string in the popup zsh. Failure logs `rc` and always holds the
   popup; success dismisses immediately iff `meta.tmux-oneshot.autodismiss`, else holds until
   esc. All unchanged from today.

### 2.3 Responsibility matrix

| Responsibility | karabiner | tmux-oneshot |
|---|---|---|
| Assembly | bake time (all combinations) | run time (one path) |
| Value validation | validator/bake — no free input exists | validator/load for choices; runtime re-prompt for free text |
| Quoting | `karabiner_script` wrapper, per argv token | serializer, per token, at eval-string build |
| Env delivery | wrapper prepends assignments (extension required) | leading `VAR=value` assignments in the eval string |
| cwd | unsupported (exclusion verdict) | `cd` before eval |
| Failure surface | wrapper log file + Notification Center (script's own duty) | popup output held open + `log::err` |
| Destructive gate | bake-time exclusion unless opted in | policy (no autodismiss; confirm TBD §5.7) |

---

## 3. Migration plan

Both migrations follow the same shape: author the doc, build a loader/projector, prove parity
against today's behavior, cut over, delete the inline config. No frontend changes its UX.

### 3.1 `typing.ts` consumes a cmdson doc

Target: the hand-written `typingBuilder` in `typing.ts` (two inline groups, `WORD_OPTIONS`,
fire closure) is replaced by a bake-time projection of the `typing-test` document
(data-model §3b).

1. **Author the doc.** `typing-test` per the worked example: positional `action` with
   `default: "next"` and `meta.karabiner.omitChoices: ["status"]`; flag `--words`, `type: int`,
   `open: true`, `openPolicy: "close"`, `initial: 50` (no `default` — the `passage` CLI owns
   the true default). Lives with the dotfiles (proposal: `karabiner.ts/src/cmdson/`; shared
   location is §5.1).
2. **Build the projector.** A new module beside `argbuilder.ts` (`cmdson.ts`): parse →
   canonicalize → karabiner-profile verdicts (throwing at bake, the same failure mode
   `argBuilder`'s own key-uniqueness checks use today) → emit `argBuilder(name, title, groups,
   fire)` with `fire` implementing §2.1's render semantics.
3. **Parity gate.** Before cutover, a bake assertion compares the projected builder to the
   current hand-written one: identical group names, option keys/labels/values, `defaultKey`s,
   and — for all 3 × 4 = 12 combinations — identical `script` name + args
   (`karabiner-typing-test <action> --words <n>`, byte-for-byte). Delete the assertion after
   cutover.
4. **Cut over.** `typing.ts` loads the doc and registers the projected builder on `x`;
   the inline groups and fire closure are deleted.
5. **Keep the curated dict hand-written for now.** The direct bindings (`0/1/2/3` quick-fire
   word counts, `s` → status) are frontend curation of the same command, not part of the
   builder. They stay as hand-authored dict entries in v1; deriving them from the doc via a
   declared `meta.karabiner` quick-fire block is §5.5. Note `s: status` is precisely why
   `status` is a real choice in the doc but curated out of the builder — the spec models the
   script's contract, the meta models the keyboard surface.
6. **Verify live.** Re-bake, reload, smoke-test hyper+t → x: notification groups render, ⏎
   fires, `/tmp/karabiner.karabiner-typing-test/log.txt` shows the expected argv, esc clears.
7. **Follow-on: the `ctx` doc.** The context-picker family (data-model §3a) exercises env binds
   and flattening (3 × 10 = 30 manipulators). Preconditions for karabiner, both unverified:
   the wrapper env extension (§5.2), AND exec resolvability plus a smoke-run under the
   wrapper — `exec[0]` is `irun` (an interactive-shell wrapper) and the ctx functions do
   clipboard writes and sign in, none of it proven under karabiner's minimal no-tty
   environment. It can land on tmux-oneshot first.

### 3.2 tmux-oneshot consumes cmdson documents

Target: `commands.json` becomes a cmdson **database file** (a JSON array of documents, per the
data model); the interactive machinery is rebuilt around the render semantics. fzfdb stays —
cmdson is standalone and says nothing about how a frontend indexes or previews its documents.

1. **Dual-format db.** The loader distinguishes formats per element: an object with a `cmdson`
   key is a document; anything else is a legacy entry handled by today's code paths. The db
   migrates entry-by-entry; the legacy reader is deleted when the array is homogeneous (§5.8).
2. **Rewrite the assembler, don't adapt the docs down.** A cmdson→legacy-entry adapter would be
   cheaper but silently drops positionals, env hoisting, `required`, and typed validation —
   the features the migration exists to gain. The new `_assemble` walks the document per §2.2
   step 3 and returns `(env, argv)`; a new serializer implements step 4. The pure-renderer and
   seam structure of the current script (`_fzf`, `_read_value` stubs) carries over so the
   headless tests keep driving the interactive paths.
3. **Picker surface.** `list` / `menuitem` / `value` read `name`, `description`, and
   `meta.tmux-oneshot.{menuName,menuText}` — output identical to today's `menu.name` /
   `menu.text` behavior, including the `…` hint when a doc has params or subcommands.
4. **Preserved semantics.** esc at the optional-flags multiselect = no flags; esc at a
   subcommand pick or required prompt = abort; hold-until-escape on completion; autodismiss on
   success only; failures always hold.
5. **New semantics.** Required params cannot be skipped; positionals prompt in document order;
   env params render as leading assignments; free-typed values are validated
   (type/pattern/min/max) with re-prompt; choices with `open: true` offer list + free text.
6. **Migrate the live db.** Three entries: `killall NotificationCenter` and the hello demo are
   exec-only documents (plus `meta.tmux-oneshot.autodismiss` / root `cwd` respectively); the
   `ctx` family becomes the §3a document — its `ACTION` kv-flag turns into an env bind, moving
   the assignment from mid-line to line-front (behavior-equivalent; decision log #7).
7. **Verify.** Headless tests for each resolution path; manual popup run of all three migrated
   entries, confirming the `ctx` serialization `ACTION=login irun cXt`.

### 3.3 Sequencing

1. Validator core + karabiner/tmux profile checks (the migrations lean on its verdicts).
2. tmux-oneshot migration (run-time loader; cheapest iteration loop; no wrapper changes).
3. `typing.ts` migration (parity gate; no env binds needed).
4. `karabiner_script` env extension, then the `ctx` doc on karabiner.
5. Delete legacy: tmux legacy entry reader, typing.ts parity assertion.

---

## 4. Capability-tier negotiation

A frontend never guesses. It ships a **static profile** — a capability set plus budgets — and
runs the data model's degradation contract against every document, producing per-command and
per-branch **verdicts** with logged reasons. karabiner evaluates at bake time (a failed verdict
is absence from `karabiner.json`); tmux-oneshot evaluates at db-load time (absence from the
picker). The rules are the data model's, restated here as the evaluation order both frontends
and the validator share:

```
profile karabiner:    capabilities {}                      budgets {maxCombinations, maxChoicesPerGroup, keyAlphabet}
profile tmux-oneshot: capabilities {FREE_TEXT, RECURSION, CWD}   budgets none
```

Per document, in order:

1. **Value resolution.** For each param without FREE_TEXT: `open: true` resolves via
   `openPolicy` — `"close"` makes the choice list total; `"exclude"` marks the param
   unrenderable.
2. **Param ladder.** An unrenderable param: pre-emit its `default` as a fixed constant if it
   has one, required or not (emit≡omit licenses `default` only — never a bare `initial`,
   whose invisible emission would change semantics); else, if optional, synthesize a
   zero-token "(skip)" default option (reserved keycap `-`); else — required, no `default` —
   **command excluded**.
3. **Subcommands.** All branches bare → flatten to one synthetic choice group. Otherwise,
   without RECURSION each non-bare branch is **branch-excluded**; survivors are still offered;
   zero survivors → command excluded.
4. **Node gates.** Root `cwd` without CWD → command excluded. `effect: "destructive"` in an
   auto-firing frontend → command excluded unless the operator's profile config opts in.
5. **Budgets** (karabiner only, after curation via `meta.karabiner.omitChoices` and all
   synthesis above): every group ≤ `maxChoicesPerGroup`; every choice key ∈ `keyAlphabet` and
   unique across the node's whole surface; Π(group sizes) ≤ `maxCombinations`. Current usage
   calibrates the numbers: typing = 12 combinations, flattened ctx = 30 (§5.9).
6. **Report.** Every exclusion is one logged line:
   `excluded from <profile>: <command|branch> — <rule> (<detail>)`.

The validator ships the same named profiles (`cmdson validate --profile karabiner …`), so an
author learns a doc's fate on every frontend without baking or opening a popup — and so the
rule table has one home the frontends vendor rather than three drifting copies.

tmux-oneshot passes everything through this table today; its profile exists so that future
gates (and the `effect` policy) have a place to live, and so "supported everywhere" is a
checked claim, not an assumption.

---

## 5. Open questions

1. **Document home and discovery.** One shared database directory (e.g.
   `~/.config/cmdson/db/`) that both frontends read, or per-frontend copies
   (`karabiner.ts/src/cmdson/`, `~/.local/share/tmux_oneshot/`)? Shared is the point of
   cmdson; but karabiner needs docs at bake time in a repo it tracks, while tmux reads at
   runtime from XDG data. A likely answer: docs live in dotfiles, tmux's db path becomes a
   symlink — needs a decision before §3.3 step 2.
2. **`karabiner_script` env extension.** The wrapper macro currently takes `{args}` only.
   Exact shape of the env parameter, and where quoting of assignment values happens, must be
   settled in `macros.ts` before the `ctx` doc can pass the karabiner profile.
3. **Missing `Choice.key` on karabiner.** Deterministic auto-assignment from `keyAlphabet` in
   listing order, or a profile rule requiring explicit keys? Auto-assignment keeps docs terse
   but makes keycaps shift when a choice is inserted; explicit keys are stable but verbose.
   Leaning: profile requires explicit keys for v1 (matching today's hand-written configs);
   auto-assignment is additive later.
4. **Non-bare subcommand trees on karabiner.** v1 excludes such branches. The alternative —
   bake one builder per non-bare branch ("recursion by multiplication") — keeps more documents
   reachable but needs an entrypoint-key scheme and multiplies the manipulator count. Worth
   revisiting once a real doc hits the exclusion.
5. **Quick-fire curated bindings.** typing.ts's `0/1/2/3/s` dict entries duplicate doc
   knowledge (choice values, the status action). Should `meta.karabiner` grow a declared
   quick-fire block the bake consumes, or is hand-written curation fine forever?
6. **fzf free-text UX for `open: true`.** `--print-query` (accepted query wins when no row is
   picked) vs an explicit "(type a value)" sentinel row. `--print-query` is fewer keystrokes
   but ambiguous when the query prefixes a real row; the sentinel is unambiguous but adds a
   step. Prototype both in §3.2 step 2.
7. **`effect` policy in tmux-oneshot.** Destructive entries: confirm prompt before eval?
   Certainly never `autodismiss` — but is that a validator warning on the doc, or emitter
   behavior?
8. **Legacy-entry support window.** How long does tmux-oneshot's dual-format loader live?
   Proposal: one mechanical translation pass over the live db at migration time, legacy reader
   deleted in the same change — the db is personal and small.
9. **Budget numbers.** `maxCombinations` must admit today's 12 and 30. The numbers live in
   ONE home — the lint karabiner profile (`maxCombinations: 64`, `maxChoicesPerGroup: 10`,
   `keyAlphabet` = letters + digits) — and this plan references them rather than restating;
   tighten or loosen with evidence from real docs.
10. **emit≡omit auditing.** The contract licensing default pre-emission is a claim about the
    target CLI that no validator can check. Where is it attested — a doc-authoring checklist,
    or a `meta` note recording how it was verified (e.g. `ctx` functions default `ACTION` to
    `copy_env`; `passage` treats absent `--words` as its own default)?
11. **CWD on karabiner.** Teaching the wrapper to `cd` (root `cwd` only) would flip CWD into
    the karabiner profile and delete an exclusion rule. Cheap, but no current karabiner-bound
    doc needs it — do it when one does.
