// hyper+l leader mode: from anywhere, jump to the next/prev agent and return to chat.

import { hyperLayer, map, toKey, type FromAndToKeyCode } from "karabiner.ts"
import { claudeActions } from "./actions.ts"

const CURSOR_TO_BOTTOM_PRESSES = 30
const FOOTER_EXIT_PRESSES = 10

// ctrl+n: cursor down a line — downward doesn't accept the inline suggestion (rightward does).
const LINE_DOWN = toKey("n", "⌃")

// Descend to the bottom of the buffer (ctrl+e to end the last line), then fall into the footer.
const ENTER_FOOTER = [
  ...Array.from({ length: CURSOR_TO_BOTTOM_PRESSES }, () => LINE_DOWN),
  toKey("e", "⌃"),
  toKey("down_arrow"),
]

// Spam the prev-agent chord (alt+l alt+k = footer:up) to exit back to chat; a no-op in chat.
const EXIT_TO_CHAT = Array.from({ length: FOOTER_EXIT_PRESSES }, () => [toKey("l", "⌥"), toKey("k", "⌥")]).flat()

// Nav to the agent (alt+l alt+suffix), open it (enter), then walk back up to the chat.
const navAndOpen = (suffix: FromAndToKeyCode) => [toKey("l", "⌥"), toKey(suffix, "⌥"), toKey("return_or_enter"), ...EXIT_TO_CHAT]

export const claudeLeaderMode = hyperLayer("l", "claude-leader")
  .description(`(hyper + l): Claude agent nav\n\n${claudeActions.map((a) => `• \`${a.suffix}\` → ${a.desc}`).join("\n")}`)
  .leaderMode()
  .notification()
  .manipulators(claudeActions.map((a) => map(a.suffix).to([...ENTER_FOOTER, ...navAndOpen(a.suffix)])))
