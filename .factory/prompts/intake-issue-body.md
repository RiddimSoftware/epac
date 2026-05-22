# Intake Issue Body Contract

Use this contract as the canonical body format for Stage-1 intake tools (kiosk, mobile web, repo-local) and Stage-2 parsers.

## Required markers

Every intake-produced GH Issue body must begin with the exact HTML comment block below. Stage 1 clients must preserve all fields and names.

```text
<!--
Intake-Session: <session-id, UUID v4>
Reporter-Email: <email or "anonymous">
Reporter-GitHub: <github-handle or empty>
Source: science-fair-2026-05-28 | mobile-web | repo-local
Mode: bug | feature | fact-check | open-data
Estimate: 1 | 2 | 4 | 8 | 16 | 32 | 64
Cost-Estimate-USD: <number or "pending">
-->
```

## Required body sections

### Bug
- `## Observed behaviour`
- `## Expected behaviour`
- `## Reproduction steps`
- `## Acceptance criteria`
- `## Validation plan`

### Feature
- `## Feature description`
- `## Use case`
- `## Acceptance criteria`
- `## Validation plan`

### Fact-check
- `## Question`
- `## Validation plan` (optional; no acceptance criteria required)

### Open-data
- `## Data source`
- `## Use case`
- `## Sample payload`
- `## Acceptance criteria`
- `## Validation plan`

## Required labels

Applied with `gh issue create --label`, all intake issues must use:

- `intake/<mode>` (for example, `intake/bug`)
- `science-fair-2026-05-28` for science-fair source intake
- `intake/needs-enrichment`

For example:

```bash
gh issue create \
  --label intake/bug \
  --label science-fair-2026-05-28 \
  --label intake/needs-enrichment
```

## Marker parsing rules

Downstream parsers must use the exact regex below:

- `^Intake-Session:\s*([a-f0-9-]{36})$`
- `^Reporter-Email:\s*(\S+@\S+|anonymous)$`
- `^Mode:\s*(bug|feature|fact-check|open-data)$`
- `^Estimate:\s*(1|2|4|8|16|32|64)$`
- `^Cost-Estimate-USD:\s*([\d.]+|pending)$`

## Worked examples

### Example: bug

```text
<!--
Intake-Session: 7f8d9a1a-3f3c-4d5a-8f8a-1b4d5bb3f6d1
Reporter-Email: reporter@example.com
Reporter-GitHub: octocat
Source: mobile-web
Mode: bug
Estimate: 2
Cost-Estimate-USD: 12.50
-->

## Observed behaviour
When searching for a bill, the app opens the previous bill details instead of the selected bill.

## Expected behaviour
Selecting a bill opens the exact bill selected in search.

## Reproduction steps
1. Open mobile web search.
2. Search "Justice Act".
3. Tap the second result.
4. Observe that details page does not match the selected title.

## Acceptance criteria
- Given a bill result is selected in search
  When the user opens the detail view
  Then the detail title and identifier match the selected result.
- Given the bug is fixed
  When Stage-2 enrichment runs
  Then the issue moves to intake review with the original reporter context intact.

## Validation plan
Reporter receives TestFlight build at reporter@example.com and confirms via reply or fixed-in-build tag.
```

### Example: feature

```text
<!--
Intake-Session: 1c3d5f27-8c2e-49da-96aa-2fd5d3f4a9fb
Reporter-Email: anonymous
Reporter-GitHub: feature-advocate
Source: repo-local
Mode: feature
Estimate: 8
Cost-Estimate-USD: pending
-->

## Feature description
Add a quick-save button to pin a member’s upcoming debate participation directly from the member profile.

## Use case
A civic-minded user visits the member profile and wants to save the next debate to revisit later.

## Acceptance criteria
- Given a member profile is open
  When a user taps "Save this debate"
  Then the debate appears in saved items with the selected member context.
- Given a saved debate exists
  When the user opens saved items
  Then the item links to the same debate details opened from profile.

## Validation plan
Reporter receives TestFlight build at reporter@example.com and confirms via reply or fixed-in-build tag.
```

### Example: fact-check

```text
<!--
Intake-Session: 9f3a9ce8-2a6a-4f4f-bf0c-6f9c8de7a4e5
Reporter-Email: reporter@example.org
Reporter-GitHub: civics-reviewer
Source: science-fair-2026-05-28
Mode: fact-check
Estimate: 4
Cost-Estimate-USD: pending
-->

## Question
Can the attendance list be verified against parliamentary records for the same vote session date?

## Validation plan
Cross-check vote attendance against the official parliamentary CSV export and include source links plus checksum in follow-up notes.
```

### Example: open-data

```text
<!--
Intake-Session: 2e6b4f6f-bf2e-4f9d-8fb1-3a5b7d9c4d8e
Reporter-Email: data-curator@example.net
Reporter-GitHub: open-data-maintainer
Source: repo-local
Mode: open-data
Estimate: 16
Cost-Estimate-USD: 200
-->

## Data source
Open-Canada API endpoint: `/api/v1/sittings?house=commons`.

## Use case
Researchers want to ingest a corrected sitting identifier into downstream debate indexing.

## Sample payload
```json
{
  "sittingId": "1234",
  "parliamentNumber": 44,
  "house": "commons",
  "source": "open-canada"
}
```

## Acceptance criteria
- Given a valid payload is submitted
  When enrichment receives the issue
  Then it creates a canonical reference with the raw payload attached.
- Given a malformed payload is submitted
  When enrichment validates the payload
  Then the issue is routed to manual review and does not create index entries.

## Validation plan
Reporter receives TestFlight build at data-curator@example.net and confirms via reply or fixed-in-build tag.
```

## Backward-compatibility statement

This contract is additive. New markers may be appended, but existing marker names and formats must not change until a version bump is announced via this doc (for example, `Intake-Contract-Version: 2`).
