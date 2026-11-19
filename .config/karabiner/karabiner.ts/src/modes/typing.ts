import { AriMode, deeplink, script, url } from "../utils/mode.ts"
import { argBuilderRules } from "../utils/argbuilder.ts"
import { argBuilderFromCmdson, loadCmdson } from "../utils/cmdson.ts"
import { monkeytypeTestUrl } from "../utils/monkeytype.ts"

// Word-count tests are seeded with the next unread passage of the current
// book via the `passage` CLI.

const meta = {
  entrypoint: "t",
  layerName: "typing-mode",
  description: "Typing practice",
}

const typingTest = (...args: string[]) => script("karabiner-typing-test", args)

const typingDoc = loadCmdson(new URL("../cmdson/typing-test.cmdson.json", import.meta.url))

// Firing current or previous with a length re-anchors the bookmark and
// re-reads at that length.
const typingBuilder = argBuilderFromCmdson("typing", "typing test builder", typingDoc)

// The 58008 funbox generates number groups to type.
const MONKEYTYPE_NUMBERS_URL = monkeytypeTestUrl([
  "time", null, null, false, false, "english", "normal", ["58008"],
])

const dict = {
  "0": typingTest("--words", "5"),
  "1": typingTest("--words", "50"),
  "2": typingTest("--words", "100"),
  "3": typingTest("--words", "300"),
  "s": typingTest("status"),
  "#": url(MONKEYTYPE_NUMBERS_URL, "numbers"),
  "x": typingBuilder,
  "r": deeplink("extensions/raycast/typing-practice/start-typing-practice", {
    title: "Typing Practice",
    description: "Start a Raycast typing practice round",
  }),
}

export const typingBuilderRules = argBuilderRules(typingBuilder)

export const typingMode = new AriMode(meta, dict)
export default typingMode.asRule()
