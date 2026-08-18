# cmdson

Commands via JSON. One declarative document fully defines a shell command —
name, subcommands (recursive), flags, positionals, env vars, typed values,
descriptions — and is obeyed by every consumer:

- **UI frontends** interactively BUILD a command from the spec, then dispatch
  it to a shell entrypoint. Two exist today, both in Ari's dotfiles:
  - `tmux-oneshot` (fzf in a tmux popup: free text, recursion, multiselect)
  - the karabiner argbuilder (one keycap per option; static commands baked as
    the cartesian product of finite choice groups — no free text)
- **SDKs** (planned) take the same document and parse argv into a typed
  object, docopt-direction: the spec drives the parser.
- **`cmdson-lint`** (planned) validates documents and answers "which
  frontends can actually serve this?" via named capability profiles.

The core idea: a document is a template for the invocation triple
`(env, argv, cwd)`. Five nouns — Command, Param, Bind, Value, Choice — and
everything else (quoting, menus, keycaps, degradation) is a consumer duty
computed from the spec, never guessed. JSON is primary; YAML is 1:1.

## Layout

| Path | What |
|---|---|
| `schema/cmdson.schema.json` | The meta-schema (JSON Schema 2020-12). Put `$schema` in your docs for editor validation. |
| `types/cmdson.d.ts` | TypeScript types, including the Selection / RenderTriple / ParseOutcome contracts. |
| `examples/` | The two worked examples: the `ctx` context-picker family and the hyper+t typing test. |
| `docs/01-spec.md` | The data model: normative render semantics, degradation contract, SDK parse contract, decisions log. |
| `docs/02-frontends.md` | Frontend integration plan: concept mapping, dispatch contract, migration plan, open questions. |
| `docs/03-sdks-and-validator.md` | cmdson-lint plan, SDK plans (TS reference, zsh helper), conformance fixture strategy, build sequencing. |
| `docs/05-prior-art.md` | Research digests: Fig/Amazon-Q specs, docopt / usage / carapace-spec, clap / cobra / argparse / click / oclif. |
| `docs/06-critique.md` | The completeness critique of the planning effort; its High/Medium fixes are already folded into the other docs. |

## Status

Planned, not built. The schema, types, and examples are real artifacts; all
code (lint, SDKs, frontend migrations) is plan-only. Build order and the
proof for each step: `docs/03-sdks-and-validator.md` Part 5.

## Two conscious deviations from the original brief (need Ari's sign-off)

1. **Usage strings are generated, never authored** — the brief asked for
   usage strings at every level; the model generates them from structure and
   round-trip-tests them, so help can never drift (decisions log #13).
2. **No parsing-function registry** — the brief asked for validation/parsing
   functions; the model closes the type list at `string|int|float` +
   constraints + `format` annotation instead, keeping documents pure data
   (decisions log #11).
