// cmdson v1 — TypeScript types. Structural mirror of schema/cmdson.schema.json;
// semantic rules (uniqueness, exclusivity, typed defaults) live in cmdson-lint.
// A document is a template for the invocation triple (env, argv, cwd).

/** A database file: an array of documents. */
export type Database = Document[]

/** The root Command plus the two root-only fields. */
export type Document = Command & {
  /** Spec major version. Loaders reject unknown majors. */
  cmdson: "1"
  /** Working directory for the invocation (~ allowed). Root only. */
  cwd?: string
}

/** The one recursive node. */
export interface Command {
  /** Parse identity: matched in argv, shown in menus. Unique among siblings. */
  name: string
  /** argv TOKENS to emit; default [name]. Never a shell string — quoting is a frontend duty. */
  exec?: string[]
  /** Keycap when offered as a subcommand choice in one-key frontends. */
  key?: string
  description?: string
  /** Max along the chosen path wins; auto-firing frontends refuse "destructive" unless opted in. Default "write". */
  effect?: "read" | "write" | "destructive"
  /** ORDERED — emission order = document order. Flags, positionals, and env vars in one list; bind discriminates. */
  params?: Param[]
  /** If present, exactly one MUST be chosen. Mutually exclusive with positional params on this node. */
  subcommands?: Command[]
  meta?: Meta
}

/** One value slot in the invocation. */
export interface Param {
  /** Typed-result key (argparse `dest`) and usage placeholder; never rendered. Unique per root→leaf path. */
  name: string
  /** WHERE the value lands. */
  bind: Bind
  description?: string
  /** Defaults are asymmetric, matching CLI reality: flag=false, env=false, positional=true. */
  required?: boolean
  /** Absent = presence-only switch (flag binds only; result: boolean). Present (even {}) = takes one value. */
  value?: Value
  meta?: Meta
}

export type Bind = FlagBind | PositionalBind | EnvBind

export interface FlagBind {
  at: "flag"
  /** Exact spelling, dashes included. Dash-less tokens are legal ("ACTION"). */
  token: string
  /** '--f v' vs '--f=v'. Render preference of the target CLI; parsers accept both. Default "space". */
  join?: "space" | "equals"
}

/** Order among positionals = document order. */
export interface PositionalBind {
  at: "positional"
}

/** Frontends WRITE a VAR=value prefix hoisted to the line front; SDKs READ getenv(var). */
export interface EnvBind {
  at: "env"
  /** Must match [A-Z_][A-Z0-9_]*. */
  var: string
}

/** The legal-value space. */
export interface Value {
  /** Closed list; booleans are switch-absence, enums are choices, the rest is `format`. Default "string". */
  type?: "string" | "int" | "float"
  /** Free annotation ("path", "email"); unknown formats degrade to the base type. */
  format?: string
  /** Anchored regex. Strings only. */
  pattern?: string
  /** Inclusive. int/float only. */
  min?: number
  /** Inclusive. int/float only. */
  max?: number
  /** Bare string "s" ≡ {value: "s"}; loaders canonicalize. */
  choices?: Array<string | Choice>
  /** Default: true iff choices absent. true = choices are suggestions; false requires choices. */
  open?: boolean
  /** No-free-text frontends only, when open=true: "close" = the list becomes the whole set there; "exclude" = mere examples, param unrenderable. Default "close". */
  openPolicy?: "close" | "exclude"
  /** PARSE-TIME injection when absent. Contract: emitting it ≡ omitting it (licenses finite-frontend pre-emission). */
  default?: string | number
  /** BUILD-TIME preselection only; parsers never inject it. Use when the downstream tool owns the true default. */
  initial?: string | number
  meta?: Meta
}

/** One enumerated value. */
export interface Choice {
  /** Emitted (canonical string form) and returned by SDKs; typed per the owning Value.type. */
  value: string | number
  /** Display text; falls back to the value. */
  label?: string
  /** Keycap for one-key frontends; unique across the node's key surface. `-` is reserved for synthesized options. */
  key?: string
  description?: string
  meta?: Meta
}

/** Opaque bags namespaced by frontend id; unknown namespaces are ignored.
 *  Known: "tmux-oneshot" {autodismiss, key, menuName, menuText, window}, "karabiner" {omitChoices, skipKey}. */
export type Meta = Record<string, Record<string, unknown>>

// ── Assembly & SDK contracts (docs/01-spec.md, normative) ──────────────────

/** One resolved user choice: what a frontend fires and what render() consumes.
 *  Switches are booleans; omitted optionals are absent keys. Symmetric with ParseOutcome. */
export interface Selection {
  /** Command names, root → leaf. */
  path: string[]
  values: Record<string, string | number | boolean>
}

/** render(doc, selection) output. argv starts with the exec tokens; quoting is the serializer's duty. */
export interface RenderTriple {
  env: Record<string, string>
  argv: string[]
  cwd?: string
}

/** spec.parse(argv, {env}) result. Parse input is argv after the invoking program; exec tokens are never parsed. */
export type ParseOutcome =
  | {
      ok: true
      path: string[]
      values: Record<string, string | number | boolean>
      /** Which source won per param. `initial` is never a source. */
      provenance: Record<string, "argv" | "env" | "default">
    }
  | { ok: false; errors: ParseError[]; usage: string }

/** Errors are data so frontends can render them natively. */
export interface ParseError {
  param?: string
  raw?: string
  message: string
  choices?: string[]
  path: string[]
}
