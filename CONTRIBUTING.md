# Contributing to epac

Thanks for your interest in helping improve epac. This repository is open source so you can inspect how the product works and use your own coding agent to help shape feature proposals.

epac's community contribution path is product-first. We are not currently using community source-code pull requests as the main way to add product features. Instead, we want each substantial contribution to become a well-formed spec that maintainers can review and, if accepted, route into the [Riddim Software](https://riddimsoftware.com/) Factory.

The public intake service and tracker are not live yet. Until they are, use this guide to prepare a proposal before opening a GitHub issue or contacting the maintainers.

## How to report an issue

For a bug report, open an issue with:

- a short, descriptive title
- what you expected to happen
- what actually happened
- reproducible steps (if applicable)
- logs or screenshots when helpful

For bug fixes that should be ready for an LLM or autonomous developer session,
create a bugfix SPEC first:

```bash
python3 scripts/intake/bugfix_spec.py new
python3 scripts/intake/bugfix_spec.py validate .factory/intake/<generated>/SPEC.md
```

The guide lives at [`docs/factory/bugfix-intake.md`](docs/factory/bugfix-intake.md).
Attach the validated `SPEC.md` contents or rendered issue body to the issue.

If this is a question or clarification request, reach out via email at [sunny@riddimsoftware.com](mailto:sunny@riddimsoftware.com).

## How to propose a feature

Start by cloning the repo and opening it in your preferred coding agent. Ask the agent to read this file, `README.md`, `CLAUDE.md` or `AGENTS.md`, and the relevant product or architecture docs before drafting a proposal.

Your agent may edit the checkout locally to explore an idea or draft evidence for the spec. Those edits are scratch work. They are not the expected contribution artifact, and you do not need to run the app locally to contribute.

The expected artifact is one top-level spec. Depending on scope, that spec may describe:

- one issue for a narrow feature or bug fix
- one project with several child issues
- one initiative with multiple projects

Do not split one discussion into unrelated proposals. If your idea contains several independent outcomes, ask your agent to identify the single top-level shape or recommend splitting the discussion.

## Factory readiness checklist

A proposal is ready for maintainer review when it includes:

- **Use case** — who the feature is for, what they are trying to do, and what success looks like.
- **User value** — why this matters for epac users now.
- **Official data source** — the government or open-data source, owner, URL, format, update cadence, and required fields.
- **Data provenance** — how any app-visible claim traces back to the source.
- **App behavior** — what the user will see, do, receive, or configure in epac.
- **Acceptance criteria** — testable criteria, preferably written as `Given / When / Then`.
- **Out of scope** — related work that is intentionally not included.
- **Implementation surface** — likely affected areas such as `ios/`, `backend/`, `website/`, `data/`, `shared/`, or release metadata.
- **Verification plan** — commands, manual checks, screenshots, or a clear reason verification was not run.
- **Risks and edge cases** — privacy, stale data, missing data, civic neutrality, App Store review, or release concerns.

If the official data source is unclear, submit a source-discovery proposal instead of a product feature. A good source-discovery proposal explains the user need, candidate sources, and what must be proven before the feature can be built.

## Data source policy

epac is a civic app. Product features must be grounded in authoritative public sources.

- Prefer official government or open-data sources.
- Do not propose new Riddim-owned runtime backend dependencies for the app.
- Do not invent, summarize, or rewrite civic facts with generated text.
- Treat postal code, location, and notification data as sensitive. Explain why the data is needed and how the app can minimize retention or avoid server-side collection.
- If data is unavailable, stale, licensed restrictively, or not machine-readable, state that clearly in the proposal.

Examples of appropriate source categories include House of Commons open data, Elections Canada electoral geography, Statistics Canada public datasets, and other official Canadian public records.

## What about local edits?

Local edits are optional scratch work. They can help your agent answer questions like:

- Is this feasible in the current architecture?
- Which module would be affected?
- What source data shape does the app need?

Please do not open product-feature PRs with those local edits unless a maintainer explicitly asks for one. Maintainers own final implementation, review, release, and App Store submission.

## Pull requests

Small non-product fixes may still be appropriate as pull requests, such as documentation corrections, typo fixes, broken links, or test-only reproductions requested by a maintainer.

For any PR a maintainer asks you to open:

- create a branch from `main`
- keep the PR small and scoped to one purpose
- include a clear title and summary of what changed and why
- reference the issue or proposal you are addressing
- include test evidence in the PR description

## Community behavior

By contributing, you agree to follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## Support and contact

For non-security community questions, use issues. For other help requests, email [sunny@riddimsoftware.com](mailto:sunny@riddimsoftware.com).
