# dotfiles/jobs

Job plugins for `dotfiles jobs`: one launchd job, `com.<user>.dotfiles-jobs`, runs the plugins
whose triggers match on screen unlock, at login and every five minutes. Its program is a small
resident agent launchd keeps alive, because macOS announces an unlock only as a distributed
notification, which launchd itself cannot subscribe to; the agent observes it, keeps the timer,
runs the load tick when it starts, and never overlaps two runs. This
directory holds the shared tier's plugins; the local tier adds its own under
`~/.local/share/dotfiles/jobs/`, and the framework runs both (`dotfiles jobs list` shows each
with its tier). Same shape as the Chrome Exoskeleton: framework and public plugins in df,
private plugins in ldf, one place they meet.

A plugin is one executable file named for the job. Its header says when it runs: a
`# triggers:` line, and any number of `# cron:` lines, one five-field expression each:

    # triggers: unlock load
    # cron: 20 * * * *

- `unlock` — the screen was unlocked.
- `load` — the job was (re)loaded: login, or `dotfiles jobs install`.
- `# cron: minute hour day-of-month month day-of-week` — standard five fields: `*`, `n`,
  `a-b`, `*/s`, `a-b/s`, comma lists; Sunday is 0 or 7. Due on a tick, and at load, once the
  expression's most recent moment at or before now is later than the plugin's last run,
  whatever that run exited with, so a failing check waits for its next moment rather than
  retrying every five minutes. Unlike cron, a moment missed while the machine was asleep fires
  on the first tick after wake, as launchd's own calendar jobs do; a plugin that has never run
  is due at once. Resolution is the tick, five minutes. `dotfiles jobs list` shows each
  plugin's last run and rc.

An optional `# timeout: <seconds>` line caps a run (default 900); the framework kills a
plugin that overruns, children first, and logs it as timed out. One hung plugin must not
hold the job, because launchd runs one instance at a time.

A plugin that needs setup names it on a `# deps:` line:

    # deps: node

Each name is an executable under `~/.local/share/dotfiles/deps/` (this machine) or
`~/.config/dotfiles/deps/` (shared). The local one wins: a dep says how this machine provides
something, and the machine knows best. The framework runs a plugin's deps in order before the
plugin, every time it runs, with the plugin's name as `$1` and 120 s each. A dep's stdout is
its contribution to the plugin's environment, `NAME=VALUE` lines and nothing else, exported
before the plugin starts; its stderr is setup chatter and goes to the plugin's log. A dep that
is unknown, exits non-zero, overruns, or prints anything but `NAME=VALUE` blocks the plugin:
the run is recorded with rc 125, the log says which dep and why, and the alert says "blocked".
`dotfiles jobs list` shows every dep, its tier, and the plugins that want it. This machine's
`node` dep activates the company node venv and prints the resulting `PATH`, so the checks in
`dotfiles-verify` that shell out to node find it under launchd.

The framework runs the plugin with the trigger as `$1`, keeps its output in
`~/.local/state/dotfiles/jobs/<name>.log` (the five runs before it in `.log.bak.1` …
`.log.bak.5`), stamps the run,
and tells the user how it ended: on success a two-second banner carrying the plugin's last
output line, on failure or timeout a persistent alert whose click opens the log. So a plugin
prints a one-line summary last and posts no completion banner of its own; a notification a
plugin does post is about its domain (aws-sso-autologin's click-to-login notice), never about
having finished. Plugins are independent of one another, so the order they run in is irrelevant and
no name carries a number. A job with a CLI of its own (git-health, aws-sso-autologin) keeps it
in a `bin/` and leaves a shim here that execs it.

    dotfiles jobs list          plugins of both tiers, triggers, last run and rc, agent state
    dotfiles jobs run <name>    run one now (trigger 'manual')
    dotfiles jobs unlock        simulate a screen unlock (SIGUSR1 to the agent)
    dotfiles jobs install       the launchd job; idempotent; `dotfiles init` runs it

Only a real lock and unlock proves the observer; the simulation proves everything after it.
