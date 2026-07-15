---
description: Execute a scoped task through exploration, implementation, verification, and review
argument-hint: "<approved spec, task, or spec path>"
---

Solve this task end to end:

$@

Use an evidence-driven workflow. Do not skip phases silently.

1. **Contract**: Extract observable acceptance criteria, constraints, and non-goals. Inspect any referenced specification. Ask one blocking question with `ask_question` only when repository inspection cannot resolve it.
2. **Explore**: Inspect the smallest relevant surface using `git_inspect`, `read`, `grep`, `find`, and `ls`. Use an Explore agent only when discovery is broad or uncertain.
3. **Plan**: For a change touching three or more files, changing architecture/contracts, or carrying meaningful migration risk, state a short ordered plan before editing. Create or claim `project_tasks` entries when persistent coordination is useful.
4. **Implement**: Make the smallest coherent change that satisfies the contract. Follow existing patterns and avoid unrelated refactors. Use an isolated Implement agent only when all required inputs are committed and the worktree boundary is useful.
5. **Verify**: Run `project_check` with the narrowest relevant action first, then broaden when justified. Treat failed, skipped, and unavailable checks distinctly. Diagnose failures rather than rerunning blindly.
6. **Inspect**: Use `git_inspect` for final status, changed files, and the full relevant diff. Check for accidental files, debug output, generated artifacts, secrets, and scope drift.
7. **Review**: For nontrivial or risky work, use a fresh Review agent with the acceptance criteria and exact diff. Fix actionable findings and rerun affected checks. Do not manufacture review findings when none exist.
8. **Close**: Mark claimed tasks done only after verification. Report files changed, exact checks and results, acceptance criteria coverage, and remaining limitations. Never claim completion without evidence.

If implementation cannot safely proceed, stop at the blocked phase and explain the smallest decision or input needed.
