import { Modifier, ToEvent, ToKeyCode, toApp } from "karabiner.ts"
import { karabiner_script } from "./macros.ts"

// Shared action vocabulary for AriMode dicts and argbuilder fire targets.
// The interactive argbuilder kind carries its own definition; its open/rule
// generation lives in argbuilder.ts so this module stays import-cycle-free.

// --- Types ---
// A deeplink carries what the ari-raycast link widget needs (generate_bindings.ts): the path is the
// identity (its last segment, the command slug, is how the widget is addressed), title defaults
// to the slug title-cased, allowId is the key Raycast stores under alwaysAllowCommandDeeplinking
// once "Always allow" is clicked (ari-raycast link allow writes it).
export type Deeplink = {
  kind: "deeplink"
  path: string
  title: string
  keepFocus?: boolean
  allowId?: string
}
export type DeeplinkOptions = { title?: string; keepFocus?: boolean; allowId?: string }
export const deeplinkSlug = (path: string): string => path.split("/").filter(Boolean).pop() ?? path
export type Url = { kind: "url"; url: string; label?: string }
export type Script = { kind: "script"; name: string; args?: string[] }
export type App = { kind: "app"; name: string }
export type KeyCode = { kind: "key_code"; key_code: ToKeyCode; modifiers?: Modifier[]; description: string }
export type WhichKeyboard = { kind: "which_keyboard" }

export type ArgOption = { key: string; label: string; value: string }
export type ArgGroup = { name: string; label: string; options: ArgOption[]; defaultKey: string }
export type ArgBuilder = {
  kind: "argbuilder"
  id: string
  title: string
  groups: ArgGroup[]
  fire: (selection: Record<string, string>) => Action
}

export type Action = Deeplink | Url | Script | App | KeyCode | WhichKeyboard | ArgBuilder

// --- Constructors (the argbuilder constructor lives with its engine) ---
export const titleCase = (slug: string): string =>
  slug.split(/[-_]+/).filter(Boolean).map((w) => w[0].toUpperCase() + w.slice(1)).join(" ")
export const deeplink = (path: string, opts: DeeplinkOptions = {}): Deeplink => ({
  kind: "deeplink",
  path,
  title: opts.title ?? titleCase(deeplinkSlug(path)),
  ...(opts.keepFocus ? { keepFocus: true } : {}),
  ...(opts.allowId ? { allowId: opts.allowId } : {}),
})
export const url = (u: string, label?: string): Url => ({ kind: "url", url: u, label })
export const script = (name: string, args?: string[]): Script => ({ kind: "script", name, args })
export const app = (name: string): App => ({ kind: "app", name })
export const which_keyboard = (): WhichKeyboard => ({ kind: "which_keyboard" })
export const key_code = (key: string, modifiers: Modifier[], description: string): KeyCode => ({
  kind: "key_code",
  key_code: to_key_code(key),
  modifiers: modifiers,
  description: description,
})

// Karabiner key codes are names, not symbols. Map the symbols and aliases the
// dicts use to their key code names.
const KEY_CODE_ALIASES: Record<string, ToKeyCode> = {
  "=": "equal_sign",
  "-": "hyphen",
  "minus": "hyphen",
  "⏎": "return_or_enter",
  "return": "return_or_enter",
  "⌫": "delete_or_backspace",
  "delete": "delete_or_backspace",
  ",": "comma",
  ".": "period",
  "[": "open_bracket",
  "]": "close_bracket",
  "`": "grave_accent_and_tilde",
  ";": "semicolon",
  "'": "quote",
  "/": "slash",
  "\\": "backslash",
  "space": "spacebar",
}
export const to_key_code = (key: string): ToKeyCode => KEY_CODE_ALIASES[key] ?? (key as ToKeyCode)

// --- Rendering ---

// To-events for the fire-and-forget kinds. The interactive argbuilder kind
// and which_keyboard (needs per-device conditions) don't reduce to a plain
// to-list; callers dispatch those before falling through to here.
export const actionToTos = (action: Action): ToEvent[] => {
  switch (action.kind) {
    case "deeplink":
      // keepFocus adds -g so the front window stays frontmost: Raycast's window commands act on
      // whatever is in front, and a plain `open` activates Raycast first. Opt-in per action.
      return [{ shell_command: `open${action.keepFocus ? " -g" : ""} raycast://${action.path}` }]
    case "url":
      return [{ shell_command: `open ${JSON.stringify(action.url)}` }]
    case "script":
      return [karabiner_script(action.name, { args: action.args })]
    case "app":
      return [toApp(action.name)]
    case "key_code":
      return [{ key_code: action.key_code, modifiers: action.modifiers || [] }]
    default:
      throw new Error(`actionToTos cannot render this kind | kind=${action.kind}`)
  }
}

export const describeAction = (action: Action): string => {
  switch (action.kind) {
    case "key_code":
      return action.description || `key_code: ${action.key_code}`
    case "app":
      return `open app: ${action.name}`
    case "script":
      return `run script: ${[action.name, ...(action.args ?? [])].join(" ")}`
    case "deeplink":
      return `deeplink: ${action.path}`
    case "url":
      return `open url: ${action.label ?? action.url}`
    case "which_keyboard":
      return `notify keyboard name`
    case "argbuilder":
      return `builder: ${action.title}`
  }
}

// One owner for the notification help-bullet format, shared across layer
// notifications so they stay visually consistent.
export const helpLine = (key: string, desc: string) => `• \`${key}\` → ${desc}`
