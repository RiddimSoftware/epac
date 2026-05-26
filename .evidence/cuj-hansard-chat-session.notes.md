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

The fixture `45-1-HAN050-E` corresponds to Parliament 45, Session 1, Hansard number 050 (Tuesday, **November 4, 2025**). When the CUJ sub-step says "verify today's date is visible on the calendar," the LLM decision maker must assert against **2025-11-04**, not wall-clock today. The fixture date is static; wall-clock today will not equal it after 2025-11-04.

## Green date meaning

In the current Parliament calendar, dates with Hansard content are shown with a green date affordance. They are visually distinguished from non-sittings by an app-positive green date chip (filled green rounded rectangle), and their accessibility labels resolve as `sitting day`.

## Pagination interaction

The current debate view advances through content by exposing a tap gesture on the chat surface (`"Tap anywhere to continue"` hint). Repeated taps (or equivalent tap-next interaction) move the view forward until the terminal state appears (`End`).

## Related files

| File | Purpose |
|---|---|
| `.evidence/cuj-hansard-chat-session.json` | Deterministic JSON evidence plan for the same CUJ (xctest runner) |
| `.evidence/regression-parliament-calendar.json` | Broader Parliament-tab regression plan |
| `.evidence/README.md` | Evidence directory schema and runner contract |
