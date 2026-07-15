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

After presenting the draft, use `ask_question` to ask whether I want to:

- Approve the specification
- Revise a specific section
- Explore another design option
- Produce a read-only implementation plan from the approved specification

If I request revision, ask only for the missing decision and then present the complete updated specification. Do not begin implementation in this workflow. When approved, clearly label the final version `Approved specification` and tell me that `/solve` will leave plan mode and can implement it.
