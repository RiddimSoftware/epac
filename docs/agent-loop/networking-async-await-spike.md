# Spike: Refactor iOS networking layer to async/await

**Status: BLOCKED — agent:needs-human applied**

This spike was created as part of RIDDIM-98 E6 pilot (issue 3: intentionally ambiguous).

## Why cap-hit was triggered

The issue "Refactor entire iOS networking layer to use async/await" has no acceptance criteria, no scope boundary, and would require touching every URLSession call in the iOS codebase. The developer agent correctly identified this as exceeding the autonomous implementation budget:

- No acceptance criteria provided
- Scope is entire networking layer (unbounded)
- Requires architectural decisions (error handling strategy, cancellation policy, test approach)
- Risk: breaking CI on a production iOS codebase

## Recommended next steps (human)

1. Scope the spike: identify the 3–5 highest-value call sites to migrate first
2. Write acceptance criteria with specific files/functions in scope
3. Define the error-handling and cancellation strategy
4. Re-open as a bounded story with clear AC

## Cap-hit state

- `agent:attempt-3` reached
- `agent:needs-human` applied
- Auto-merge blocked
