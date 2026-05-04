# epac

iOS civic-engagement app — Canada's House of Commons Hansard debates in a group-chat format.

> **Autonomous PR loop active** — cosmetic and functional changes may be implemented and reviewed automatically by the agent loop (RIDDIM-91 pilot). See `docs/agent-loop-enrollment.md` for details.

## Development

See `CLAUDE.md` for the full engineering guide.

## Open design question: search result ordering

The search backend currently uses Postgres `tsvector` rank ordering. As result volume grows there are two reasonable options for surfacing the most relevant debates:

**Option A — Recency bias:** Weight newer debates more heavily in ranking. Simpler, predictable. Risk: buries historically significant but older speeches.

**Option B — Engagement signals:** Rank by a combination of text relevance + member prominence (cabinet vs backbench) + sitting recency. More nuanced. Risk: "prominence" is politically loaded and hard to define objectively.

A decision is needed before the search ranking spike (EPAC-452 follow-on) can proceed. Both options are defensible — this requires a product judgment call, not just a technical one.
