import { execFile, spawn } from "node:child_process"
import { appendFile } from "node:fs"
import { For, createSignal } from "solid-js"
import { Plugin } from "@opencode/plugin/tui"

// Bead ids for the current session: a one-line index above the composer, and a picker
// on ctrl+b.
//
// A click on an id opens the bead's Scotty page, and the picker pops the bead's
// tmux-tooltip card and copies "<id> | <title>". The split is forced by OpenCode: its
// link handler calls the http-only `open` helper, which rejects a tmux-tooltip:// href
// outright, and the TUI takes mouse events itself so tmux's MouseUp1Pane binding never
// sees the click. So the href must be https, and the card comes from ctrl+b.
//
// Everything about the card — fields, colors from beads.conf, copy text, URL — is built
// by bead_link.zsh; this plugin never assembles one.
//
// Two things keep the keypress fast, both measured:
//   - No scanning on the keypress. Scanning means stringifying the message list, which
//     grows without bound; ids are collected on turn end instead.
//   - One shell call in flight at a time. bd is a single-writer embedded Dolt, so two
//     concurrent reads take 1.5s where one takes 0.9s.
const SCRIPT = `${process.env.HOME}/.config/opencode/bead-links.zsh`
const TOOLTIP = `${process.env.HOME}/.config/bin/tmux-tooltip`
const LOG = "/tmp/opencode-bead-links.log"
const ID = /beads-[a-z0-9]+/g
const MAX_FOOTER = 3
const MAX_PICKER = 12
// Only the tail is scanned: the ids in play are the ones just mentioned, and the scan
// runs on every turn end.
const TAIL = 20

type Link = { id: string; card: string; page: string; title: string }

export default Plugin.define({
  id: "opencode.bead-links.tui",
  setup(context) {
    const [links, setLinks] = createSignal<Link[]>([])
    let current = ""
    let ids: string[] = []
    let attempts = 0
    let inflight: Promise<Link[]> | null = null

    const trace = (line: string) => {
      appendFile(LOG, `${new Date().toISOString()} ${line}\n`, () => {})
    }

    const scan = async (id: string): Promise<string[]> => {
      try {
        // A freshly loaded plugin has an empty message cache: list() returns nothing
        // until the session is synced from the server.
        await context.data.session.message.sync(id)
      } catch {
        // Fall through to whatever is cached.
      }
      try {
        const messages = context.data.session.message.list(id) ?? []
        trace(`messages id=${id.slice(-6)} n=${Array.isArray(messages) ? messages.length : typeof messages}`)
        const slice = Array.isArray(messages) ? messages.slice(-TAIL) : messages
        return [...new Set(JSON.stringify(slice).match(ID) ?? [])]
      } catch {
        return []
      }
    }

    const load = (wanted: string[]): Promise<Link[]> =>
      new Promise((resolve) => {
        if (wanted.length === 0) {
          resolve([])
          return
        }
        const started = Date.now()
        execFile("/bin/zsh", [SCRIPT, ...wanted], { timeout: 5000 }, (error, stdout) => {
          trace(`load ids=${wanted.length} ms=${Date.now() - started} err=${error ? "yes" : "no"}`)
          if (error) {
            resolve([])
            return
          }
          resolve(
            stdout
              .split("\n")
              .filter((line) => line.split("\t").length >= 4)
              .map((line) => {
                const [beadID, card, page, title] = line.split("\t")
                return { id: beadID, card, page, title }
              }),
          )
        })
      })

    // One load at a time: a second caller joins the first rather than starting a
    // competing bd read.
    const loadAll = (): Promise<Link[]> => {
      if (inflight) return inflight
      inflight = load(ids).then((rows) => {
        inflight = null
        return rows
      })
      return inflight
    }

    const remember = (found: string[]) => {
      if (found.length === 0) return
      ids = [...new Set([...ids, ...found])].slice(-MAX_PICKER)
    }

    const warm = async (id: string) => {
      if (!id) return
      const started = Date.now()
      remember(await scan(id))
      trace(`scan ids=${ids.length} ms=${Date.now() - started}`)
      // A plugin reload renders before the session's message cache is populated, so an
      // empty scan is retried a few times rather than leaving the footer blank until the
      // next turn ends.
      if (ids.length === 0 && attempts < 3) {
        attempts += 1
        setTimeout(() => void warm(id), 1000)
        return
      }
      attempts = 0
      const rows = await loadAll()
      setLinks(rows.slice(-MAX_FOOTER))
    }

    // Called from the render prop, which is where the session id actually is.
    const show = (id: string | undefined) => {
      if (!id || id === current) return
      current = id
      ids = []
      void warm(id)
    }

    try {
      context.ui.slot({
        append: "session.composer.top",
        render: ({ sessionID }) => {
          show(sessionID)
          return (
            <text>
              <span>beads: </span>
              <For each={links()}>
                {(link) =>
                  link.page ? (
                    <a href={link.page}>
                      <u>{link.id + " "}</u>
                    </a>
                  ) : (
                    <span>{link.id + " "}</span>
                  )
                }
              </For>
            </text>
          )
        },
      })
    } catch {
      // A missing slot must not take the TUI down; ctrl+b still works.
    }

    try {
      context.keymap.layer(() => ({
        mode: "global",
        commands: [
          {
            id: "beads.openCard",
            title: "Bead: pick one and pop its card",
            group: "Beads",
            bind: "ctrl+b",
            palette: true,
            run: async () => {
              const started = Date.now()
              const rows = await loadAll()
              trace(`ctrl+b ids=${ids.length} rows=${rows.length} ms=${Date.now() - started}`)
              if (rows.length === 0) {
                context.ui.toast.show({ message: "No bead ids in this session", variant: "info" })
                return
              }
              const chosen = await context.ui.dialog.select({
                title: "Bead card",
                options: rows.map((link) => ({
                  title: link.id,
                  value: link.card,
                  description: link.title,
                })),
              })
              if (!chosen) return
              spawn(TOOLTIP, ["open", "--url", chosen], {
                detached: true,
                stdio: "ignore",
              }).unref()
            },
          },
        ],
      }))
    } catch {
      // No keymap: the footer still renders.
    }

    const stops = [
      context.data.on("session.execution.succeeded", (event) => {
        if (event.data.sessionID !== current) return
        // Collect ids and warm every row in the background, so the next ctrl+b reads
        // cache instead of paying a cold bd read while Ari waits.
        void warm(current)
      }),
    ]

    return () => stops.forEach((stop) => stop())
  },
})
