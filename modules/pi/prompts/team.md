---
description: Coordinate independent work across parallel subagents
argument-hint: "<task>"
---

Coordinate this task using the shared project task board and subagents:

$@

Use `/team` only when the task has genuinely independent components. For trivial or tightly coupled work, use `/solve` instead.

First define observable acceptance criteria, non-goals, dependencies, and file ownership. Inspect Git status and confirm each isolated agent's required inputs exist in the committed base. Never stash, discard, or checkpoint task-relevant dirty changes without explicit approval.

Create `project_tasks` entries with explicit dependencies and non-overlapping ownership. The main coordinator owns all task-board updates because isolated worktrees do not share `.pi/tasks.json`.

Launch independent agents in one parallel tool call with worktree isolation for agents that modify files. Give each agent the base revision, exact owned paths, acceptance criteria, required checks, and a compact output contract. Do not assign overlapping files concurrently or ask multiple agents to perform the same discovery.

Require implementation agents to return one coherent commit plus a report under 400 words containing status, branch and commit, files, checks, risks, and integration action. Do not import pasted source or logs into the parent context.

Gather results and require each returned commit to have the assigned base as its direct parent and to touch only owned paths. If not, stop and inspect its complete base-to-tip range instead of cherry-picking an ambiguous tip. Integrate validated commits in dependency order, resolve conflicts centrally, and inspect the combined diff for artifacts, secrets, and scope drift. After integration, launch Review and Verify together in one parallel tool call against the exact combined revision range.

A failed required check, actionable review finding, missing commit, unexpected path, or integration conflict blocks completion. Fix findings narrowly, then run a fresh Review plus affected verification against the final range. Retry a failed agent once only with a narrower prompt; otherwise stop and report the smallest decision needed. Update every task with its final status and concise completion notes, then summarize acceptance coverage and remaining limitations.
