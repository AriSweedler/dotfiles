import { deeplink, type Deeplink } from "./utils/actions.ts"

// Raycast commands on a direct chord, no layer. raycast.ts compiles each into a Karabiner rule
// and bake generates raycast_bindings.json from this table (plus the modes' deeplinks); the
// `dotfiles raycast link` widget reads the same generator and addresses an entry by the last segment of
// its path (clipboard-history, my-schedule, …). Chord grammar: "+"-joined tokens, modifiers
// first (hyper, cmd, ctrl, opt, shift, fn), one key last (a-z, 0-9, a karabiner key name, or a
// symbol alias from utils/actions.ts such as ` or ⏎). Raycast's own hotkey settings stay empty
// for everything bound here.
//
// Shared tier only: karabiner.json is generated from these tables and committed to the public
// repo, so a binding for a work-only command (an employer's extension, an internal URL) does
// not go here. Set its hotkey in Raycast's own settings instead.
//
// Raycast asks "Always allow" the first time a binding's deeplink runs; `dotfiles raycast link
// prime <slug>` opens a new one so it is answered once.
// description says in one line what the command does; every binding needs one (the
// raycast_sync healthcheck step fails without it; `dotfiles raycast link edit <slug>` opens it).
export type RaycastShortcut = { chord: string; action: Deeplink }

export const raycastShortcuts: RaycastShortcut[] = [
  {
    chord: "hyper+4",
    action: deeplink("extensions/raycast/clipboard-history/clipboard-history", {
      title: "Clipboard History",
      description: "Search Raycast's clipboard history and paste an earlier copy",
    }),
  },
  {
    chord: "opt+s",
    action: deeplink("extensions/raycast/calendar/my-schedule", {
      title: "My Schedule",
      description: "Show today's and upcoming calendar events, with links to join meetings",
    }),
  },
  {
    chord: "ctrl+cmd+spacebar",
    action: deeplink("extensions/raycast/emoji-symbols/search-emoji-symbols", {
      title: "Search Emoji & Symbols",
      description: "Search emoji and symbols by name and insert the one picked",
    }),
  },
  {
    chord: "hyper+`",
    action: deeplink("extensions/raycast/snippets/search-snippets", {
      title: "Search Snippets",
      description: "Search the Raycast snippets (the dotfiles' raycast-snippets tiers) and paste one",
    }),
  },
]
