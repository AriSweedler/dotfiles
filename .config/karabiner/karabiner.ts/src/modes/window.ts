import { AriMode, key_code } from "../utils/mode.ts"

// Each key sends ctrl+option+<key>, which Raycast must have configured as the
// matching Window Management hotkey (Raycast > Settings > Extensions).
//
// TODO: On my 34 inch monitor, I may want a different set of entries for this.
// For example, 'h' should maybe mean "left-third" instead of "left-half"

const meta = {
  entrypoint: "w",
  layerName: "window-mode",
  description: "Window management",
}

const dict = Object.fromEntries(
  Object.entries({
    "⌫": "restore",
    "⏎": "almost-maximize",

    "h": "left-half",
    "l": "right-half",

    "q": "left-third",
    "w": "center-third",
    "e": "right-third",

    "u": "top-left-quarter",
    "i": "top-right-quarter",
    "j": "bottom-left-quarter",
    "k": "bottom-right-quarter",

    "c": "center",
    "r": "reasonable-size",
    "f": "toggle-fullscreen",

    "-": "make-smaller",
    "=": "make-larger",

    ",": "previous-display",
    ".": "next-display",

    "[": "previous-desktop",
    "]": "next-desktop"
  })
    // Deeplinks steal focus from the target window by opening Raycast, so
    // each key replays the configured Raycast hotkey instead.
    .map(([key, value]) => [
      key,
      key_code(key, ["control", "option"], value)
    ])
)

const windowMode = new AriMode(meta, dict)
export default windowMode.asRule()
