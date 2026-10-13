# The fast path (every lane agent)

You develop one feature and hand it off. You never watch CI, merge, or verify live: the orchestrator does.

## Scope

- One feature per PR. A working first pass with the touched suites green, not polish. Never fold an unrelated ask in.
- Budget: 25 minutes. Past it: commit what works, push, open the PR anyway, list what is left in the Result, return.
- Never end your turn to wait for something. Nothing wakes you. Poll in foreground loops of at most 60 s, or return.
- A permission denial is final: record it in the Result and route around; never re-run the same action in another form.

## Where

- Work only in your worktree `{{worktree}}` (branch `{{branch}}`, from `{{base}}`). `cd` there in every Bash call. Never touch the root checkout `{{root}}` or another lane's worktree.
- Dependencies: {{deps_rule}} Never `git clean -fdx`, never `git worktree remove` (the handoff script does it).
- Tooling: {{tooling}}
{{lane_env}}

## Gate (local; it stands in for CI on chain sub-PRs)

{{gate}}

No review agent for a change under about 300 lines.

## Code rules

{{code_rules}}

## Commit

- `git add <path>` one by one, never `git add -A`. `git -c commit.gpgsign=false commit -F <msgfile>`; the message ends with a blank line then `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. On a `/dev/tty` hook failure: `yes y | tr -d '\n' | script -q /dev/null git -c commit.gpgsign=false commit -q -F <msgfile>`.
- Chain lane (`{{chain_lane}}` is `yes`): the HEAD commit's subject ends with ` [skip ci]`; no chain PR runs CI on its own, the orchestrator runs it once on the finished chain.
{{commit_extra}}

## Land

1. `git fetch origin && git rebase {{base}}`: resolve conflicts yourself keeping both intents; re-run the touched suite. A base that is another lane's branch moves while you work: fetch and rebase again right before you push.
2. `git push --no-verify --force-with-lease -u origin {{branch}}`.
3. `{{gh_write}} gh pr create --base {{pr_base}} --title "<type>(<scope>): <what the user gains>" --body-file <file>`; the body: `## Summary` (the owner's words, what changes), `## Tests` (the gates you ran), then the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. An existing PR: `gh pr edit <n> --base {{pr_base}}`.
4. Append `## Result` to `{{ask_file}}` (outcome first, PR URL, head sha, files, gates run, what is left, denials). Touch nothing else in that folder.
5. Hand off: `zsh $HOME/.claude/skills/ari-parallel-play/bin/worktree.zsh --action handoff --root {{root}} --dir {{worktree}} {{link_flag}}` (unlinks the shared dependency symlink if any, removes the worktree; the branch stays).
6. Return your Result as your final text.
