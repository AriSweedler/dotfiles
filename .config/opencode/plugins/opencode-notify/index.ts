import { Plugin } from "@opencode/plugin"

// Empty on purpose. This part exists only so the plugin registers and appears in
// `opencode plugin list`; the notification logic lives in tui.ts, because the
// server is one shared process and its TMUX_PANE is the pane that started it.
// Moving any of this here silently notifies the wrong pane.
export default Plugin.define({
  id: "opencode.notify",
  setup() {},
})
