import { writeToProfile } from "karabiner.ts"
import homeRow from "./homerow.ts"
import applicationMode from "./modes/application"
import karabinerMode from "./modes/karabiner"
import windowMode from "./modes/window"

writeToProfile("Default", [
  ...homeRow,
  applicationMode,
  karabinerMode,
  windowMode,
])
