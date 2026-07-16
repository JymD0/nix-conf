---
description: Interview me about a feature and produce an approved implementation specification
argument-hint: "<feature idea>"
---

# Adaptive specification interview

Help me turn this feature idea into a decision-complete specification:

$@

Stay read-only. Do not edit application code, configuration, or documentation during this workflow.

## Interview process

1. Inspect the repository first when it can answer architecture, naming, behavior, or compatibility questions. Prefer `git_inspect`, `read`, `grep`, `find`, and `ls` over asking me to rediscover the codebase.
2. Identify the decisions that materially affect scope, user behavior, data/API contracts, security, migration, compatibility, or acceptance criteria.
3. Ask one high-value question at a time with `ask_question`. Adapt each next question to the repository and prior answers.
4. Prefer 2-5 concrete choices. Explain the meaningful trade-off in each option description and identify your recommended choice when you have enough evidence. Use free text only when predetermined choices would be misleading.
5. Do not ask low-value questions, repeat answered questions, or ask implementation details that existing code resolves. Stop interviewing when remaining uncertainty is non-blocking. Aim for 3-8 questions, but use fewer when the request is already clear.
6. If interactive questions are unavailable, state explicit assumptions and continue with a draft rather than blocking indefinitely.

## Draft specification

Produce a concise draft containing:

- Summary and user outcome
- Goals
- Non-goals
- User-visible behavior and main flows
- Technical design and affected components
- Data, state, API, or interface changes
- Failure behavior and edge cases
- Security, privacy, compatibility, and migration considerations
- Acceptance criteria written as observable outcomes
- Verification strategy
- Decisions made, assumptions, and genuinely open questions

Keep requirements separate from implementation preferences. Label inferred details as assumptions.

## Convergence gate

Before offering approval, run a fresh `Critic` agent against the complete draft, the decisions made, and only the repository context needed to validate its assumptions. Count this initial critique as round one. Revise every blocking or material finding without expanding the agreed scope, then run another fresh Critic pass. Use at most three total Critic passes.

The specification converges when no blocking or material findings remain, acceptance criteria are observable and testable, assumptions and non-goals are explicit, and no contradictory or unresolved architectural decision remains. Minor wording and optional improvements do not block convergence. If blocking or material findings remain after the third pass, use `ask_question` to escalate the smallest unresolved decision instead of continuing automatically. Do not label the specification approved before it converges unless I explicitly accept the remaining risk.

Present the converged draft with a short `Convergence` note stating the number of passes and any non-blocking residual risks. Then use `ask_question` to ask whether I want to:

- Approve the specification
- Revise a specific section
- Explore another design option
- Produce a read-only implementation plan from the approved specification

If I request revision, ask only for the missing decision and then present the complete updated specification. Do not begin implementation in this workflow. When approved, clearly label the final version `Approved specification` and tell me that `/solve` will leave plan mode and can implement it.
