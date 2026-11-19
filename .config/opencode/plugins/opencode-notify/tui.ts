import { spawn } from "node:child_process"
import { Plugin } from "@opencode/plugin/tui"

// The TUI part, not the server part, because it runs in the TUI's own process:
// the notifier reads TMUX_PANE from its environment to name the pane to jump
// back to, and the shared server process was started from whichever pane
// happened to start it first.
const SCRIPT = `${process.env.HOME}/.config/opencode/notify.zsh`
const MAX_MESSAGE = 90

function truncate(text: string, max: number) {
  return text.length > max ? `${text.slice(0, max - 1)}…` : text
}

function run(args: string[]) {
  const child = spawn("/bin/zsh", [SCRIPT, ...args], {
    detached: true,
    stdio: "ignore",
  })
  // A missing script must not become an unhandled 'error' event in the TUI.
  child.on("error", () => {})
  child.unref()
}

export default Plugin.define({
  id: "opencode.notify.tui",
  setup(context) {
    // Proves this part loaded and can reach the script, without waiting for a
    // turn to end; a loaded part with no `firing` lines points at the event name.
    run(["--loaded"])

    // session.execution.* fires for child sessions too, so a turn that fans out
    // subagents would post one banner per child, each replacing the last.
    const isRoot = (sessionID: string) => {
      const root = context.data.session.root(sessionID)
      return !root || root === sessionID
    }

    const fire = (message: string) => run([truncate(message, MAX_MESSAGE)])

    const sessionTitle = (sessionID: string) => {
      const title = context.data.session.get(sessionID)?.title
      return title ? truncate(title, 50) : ""
    }

    const stops = [
      context.data.on("session.execution.succeeded", (event) => {
        if (!isRoot(event.data.sessionID)) return
        const title = sessionTitle(event.data.sessionID)
        fire(title ? `Turn finished — ${title}` : "Turn finished")
      }),
      context.data.on("session.execution.failed", (event) => {
        if (!isRoot(event.data.sessionID)) return
        fire(`Turn failed: ${event.data.error.message}`)
      }),
      context.data.on("permission.asked", (event) => {
        if (!isRoot(event.data.sessionID)) return
        fire(`Needs permission: ${event.data.message ?? event.data.action}`)
      }),
    ]

    return () => stops.forEach((stop) => stop())
  },
})
