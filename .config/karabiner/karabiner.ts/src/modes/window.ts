import { AriMode, deeplink, titleCase } from "../utils/mode.ts"
import type { Meta } from "../utils/mode.ts"

// Window management through Raycast on direct ⌃⌥<key> chords, one table. Each key is a
// deeplink opened with `open -g` (keepFocus), so the front window stays frontmost while Raycast
// acts on it; nothing here replays a Raycast hotkey, and Raycast's own hotkey settings stay
// empty for these commands. Window management has no layer (meta has no entrypoint): the
// direct chords are the whole interface. bake generates raycast_bindings.json from this table
// and the ari-raycast link widget reads the same generator, so the key Claude prints is the key
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

const wm = (slug: string) =>
  deeplink(`extensions/raycast/window-management/${slug}`, {
    keepFocus: true,
    title: titleCase(slug),
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
