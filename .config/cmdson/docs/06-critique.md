# cmdson completeness critique

Verified against the six frontend sources (all read in full) and the requirements re-read line by line. Findings ordered by priority; each has what/where/fix.

## High

1. **The degradation ladder for required params contradicts itself across all three documents.**
   - Data model (degradation table): an unrenderable **required** param → command excluded, unconditionally — even when it has a `default`.
   - Frontend plan §4 step 2: pre-emit `initial ?? default` **first**, for any unrenderable param; only "required, no preselection" excludes. So a required param with a default survives there.
   - Lint `CMD013` warns that `required: true` + `default` is "dead code" — false under the frontend plan, where that combination is precisely what rescues the param on karabiner.
   - Fix: pick one ladder (suggest the frontend plan's: preselection-first, required or not), quote it verbatim in the other two docs, and rewrite CMD013's rationale to "dead for parsers, live for finite-frontend pre-emission."

2. **The emit≡omit contract is defined only for `default` but cited to license pre-emitting `initial`.**
   - Data model: the contract is stated on `default` ("emitting the default explicitly MUST be semantically identical to omitting"). `initial` exists precisely because omission means *something else* (the downstream tool's own default — the typing-test case). Yet the ladder row "unrenderable optional param, has `initial`/`default` → pre-emit it as a fixed constant (legal by the emit≡omit contract)" — and frontend plan §4 step 2's `initial ?? default` — silently emit `initial` with no visible preselection, changing semantics versus omission by the model's own definition. (Visible-group preselection of `initial` is fine — the user sees and can change it; the invisible fixed-constant case is not.)
   - Fix: restrict fixed-constant pre-emission to `default`; an `initial`-only unrenderable param falls through to skip-synthesis or exclusion. (No current doc is affected — `--words` is renderable on karabiner — so the fix is free.)

## Medium

3. **The SDK parse contract never defines the argv frame: are `exec` tokens consumed?** `spec.parse(argv)` — does argv start after the program name (shell `$@` convention, exec never parsed), or include exec tokens (multi-token exec)? For the ctx doc (`name: "ctx"`, `exec: ["irun"]`) it is genuinely ambiguous what a conforming parse of `["cXt"]` vs `["irun", "cXt"]` returns. Usage generation includes exec tokens; parse says nothing. Fix: one sentence in the parse contract ("parse input is argv after the invoking program; exec tokens are render-only") plus a fixture.

4. **`Selection` is an undefined noun.** `render(doc, selection)`, `fire(selection)`, and the render fixtures all use ad-hoc shapes (`{action: "login", subcommand: "cXt"}`), but no schema exists: how nested subcommand choices at depth >1 are keyed, whether `subcommand` collides with a param literally named `subcommand`, how switches (bool?) and omitted optionals are represented. Fix: define Selection in the render-semantics section (e.g. `{path: [...names], values: {paramName: typedValue}}` — symmetric with ParseOutcome).

5. **The two plans contradict each other on the tmux migration strategy.** Frontend plan §3.2 step 2 explicitly rejects a cmdson→legacy-entry adapter ("silently drops positionals, env hoisting, required, typed validation"); SDK plan Part 5 step 5 builds exactly that ("a converter emitting today's entry schema first; native cmdson reading second"). Fix: make step 5 the frontend plan's rewrite, and drop its "all four quoting styles" byte-parity proof (the new quote-iff-needed serializer deliberately does not reproduce `equals-quoted` byte-for-byte).

6. **Conformance fixture 8 contradicts the normative render semantics.** Part 4 pins the typing render triple as `["previous", "--words", "100"]` — missing the `exec` token — while the same fixture list includes `"irun"` in the ctx triple, and the model's `render()` says argv starts with `node.exec` tokens. As written, the most load-bearing golden file would pin the wrong string. Fix: `["karabiner-typing-test", "previous", "--words", "100"]` (the karabiner projection then maps argv[0]→script name, rest→args).

7. **Karabiner budget numbers disagree: 48 vs 64.** Frontend plan §5.9 proposes `maxCombinations: 48`; lint plan §1.3 ships `maxCombinations: 64`. Both docs claim the profile table has "one home the frontends vendor." Fix: one number, declared in the lint profile, referenced (not restated) by the frontend plan.

8. **The validator as planned is not "simpler than either frontend," and the plan's structural argument doesn't rescue it.** tmux-oneshot is a 285-line zsh script; `cmdson-lint` specifies 5 layers, ~20 stable rule IDs with severities and rationales, JSON-pointer findings, two output formats, `--explain` with minimal failing examples per rule, profile verdict taxonomy, `--profile-config`, and a 4-code exit convention. That is over-designed for a personal-tooling spec regardless of how thin the CLI shim is. Fix: v1 = schema check + semantic errors + profile verdicts, plain-text output, exit 0/1; defer `--explain`, `--rules`, JSON output, and configurable budgets.

9. **ctx-on-karabiner feasibility is asserted, not examined.** Frontend plan §1.1 requires `exec[0]` to resolve to a `karabiner_script`-known script; §3.1.7 and data model §3a promise 30 manipulators blocked only on the env-wrapper extension. But `exec[0] = "irun"` is the interactive-shell wrapper, and the ctx functions (clipboard writes, sign in) run in karabiner's minimal, no-tty environment — unverified that any of it works there. Fix: add "exec resolvability + smoke-run under the wrapper" as an explicit precondition in §3.1.7 rather than treating the env extension as the sole blocker.

## Low

10. **YAML "trivially supported" is undecided at the edges and untested.** No YAML fixture exists anywhere in Part 4 (all `spec.json`), and YAML implicit typing breaks the claim: `cmdson: 1` parses as a number, choice values like `no`/`50` shift type. Fix: one YAML conformance case plus a stated scalar-mapping rule in the canonicalizer.

11. **No database-scope identity rules.** CMD001 covers sibling names *within* a document; nothing requires root `name` / `menuName` uniqueness across a database file (tmux's `_key_to_index` silently takes the first match), and the source's constraint that `menu.name` must not contain `" | "` appears in no rule. Fix: a database-level lint rule (unique root key = `menuName ?? name`; character ban) in the tmux profile.

12. **Parse edge cases undefined.** Repeated non-repeatable flag (error vs last-wins — note today's script is last-wins for positionals, so migration step 7's "behavior unchanged" proof is slightly false at the edges); a positional value colliding with a declared flag token; no `--` end-of-options convention. Fix: one sentence each in the parse contract (suggest: repeat = error, flags match before positional fill, no `--` in v1) + fixtures.

13. **Keys for synthesized options are unassigned.** The "(off)"/"(on)" switch pair and the "(skip)" option need keycaps and become group defaults, but open question §5.3 only covers authored choices, and its leaning ("require explicit keys") cannot apply to options the author never wrote. Fix: reserve fixed keys for synthetics (or a `meta.karabiner` slot), decided before sequencing step 1.

14. **`meta.karabiner.omitChoices` can orphan the default.** CMD030 checks that omitted values exist, but nothing prevents curating out the `default`/`initial` choice (or every choice), which breaks `defaultKey` at bake. Fix: extend CMD030 — the surviving set must be non-empty and contain the preselection.

15. **Preselection asymmetry is an unstated decision.** Flattened subcommand groups default to the *first* entry, but param choice groups require an explicit `initial`/`default` or fail the karabiner profile. Fix: either allow first-choice defaulting for closed param groups too, or state the asymmetry and why.

16. **Two requirement phrases were consciously inverted — confirm they're blessed.** The brief asks for "usage strings at every level" (model: generated, never authored — decision #13) and "validation/parsing functions" (model: closed type list, parser registry rejected — decision #11). Both are argued, and both are defensible, but they are deviations from the literal brief, not coverage of it — the owner should sign off explicitly.

17. **Over-design rollup.** Part 3 type generation has no named consumer (the only TS consumer, `typing.ts`, loads docs directly; the only SDK consumer is a zsh script); the Python SDK has no named consumer; the `(number & {})` widening and blessed-regeneration ceremony are gold-plating. Also a scoring-consistency note: P3's capability algebra was dinged as "a second spec," then the synthesis adopted machinery of comparable weight (capability sets, budgets, ladder, OK/DEGRADED/EXCLUDED verdicts, profile-config). Fix: gate Part 3 and Python behind a named consumer exactly the way Rust already is.

## Genuinely complete

Verified against source, the following are correct and fully covered: the karabiner ground truths (static bake via cartesian product, argv-list `script(name, args)` fire, mandatory `defaultKey`, cross-group key uniqueness, esc/⏎ semantics, `status` outside the builder); the tmux ground truths (four kv styles = 2 joins × quoting, top-level-only `pwd`, esc semantics, `autodismiss`, menu override, `eval` dispatch, dash-less `ACTION` kv); both env-var directions from one bind; boolean-vs-kv via value presence; option enumerations with open/closed; positionals; descriptions at every level; JSON-primary serialization; and the prior-art adopt/reject ledger. The two worked examples are faithful to today's behavior (typing-test's `--words`-with-`status` leniency and `words_requested=""` passthrough both check out against the script).
