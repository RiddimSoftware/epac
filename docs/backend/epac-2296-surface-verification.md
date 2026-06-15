# EPAC-2296 Project Surface Verification — Bill diff backend completion

Date: 2026-06-15
Verification issue: [EPAC-2296](https://linear.app/riddimsoftware/issue/EPAC-2296/surfacedesign-verification-for-bill-diff-backend-completion)
Parent Project: *Bills, Votes & Committees — depth across the legislative cycle*
Repo in scope: `RiddimSoftware/epac`
Environment for live checks: staging — `https://staging-api.epac.riddimsoftware.com`

This is the **project-level surface/design verification** gate for the bill diff
backend completion work. It is a read-only gate over merged `main`, not an
implementation change and not a per-PR review. It inventories every changed
human- or agent-observed surface, scores each against the standard that governs
it, and files concrete remediation work for surface-quality gaps. The companion
**backend route** gate is recorded separately in
[`epac-2292-backend-route-verification.md`](epac-2292-backend-route-verification.md);
this document does not restate it.

## Verdict: PASS with remediation

One remediation issue filed:
[EPAC-2309](https://linear.app/riddimsoftware/issue/EPAC-2309/default-bill-diff-viewer-to-a-version-pair-that-has-an-available-diff)
(iOS). No backend, contract, or CLI remediation required. No code is changed by
this gate.

## Stop-condition check — implementation siblings complete

All blockers of EPAC-2296 are `Done` / merged (verified in Linear 2026-06-15):

| Sibling | State | PR |
|---|---|---|
| EPAC-2286 IngestBillVersionText | Done | #810 |
| EPAC-2287 LoadBillVersionDiff | Done | #811 |
| EPAC-2288 Expose diff route in manifests/smoke | Done | #812 |
| EPAC-2289 Backfill and prove staging coverage | Done | #818 |
| EPAC-2292 Backend route verification | Done | #827 |
| EPAC-2302 All-pair diff generation for iOS selections | Done | #826 |
| EPAC-2307 Fix diff entry point hidden by display-number id | Done | #829 |

EPAC-2290 (original backfill issue) is `Duplicate`, folded into EPAC-2289. No
incomplete siblings; the gate proceeds.

## Diff reconstruction method

`git fetch origin main`; read the merged sibling PRs and the merged
`BillsService` / diff-viewer / bills-Lambda / smoke-script state on `main`; then
verify observed states directly — Go/iOS/Python source on `main` plus six live
`curl` probes against staging. The merged state was read from this worktree
(top commit `04e05105`, EPAC-2307), **not** from the root checkout, which still
carried the pre-EPAC-2307 `Bill.id = number` mapping.

## Standards loaded, by surface type

- **API (HTTP JSON):** OpenAPI contract (`backend/openapi/openapi.json`) as the
  schema of record; no dedicated `ui/*` API standard exists, so success/error
  bodies are judged for schema-conformance and absence of raw parser/debug noise.
- **CLI / script:** `/Users/sunny/code/agent-config/ui/README.md`,
  `ui-doctrine.md`, `cli-standards.md`, `cli-scorecard.md`.
- **iOS / product UI:** `design-team` Project Surface Verification mode —
  Refactoring UI, Nielsen/Krug, WCAG 2.2 AA, content quality, plus the repo's
  civic-content rule (verbatim authoritative text, no LLM summaries) and the
  [EPAC-962](https://linear.app/riddimsoftware/issue/EPAC-962/bill-diff-viewer-compare-versions-across-readings)
  design intent.
- **Linear artifacts:** `/Users/sunny/code/agent-config/context/linear-standards.md`.

## Surface inventory

| # | Surface | Type | Verdict |
|---|---|---|---|
| 1 | `GET /api/v1/bills/{id}/diff` success / 204 / 400 / 404 JSON | API | Pass |
| 2 | `scripts/ci/backend_staging_smoke.py` diff checks output | CLI | Pass (74/100) |
| 3 | `backend/bills-indexer` run logs (versions/diffs/clauses) | CLI/log | Pass |
| 4 | iOS bill diff viewer — populated / no-changes / unavailable / one-version | iOS | Pass with remediation (EPAC-2309) |
| 5 | iOS "Compare versions" entry point | iOS | Pass |
| 6 | Linear evidence + remediation artifacts | Linear | Pass |
| — | App Store listing | — | Out of scope → `aso-team` (no listing change here) |

## 1. API surface — `GET /api/v1/bills/{id}/diff`

Live staging probes captured 2026-06-15 (numeric LEGISinfo id `13608745` = C-11):

| # | Request | Observed |
|---|---|---|
| A | `…/13608745/diff?from=c-11-13615955-first-reading&to=c-11-14114368-as-passed-by-the-house-of-commons` | **204**, 0-byte body |
| B | `…/13608745/diff?from=c-11-13615955-first-reading&to=c-11-13896514-as-amended-by-committee` | **200**, ~156 KB, `from`/`to` + non-empty `clauses` |
| C | `…/13608745/diff` (no `from`/`to`) | **400** `{"error":"missing required query parameters: from, to"}` |
| D | `…/13608745` (bill depth, numeric id) | **200**, C-11 + version stages |
| E | `…/C-11` (bill depth, display number) | **404** `{"error":"bill not found"}` |
| F | `…/ZZ-9999/diff?from=v1&to=v2` (unknown bill) | **404** `{"error":"bill not found"}` |

Findings:

- **Schema-conformant.** The 200 body matches OpenAPI `BillVersionDiff`
  (`from`, `to`, `clauses[]`); clause objects carry `change_type` ∈
  `{added, removed, modified, unchanged}` plus verbatim `from_text` / `to_text`.
- **No raw parser/debug noise.** Internal errors are logged with `slog.Error`
  and the response body is a fixed generic string. `mapBillVersionDiffError`
  (`backend/bills/main.go:283`) returns only hardcoded messages
  (`"bill not found"`, `"missing required query parameter(s)…"`,
  `"internal error"`); no `err.Error()`, SQL text, or file path reaches the body.
- **Clean state separation.** 200 + non-empty `clauses` (changes), 200 + empty
  `clauses` (no changes), 204 (no servable diff / unavailable), 400 (missing
  params), 404 (unknown bill) are distinct and intentional
  (`backend/bills/internal/usecase/bills.go`,
  `backend/bills/internal/adapter/sqlite/repository.go:172`).
- **Cross-surface id consistency holds.** `lookupBillID`
  (`repository.go:278`) resolves `WHERE id = ? OR number = ?`, so the diff route
  serves both the numeric id the iOS app now sends (post-EPAC-2307) and the
  display number used by the smoke checks and curl evidence.

Minor observations (not remediated — no observable-surface defect):

- OpenAPI marks only `change_type` required on `BillClauseDiff`, but the Go type
  always serializes `from_text` / `to_text` (no `omitempty`). The live payload
  satisfies the schema; this is a permissive-spec documentation gap, not a
  conformance failure. OpenAPI sync ownership stays with EPAC-2287.
- Extracted clause text concatenates the marginal note with the clause body
  without a separator (e.g. `"Short titleThis Act may be cited as…"`). It is
  faithful source text, mildly less readable. Any future fix must preserve
  verbatim text (separate the marginal note as its own element rather than
  rewriting); below the remediation bar for this gate.

**API verdict: Pass.** Success, unavailable, and error responses are
understandable, schema-conformant, and free of debug noise.

## 2 & 3. CLI / script surface

### `scripts/ci/backend_staging_smoke.py` — staging smoke

Scored against `cli-scorecard.md` (one surface, not averaged):

| Criterion | Score | Note |
|---|---:|---|
| First byte | 4 | No startup banner; first output is the first check line. |
| Progress on long work | 8 | One `PASS`/`FAIL <name>: <evidence>` line per check as it completes. |
| Naming the long step | 6 | Descriptive check names (`bills:diff-route`, `bills:diff-full`, …); no per-step duration hint (checks are fast HTTP calls). |
| Outcome line | 7 | Clear end summary block (base URL, active/skipped, passed/failed counts); multi-line rather than a single line. |
| Error quality | 9 | Failures say expected-vs-got (e.g. `expected HTTP 204 unavailable diff, got 200`); no tracebacks. |
| TTY-awareness | 9 | `supports_color` honours `NO_COLOR` / `FORCE_COLOR` / `GITHUB_ACTIONS` / `isatty`; writes `$GITHUB_STEP_SUMMARY` in CI. |
| Signal levels | 4 | `--mode`, `--list`, `--manifest`, `--services` present; no `--quiet` / `--verbose`. |
| No fake progress | 10 | Real HTTP requests; no synthetic bars. |
| Word economy | 8 | Terse, scannable `PASS`/`FAIL` lines. |
| Non-interactive safety | 9 | Every arg has a default or env fallback; no interactive prompts. |
| **Total** | **74 / 100** | "Decent" band. |

Diff-specific checks present and asserting the right contract:
`bills:diff-route` (400/404), `bills:diff-unknown` (404), `bills:diff-full`
(200), `bills:diff-one-version` (204).

Three worst findings: (1) no first-byte banner identifying the run; (2) no
`--quiet` / `--verbose`; (3) outcome is a summary block rather than a single
outcome line. All three are minor for an internal CI tool whose output is
already professional, TTY-aware, and has excellent error messages. **No
remediation issue** filed — the surface clears the AC ("actionable and
professional") and sits above the cli-scorecard 60 threshold.

### `backend/bills-indexer` run logs

Structured JSON to stderr per the repo convention (`ingest_started`,
`fetch_started/completed`, `write_completed`, `artifact_uploaded`), with the
final `table_counts` surfacing `bill_diffs` and `bill_clause_diffs` row counts
— the exact signal that exposed the earlier "77 diffs / 0 clause diffs" gap.
Errors log a single `ingest_failed` JSON line and exit non-zero; no raw
tracebacks. **Pass.**

## 4 & 5. iOS surface — bill diff viewer

Read from `ios/epac/Views/Bills/BillVersionsDiffView.swift`,
`BillDetailView.swift`, `ios/epac/Data/Adapters/BillsService.swift`, and
`ios/epac/en.lproj/Localizable.strings` on `main` (post-EPAC-2307).

Observed states and copy:

- **Populated:** clause rows render added (green), removed (red), modified
  (orange, before/after), unchanged (gray) — each with a **text label** badge
  ("Added"/"Removed"/"Modified"/"Unchanged") and a combined accessibility label,
  so meaning is **not conveyed by colour alone** (WCAG 1.4.1 satisfied). Inline
  and side-by-side modes; clause text is `.textSelection(.enabled)`.
- **No changes (200 + empty `clauses`):** "No clause-level changes between these
  two versions."
- **Unavailable (204/404 → `nil`):** "Couldn't load the diff for the selected
  versions. Try a different pair or try again later." — actionable, no raw codes.
- **One version (`< 2` versions):** "Only one version published" + explanatory
  body. Matches the EPAC-962 empty-state intent.
- **Source attribution:** "Source: LEGISinfo published bill text on parl.ca".
- **Civic-content rule:** clause text is rendered verbatim from the backend; no
  client-side summarization. **Compliant.**
- **Entry point:** "Compare versions" row shows only when versions load. Post
  EPAC-2307, `BillsService` maps `Bill.id` to the numeric LEGISinfo id
  (`BillsService.swift` — `legisInfoID` from `raw.BillId`), so the depth/versions
  call resolves (live probe D = 200) and the row appears; the old display-number
  path is correctly rejected by the backend (live probe E = 404). **Pass.**
- Snapshot tests cover inline, side-by-side, no-changes, and one-version states
  (light / dark / accessibility-large).

**Finding (remediated): default version pair can open on the unavailable state.**
`BillVersionsDiffView.swift:79-80` defaults `from = sorted.first` (First Reading)
and `to = sorted.last` (latest), then loads that pair with no fallback. For C-11
the first→last pair returns **204** (live probe A) while first→middle returns
**200** (live probe B), so the marquee bill opens on "Couldn't load the diff…"
until the user changes the To picker. The backend 204 is correct by design
(EPAC-2302 returns 204 when a version lacks comparable source text; forcing a
diff would violate the no-rewrite civic-content rule), so the fix is iOS-side:
default to a servable pair. Filed as
[EPAC-2309](https://linear.app/riddimsoftware/issue/EPAC-2309/default-bill-diff-viewer-to-a-version-pair-that-has-an-available-diff)
(High, estimate 4). This is precisely the risk EPAC-2296 names: a technically
valid payload that leaves the viewer on an empty first impression.

Voice scores (0–10): Accessibility 8 · Visual/Design 8 · Content 8 ·
Interaction 6 (default-selection gap) · Brand/consistency 8.

## 6. Linear artifact surface

The sibling evidence comments and in-repo verification docs
(`epac-2289-staging-bill-diff-coverage.md`, `staging-smoke-tests.md`,
`epac-2291`/`epac-2292-backend-route-verification.md`) carry concrete commands,
timestamps, ids, and outputs; they read as reproducible evidence, not debug
dumps. The remediation issue EPAC-2309 meets `linear-standards.md`:
self-contained context, root-cause analysis with evidence, autonomous Gherkin
AC, single owning repo (`RiddimSoftware/epac`), estimate, mergeability, and
explicit out-of-scope. **Pass.**

## Remediation

- [EPAC-2309](https://linear.app/riddimsoftware/issue/EPAC-2309/default-bill-diff-viewer-to-a-version-pair-that-has-an-available-diff)
  — iOS: default the diff viewer to a version pair that has an available diff.

## Stop outcome

`verified-with-remediation`. Every changed observed surface was inventoried and
scored; the API, CLI, indexer-log, and Linear surfaces pass; the iOS surface
passes with one filed remediation (EPAC-2309). This gate clears the
surface/design dimension of the parent Project. The final human/product closeout
remains
[EPAC-2018](https://linear.app/riddimsoftware/issue/EPAC-2018/human-handoff-bills-votes-and-committees-depth)
and is out of scope here.
