import { hyperLayer, map, FromKeyCode, LayerKeyParam } from "karabiner.ts"
import { Action, actionToTos, describeAction } from "./actions"
import { argBuilderOpenEvents } from "./argbuilder"
import { submenuOpenEvents } from "./submenu"
import { allDevices } from "./devices"

// Re-export the action vocabulary so mode files keep a single import site.
export { app, deeplink, key_code, script, which_keyboard } from "./actions"
export type { Action } from "./actions"

type Meta = {
  entrypoint: string
  layerName: string
  description: string
}

const notify = (message: string) => ({
  shell_command: `osascript -e 'display notification ${JSON.stringify(message)} with title "Keyboard"'`,
})

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

  private toManipulator = ([key, action]: [FromKeyCode, Action]) => {
    switch (action.kind) {
      case "submenu":
        return map(key).to(submenuOpenEvents(action))
      case "argbuilder":
        return map(key).to(argBuilderOpenEvents(action))
      case "which_keyboard": {
        const known = allDevices.map(d =>
          map(key)
            .to(notify(d.label))
            .condition({ type: 'device_if', identifiers: d.identifiers })
        )
        const fallback = map(key)
          .to(notify("Unknown keyboard"))
          .condition({ type: 'device_unless', identifiers: allDevices.flatMap(d => d.identifiers) })
        return [...known, fallback]
      }
      default:
        return map(key).to(actionToTos(action))
    }
  }

  private toManipulators() {
    return Object.entries(this.actionDict).flatMap(entry => {
      const result = this.toManipulator(entry as [FromKeyCode, Action])
      return Array.isArray(result) ? result : [result]
    })
  }

  asRule() {
    return hyperLayer(this.meta.entrypoint as LayerKeyParam, this.meta.layerName)
      .description(this.toDescription())
      .leaderMode()
      .notification()
      .manipulators(this.toManipulators())
  }
}
