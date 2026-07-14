import { FromKeyParam, ToEvent, ifVar, map, rule, toNotificationMessage, toRemoveNotificationMessage, toUnsetVar, toSetVar } from "karabiner.ts"
import { ArgBuilder, ArgGroup, ArgOption, actionToTos } from "./actions"

// Order-free "arg builder" menus: each exclusive group of options gets its
// own Karabiner variable and its own notification line; pressing an option
// key re-selects within that group (any order, any number of times), and ⏎
// fires the built action. Because Karabiner shell commands are static, the ⏎
// binding is generated once per combination — the cartesian product of all
// group options — so keep groups small. Option keys must be unique across
// groups (enforced at bake time). Implicit at every level: escape clears
// builder state — deliberately absent from the help text.
//
// Caveats match submenu.ts: no variable timeout (an abandoned builder stays
// armed until escape or ⏎), and these rules must be registered AFTER the
// AriMode layers in writeToProfile so an active layer beats a stale builder.

const openVar = (b: ArgBuilder) => `ari_argbuilder_${b.id}`
const groupVar = (b: ArgBuilder, g: ArgGroup) => `ari_argbuilder_${b.id}_${g.name}`
const titleNotification = (b: ArgBuilder) => `ari-argbuilder-${b.id}`
const groupNotification = (b: ArgBuilder, g: ArgGroup) => `ari-argbuilder-${b.id}-${g.name}`

export const argBuilder = (
  id: string,
  title: string,
  groups: ArgGroup[],
  fire: ArgBuilder["fire"],
): ArgBuilder => {
  const seen = new Map<string, string>()
  for (const group of groups) {
    if (!group.options.some((o) => o.key === group.defaultKey)) {
      throw new Error(`argBuilder defaultKey not among options | builder=${id} group=${group.name} defaultKey=${group.defaultKey}`)
    }
    for (const option of group.options) {
      const owner = seen.get(option.key)
      if (owner) {
        throw new Error(`argBuilder option keys must be unique across groups | builder=${id} key=${option.key} groups=${owner},${group.name}`)
      }
      seen.set(option.key, group.name)
    }
  }
  return { kind: "argbuilder", id, title, groups, fire }
}

const optionByKey = (g: ArgGroup, key: string): ArgOption =>
  g.options.find((o) => o.key === key)!

const groupText = (g: ArgGroup, selectedKey: string): string =>
  `${g.label}:  ` +
  g.options.map((o) => `${o.key === selectedKey ? "●" : "○"} [${o.key}] ${o.label}`).join("   ")

export const argBuilderOpenEvents = (b: ArgBuilder): ToEvent[] => [
  toSetVar(openVar(b), 1),
  ...b.groups.map((g) => toSetVar(groupVar(b, g), optionByKey(g, g.defaultKey).value)),
  toNotificationMessage(titleNotification(b), `(${b.title}) — ⏎ to run`),
  ...b.groups.map((g) => toNotificationMessage(groupNotification(b, g), groupText(g, g.defaultKey))),
]

const closeEvents = (b: ArgBuilder): ToEvent[] => [
  toUnsetVar(openVar(b)),
  ...b.groups.map((g) => toUnsetVar(groupVar(b, g))),
  toRemoveNotificationMessage(titleNotification(b)),
  ...b.groups.map((g) => toRemoveNotificationMessage(groupNotification(b, g))),
]

// Every way to pick one option from each group, as [group.name → option] maps.
const combinations = (groups: ArgGroup[]): Array<Record<string, ArgOption>> =>
  groups.reduce<Array<Record<string, ArgOption>>>(
    (acc, group) => acc.flatMap((combo) => group.options.map((option) => ({ ...combo, [group.name]: option }))),
    [{}],
  )

export const argBuilderRules = (b: ArgBuilder) => {
  const selectionManipulators = b.groups.flatMap((group) =>
    group.options.map((option) =>
      map(option.key as FromKeyParam)
        .condition(ifVar(openVar(b), 1))
        .to([toSetVar(groupVar(b, group), option.value), toNotificationMessage(groupNotification(b, group), groupText(group, option.key))]),
    ),
  )

  const fireManipulators = combinations(b.groups).map((combo) => {
    const selection = Object.fromEntries(b.groups.map((g) => [g.name, combo[g.name].value]))
    let m = map("⏎" as FromKeyParam).condition(ifVar(openVar(b), 1))
    for (const group of b.groups) {
      m = m.condition(ifVar(groupVar(b, group), combo[group.name].value))
    }
    return m.to([...actionToTos(b.fire(selection)), ...closeEvents(b)])
  })

  return [
    rule(`argbuilder: ${b.id}`).manipulators([
      ...selectionManipulators,
      ...fireManipulators,
      map("escape").condition(ifVar(openVar(b), 1)).to(closeEvents(b)),
    ]),
  ]
}
