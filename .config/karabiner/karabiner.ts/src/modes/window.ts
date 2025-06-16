import { hyperLayer, map } from "karabiner.ts"
import { AriMode, key_code } from "../utils/mode"

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
  }).map(([key, value]) => [key, key_code({
    // NOTE: Deeplinks lose window focus, as they 'open' raycast. Rip... So I
    // have to use a key_code that has been configured in raycast instead of a
    // `deeplink`
    //
    // This key_code mapping requires raycast to be set up with the right
    // keystroke shortcuts. It entirely bypasses the mapping of key to action
    // (the action is the configured raycast keystroke matching the key)
    key_code: to_key_code(key), modifiers: ["control", "option"] 
  }, `${value}`)])
)

function to_key_code(key: string)  {
  if (key == '=') { // karabiner doesn't like '=' as a key
    return "equal_sign"
  } else if (key == '-' || key == 'minus') { // karabiner doesn't like '-' as a key
    return "hyphen"
  } else if (key == '⏎' || key == 'return') { // karabiner doesn't like 'return' as a key
    return "return_or_enter"
  } else if (key == '⌫' || key == 'delete') { // karabiner doesn't like 'delete' as a key
    return "delete_or_backspace"
  }
  return key
}

// --- Export Final Rule ---
const windowMode = new AriMode(meta, dict)
export default windowMode.asRule()
