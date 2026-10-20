import { AriMode, deeplink, titleCase } from "../utils/mode.ts"
import type { Meta } from "../utils/mode.ts"

// Window management through Raycast on direct ⌃⌥<key> chords, one table. Each key is a
// deeplink opened with `open -g` (keepFocus), so the front window stays frontmost while Raycast
// acts on it; nothing here replays a Raycast hotkey, and Raycast's own hotkey settings stay
// empty for these commands. Window management has no layer (meta has no entrypoint): the
// direct chords are the whole interface. bake generates raycast_bindings.json from this table
// and the `dotfiles raycast link` widget reads the same generator, so the key Claude prints is the key
// this file compiles.
//
// TODO: On my 34 inch monitor, I may want a different set of entries for this.
// For example, 'h' should maybe mean "left-third" instead of "left-half"

// Raycast's allow-list id for a window-management command is the slug in CamelCase after a
// fixed prefix, except where Raycast's own enum names it differently.
const WM_ALLOW_ID_IRREGULARS: Record<string, string> = { "almost-maximize": "MaximizeAlmost" }
const camel = (slug: string) => slug.split("-").map((w) => w[0].toUpperCase() + w.slice(1)).join("")
export const windowManagementAllowId = (slug: string) =>
  `builtin_command_windowManagement${WM_ALLOW_ID_IRREGULARS[slug] ?? camel(slug)}`

// What each command does to the front window, one line: the binding's documentation (the
// title is a name, not documentation). Every slug in the dict below needs a line here; the
// raycast_sync healthcheck step fails on one without, and `dotfiles raycast link edit <slug>`
// opens this map at the slug's line.
const WM_DESCRIPTIONS: Record<string, string> = {
  "restore": "Put the front window back where it was before the last window command",
  "almost-maximize": "Grow the front window to nearly fill the screen, leaving a margin",

  "left-half": "Move the front window to the left half of the screen",
  "right-half": "Move the front window to the right half of the screen",

  "first-third": "Move the front window to the left third of the screen",
  "center-third": "Move the front window to the middle third of the screen",
  "last-third": "Move the front window to the right third of the screen",

  "top-left-quarter": "Move the front window to the top-left quarter of the screen",
  "top-right-quarter": "Move the front window to the top-right quarter of the screen",
  "bottom-left-quarter": "Move the front window to the bottom-left quarter of the screen",
  "bottom-right-quarter": "Move the front window to the bottom-right quarter of the screen",

  "center": "Center the front window on the screen, keeping its size",
  "reasonable-size": "Resize the front window to Raycast's medium default size",
  "toggle-fullscreen": "Toggle the front window in and out of macOS full screen",

  "top-left-sixth": "Move the front window to the top-left sixth of the screen",
  "top-center-sixth": "Move the front window to the top-center sixth of the screen",
  "top-right-sixth": "Move the front window to the top-right sixth of the screen",
  "bottom-left-sixth": "Move the front window to the bottom-left sixth of the screen",
  "bottom-center-sixth": "Move the front window to the bottom-center sixth of the screen",
  "bottom-right-sixth": "Move the front window to the bottom-right sixth of the screen",

  "make-smaller": "Shrink the front window one step, around its center",
  "make-larger": "Grow the front window one step, around its center",

  "previous-display": "Move the front window to the previous display",
  "next-display": "Move the front window to the next display",

  "previous-desktop": "Move the front window to the previous desktop (Space)",
  "next-desktop": "Move the front window to the next desktop (Space)",
}

const wm = (slug: string) =>
  deeplink(`extensions/raycast/window-management/${slug}`, {
    keepFocus: true,
    title: titleCase(slug),
    description: WM_DESCRIPTIONS[slug],
    allowId: windowManagementAllowId(slug),
  })

const meta: Meta = {
  layerName: "window-management",
  description: "Window management",
  directModifiers: ["control", "option"],
}

const dict = Object.fromEntries(
  Object.entries({
    "⌫": "restore",
    "⏎": "almost-maximize",

    "h": "left-half",
    "l": "right-half",

    "q": "first-third",
    "w": "center-third",
    "e": "last-third",

    "u": "top-left-quarter",
    "i": "top-right-quarter",
    "j": "bottom-left-quarter",
    "k": "bottom-right-quarter",

    "c": "center",
    "r": "reasonable-size",
    "f": "toggle-fullscreen",

    // Sixths sit on a 3×2 block by screen position under the left hand; `c` stays Center, so
    // bottom-right lands on `v`.
    "a": "top-left-sixth",
    "s": "top-center-sixth",
    "d": "top-right-sixth",
    "z": "bottom-left-sixth",
    "x": "bottom-center-sixth",
    "v": "bottom-right-sixth",

    "-": "make-smaller",
    "=": "make-larger",

    ",": "previous-display",
    ".": "next-display",

    "[": "previous-desktop",
    "]": "next-desktop",
  }).map(([key, slug]) => [key, wm(slug)]),
)

export const windowMode = new AriMode(meta, dict)
export const windowDirectRules = windowMode.directRules()
