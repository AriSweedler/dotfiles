import { Modifier, ToEvent, ToKeyCode, toApp } from "karabiner.ts"
import { karabiner_script } from "./macros"

// Shared action vocabulary for AriMode dicts, submenu entries, and argbuilder
// fire targets. The interactive kinds (submenu, argbuilder) carry their own
// definitions; their open/rule generation lives in submenu.ts / argbuilder.ts
// so this module stays import-cycle-free.

// --- Types ---
export type Deeplink = { kind: "deeplink"; path: string }
export type Url = { kind: "url"; url: string; label?: string }
export type Script = { kind: "script"; name: string; args?: string[] }
export type App = { kind: "app"; name: string }
export type KeyCode = { kind: "key_code"; key_code: string; modifiers?: Modifier[]; description: string }
export type WhichKeyboard = { kind: "which_keyboard" }
export type Submenu = { kind: "submenu"; id: string; title: string; entries: Record<string, Action> }

export type ArgOption = { key: string; label: string; value: string }
export type ArgGroup = { name: string; label: string; options: ArgOption[]; defaultKey: string }
export type ArgBuilder = {
  kind: "argbuilder"
  id: string
  title: string
  groups: ArgGroup[]
  fire: (selection: Record<string, string>) => Action
}

export type Action = Deeplink | Url | Script | App | KeyCode | WhichKeyboard | Submenu | ArgBuilder

// --- Constructors (submenu/argbuilder constructors live with their engines) ---
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

export function to_key_code(key: string) {
  if (key == '=') { // karabiner doesn't like '=' as a key
    return "equal_sign"
  } else if (key == '-' || key == 'minus') { // karabiner doesn't like '-' as a key
    return "hyphen"
  } else if (key == '⏎' || key == 'return') { // karabiner doesn't like 'return' as a key
    return "return_or_enter"
  } else if (key == '⌫' || key == 'delete') { // karabiner doesn't like 'delete' as a key
    return "delete_or_backspace"
  } else if (key == ',') {
    return "comma"
  } else if (key == '.') {
    return "period"
  } else if (key == '[') {
    return "open_bracket"
  } else if (key == ']') {
    return "close_bracket"
  }
  return key
}

// --- Rendering ---

// To-events for the fire-and-forget kinds. The interactive kinds (submenu,
// argbuilder) and which_keyboard (needs per-device conditions) don't reduce to
// a plain to-list; callers dispatch those before falling through to here.
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
      return [{ key_code: action.key_code as ToKeyCode, modifiers: action.modifiers || [] }]
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
    case "submenu":
      return `menu: ${action.title}`
    case "argbuilder":
      return `builder: ${action.title}`
  }
}
