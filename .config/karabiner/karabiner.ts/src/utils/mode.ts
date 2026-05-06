import { hyperLayer, toApp, map, FromKeyCode, Modifier } from "karabiner.ts"
import { karabiner_script } from "./macros"
import { allDevices } from "./devices"

// --- Types ---
type Deeplink = { kind: "deeplink"; path: string }
type Script = { kind: "script"; name: string }
type App = { kind: "app"; name: string }
type KeyCode = { kind: "key_code"; key_code: string; modifiers?: Modifier[]; description: string }
type WhichKeyboard = { kind: "which_keyboard" }
type Action = Deeplink | Script | KeyCode | App | WhichKeyboard

type Meta = {
  entrypoint: string
  layerName: string
  description: string
}

// --- Helpers ---
export const deeplink = (path: string): Deeplink => ({ kind: "deeplink", path })
export const script = (name: string): Script => ({ kind: "script", name })
export const app = (name: string): App => ({ kind: "app", name })
export const which_keyboard = (): WhichKeyboard => ({ kind: "which_keyboard" })
export const key_code = (key: string, modifiers: Modifier[], description: string): KeyCode => ({
  kind: "key_code",
  key_code: to_key_code(key),
  modifiers: modifiers,
  description: description,
})

const notify = (message: string) => ({
  shell_command: `osascript -e 'display notification ${JSON.stringify(message)} with title "Keyboard"'`,
})

function to_key_code(key: string)  {
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

type ActionDict = Record<string, Action>
export class AriMode {
  meta: Meta
  actionDict: ActionDict

  constructor(meta: Meta, actionDict: ActionDict) {
    this.meta = meta
    this.actionDict = actionDict
  }

  private toDescription() {
    const entries = Object.entries(this.actionDict)
    .map(([_, val]) => {
      if (typeof val === "string") {
        return val
      }
      switch (val.kind) {
        case "key_code":
          return val.description || `key_code: ${val.key_code}`
        case "app":
          return `open app: ${val.name}`
        case "script":
          return `run script: ${val.name}`
        case "deeplink":
          return `deeplink: ${val.path}`
        case "which_keyboard":
          return `notify keyboard name`
        default:
          return "unknown"
      }
    })
    .map((rhs, i) => {
      const key = Object.keys(this.actionDict)[i]
      return `• \`${key}\` → ${rhs}`
    })
    .join("\n")

    return `(hyper + ${this.meta.entrypoint}): ${this.meta.description}\n\n${entries}`
  }

  private toManipulator = ([key, action]: [FromKeyCode, Action]) => {
    switch (action.kind) {
      case "deeplink":
        return map(key).to({shell_command: `open raycast://${action.path}`})
      case "script":
        return map(key).to(karabiner_script(action.name))
      case "app":
        return map(key).to(toApp(action.name))
      case "key_code":
        return map(key).to({
          key_code: action.key_code,
          modifiers: action.modifiers || [],
          description: action.description || `key_code: ${action.key_code}`,
        })
      case "which_keyboard":
        const known = allDevices.map(d =>
          map(key)
            .to(notify(d.label))
            .condition({ type: 'device_if', identifiers: [d.identifier] })
        )
        const fallback = map(key)
          .to(notify("Unknown keyboard"))
          .condition({ type: 'device_unless', identifiers: allDevices.map(d => d.identifier) })
        return [...known, fallback]
    }

    throw new Error(`Unknown action type: ${JSON.stringify(action)}`)
  }

  private toManipulators() {
    return Object.entries(this.actionDict).flatMap(entry => {
      const result = this.toManipulator(entry as [FromKeyCode, Action])
      return Array.isArray(result) ? result : [result]
    })
  }

  asRule() {
    return hyperLayer(this.meta.entrypoint, this.meta.layerName)
      .description(this.toDescription())
      .leaderMode()
      .notification()
      .manipulators(this.toManipulators())
  }
}
