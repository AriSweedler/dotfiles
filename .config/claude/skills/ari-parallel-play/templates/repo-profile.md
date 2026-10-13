# Parallel-play profile: <repo name>

<!-- One file per repo. Each `##` section below is read verbatim into the lane prompt or a script flag by /ari-parallel-play. Delete an optional section you do not need; keep the required ones. -->

## Tooling

<!-- Required. How a lane runs the toolchain inside its worktree, e.g. the `node node_modules/<tool>/bin/<tool>.js <paths>` forms when `npx` is denied, or `.venv/bin/<tool>`. One sentence per tool. -->

## Gate

<!-- Required. The numbered local gate, in order: typecheck; lint and format on the touched files only; the test files or suites the change touches only. Nothing that runs the whole tree. -->

1.
2.
3.

## Code rules

<!-- Required. The project's conventions in one paragraph: language strictness, module layout, where tests live, generated files that are never hand-edited. -->

## Dependencies

<!-- Required. First line: the shared dependency directory the orchestrator symlinks from the root into each worktree (`node_modules`, `.venv`, `vendor`), or `none`. Then the install rule in prose, e.g. "`node_modules` is a symlink to the root's; never `npm install`/`npm ci` in a worktree." -->

- Link:

## Shared paths

<!-- Optional. Path prefixes only one lane of a group may touch at a time. Default when absent: `docs/`. One per line. -->

## CI

<!-- Required. The workflow name (as `gh run list --workflow` sees it) and the job whose success merges a PR. -->

- Workflow:
- Gate job:

## GitHub

<!-- Required. The gh account for reads and the one for writes; the same account is fine. Name any env var that must be unset so gh uses the account's keyring token (e.g. GITHUB_TOKEN). -->

- Read account:
- Write account:
- Unset first:

## Groups

<!-- Optional. The areas whose lanes land as one chain, and how an ask maps to one (a path prefix, a tag in the ask title). Absent: every lane is solo. -->

## Lane environment

<!-- Optional. Per-lane values a lane must use, with the formula: "E2E_PORT_OFFSET = <group base> + 100 × <lane index>". Rendered into the lane prompt as written. -->

## Live check

<!-- Optional. Per group: the URL and the command that proves a merge is live (a curl for 200 and a new bundle hash, a health endpoint). Absent: a verified MERGED is the outcome. -->

## Commit

<!-- Optional. Extra commit or PR-body rules beyond /ari-pr. The Co-Authored-By trailer, the `[skip ci]` rule for chain lanes and the /dev/tty hook fallback always apply. -->
