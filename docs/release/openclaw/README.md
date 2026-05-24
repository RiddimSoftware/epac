# OpenClaw release-decision gate for epac

OpenClaw is a read-only release governor for epac App Store actions. It does not upload builds, submit App Store metadata, release versions, pause or continue phased release, or edit App Store Connect. It renders a decision that the existing release-manager path can use before taking those actions.

The repo-controlled policy lives in [`release-decision-policy.json`](./release-decision-policy.json). The executable evaluator is [`scripts/release/openclaw_release_decision.py`](../../../scripts/release/openclaw_release_decision.py).

## Source of truth

OpenClaw uses App Store Connect app-store-version state as the primary source of truth for the previous version:

1. `app_store_connect_app_store_version` — previous version, previous App Store state, and the timestamp when the previous version reached an accepted terminal state.
2. `github_release_metadata` — fallback when App Store Connect is unavailable; the release-manager receipt must identify the release/tag used.
3. `linear_release_issue_status` — fallback when App Store Connect is unavailable and the Linear release issue records the reviewed/released timestamp.
4. `manual_release_receipt` — last-resort fallback for demos or credential outages; it must include an approver and public-safe audit note.

Accepted previous-version terminal states are configured in the policy. The current v1 set is `APPROVED`, `READY_FOR_SALE`, `RELEASED`, `PHASED_RELEASE_COMPLETE`, and `DEVELOPER_REMOVED_FROM_SALE`.

## Decision vocabulary

OpenClaw returns exactly one of:

- `allow` — the release-manager may continue.
- `wait` — the action is valid, but the 24-hour gate has not elapsed.
- `request_approval` — a human approval is required before the release-manager continues.
- `escalate` — a risk signal needs owner attention before this can be decided.
- `block` — the release-manager must not continue from this evidence.

Every decision includes the candidate version/build, previous version, previous terminal timestamp, elapsed hours, risk signals, and the policy rule that fired.

## Action treatment

| Action | Gate behaviour |
|---|---|
| `testflight_upload` | Allowed by default. The 24-hour App Store release gate does not apply because no customer release or review submission happens. |
| `app_store_submit_for_review` | Requires at least 24 hours after the previous version reached an accepted terminal state. |
| `manual_release` | Requires the same 24-hour gate before releasing an already-approved version. |
| `phased_release_continue` | Requires human approval, but not the previous-version 24-hour age gate. |
| `emergency_hotfix_release` | May bypass the 24-hour gate only with an explicit emergency or human-approved override. |

## Override requirements

The 24-hour gate is bypassable only through an `emergency_hotfix_release` action or a human-approved override receipt. Overrides must record:

- who approved (`approvedBy`),
- why (`reason`),
- when (`approvedAt`),
- the candidate version and build,
- a public-safe audit note that can appear in the Feedvote demo receipt or release notes.

## Demo receipt

Render the included simulated decision:

```bash
python3 scripts/release/openclaw_release_decision.py \
  --policy docs/release/openclaw/release-decision-policy.json \
  --input docs/release/openclaw/demo-decision-input.json \
  --format markdown
```

Expected result: `wait`, because candidate `1.4.2` build `20260512.1` is only 15.5 hours after previous version `1.4.1` reached `READY_FOR_SALE`.

Release-manager automation can add `--fail-closed` to make any decision other than `allow` exit non-zero before the existing App Store submission/release step.
