---
description: Coordinate a task across parallel subagents
argument-hint: "<task>"
---

Coordinate this task using the shared project task board and subagents: $@

First inspect enough context to split the work safely. Create project_tasks entries with explicit dependencies and file ownership. The main coordinator owns task-board updates because isolated worktrees do not share `.pi/tasks.json`. Launch independent subagents in one parallel tool call, using worktree isolation for agents that modify files. Do not assign overlapping files concurrently. Gather results, integrate and verify centrally, then update every task with its final status and concise completion notes.
