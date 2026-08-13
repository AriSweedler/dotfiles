import { hyperLayer, map, BasicManipulator, FromKeyCode, LayerKeyParam, Rule, ToEvent } from "karabiner.ts"
import { Action, actionToTos, describeAction, helpLine } from "./actions.ts"
import { argBuilderOpenEvents } from "./argbuilder.ts"
import { allDevices } from "./devices.ts"

// Re-export the action vocabulary so mode files keep a single import site.
export { app, deeplink, key_code, script, url, which_keyboard } from "./actions.ts"
export type { Action } from "./actions.ts"

type Meta = {
  entrypoint: string
  layerName: string
  description: string
}

const notify = (message: string) => ({
  shell_command: `osascript -e 'display notification ${JSON.stringify(message)} with title "Keyboard"'`,
})

// karabiner.ts has no from-key aliases for shifted symbols, and its layer
// builder rejects manipulator modifiers outright (hyper layers rewrite every
// from to mandatory ['any']). So shifted dict keys are emitted on their base
// key here, then patchShiftedKeys fixes up the built rule.
const SHIFTED_KEYS: Record<string, FromKeyCode> = { "#": "3" }
const mapFrom = (key: string) =>
  map((SHIFTED_KEYS[key] ?? key) as FromKeyCode)

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
      .map(([key, action]) => helpLine(key, describeAction(action)))
      .join("\n")

    return `(hyper + ${this.meta.entrypoint}): ${this.meta.description}\n\n${entries}`
  }

  // To-events that open/fire an action, for every kind except which_keyboard
  // (which needs per-device conditions, not a single to-list).
  private openTos(action: Action): ToEvent[] {
    switch (action.kind) {
      case "argbuilder":
        return argBuilderOpenEvents(action)
      case "which_keyboard":
        throw new Error("shifted key cannot be which_keyboard")
      default:
        return actionToTos(action)
    }
  }

  private toManipulator = ([key, action]: [string, Action]) => {
    switch (action.kind) {
      case "which_keyboard": {
        const known = allDevices.map(d =>
          mapFrom(key)
            .to(notify(d.label))
            .condition({ type: 'device_if', identifiers: d.identifiers })
        )
        const fallback = mapFrom(key)
          .to(notify("Unknown keyboard"))
          .condition({ type: 'device_unless', identifiers: allDevices.flatMap(d => d.identifiers) })
        return [...known, fallback]
      }
      default:
        return [mapFrom(key).to(this.openTos(action))]
    }
  }

  private toManipulators() {
    return Object.entries(this.actionDict).flatMap(this.toManipulator)
  }

  // The bare key matches with mandatory ['any'], so the shifted manipulator
  // must sit above it or shift+base would never fire.
  private patchShiftedKeys(rule: Rule) {
    for (const [key, action] of Object.entries(this.actionDict)) {
      const base = SHIFTED_KEYS[key]
      if (!base) continue
      const marker = JSON.stringify(this.openTos(action)[0])
      const idx = rule.manipulators.findIndex(
        m =>
          m.type === "basic" &&
          "key_code" in m.from &&
          m.from.key_code === base &&
          !!m.to?.some(t => JSON.stringify(t) === marker),
      )
      if (idx < 0) {
        throw new Error(`shifted-key manipulator not found | key=${key} base=${base}`)
      }
      const [manipulator] = rule.manipulators.splice(idx, 1) as BasicManipulator[]
      manipulator.from.modifiers = { mandatory: ["shift"] }
      rule.manipulators.unshift(manipulator)
    }
  }

  asRule() {
    const rule = hyperLayer(this.meta.entrypoint as LayerKeyParam, this.meta.layerName)
      .description(this.toDescription())
      .leaderMode()
      .notification()
      .manipulators(this.toManipulators())
      .build()
    this.patchShiftedKeys(rule)
    return rule
  }
}
