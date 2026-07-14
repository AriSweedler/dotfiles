import { FromKeyParam, ToEvent, ifVar, map, rule, toNotificationMessage, toRemoveNotificationMessage, toUnsetVar, toSetVar } from "karabiner.ts"
import { Action, Submenu, actionToTos, describeAction } from "./actions"
import { argBuilderOpenEvents } from "./argbuilder"

// Nested key menus. A submenu entry in an AriMode dict (or in another
// submenu) opens the menu: one shared variable records which menu is open,
// and a Karabiner notification shows its keys. Terminal entries fire their
// action and close everything; nested entries descend. Implicit at every
// level: escape clears menu state — deliberately absent from the help text.
//
// Caveats (same class as leader modes, one level deeper): Karabiner variables
// have no timeout, so an abandoned menu stays armed until escape or a mapped
// key; and menu keys are claimed by bare keycodes, so register these rules
// AFTER the AriMode layers in writeToProfile so an active layer beats a stale
// menu.

const SUBMENU_VAR = "ari_submenu"
const SUBMENU_NOTIFICATION_ID = "ari-submenu"

export const submenu = (id: string, title: string, entries: Record<string, Action>): Submenu => ({
  kind: "submenu",
  id,
  title,
  entries,
})

const helpText = (menu: Submenu): string => {
  const lines = Object.entries(menu.entries)
    .map(([key, action]) => `• \`${key}\` → ${describeAction(action)}`)
    .join("\n")
  return `(${menu.title})\n\n${lines}`
}

export const submenuOpenEvents = (menu: Submenu): ToEvent[] => [
  toSetVar(SUBMENU_VAR, menu.id),
  toNotificationMessage(SUBMENU_NOTIFICATION_ID, helpText(menu)),
]

const closeEvents: ToEvent[] = [
  toUnsetVar(SUBMENU_VAR),
  toRemoveNotificationMessage(SUBMENU_NOTIFICATION_ID),
]

const collectMenus = (menu: Submenu): Submenu[] => [
  menu,
  ...Object.values(menu.entries).flatMap((entry) => (entry.kind === "submenu" ? collectMenus(entry) : [])),
]

const entryManipulator = (menu: Submenu, key: string, entry: Action) => {
  const m = map(key as FromKeyParam).condition(ifVar(SUBMENU_VAR, menu.id))
  if (entry.kind === "submenu") {
    return m.to(submenuOpenEvents(entry))
  }
  if (entry.kind === "argbuilder") {
    return m.to([...closeEvents, ...argBuilderOpenEvents(entry)])
  }
  return m.to([...actionToTos(entry), ...closeEvents])
}

export const submenuRules = (root: Submenu) =>
  collectMenus(root).map((menu) =>
    rule(`submenu: ${menu.id}`).manipulators([
      ...Object.entries(menu.entries).map(([key, entry]) => entryManipulator(menu, key, entry)),
      map("escape").condition(ifVar(SUBMENU_VAR, menu.id)).to(closeEvents),
    ]),
  )
