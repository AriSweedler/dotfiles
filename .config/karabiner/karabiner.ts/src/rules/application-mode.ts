import { hyperLayer, toApp, map } from "karabiner.ts"

const entrypoint = "a"
const layer_name = "application-mode"
const description = "Open application"

const key_action_map = {
  "a": "Arc",
  "f": "Finder",
  "t": "Terminal",
  "s": "Spotify",
  "v": "Cisco AnyConnect Secure Mobility Client",
}

const to_manipulator = ([key, app]: [string, string]) => {
  return map(key).to(toApp(app))
}

const to_description = (map: Record<string, string>) => {
  const entries = Object.entries(map)
    .map(([key, app]) => `• \`${key}\` → ${app}`)
    .join("\n")

  return `(hyper + ${entrypoint}): ${description}\n\n${entries}`
}

export const applicationMode = hyperLayer(entrypoint, layer_name)
  .description(to_description(key_action_map))
  .leaderMode()
  .notification()
  .manipulators(Object.entries(key_action_map).map(to_manipulator))
