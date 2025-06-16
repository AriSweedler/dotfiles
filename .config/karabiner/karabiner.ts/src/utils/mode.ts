import { hyperLayer, toApp, map } from "karabiner.ts"
import { raycast_deeplink, karabiner_script } from "./macros"

// --- Types ---
type Deeplink = { kind: "deeplink"; path: string }
type Script = { kind: "script"; name: string }
type App = { kind: "app"; name: string }
type KeyCode = { kind: "key_code"; key: string; modifiers?: string[] }
type Action = Deeplink | Script | Lambda | KeyCode | App
type Map = Record<string, string>

type Meta = {
  entrypoint: string
  layerName: string
  description: string
}

// --- Helpers ---
export const deeplink = (path: string): Deeplink => ({ kind: "deeplink", path })
export const script = (name: string): Script => ({ kind: "script", name })
export const toApp = (name: string): App => ({ kind: "app", name })
export const key_code = (kc: KeyCode, descr: string): KeyCode => ({
  kind: "key_code",
  key: kc.key,
  modifiers: kc.modifiers || [],
  descr,
})

export class AriMode {
  meta: Meta
  dict: Map

  constructor(meta: Meta, dict: Map) {
    this.meta = meta
    this.dict = dict
  }

  private toDescription() {
    const entries = Object.entries(this.dict)
      .map(([_, val]) => {
        if (typeof val === "string") {
          return val
        } 

        switch (val.kind) {
        case "deeplink":
          return `deeplink: ${val.path}`
        case "script":
          return `script: ${val.name}`
        case "app":
          return `${val.name} (open app)`
        case "key_code":
          return `${val.descr} (key code)`
        default:
          return "unknown"
        }
      })
      .map((rhs, i) => {
        const key = Object.keys(this.dict)[i]
        return `• \`${key}\` → ${rhs}`
      })
      .join("\n")

    return `(hyper + ${this.meta.entrypoint}): ${this.meta.description}\n\n${entries}`
  }

  private toManipulator([key, action]: [string, Action]) {
    switch (action.kind) {
      case "deeplink":
        return map(key).to(raycast_deeplink(action.path))
      case "script":
        return map(key).to(karabiner_script(action.name))
      case "app":
        return map(key).to(toApp(action.name))
      case "key_code":
        return map(key).to({ key_code: action.key, modifiers: action.modifiers || [] })
      default:
        throw new Error("Unknown action kind")
    }
  }

  asRule() {
    return hyperLayer(this.meta.entrypoint, this.meta.layerName)
      .description(this.toDescription())
      .leaderMode()
      .notification()
      .manipulators(Object.entries(this.dict).map(this.toManipulator))
  }
}
