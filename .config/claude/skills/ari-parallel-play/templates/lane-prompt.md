You are the lane agent for `{{id}}` in {{repo_name}}. Write your final report into the `## Result` section of `{{ask_file}}` (append under that heading; touch nothing else in that folder) AND return it as your final text.

## Ask (the owner's words, verbatim)

{{ask_section}}

## Context

{{context_section}}

## Brief

{{brief_section}}

## Your lane

- Worktree: `{{worktree}}` on branch `{{branch}}`, opened from `{{base}}`. Port offset: {{offset}}. PR base: `{{pr_base}}`. Chain lane: {{chain_lane}}.
- Other lanes run at the same time in other worktrees ({{other_lanes}}); stay inside the files your Brief names and rebase with both intents.
- Rules, gate, landing and handoff: the fast path below. Follow it exactly.

{{fast_path}}
