# cuj-hansard-chat-session — Runner Notes

## Launch arguments and environment

| Key | Value |
|---|---|
| Launch argument | `-evidence-mode` |
| Environment variable | `EPAC_EVIDENCE_MODE=1` |
| Fixture identifier | `EPAC_EVIDENCE_FIXTURE=45-1-HAN050-E` |

These match the determinism contract used by the sibling JSON evidence plan (`.evidence/cuj-hansard-chat-session.json`). The smoke runner must pass all three when launching the app so the in-memory SwiftData store is seeded from the Hansard fixture before any step executes.

## Simulator

| Field | Value |
|---|---|
| Device | iPhone 17 Pro Max |
| UDID | `1B4F22DF-E851-4A3B-AFFE-0EA338BD5D48` |
| Destination string | `platform=iOS Simulator,name=iPhone 17 Pro Max` |

## Fixture date implication

The fixture `45-1-HAN050-E` corresponds to Parliament 45, Session 1, Hansard number 050 (Tuesday, **November 4, 2025**). When the CUJ sub-step says "verify today's date is visible on the calendar," the LLM decision maker must assert against **2025-11-04**, not wall-clock today. The fixture date is static; wall-clock today will never match it after 2025-11-04 has passed.

The first subject of business in HAN050 is "Foreign Affairs" (under Routine Proceedings). Steps that tap into a subject of business should target that entry or the first visible one, not a hardcoded label that may change if a different fixture is used in future.

## Related files

| File | Purpose |
|---|---|
| `.evidence/cuj-hansard-chat-session.json` | Deterministic JSON evidence plan for the same CUJ (xctest runner) |
| `.evidence/regression-parliament-calendar.json` | Broader Parliament-tab regression plan |
| `.evidence/README.md` | Evidence directory schema and runner contract |
