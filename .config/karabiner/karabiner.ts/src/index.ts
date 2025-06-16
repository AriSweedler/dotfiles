import { map, rule, writeToProfile } from "karabiner.ts"
import applicationMode from "./modes/application"
import karabinerMode from "./modes/karabiner"
import windowMode from "./modes/window"

writeToProfile("Default", [
  rule('Right option → Hyper').manipulators(map('right_option').toHyper()),
  applicationMode,
  karabinerMode,
  windowMode,
])
