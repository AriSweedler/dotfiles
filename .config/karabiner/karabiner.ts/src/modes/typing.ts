import { AriMode, deeplink, script, url } from "../utils/mode.ts"
import { argBuilder, argBuilderRules } from "../utils/argbuilder.ts"
import { monkeytypeTestUrl } from "../utils/monkeytype.ts"

// Word-count tests are seeded with the next unread passage of the current
// book via the `passage` CLI.

const meta = {
  entrypoint: "t",
  layerName: "typing-mode",
  description: "Typing practice",
}

const typingTest = (...args: string[]) => script("karabiner-typing-test", args)

const WORD_OPTIONS = [
  { key: "0", label: "5 words", value: "5" },
  { key: "1", label: "50 words", value: "50" },
  { key: "2", label: "100 words", value: "100" },
  { key: "3", label: "300 words", value: "300" },
]

// Firing current or previous with a length re-anchors the bookmark and
// re-reads at that length.
const typingBuilder = argBuilder(
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
  (selection) => typingTest(selection.action, "--words", selection.words),
)

// The 58008 funbox generates number groups to type.
const MONKEYTYPE_NUMBERS_URL = monkeytypeTestUrl([
  "time", null, null, false, false, "english", "normal", ["58008"],
])

const dict = {
  ...Object.fromEntries(WORD_OPTIONS.map((o) => [o.key, typingTest("--words", o.value)])),
  "s": typingTest("status"),
  "#": url(MONKEYTYPE_NUMBERS_URL, "numbers"),
  "x": typingBuilder,
  "r": deeplink("extensions/raycast/typing-practice/start-typing-practice"),
}

export const typingBuilderRules = argBuilderRules(typingBuilder)

const typingMode = new AriMode(meta, dict)
export default typingMode.asRule()
