# dotfiles/jobs

Job plugins for `dotfiles jobs`: one launchd job, `com.<user>.dotfiles-jobs`, fires on screen
unlock, at login and every five minutes, and runs the plugins whose triggers match. This
directory holds the shared tier's plugins; the local tier adds its own under
`~/.local/share/dotfiles/jobs/`, and the framework runs both (`dotfiles jobs list` shows each
with its tier). Same shape as the Chrome Exoskeleton: framework and public plugins in df,
private plugins in ldf, one place they meet.

A plugin is one executable file named for the job. Its second line says when it runs:

    # triggers: unlock load every:3600 Mon@10:05

- `unlock` — the screen was unlocked.
- `load` — the job was (re)loaded: login, or `dotfiles jobs install`.
- `every:<seconds>` — due on a tick, and at load, once that long has passed since the plugin
  last ran, whatever it exited with: a failing check waits out its period, it does not retry
  every five minutes. `dotfiles jobs list` shows the last run and its rc.
- `daily@HH:MM`, `Mon@HH:MM` … `Sun@HH:MM` — due on a tick, and at load, once the most recent
  scheduled moment is later than the plugin's last run. A moment missed while the machine was
  asleep fires on the first tick after wake, as launchd's own calendar jobs do; a plugin that
  has never run is due at once.

An optional `# timeout: <seconds>` line caps a run (default 900); the framework kills a
plugin that overruns, children first, and logs it as timed out. One hung plugin must not
hold the job, because launchd runs one instance at a time.

The framework runs the plugin with the trigger as `$1`, keeps its output in
`~/.local/state/dotfiles/jobs/<name>.log` (the previous run in `.log.bak.1`) and stamps a
success. Plugins are independent of one another, so the order they run in is irrelevant and
no name carries a number. A job with a CLI of its own (git-health, aws-sso-autologin) keeps it
in a `bin/` and leaves a shim here that execs it.

    dotfiles jobs list          plugins of both tiers, triggers, last run and rc, launchd state
    dotfiles jobs run <name>    run one now (trigger 'manual')
    dotfiles jobs install       the launchd job; idempotent; `dotfiles init` runs it

Simulate an unlock without locking: `notifyutil -p com.apple.screenIsUnlocked`.
