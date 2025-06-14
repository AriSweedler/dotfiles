import { hyperLayer, toApp, map } from "karabiner.ts"

export const applicationMode = hyperLayer("a", "application-mode")
  .description("Open App Mode (hyper + a)")
  .leaderMode()
  .notification()
  .manipulators([
    map("a").to(toApp("Arc")),
    map("f").to(toApp("Finder")),
    map("t").to(toApp("Terminal")),
    map("s").to(toApp("Spotify")),
    map("v").to(toApp("Cisco AnyConnect Secure Mobility Client")),
  ])
