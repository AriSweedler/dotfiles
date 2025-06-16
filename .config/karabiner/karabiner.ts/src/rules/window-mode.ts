import { hyperLayer, map } from "karabiner.ts"
import { raycast_deeplink } from "../utils"

const key_action_map = {
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
}

////////////////////////////////////////////////////////////////////////////////
// opening a deeplink loses focus so you can't use raycast deeplinks for this...
const to_manipulator = ([key, action]: [string, string]) => {
  return map(key).to([
    raycast_deeplink(`extensions/raycast/window-management/${action}`)
  ])
}

////////////////////////////////////////////////////////////////////////////////
const to_key_code = (key: string) => {
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

// This requires raycast to be set up with the right keystroke shortcuts.
// It entirely bypasses the mapping of key to action (the action is the
// configured raycast keystroke matching the key)
const to_manipulator_keystrokes = ([key, action]: [string, string]) => {
  return map(key).to({ key_code: to_key_code(key), modifiers: ["control", "option"] })
}
////////////////////////////////////////////////////////////////////////////////

export const windowMode = hyperLayer("w", "window-mode")
  .description("Window Mode (hyper + w)")
  .leaderMode()
  .notification()
  .manipulators(Object.entries(key_action_map).map(to_manipulator_keystrokes))
