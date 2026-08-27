---
name: pi-delegate
description: Proactively delegate focused, bounded coding implementation, debugging, test-writing, refactoring, and repository investigation tasks to the local Pi worker. Use whenever the current coding task can be decomposed into a self-contained assignment while Claude retains architecture, decomposition, integration, and review.
---

# Pi delegation workflow

Use the installed `pi` Claude Code plugin as a worker harness. Claude is the orchestrator; Pi is the focused implementation/investigation worker.

## Default worker

For delegated work, pin this Pi model unless the user explicitly requests another model:

`llama.cpp/Qwen3.8-27B-Hybrid-IQ4_XS`

Delegate through the plugin's `pi:pi-companion-forwarder` agent. Include:

`--model llama.cpp/Qwen3.8-27B-Hybrid-IQ4_XS`

Do not try to invoke the user-facing `/pi:rescue` slash command from inside Claude. Use the plugin forwarder agent directly.

## Division of responsibility

Claude owns:
- understanding the user's overall goal
- architecture and design decisions
- decomposing broad work into assignments
- identifying dependencies between assignments
- integrating results across assignments
- reviewing Pi's changes
- deciding whether another assignment is needed
- final verification and user-facing summary

Pi should handle focused work such as:
- implementing one clearly specified behavior
- modifying a bounded function, module, or small set of files
- writing or updating tests for known behavior
- investigating one concrete bug or failing test
- tracing a localized code path
- performing mechanical or repetitive refactors
- implementing a design Claude has already chosen
- checking a specific hypothesis against the repository

Bias toward Pi for implementation work when the task is meaningfully larger than a trivial one-line edit and can be bounded cleanly.

Do not delegate:
- the entire broad feature when it can be decomposed
- unresolved architectural decisions
- ambiguous product requirements
- integration decisions spanning many subsystems
- tiny edits where delegation overhead exceeds the work
- final acceptance of Pi's own work

## Decompose before delegating

Before each delegation:

1. Determine the next smallest useful unit of work.
2. Resolve architectural choices that Pi should not have to invent.
3. Identify the relevant files or directories when reasonably knowable.
4. Specify behavior that must remain unchanged.
5. Define an observable completion condition.
6. Specify the verification Pi should perform.

Prefer one conceptual change per Pi run.

If several tasks are independent, delegate them separately. Do not bundle unrelated changes merely to reduce the number of Pi calls.

## Assignment contract

Shape each Pi assignment approximately like this:

```text
--model llama.cpp/Qwen3.8-27B-Hybrid-IQ4_XS --fresh

<task>
[One concrete objective.]

Relevant files/directories:
- [path]
- [path]

Requirements:
1. [required behavior]
2. [required behavior]
3. [important invariant]
</task>

<action_safety>
- Limit edits to [expected files/directories] unless another file is strictly necessary.
- Do not redesign adjacent systems.
- Preserve existing public behavior except where the task explicitly changes it.
</action_safety>

<completeness_contract>
- Implement the requested behavior completely.
- Add or update appropriate tests when applicable.
- Run the narrowest relevant tests/checks.
- Report files changed, verification performed, and any unresolved issue.
</completeness_contract>
```

Adapt the contract to the task rather than filling sections mechanically. Keep it concise enough that the worker's context is dominated by repository evidence, not instructions.

## Fresh vs. resume

Use `--fresh` for:
- a new independent assignment
- a different subsystem
- a new conceptual change
- work where old Pi context could distract from the current task

Use `--resume` only for a direct continuation of the immediately preceding Pi assignment, for example:
- fix the test failure from your previous change
- apply the specific correction identified in review
- continue the same investigation with one new piece of evidence

When resuming, send only the delta instruction and necessary new evidence. Do not restate the entire original assignment unless the direction changed materially.

## Read-only investigations

For diagnosis, exploration, or repository questions where Pi should not edit files, explicitly make the assignment read-only.

Ask Pi to return:
- evidence with file paths and relevant symbols
- the most likely explanation
- uncertainty or competing hypotheses
- a concise recommendation to Claude

Claude should use that evidence to make the higher-level decision.

## After every Pi assignment

Do not blindly accept Pi's result.

Claude must:
1. Inspect the result and relevant diff/files.
2. Check that Pi stayed within scope.
3. Verify important assumptions against the repository.
4. Run or inspect relevant tests/checks when warranted.
5. Decide whether the work is complete, needs a focused follow-up, or should be corrected directly by Claude.
6. Keep responsibility for the final integrated solution.

If Pi made a reasonable implementation mistake, prefer a short `--resume` correction when the same context is useful. If the approach itself is wrong, start a fresh assignment with the corrected design.

## Parallel work

Use separate Pi assignments for genuinely independent workstreams. Keep dependencies sequential.

Do not ask multiple workers to edit overlapping files concurrently unless the plugin's isolated-worktree/race mechanism is intentionally being used.

Use model racing only when comparing alternative solutions or diagnoses is worth the extra compute; it is not the default workflow.

## User requests

If the user explicitly says to:
- keep work in Claude: do not delegate
- use Pi/Qwen: bias strongly toward delegation
- use a different Pi model: honor that model for the requested assignment
- review rather than implement: use the plugin's review workflow when appropriate instead of inventing a rescue prompt

When this skill is invoked manually with `/pi-delegate`, apply this workflow to the user's current coding task. If arguments are supplied, treat them as the work the user wants orchestrated through Pi.
