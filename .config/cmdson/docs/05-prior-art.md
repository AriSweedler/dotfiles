# Prior art survey

Three research digests from the planning workflow (2026-08-18). Each ends with the
STEAL LIST the synthesis drew from; the adopt/reject decisions live in docs/01-spec.md §4.

---

# Fig Autocomplete Spec (now Amazon Q CLI completion specs) — Research Digest

Source of truth: `Fig` TypeScript namespace in `withfig/autocomplete-tools` (`types/index.d.ts`, 1300 lines, fetched verbatim; saved at `fig-types.d.ts`), plus fig.io docs via search. Web access succeeded; all field names below are exact quotes from the .d.ts.

## 1. Data model

**Three structural objects + one presentation object.** `Subcommand` and `Option` extend `BaseSuggestion`; `Arg` does not (it represents free user input, not a selectable token).

**`BaseSuggestion`** (shared presentation layer): `displayName?` (UI label; `name` stays the parse token), `insertValue?` (text inserted on accept; supports `\n`, `\b`, and a `{cursor}` placeholder for post-insert caret position), `replaceValue?`, `description?`, `icon?` (1-char string, URL, or `fig://icon?type=...` protocol), `isDangerous?` (disables auto-execute, red icon), `priority?` (0–100, default 50; engine blends with recency: previously-selected items get timestamp added as a decimal, bands 49-/50–75/76+ control whether spec ranking can be overridden), `hidden?` (only shown on exact-name match), `deprecated?: boolean | BaseSuggestion` (can carry a replacement `insertValue` + reason).

**`Suggestion extends BaseSuggestion`**: `name?: string | string[]` (prefix-filter key), `type?: "folder"|"file"|"arg"|"subcommand"|"option"|"special"|"mixin"|"shortcut"` (drives default icon + auto-execute eligibility).

**`Subcommand extends BaseSuggestion`** (recursive skeleton): `name: string | string[]` (aliases as array — must match typed text exactly), `subcommands?: Subcommand[]`, `options?: Option[]`, `args?: Arg | Arg[]`, `requiresSubcommand?`, `filterStrategy?: "fuzzy"|"prefix"|"default"`, `additionalSuggestions?: (string|Suggestion)[]`, `loadSpec?` (lazy-load another spec by name/object/async fn — used to split `aws` into per-service files and to alias wrappers to wrapped tools), `generateSpec?` (async fn returning a Spec, merged in — for plugin-extensible CLIs), `generateSpecCacheKey?`, `cache?`, `parserDirectives?: { flagsArePosixNoncompliant?, optionsMustPrecedeArguments?, optionArgSeparators?: string|string[] }`.

**`Option extends BaseSuggestion`**: `name: string | string[]` (e.g. `["-m","--message"]` — aliases collapse into one entry), `args?: Arg | Arg[]` (**this is how options declare arguments** — presence of even an empty `{}` arg object tells the parser the next token belongs to the option; absence means flag), `isPersistent?` (inherited by all child subcommands, cobra-style), `isRequired?`, `isRepeatable?: boolean | number` (max count enforced at parser level; beyond it the token reparses as a positional), `requiresSeparator?: boolean | string` (must use `--opt=value` or `--opt:value`; supersedes deprecated `requiresEquals?`), `exclusiveOn?: string[]` (names of options this conflicts with — engine hides them once this is typed), `dependsOn?: string[]` (unmet dependencies get boosted priority in suggestions).

**`Arg`** (positional/option argument): `name?` (human-readable placeholder only — never parsed), `description?`, `isOptional?` (default mandatory: engine forces input and hides sibling suggestions), `isVariadic?`, `optionsCanBreakVariadicArg?` (default true), `isDangerous?`, `default?`, `suggestions?: (string|Suggestion)[]` (static), `template?: "filepaths"|"folders"|"history"|"help"` (prebuilt generators), `generators?: Generator | Generator[]`, `filterStrategy?`, `suggestCurrentToken?`, `debounce?`, `isCommand?` (restart completion as a new command, e.g. `sudo`, `time`), `isScript?`, `loadSpec?`, `parserDirectives?: { alias }` (expand token like `git p` → `push` and re-parse).

