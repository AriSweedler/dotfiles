import { Modifier, ToEvent, ToKeyCode, toApp } from "karabiner.ts"
import { karabiner_script } from "./macros.ts"

// Shared action vocabulary for AriMode dicts and argbuilder fire targets.
// The interactive argbuilder kind carries its own definition; its open/rule
// generation lives in argbuilder.ts so this module stays import-cycle-free.

// --- Types ---
export type Deeplink = { kind: "deeplink"; path: string }
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
export const deeplink = (path: string): Deeplink => ({ kind: "deeplink", path })
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
}
const to_key_code = (key: string): ToKeyCode => KEY_CODE_ALIASES[key] ?? (key as ToKeyCode)

// --- Rendering ---

// To-events for the fire-and-forget kinds. The interactive argbuilder kind
// and which_keyboard (needs per-device conditions) don't reduce to a plain
// to-list; callers dispatch those before falling through to here.
export const actionToTos = (action: Action): ToEvent[] => {
  switch (action.kind) {
    case "deeplink":
      return [{ shell_command: `open raycast://${action.path}` }]
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
