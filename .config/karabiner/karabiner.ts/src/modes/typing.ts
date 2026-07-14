import { AriMode, deeplink, script } from "../utils/mode"
import { argBuilder, argBuilderRules } from "../utils/argbuilder"

// Monkeytype tests are seeded with the next unread passage of the current
// book via the `passage` CLI (~/.config/bin/passage). Digits fire directly;
// x opens the arg builder (pick action and length in any order, ⏎ to run —
// current/previous with a length re-anchor the bookmark and re-read at that
// length); s notifies progress; r falls back to Raycast's native typing
// practice with its own stock text.

const meta = {
  entrypoint: "t",
  layerName: "typing-mode",
  description: "Typing practice",
}

const WORD_OPTIONS = [
  { key: "0", label: "5 words", value: "5" },
  { key: "1", label: "50 words", value: "50" },
  { key: "2", label: "100 words", value: "100" },
  { key: "3", label: "300 words", value: "300" },
]

export const typingBuilder = argBuilder(
  "typing",
  "typing test builder",
  [
    {
      name: "action",
      label: "action",
      defaultKey: "n",
      options: [
        { key: "n", label: "next", value: "next" },
        { key: "c", label: "current", value: "current" },
        { key: "p", label: "previous", value: "previous" },
      ],
    },
    { name: "words", label: "words", defaultKey: "1", options: WORD_OPTIONS },
  ],
  (selection) => script("karabiner-typing-test", [selection.action, "--words", selection.words]),
)

const dict = {
  "0": script("karabiner-typing-test", ["--words", "5"]),
  "1": script("karabiner-typing-test", ["--words", "50"]),
  "2": script("karabiner-typing-test", ["--words", "100"]),
  "3": script("karabiner-typing-test", ["--words", "300"]),
  "s": script("karabiner-typing-test", ["status"]),
  "x": typingBuilder,
  "r": deeplink("extensions/raycast/typing-practice/start-typing-practice"),
}

export const typingBuilderRules = argBuilderRules(typingBuilder)

// --- Export Final Rule ---
const typingMode = new AriMode(meta, dict)
export default typingMode.asRule()
