# epac

epac is built through agent-assisted specs.

The canonical way to contribute is not to set up the app locally, pick a programming language, or send a feature patch. Clone the repo, open it in your coding agent, and use the repository context to turn an idea into a `SPEC.md`.

The spec is the contribution. The [Riddim Software](https://riddimsoftware.com/) Factory takes over from there: it reviews accepted specs, turns them into implementation work, produces something testable, iterates when needed, and can ship the result to TestFlight and the App Store.

## How It Works

1. Clone this repository.
2. Open the repo in your preferred coding agent.
3. Discuss the feature, bug, or release improvement with the agent.
4. Let the agent read the repo context and shape the proposal.
5. Open a spec-only pull request that adds:

```text
proposals/<short-slug>/SPEC.md
```

The PR should not include product-code changes unless a maintainer explicitly asks for them. Local edits are fine as scratch work while your agent explores the idea, but they are evidence for the spec, not the artifact we review.

## What Goes In The Spec

A useful `SPEC.md` is a short design document. It should explain:

- the problem
- the goals and non-goals
- the user jobs or use cases
- the official government or open-data sources involved
- how app-visible claims trace back to those sources
- the proposed product behavior
- privacy, safety, and civic-neutrality risks
- validation evidence from the discussion or local exploration
- open questions and alternatives considered
- whether the work looks like one issue, a project, or an initiative

The most important epac rule: product behavior must be grounded in authoritative public sources. If the data source is unclear, write a source-discovery spec instead of a feature spec.

## What Happens Next

Maintainers review the spec PR. If the spec needs more detail, the reviewer asks for changes and you can continue the discussion with your coding agent. If the spec is accepted, it can be routed into the Riddim Software Factory.

The factory does a strong job of implementation, but software still needs feedback. Some specs produce a testable result on the first pass. Some need an iteration after testing. The contribution loop is designed for that: spec, implement, test, refine, release.

Future intake service work may add a tracker that follows an accepted spec into Linear, implementation, PR review, TestFlight, and App Store release. For now, the spec PR is the source of truth.

## Repo Context

This repo contains the source, data tooling, release scripts, and agent-readable project context that a coding agent needs to reason about epac. You do not need to run the app locally to contribute a spec.

For the current contribution rules, read [CONTRIBUTING.md](CONTRIBUTING.md).
