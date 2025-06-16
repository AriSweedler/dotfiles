import { hyperLayer, toApp, map } from "karabiner.ts"

// --- Types ---
type Deeplink = { kind: "deeplink"; path: string }
type Script = { kind: "script"; name: string }
type Action = Deeplink | Script
type Map = Record<string, string>
type ManipulatorFn = ([key, action]: [string, string]) => any

type Meta = {
  entrypoint: string
  layerName: string
  description: string
}

// --- Helpers ---
export const deeplink = (path: string): Deeplink => ({ kind: "deeplink", path })
export const script = (name: string): Script => ({ kind: "script", name })

export class AriMode {
  meta: Meta
  map: Map
  toManipulatorFn: ManipulatorFn

  constructor(meta: Meta, map: Map, toManipulatorFn: ManipulatorFn) {
    this.meta = meta
    this.map = map
    this.toManipulatorFn = toManipulatorFn
  }

  private toDescription() {
    const entries = Object.entries(this.map)
      .map(([_, val]) => {
        if (typeof val === "string") {
          return val
        } else if (val.kind === "deeplink") {
          return `deeplink: ${val.path}`
        } else if (val.kind === "script") {
          return `script: ${val.name}`
        } else {
          return "unknown"
        }
      })
      .map((rhs, i) => {
        const key = Object.keys(this.map)[i]
        return `• \`${key}\` → ${rhs}`
      })
      .join("\n")

    return `(hyper + ${this.meta.entrypoint}): ${this.meta.description}\n\n${entries}`
  }

  get manipulators() {
    return Object.entries(this.map).map(this.toManipulatorFn)
  }

  asRule() {
    return hyperLayer(this.meta.entrypoint, this.meta.layerName)
      .description(this.toDescription())
      .leaderMode()
      .notification()
      .manipulators(this.manipulators)
  }
}
