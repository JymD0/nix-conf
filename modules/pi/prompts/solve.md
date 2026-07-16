---
description: Execute a scoped task through adaptive subagent-driven development
argument-hint: "<approved spec, task, or spec path>"
---

Solve this task end to end:

$@

Use an evidence-driven workflow. Do not skip required gates silently.

## Route

Extract observable acceptance criteria, constraints, and non-goals, then classify the task before editing:

- **Direct**: mechanical, one file, roughly 15 changed lines or fewer, with no behavioral, dependency, schema, security, or migration impact.
- **Delegated**: any behavioral change, bug fix, test change, or change spanning two or more files. Delegate decision-complete normal implementation to `Implement` when all required inputs are committed.
- **Full pipeline**: four or more files, architecture or API changes, migrations, security or concurrency concerns, or unclear requirements. Use Explore -> Plan -> Critic convergence -> Implement -> parallel Review + Verify. Use `Implement-Critical` instead of `Implement` for security, concurrency, migrations, complex debugging, or high-risk API and architecture work.

State the chosen route in one sentence. Respect an explicit user request to work directly or use another workflow.

## Contract and discovery

Inspect referenced specifications and the smallest relevant code surface. Ask one blocking question with `ask_question` only when repository inspection cannot resolve it. Treat an approved, converged specification as the frozen implementation contract; do not silently reinterpret it. For the full pipeline, require a concise Explore pass followed by Plan even when the target appears known; scale their breadth to the uncertainty and do not duplicate their work in the main session. Outside the full pipeline, use Explore or Plan only when discovery or design uncertainty justifies them.

## Design convergence

For the full pipeline, give a fresh `Critic` agent the complete specification, proposed plan, acceptance criteria, and only the repository context needed to challenge assumptions. Count this initial critique as round one. Send blocking and material findings back to Plan for revision, then run another fresh Critic pass. Use at most three total Critic passes.

The plan converges when Critic reports no blocking or material findings and the plan covers dependencies, failure behavior, migration or rollback where relevant, and verification gates. Minor wording and optional enhancements do not block. If blocking or material findings remain after the third pass, stop and use `ask_question` to escalate the smallest unresolved decision. Do not begin implementation against an unconverged specification or plan unless the user explicitly accepts the remaining risk.

## Git and isolation gate

Inspect Git status before delegation and classify dirty paths. Launch an isolated implementation agent only when the committed base contains every required source file, test, fixture, and specification. Pass the base revision, acceptance criteria, non-goals, owned paths, and required checks in the prompt.

Unrelated dirty files are acceptable only when paths do not overlap. If task-relevant inputs are uncommitted, never stash, discard, or commit them silently. Ask for approval to create a checkpoint commit, or implement directly and report the reduced isolation.

## Implement and integrate

For delegated routes, let the selected implementation agent own source edits and focused checks. Use `Implement` for normal decision-complete work and `Implement-Critical` only for the high-risk categories above. Require one coherent commit and a compact report naming its branch, commit, files, checks, risks, and exact integration action. Do not redo its implementation in the main session.

Before integration, verify the returned commit has exactly the expected base as its parent and touches only expected paths. If it does not, stop and inspect the complete base-to-tip range rather than cherry-picking an ambiguous tip. Integrate the validated single commit, then inspect the integrated diff for accidental files, generated artifacts, debug output, secrets, and scope drift. The main coordinator owns `project_tasks` updates; isolated agents must not modify the shared board.

## Verify and review

Run the narrowest relevant verification first and broaden only when justified. For the full pipeline, launch Review and Verify together in one parallel tool call against the exact integrated commit or range. For ordinary delegated work, Verify is required; add Review when the change is nontrivial or risky. If checkpoint approval was declined and the main agent edited dirty task paths directly, give Review and Verify the explicit path-limited working-tree diff instead.

Any failed required check or actionable review finding blocks completion. Count the initial Review and Verify pass as round one. Fix findings through a narrowly scoped pass, then run a fresh Review plus affected verification against the final revision or working-tree diff. Use at most three total Review and Verify passes, stopping when no actionable findings remain and all required checks pass. Minor optional improvements do not block convergence. After the third pass, stop and report the smallest unresolved defect or decision instead of claiming completion. Treat failed, skipped, and unavailable checks distinctly.

On a timeout, missing commit, input mismatch, scope drift, or integration conflict, inspect the state rather than retrying blindly. Retry once only with a narrower prompt; otherwise stop and report the smallest decision needed.

## Close

Mark claimed tasks done only after verification. Report acceptance coverage, files changed, exact checks and results, review status, and remaining limitations. Keep agent handoffs compact and never paste full logs or diffs into the parent conversation.
