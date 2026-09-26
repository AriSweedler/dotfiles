# The fast path (every lane agent)

You develop one feature and hand it off. You never watch CI, merge, or verify live: the orchestrator does.

## Scope

- One feature per PR. A working first pass with the touched suites green, not polish. Never fold an unrelated ask in.
- Budget: 25 minutes. Past it: commit what works, push, open the PR anyway, list what is left in the Result, return.
- Never end your turn to wait for something. Nothing wakes you. Poll in foreground loops of at most 60 s, or return.
- A permission denial is final: record it in the Result and route around; never re-run the same action in another form.

## Where

- Work only in your worktree `{{worktree}}` (branch `{{branch}}`, from `{{base}}`). `cd` there in every Bash call. Never touch the root checkout `{{root}}` or another lane's worktree.
- `{{worktree}}/node_modules` is a symlink to the root's. Never `npm install`/`npm ci`, never `git clean -fdx`, never `git worktree remove` (the handoff script does it).
- `npx` is denied. Use `npm run typecheck`; `node node_modules/eslint/bin/eslint.js <paths>`; `node node_modules/prettier/bin/prettier.cjs --check|--write <paths>`; `node node_modules/vitest/vitest.mjs run <files>` or `npm run test:<suite>`; `node --experimental-strip-types <tool.ts>`; Playwright `PATH="$PWD/node_modules/.bin:$PATH" E2E_PORT_OFFSET={{offset}} node node_modules/@playwright/test/cli.js test <spec> --project=pages` (always offset {{offset}}).

## Gate (local; it stands in for CI on stack sub-PRs)

1. `npm run typecheck`.
2. eslint and prettier `--check` on the files you touched, not the tree.
3. Only the suites your change touches (`npm run test:<suite>`). Never the full matrix.
4. At most one e2e spec, at your offset.
5. Goldens (`test/fixtures/styles/<game>.*.json`): re-record only when a pinned selector changed, your game's files only. Story PNG baselines: re-record darwin only if a pinned screen changed; never run the linux baseline workflow (the orchestrator records linux once on the stack).
6. No review agent for a change under about 300 lines.

## Code rules

Strict TS, functional style (no raw loops outside `*.algorithms.ts`), reducer pure with effects as data, DOM only through `web/shared/edge/dom.ts`, a CONTRACT.md row for every class the TS toggles, tests beside modules, `page.ts` is the source and `index.html` is regenerated (`node --experimental-strip-types tools/shell-markup.ts --write`), never hand-edited.

## Commit

- `git add <path>` one by one, never `git add -A`. `git -c commit.gpgsign=false commit -F <msgfile>`; the message ends with a blank line then `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. On a `/dev/tty` hook failure: `yes y | tr -d '\n' | script -q /dev/null git -c commit.gpgsign=false commit -q -F <msgfile>`.
- Chain lane (`{{chain_lane}}` is `yes`): the HEAD commit's subject ends with ` [skip ci]`; no chain PR runs CI on its own, the orchestrator runs it once on the finished chain.

## Land

1. `git fetch origin && git rebase {{base}}`: resolve conflicts yourself keeping both intents; regenerate `index.html` if `page.ts` changed on either side; re-run the touched suite. A base that is another lane's branch moves while you work: fetch and rebase again right before you push.
2. `git push --no-verify --force-with-lease -u origin {{branch}}`.
3. `unset GITHUB_TOKEN; export GH_TOKEN=$(gh auth token --user {{write_user}}); gh pr create --base {{pr_base}} --title "<type>(<scope>): <what a player gets>" --body-file <file>`; the body: `## Summary` (the owner's words, what changes), `## Tests` (the gates you ran), then the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. An existing PR: `gh pr edit <n> --base {{pr_base}}`.
4. Append `## Result` to `{{ask_file}}` (outcome first, PR URL, head sha, files, gates run, what is left, denials). Touch nothing else in that folder.
5. Hand off: `zsh $HOME/.claude/skills/ari-parallel-play/bin/worktree.zsh --action handoff --root {{root}} --dir {{worktree}}` (unlinks the symlink, removes the worktree; the branch stays).
6. Return your Result as your final text.
