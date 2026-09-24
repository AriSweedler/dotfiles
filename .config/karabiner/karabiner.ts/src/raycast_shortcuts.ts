import { deeplink, type Deeplink } from "./utils/actions.ts"

// Raycast commands on a direct chord, no layer. raycast.ts compiles each into a Karabiner rule
// and bake generates raycast_bindings.json from this table (plus the modes' deeplinks); the
// raycast-link widget reads the same generator and addresses an entry by the last segment of
// its path (clipboard-history, my-schedule, …). Chord grammar: "+"-joined tokens, modifiers
// first (hyper, cmd, ctrl, opt, shift, fn), one key last (a-z, 0-9, a karabiner key name, or a
// symbol alias from utils/actions.ts such as ` or ⏎). Raycast's own hotkey settings stay empty
// for everything bound here.
//
// allowId is the key Raycast writes under alwaysAllowCommandDeeplinking after "Always allow";
// to find one, run the command once by deeplink, accept, then
//   defaults read com.raycast.macos alwaysAllowCommandDeeplinking
// (builtin_command_<camelCase> for Raycast's own commands, extension_<name>.<command>__dev for
// a dev extension). raycast-link --allow writes them so the prompt never shows.
export type RaycastShortcut = { chord: string; action: Deeplink }

export const raycastShortcuts: RaycastShortcut[] = [
  {
    chord: "hyper+4",
    action: deeplink("extensions/raycast/clipboard-history/clipboard-history", {
      title: "Clipboard History",
      allowId: "builtin_command_clipboardHistory",
    }),
  },
  {
    chord: "opt+s",
    action: deeplink("extensions/raycast/calendar/my-schedule", {
      title: "My Schedule",
      allowId: "builtin_command_calendar_schedule",
    }),
  },
  {
    chord: "ctrl+cmd+spacebar",
    action: deeplink("extensions/raycast/emoji-symbols/search-emoji-symbols", {
      title: "Search Emoji & Symbols",
      allowId: "builtin_command_searchEmoji",
    }),
  },
  {
    chord: "hyper+`",
    action: deeplink("extensions/raycast/snippets/search-snippets", {
      title: "Search Snippets",
      allowId: "builtin_command_searchSnippets",
    }),
  },
  {
    chord: "hyper+s",
    action: deeplink("extensions/arisweedler/raycast-go-aws/command-go-aws", {
      title: "Go AWS",
      allowId: "extension_raycast-go-aws.command-go-aws__dev",
    }),
  },
  {
    chord: "hyper+g",
    action: deeplink("extensions/benmusch/raycast-airtable-go-links/command-go-links", {
      title: "Search Go Links (Auto-Open)",
      allowId: "extension_raycast-airtable-go-links.command-go-links__dev",
    }),
  },
]
