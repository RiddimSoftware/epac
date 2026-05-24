# `app-store/experiments/`

Specifications for proposed and completed App Store Optimization experiments on ePac. Each file is a single experiment spec with hypothesis, variant spec, success metric, sample-size estimate, and risk.

These specs are produced by the **ASO Team** discipline (see `/Users/sunny/code/skills/aso-team/SKILL.md`) during Experiment Planning Meetings. The corresponding Linear issue tracks ownership and status; this file is the spec, version-controlled here so it lives next to the metadata it would change.

## Filename convention

`YYYY-MM-DD-<short-slug>.md` where the date is the spec creation date.

## Experiments are not auto-run

Merging an experiment spec into `main` does **not** start the experiment. Experiments run only when:

1. The corresponding Linear issue is moved to `In Progress` by a human, AND
2. Pre-conditions documented in the spec (baseline traffic, gating issues shipped, vendor selection) are met.

The ASC delivery GitHub Action does not currently auto-submit PPO treatments — it submits classic metadata, screenshots, in-app events, and CPPs. PPO treatments are configured in App Store Connect manually using the spec here as the source of truth.

## After an experiment runs

The spec file is updated in-place with a "Result" section appended (lift, significance, decision, follow-up issue). The Linear issue is closed; this folder retains the historical record.
