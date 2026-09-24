import { hyperLayer, map, rule, BasicManipulator, FromKeyCode, LayerKeyParam, Modifier, Rule, ToEvent } from "karabiner.ts"
import { Action, actionToTos, describeAction, helpLine } from "./actions.ts"
import { argBuilderOpenEvents } from "./argbuilder.ts"
import { allDevices } from "./devices.ts"

// Re-export the action vocabulary so mode files keep a single import site.
export { app, deeplink, key_code, script, titleCase, url, which_keyboard } from "./actions.ts"
export type { Action } from "./actions.ts"

export type Meta = {
  // The Hyper+<entrypoint> layer key. A mode without one has no layer (asRule() refuses) and
  // reaches its actions only through directModifiers.
  entrypoint?: string
  layerName: string
  description: string
  // When set, every key of the dict also fires as a direct chord <directModifiers>+<key>,
  // no layer needed (directRules()). Window management uses ["control", "option"].
  directModifiers?: Modifier[]
}

// Karabiner runs shell_command with launchd's minimal PATH, so the notifier
// needs its absolute path.
const notify = (message: string) => ({
  shell_command: `/opt/homebrew/bin/terminal-notifier -title Keyboard -message ${JSON.stringify(message)} -group karabiner-which-keyboard`,
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
    if (!this.meta.entrypoint) {
      throw new Error(`mode has no layer entrypoint; use directRules() | layer=${this.meta.layerName}`)
    }
    const built = hyperLayer(this.meta.entrypoint as LayerKeyParam, this.meta.layerName)
      .description(this.toDescription())
      .leaderMode()
      .notification()
      .manipulators(this.toManipulators())
      .build()
    this.patchShiftedKeys(built)
    return built
  }

  // One rule per dict key: <directModifiers>+<key> fires the same action without the layer.
  // Interactive kinds (argbuilder, which_keyboard) have no single to-list and are skipped.
  directRules(): Rule[] {
    const mods = this.meta.directModifiers ?? []
    if (mods.length === 0) return []
    return Object.entries(this.actionDict)
      .filter(([, action]) => action.kind !== "argbuilder" && action.kind !== "which_keyboard")
      .map(([key, action]) => {
        const shifted = key in SHIFTED_KEYS
        const fromMods: Modifier[] = shifted ? [...mods, "shift"] : mods
        return rule(`${this.meta.layerName} direct: ${fromMods.join("+")}+${key} → ${describeAction(action)}`)
          .manipulators([mapFrom(key).to(actionToTos(action))])
          .build()
      })
      .map((built, i) => {
        // hyperLayer-free path: set the mandatory modifiers on the single manipulator.
        const [key] = Object.entries(this.actionDict).filter(([, a]) => a.kind !== "argbuilder" && a.kind !== "which_keyboard")[i]
        const manipulator = built.manipulators[0] as BasicManipulator
        manipulator.from.modifiers = { mandatory: key in SHIFTED_KEYS ? [...mods, "shift"] : mods }
        return built
      })
  }
}
