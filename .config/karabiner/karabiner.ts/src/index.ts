import { writeToProfile } from "karabiner.ts"
import { writeBindings } from "./generate_bindings.ts"
import { homeRow } from "./homerow.ts"
import applicationMode from "./modes/application.ts"
import karabinerMode from "./modes/karabiner.ts"
import typingMode, { typingBuilderRules } from "./modes/typing.ts"
import { windowDirectRules } from "./modes/window.ts"
import { raycastRules } from "./raycast.ts"
import { shortcuts } from "./shortcuts.ts"

writeToProfile("Default", [
  ...homeRow,
  applicationMode,
  karabinerMode,
  typingMode,
  // Menu/builder rules claim bare keys gated only on their own variables.
  // They sit after every layer so an active layer beats a stale menu.
  ...typingBuilderRules,
  ...shortcuts,
  ...raycastRules,
  // ⌃⌥<key> window management; no layer, the chords are the whole interface.
  ...windowDirectRules,
])

// The ari-raycast link widget reads this artifact; it is generated from the same tables, every build.
writeBindings()