**`Generator`** (dynamic suggestions for an Arg): `script?: string[] | fn(tokens)→string[]` (shell command run in user's cwd), `postProcess?(out, tokens) → Suggestion[]`, `splitOn?` (sugar: split stdout, one suggestion per line), `custom?(tokens, executeCommand, generatorContext) → Promise<Suggestion[]>` (script+postProcess combined), `template?` + `filterTemplateSuggestions?`, `trigger?` (when to regenerate mid-token — string, fn(newToken, oldToken), or `{on: "change"|"threshold"|"match"}`), `getQueryTerm?` (which slice of the token filters, e.g. text after last `/` for `cd`), `scriptTimeout?`, `cache?: { strategy: "max-age"|"stale-while-revalidate", ttl, cacheByDirectory?, cacheKey? }`.

## 2. Design choices that make it UI-friendly

- **Parse identity vs presentation split**: `name` is byte-exact what the user types (parser key); `displayName`, `description`, `icon` are pure UI. Every renderable node shares one `BaseSuggestion` shape, so the popup renders one uniform object type — Subcommand/Option "compile down to" Suggestion.
- **Static-first, dynamic-escape-hatch**: the skeleton is plain declarative data (JSON-serializable minus functions); dynamism is isolated in three well-marked slots (`generators`, `loadSpec`, `generateSpec`) with explicit caching contracts.
- **Parser semantics live in the spec**, not the UI: `isOptional`, `isVariadic`, `isRepeatable`, `requiresSeparator`, `parserDirectives` let a generic engine tokenize any CLI without per-tool code.
- **Suggest/filter split**: suggestions regenerate per-token; keystrokes only filter cached results (`trigger`/`getQueryTerm` override this) — cheap and responsive.
- **Safety modeled as data**: `isDangerous` gates auto-execute; `hidden` keeps valid-but-obscure tokens parseable without cluttering the list.
- **Insertion is richer than the token**: `insertValue: "-m '{cursor}'"` scaffolds the next input.

## 3. STEAL LIST for a command-building spec

- `name` (exact token, `string | string[]` for aliases) vs `displayName` vs `description` — three distinct fields, never conflated.
- Options declare args via `args: Arg | Arg[]`; empty `{}` = "takes a value"; flag = no `args`.
- `isOptional` on Arg (mandatory-by-default), `isRequired` on Option (optional-by-default) — asymmetric defaults matching CLI reality.
- `isVariadic`, `isRepeatable: boolean | number`, `requiresSeparator: boolean | string`, `isPersistent`.
- `exclusiveOn` / `dependsOn` as string arrays of option names — cheap declarative constraint graph a form UI can use to disable/require fields.
- Arg `suggestions` (static) + `generators` (script → postProcess, with `cache {strategy, ttl}` and `debounce`) + `template` (prebuilt common cases: filepaths/folders/history).
- `default` on Arg; `insertValue` with `{cursor}`; `priority` band semantics; `hidden`; `deprecated` with replacement; `isDangerous` gating auto-execute.
- `filterStrategy: "fuzzy"|"prefix"|"default"` per node; `loadSpec` for lazy modular specs.

## 4. What to avoid

- Arbitrary JS functions embedded in the data model (`custom`, `postProcess`, `trigger` fns) — kills serializability/portability; Fig needed a whole build+hosting pipeline because specs are code. Prefer declarative equivalents (`splitOn`, trigger objects) which Fig itself added as sugar.
- Deprecated/overlapping fields accreted over time: `requiresEquals` vs `requiresSeparator`, `isModule` vs `loadSpec`, `isCommand`/`isScript` as sugar variants — pick one orthogonal mechanism.
- Overloaded `name` semantics: Arg.name is display-only while Subcommand/Option.name is parse-critical — same field name, opposite contracts; the JSDoc repeatedly warns "read carefully". Use distinct field names.
- Magic priority/recency blending baked into the engine (timestamp-as-decimal) — opaque; keep ranking policy out of the data model.
- `_internal?: Record<string, unknown>` backdoor and shell-execution (`executeCommand`) coupled into the spec surface.

Sources: [withfig/autocomplete-tools types/index.d.ts](https://github.com/withfig/autocomplete-tools/blob/main/types/index.d.ts), [withfig/autocomplete README](https://github.com/withfig/autocomplete/blob/master/README.md), [fig.io first completion spec docs](https://fig.io/docs/getting-started/first-completion-spec)


---

# Prior Art Digest: Spec-First CLI Definition Systems

Research via live web fetch of docopt README, usage.jdx.dev spec reference, and carapace-sh docs (all succeeded; carapace macro sub-pages partially truncated, filled from knowledge where noted).

## (a) docopt — usage string IS the spec

**Data model:** No structured schema; the help text itself is parsed into a pattern tree.
- **Usage section grammar:** `<arg>` or `UPPERCASE` = positional; lowercase bare words = subcommands; `-s`/`--long` = options (`--input=FILE` / `-i FILE` take values). Composition operators: `[ ]` optional, `( )` required group, `|` alternatives, `...` repeat (one-or-more), `[options]` = "any declared option", `[--]` positional/option separator, `[-]` stdin convention. Multiple `Usage:` lines = alternative invocation patterns (implicit top-level `|`).
- **Options section:** lines starting with `-`; declares short/long synonyms (`-o FILE --output=FILE`), whether an option takes an argument (word after space/`=`), description after two spaces, and defaults via `[default: value]` embedded in the description. Repeatable options with defaults split into lists.
- **Parsing:** argv is tokenized, then pattern-matched against the tree (backtracking match of alternatives/groups). Output is a flat dict keyed by the exact spelling in the help text (`--speed`, `<name>`, `ship`): booleans for flags/commands, strings for valued options, ints for counted flags (`-v...`), lists for repeated elements.
- **No types/validators** beyond structure — everything is a string; validation is deliberately left to user code. Help text generation is inverted: help is the source, so it's always in sync by construction.

## (b) usage (jdx, KDL)

**Data model:** structured KDL document, purpose-built to drive completions + docs + man pages + JSON/JSON-Schema export + parsing (mise uses it).
- **Top level:** `name`, `bin`, `version`, `about`, `author`, `license`, `config_file`.
- **`flag` node:** identity string encodes forms + value: `flag "-u --user <user>"`. Attributes: `help`/`long_help` (multiline), `hide`, `deprecated`, `global` (inherited by subcommands), `count` (bool→int occurrences), `negate="--no-color"`, `env="MYCLI_USER"` (env fallback), `config="settings.user"` (config-file fallback), `default`, `default_missing` (value when flag present without arg), `var`/`var_min`/`var_max` (repeatable with bounds), `delimiter=","`, `require_equals`, `allow_hyphen_values`; relations: `required_if`, `required_unless`, `requires`, `conflicts`, `overrides`, `exclusive`; enum via child node `{ choices "bash" "zsh" "fish" }`.
- **`arg` node:** required/optional encoded in brackets — `arg "<dir>"` vs `arg "[file]"`; plus `help`, `default`, `choices`, variadic.
- **`cmd` node:** nestable, `help`, multiple `alias` (each hideable), child flags/args, and **`effect="read"|"write"|"destructive"`** — a safety classification (max effect along the invocation path wins) for agent/tool gating.
- **Dynamic values:** top-level `complete "<name>" run="mycli plugins list"` binds a completion source to any arg/flag by name; or `type="file"|"dir"|"path"|"config_keys"|"config_values"`. `run` scripts get Tera template vars (`words`, `CURRENT`, `PREV`) enabling context-dependent completion (`run="ls modules/{{words[PREV]}}/controllers"`); `descriptions=#true` uses `value:description` output format. `type` and `run` mutually exclusive.
- **Help/docs:** generated from the spec (CLI reference markdown, man, completions for 4 shells, typed SDKs).

## (c) carapace-spec (YAML)

**Data model:** Cobra-shaped Command struct in YAML, completion-first but also executable.
- **Command fields:** `name`, `aliases`, `description`, `group`, `hidden`, `parsing` (interspersed / non-interspersed / disabled — controls whether flags may follow positionals), `flags`, `persistentflags` (inherited), `exclusiveflags` (mutual-exclusion groups as lists), `run`, `completion`, `commands` (recursive).
- **Flag encoding:** map where the *key* carries the whole shape — `"-r, --repeatable*"`, `"--optarg?"`, `"-v="` — suffix modifiers: `=` requires value, `?` optional value, `*` repeatable, `!` required; map value is the description. Extremely compact.
- **Completion block:** `flag:` (per-flag-name → list of values), `positional:` (ordered per-position lists), `positionalany:` (all remaining), `dash:`/`dashany:` (after `--`). Values are strings with tab-separated enrichment: `"two\twith description"`, `"three\twith description\tblue"` (value, description, style/color).
- **Macros as value sources:** `$files([.go])`, `$directories`, `$message(...)`, `$(shell command)` exec, `$list(,)`, modifiers like `$chdir`, `$nospace`, `$uniquelist` (per docs index; detail pages truncated — from knowledge), `$carapace.*` bridging to carapace-bin's library of named completers; brackets optional when no args. Exec'd scripts receive context env vars (current word etc.).
- **`run`:** makes the spec executable, not just descriptive — a shell snippet or `[alias-target, args]` redirection, so one YAML file can define both a real command wrapper and its completions.

## STEAL LIST — for a JSON command-definition spec consumed by UIs and argv parsers

1. **Single identity string parsed into structure** (usage/carapace): accept `"-u, --user <user>"` as authorable shorthand, but store canonically as `{short, long, aliases, value: {name, required}}` — JSON consumers should never re-parse strings.
2. **`choices` as first-class enum** on both flags and args (usage) — UIs render dropdowns, parsers validate membership, completion is free.
3. **Layered value resolution:** `default` < `config` key < `env` var < argv (usage's `env=`/`config=` attributes) — declare all sources in the spec so UIs can show provenance.
4. **Dynamic value sources as tagged objects** (union of carapace macros + usage `complete`): `{"source": "file"|"dir"|"static"|"exec", "run": "...", "cache_ttl": ...}` with template context (`words`, `PREV`) for position-dependent suggestions.
5. **Value+description+style triples** for every suggestion (carapace's `\t` convention → explicit JSON fields) — UIs get rich menus, shells get plain values.
6. **Relational constraints:** `requires`, `conflicts`, `required_if/unless`, `overrides`, `exclusive`, and exclusive *groups* (usage + carapace `exclusiveflags`) — declarative enough for both a form validator and a parser.
7. **Repeat semantics:** `count` (occurrences→int), `var_min/var_max` bounds, `delimiter` splitting, and docopt's typed result shapes (bool/string/int/list) as the parser's output contract.
8. **`effect: read|write|destructive`** (usage) — command safety classification; ideal for agent permissioning and UI confirmation prompts.
9. **Positional model:** ordered per-position specs + a `rest`/`positionalany` bucket + explicit post-`--` (`dash`) section (carapace) — richer than argc-style variadics.
10. **`global`/persistent flags** inherited down the subcommand tree, and hideable aliases/deprecation metadata for help vs completion divergence.
11. **Docopt's inversion as a check:** generate help text deterministically from the spec (never hand-written), and round-trip test: parse the generated usage line back to the same structure.
12. **Parsing-mode switch** (`interspersed`/`non-interspersed`/`disabled`, carapace) for wrapper commands that pass through trailing argv.


---

# Prior Art: Type Systems in Mainstream Argument Parsers

## clap (Rust)

**Type system.** Each `Arg` carries a `value_parser` — a typed string→T converter. Built-ins via `value_parser!(T)`: any `FromStr` type, `bool`, `PathBuf`, ranged numerics (`value_parser!(u16).range(1..=65535)`), `BoolishValueParser` (accepts yes/no/true/false/1/0), `PossibleValuesParser` (string choices), and `EnumValueParser` from the `ValueEnum` derive (enum variants become kebab-case possible values, auto-listed in help and completions). Custom `TypedValueParser` impls are first-class. Separately, `ValueHint` is a *completion-only* annotation, not validation: `AnyPath, FilePath, DirPath, ExecutablePath, CommandName, CommandString, Username, Hostname, Url, EmailAddress`. Clap deliberately splits "what shell should suggest" from "what parser validates."

**Validation-as-parsing.** The parser runs during `get_matches()`; results are stored typed, retrieved with `matches.get_one::<T>("name")`. Errors are structured: offending flag, raw value, possible values, and "did you mean" suggestions, rendered consistently.

**Env.** `.env("MY_VAR")` per arg; precedence is CLI > env > `default_value`. `default_missing_value` covers "flag present, no value given" (e.g. `--color` → `always`).

**Arity.** `num_args(range)` (fixed, ranges, `0..=1`), `ArgAction::Append` (repeatable), `ArgAction::Count` (`-vvv` → u8), `value_delimiter(',')` for in-token splitting, `ArgAction::SetTrue/SetFalse` for flags.

**Relations.** `conflicts_with`, `requires`, `requires_if`, `required_unless_present`, `overrides_with` (last-wins), and `ArgGroup` (a named set; `multiple(false)` = mutual exclusion, `required(true)` = exactly-one).

**Usage.** Auto-generated from the spec: required `<ARG>`, optional `[ARG]`, variadic `[ARG]...`, `[OPTIONS]` summary; `value_name` is the metavar; doc comments become help in the derive API (struct field → flag; `Option<T>` = optional, `Vec<T>` = repeatable, `bool` = SetTrue).

## cobra + pflag (Go)

**Type system.** pflag registers concretely typed flags: `String/Int/Bool/Float64/Duration/IP/IPNet/BytesHex`, slices (`StringSlice` splits on commas + repeats; `StringArray` repeats only — a deliberate two-mode arity design), maps (`StringToString`), `Count`. Anything else implements the `pflag.Value` interface: `String() string`, `Set(string) error`, `Type() string` — `Set` returning error *is* the validation contract; `Type()` feeds the help placeholder.

**Positionals.** cobra `Args` validators: `ExactArgs(n)`, `MinimumNArgs`, `MaximumNArgs`, `RangeArgs`, `OnlyValidArgs` against `ValidArgs` (choices), composable with `MatchAll`.

**Relations.** `MarkFlagRequired`, `MarkFlagsRequiredTogether`, `MarkFlagsMutuallyExclusive`, `MarkFlagsOneRequired`.

**Env.** Not built in; the viper convention layers precedence: explicit flag > env > config file > default (`viper.BindPFlag`).

**Usage/completion.** Templated `UsageTemplate()`; `FlagUsages` prints `--flag type` from `Type()`; `NoOptDefVal` = value when flag given bare; `MarkFlagFilename(ext...)`/`MarkFlagDirname` annotate completion (file/dir hints as metadata, like clap's ValueHint).

## Python argparse

`add_argument(flags..., action, nargs, const, default, type, choices, required, help, metavar, dest)`. `type=` is **any callable** str→value; raising `ValueError`/`ArgumentTypeError` yields "invalid <typename> value: …" — the purest validation-as-parsing design. `choices` is checked *after* type conversion (so choices can be typed values). `metavar` controls display; `dest` decouples storage key from flag spelling. `nargs`: `N`, `'?'` (with `const` for bare-flag), `'*'`, `'+'`, `REMAINDER`. Actions: `store`, `store_true/false/const`, `append`, `append_const`, `count`, `extend`, `BooleanOptionalAction` (auto `--foo/--no-foo`). No env support (idiom: `default=os.environ.get(...)`, which breaks `required` interplay). Mutual exclusion via `add_mutually_exclusive_group(required=)`; **no built-in "requires"** — a known gap people patch post-parse. Usage strings auto-derived by `HelpFormatter` from nargs/required/metavar.

## click (Python)

**Type system.** `ParamType` objects: `STRING, INT, FLOAT, BOOL, UUID`, `Choice(values, case_sensitive)`, `IntRange(min, max, clamp)`, `FloatRange`, `DateTime(formats)`, `File(mode, lazy)` (opens it), `Path(exists, file_okay, dir_okay, readable, writable, executable, resolve_path, path_type)` — the richest filesystem type anywhere — and `Tuple([types])` for heterogeneous nargs. Custom types subclass `ParamType` and implement `convert(value, param, ctx)` → value or `self.fail(msg)`; the same type also powers shell completion and metavar.

**Env.** `envvar='X'` (or list, first-set wins) per param, plus `auto_envvar_prefix` (`PREFIX_SUBCMD_OPTION`); precedence CLI > env > prompt > default. `prompt=True` (`hide_input`, `confirmation_prompt`) makes interactive fallback part of the value-resolution chain. `show_default`/`show_envvar` surface both in help.

**Arity.** `multiple=True` → tuple (repeatable), `count=True`, `nargs=N` per occurrence, `nargs=-1` variadic positional; boolean pairs `'--shout/--no-shout'`; `flag_value` groups several flags into one dest. No built-in mutual exclusion/requires (ecosystem: cloup, click-option-group). Usage auto-built from params; metavar defaults to the type's name.

## oclif (TypeScript)

Flags are typed at definition: `Flags.string/boolean/integer({min,max})/url` (parses to `URL`), `Flags.file({exists})`, `Flags.directory({exists})`, and `Flags.custom<T>()` with an async `parse(input, ctx) => T`. Per-flag: `char`, `options` (choices), `multiple` (+ `delimiter`), `env`, `default` (value **or** async function), `defaultHelp`, `required`, `allowNo` (boolean negation), `hidden`, `summary/description`, `helpValue` (metavar), `helpGroup`. Relations are the most complete set: `dependsOn: []`, `exclusive: []`, `exactlyOne: []`, and `relationships: [{type: 'all'|'some'|'none', flags}]` with predicate support. Args mirror flags (`Args.string/file/directory/url/integer/custom`). Precedence: flag > env > default.

**JSON manifest.** `oclif manifest` emits `oclif.manifest.json`: per-command id/description/examples plus a flags map — but types collapse to only `"option" | "boolean"` with `options`, `multiple`, `char`, `env`, `dependsOn`, `exclusive`, `required`. The rich types (integer bounds, file-exists, custom parsers) are **erased** because they live in code. Key lesson: keep types declarative data, or the manifest can't reproduce the parser.

---

## STEAL LIST — for a JSON command spec

- **Value kinds** (declarative, data-only): `string`, `boolean` (with `negatable` for `--no-x`), `integer`/`number` with `minimum`/`maximum` (clap range, click IntRange), `enum` with `values` (ValueEnum/Choice/options), `count` (-vvv), `duration` (pflag), `datetime` with `formats` (click), `map` key=value (StringToString).
- **Resource kinds with checks + completion hints**: `path {kind: file|dir|any, exists?, readable?, writable?, resolve?}` (click Path ⊃ oclif file/directory ⊃ clap ValueHint) and `url`; the kind drives both validation and shell completion.
- **Parsing contract**: every raw string passes one converter → typed value **or** structured error `{param, rawValue, message, possibleValues?, suggestion?}` (argparse callable, pflag `Set() error`, click `convert/fail`, clap error model).
- **Arity**: `arity: {min, max}` unifying nargs/num_args; `repeatable: append|count|last-wins` (clap `overrides_with`); `delimiter` for in-token splitting; pflag's slice-vs-array split = `delimiter` present/absent.
- **Value resolution**: explicit > env > default (universal); `env: [names]` (list, click), `defaultMissingValue` for bare-flag (`NoOptDefVal`/argparse `const`); `default` typed, optionally described (`defaultHelp`); `showDefault`/`showEnvVar` flags.
- **Relations**: `requires: []`, `conflictsWith: []`, plus group-level `{members, exactlyOne|atMostOne|allOrNone|atLeastOne}` (ArgGroup + cobra's four Marks + oclif relationships — group form covers argparse's gap).
- **Presentation**: `metavar` (`helpValue`/`value_name`), `hidden`, `deprecated`, `helpGroup`, `dest` (storage key ≠ flag spelling), auto-usage grammar `<required> [optional] [variadic...]`.
- **oclif's cautionary lesson**: no executable parse functions in the spec — every kind must be reconstructible by any SDK from JSON alone; provide an escape hatch as `kind: string` + `format` annotation rather than embedded code.
