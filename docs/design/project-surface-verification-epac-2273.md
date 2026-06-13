# Project Surface Verification - EPAC-2273

Date: 2026-06-13

Project: Bills, Votes & Committees - depth across the legislative cycle

Verification issue: EPAC-2273

Source implementation: EPAC-2262, PR #785, merge commit `9037d7defdad11a88bd6ae0896b1becba9b35095`

## Scope

EPAC-2262 introduced the backend push notification dispatcher for iOS notifications. The merged diff changed:

- `backend/push-notification-dispatcher/`
- `backend/live-vote-poller/internal/adapter/push/dispatcher.go`
- `backend/manifest/deployment-services.json`
- `infra/terraform/core/iam.tf`
- `docs/architecture/use-case-catalog.md`

No iOS SwiftUI screen, Settings surface, notification-preference screen, or localizable user copy changed in the implementation. The observed product surface for this verification is therefore the iOS push notification content payload delivered through APNs.

## Standards Loaded

- `CLAUDE.md` repository guidance
- `docs/brand/brand-brief-v1.md`
- `design-team` Project Surface Verification Meeting workflow
- `/Users/sunny/code/agent-config/context/linear-standards.md`

## Surface Inventory

| Surface | Status | Evidence |
| --- | --- | --- |
| iOS push notification content | Verified with remediation | `PushNotificationPayload` preserves the raw JSON document and `apns.Client.Deliver` posts it unchanged to APNs. No `aps.alert` title/body is generated. |
| In-app iOS GUI | Out of scope for this implementation | PR #785 changed backend and infra files only. |
| Backend API response text | No user-facing design finding | API responses are terse machine-facing JSON (`bad request`, `ok`). |

## Findings

### 1. Missing APNs-visible notification copy

- Severity: 7/10
- Dimension: Content strategy, interaction clarity, brand trust
- Evidence: `domain.PushNotificationPayload.JSON()` returns the compacted source payload, and `apns.Client.Deliver` sends that JSON directly to `/3/device/{token}`. The payload shape carries fields such as `division_id`, `parliament`, `session`, `result`, and `status`, but does not include an APNs `aps.alert` title/body or equivalent localized text.
- Impact: A user receiving the notification may see no useful lock-screen/banner copy, or APNs may reject the payload depending on final provider expectations. The feature promises iOS push notifications, but the human-facing surface does not yet state what happened or what the user can do next.
- Concrete fix: Add a backend payload formatter that converts the typed vote payload into an APNs notification envelope with neutral, source-grounded copy, for example title `Vote result posted` and body `Division {division_id} result: {result}.` Include a deep-link or source metadata field only if the iOS app already supports the destination.

## Scores

| Voice | Score | Notes |
| --- | ---: | --- |
| Accessibility Auditor | 6 | Notification copy is not inspectable without a generated alert body; no in-app focus or Dynamic Type surface changed. |
| Design Lead | 6 | The notification surface lacks a clear hierarchy because no title/body content is produced. |
| Brand Guardian | 6 | Raw vote fields do not satisfy epac's plain-spoken, sourced voice. |
| Interaction Critic | 5 | The user action after receiving a push is unclear; there is no visible summary or destination. |
| Content Strategist | 4 | The primary content surface is missing. |

Overall: 5.4/10, verified with remediation.

## Remediation

Created EPAC-2280 targeting `RiddimSoftware/epac`: generate APNs-visible notification copy for live-vote push payloads.

## Verification

- Reconstructed merged state from Linear EPAC-2262, PR #785, and merge commit `9037d7defdad11a88bd6ae0896b1becba9b35095`.
- Reviewed the current `origin/main` implementation files listed above.
- Simulator verification was skipped because EPAC-2262 did not change or expose an iOS GUI screen; the product surface is backend-generated notification payload content.
