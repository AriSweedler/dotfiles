<!-- new-machine-report v1 fingerprint=38bb0f918c80e4aa run_id=20260910T002640 first_seen=2026-09-10 kind=error -->
# new-machine weekly check COULD NOT RUN — testhost, 2026-09-10 00:26

2 of 12 checks could not run, 2 warnings. First seen 2026-09-10 (1 week). This file is rewritten only when the set of
problems changes; the same failure gets a banner, not a new file. Deleting it means "acknowledged".
State lives in /tmp/nmtest/home/.local/state/new-machine/ · machine-readable: last-check.json

## The check itself could not run

| step | reason | detail |
|---|---|---|
| brew_drift | timed_out | timed out after 120s |
| brew_pkgs | bundle_check_unparsed | bundle check printed an unparsed line: → Something odd happened. |

## Also noted (warnings, no report on their own)

- local_dotfiles_repo: 1 unpushed commit (`git ldf push`)

## Raw log (last 40 lines)

```
[INFO] [2026-09-10T00:26:40.000112000Z] [verify] run started | run_id='20260910T002640' mode='check' host='testhost'
[INFO] [2026-09-10T00:26:40.004881000Z] [step::run] ==> brew
[INFO] [2026-09-10T00:26:40.093007000Z] [step::run] verdict | step='brew' status='ok' reason='brew_present'
[INFO] [2026-09-10T00:26:40.094120000Z] [step::run] ==> brew_pkgs
[INFO] [2026-09-10T00:26:41.071449000Z] [step::run] verdict | step='brew_pkgs' status='fail' reason='missing'
[INFO] [2026-09-10T00:26:41.072301000Z] [step::run] ==> brew_drift
[WARN] [2026-09-10T00:26:42.480900000Z] [brew::classify] untrusted tap declared | tap='hashicorp/tap'
[INFO] [2026-09-10T00:26:42.484017000Z] [step::run] verdict | step='brew_drift' status='fail' reason='drift'
[INFO] [2026-09-10T00:26:42.485002000Z] [step::run] ==> local_dotfiles_repo
[INFO] [2026-09-10T00:26:42.543311000Z] [step::run] verdict | step='local_dotfiles_repo' status='warn' reason='unpushed'
[INFO] [2026-09-10T00:26:42.544190000Z] [step::run] ==> karabiner
[INFO] [2026-09-10T00:26:42.747788000Z] [step::run] verdict | step='karabiner' status='warn' reason='karabiner_healthcheck'
[INFO] [2026-09-10T00:26:43.101266000Z] [verify] summary | status='fail' fail='2' warn='3' ok='7'
```
Full log: /tmp/nmtest/home/.local/state/new-machine/verify/log.txt
Run dir:  /tmp/nmtest/home/.local/state/new-machine/runs/20260910T002640/  (summary.json, Brewfile.merged, bundle_check.out, drift.json)
Trail:    /tmp/nmtest/home/.local/state/new-machine/verify.log

## How to feed this to Claude

1. In a terminal: `cd ~` and paste this one line:

    claude "Read /tmp/nmtest/home/Desktop/new-machine-FAILED.md and /tmp/nmtest/home/.local/state/new-machine/verify/log.txt. Load the /ari-dotfiles skill first and follow its two-tier rules: shared tier (~/.config, git df) commit and NEVER push, end with 'Run git_df_push when ready'; local tier (~/.local, git ldf) commit and then git ldf push. Diagnose why 'new-machine check' cannot run on this machine and fix it; do not silence the check. Finish with 'new-machine check --json' and show me the output."

2. Rules for the fix (the /ari-dotfiles skill is canonical):
   - Declared brew state is the two Brewfiles: /tmp/nmtest/home/.config/new-machine/Brewfile (global, df) and
     /tmp/nmtest/home/.local/share/new-machine/Brewfile (local, ldf), plus `Brewfile.ignore` beside each.
     Undeclared items are settled with `new-machine brew decree …`, never by editing brew's state and never with
     `brew bundle cleanup`, `brew upgrade`, or `brew bundle add`.
   - Do not install anything to make the check pass except `new-machine apply <step>`, which installs only what
     the Brewfiles declare. Orphaned kegs need a human: propose the command, do not run it.
   - Never `--no-verify`; never commit a `*.secret.zsh`.
   - If a finding is a false alarm, fix the checker in /tmp/nmtest/home/.config/new-machine/ and add a
     tests/test_*.sh case that reproduces it; `bash /tmp/nmtest/home/.config/new-machine/tests/run.sh` must pass.

## What "fixed" looks like

`new-machine check` exits 0 and prints `status: ok`. The next Monday run (or `new-machine verify` now) moves this
file to /tmp/nmtest/home/.local/state/new-machine/reports/ and posts "verified OK".
