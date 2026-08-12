import { hyperLayer, map, BasicManipulator, FromKeyCode, LayerKeyParam, Rule } from "karabiner.ts"
import { Action, actionToTos, describeAction } from "./actions"
import { argBuilderOpenEvents } from "./argbuilder"
import { submenuOpenEvents } from "./submenu"
import { allDevices } from "./devices"

// Re-export the action vocabulary so mode files keep a single import site.
export { app, deeplink, key_code, script, url, which_keyboard } from "./actions"
export type { Action } from "./actions"

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
      .map(([key, action]) => `• \`${key}\` → ${describeAction(action)}`)
      .join("\n")

    return `(hyper + ${this.meta.entrypoint}): ${this.meta.description}\n\n${entries}`
  }

  private toManipulator = ([key, action]: [string, Action]) => {
    switch (action.kind) {
      case "submenu":
        return mapFrom(key).to(submenuOpenEvents(action))
      case "argbuilder":
        return mapFrom(key).to(argBuilderOpenEvents(action))
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
        return mapFrom(key).to(actionToTos(action))
    }
  }

  private toManipulators() {
    return Object.entries(this.actionDict).flatMap(entry => {
      const result = this.toManipulator(entry)
      return Array.isArray(result) ? result : [result]
    })
  }

  // The layer builder gives every key from.modifiers mandatory ['any'] (hyper
  // is held when the layer opens), so a shifted dict key like '#' builds as an
  // indistinguishable duplicate of its base key. Rewrite it to mandatory
  // ['shift'] and hoist it above the bare-key manipulator, which would
  // otherwise swallow shift+base via its ['any'] match.
  private patchShiftedKeys(rule: Rule) {
    for (const [key, action] of Object.entries(this.actionDict)) {
      const base = SHIFTED_KEYS[key]
      if (!base) continue
      const marker = (actionToTos(action)[0] as { shell_command?: string }).shell_command
      const idx = rule.manipulators.findIndex(
        m =>
          m.type === "basic" &&
          "key_code" in m.from &&
          m.from.key_code === base &&
          !!m.to?.some(t => "shell_command" in t && t.shell_command === marker),
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
