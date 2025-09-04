import { hyperLayer, map } from "karabiner.ts"
import { AriMode, key_code } from "../utils/mode"

// To enable one-click usage, the user needs to check to see if all the raycast
// shortcuts are set up properly. Go to `Raycast > Settings > Extensions` & make
// sure all the `Window Management` hotkeys are set.
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
    // NOTE: Deeplinks lose window focus, as they 'open' raycast. Rip... So I
    // have to use a key_code that has been configured in raycast instead of a
    // `deeplink`
    //
    // This key_code mapping requires raycast to be set up with the right
    // keystroke shortcuts. It entirely bypasses the mapping of key to action
    // (the action is the configured raycast keystroke matching the key)
    .map(([key, value]) => [
      key,
      key_code(key, ["control", "option"], value)
    ])
)

// --- Export Final Rule ---
const windowMode = new AriMode(meta, dict)
export default windowMode.asRule()
