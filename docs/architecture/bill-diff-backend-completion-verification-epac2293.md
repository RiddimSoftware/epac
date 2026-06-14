# Architecture Verification — Bill diff backend completion (EPAC-2293)

Post-implementation architecture verification of the **Bill diff backend completion**
Project, run after every implementation sibling merged. This is the checked-in record of
the [EPAC-2293](https://linear.app/riddimsoftware/issue/EPAC-2293/architecture-verification-for-bill-diff-backend-completion)
verification gate; the same scorecard is posted as a Linear comment on that issue. It is a
Project gate, **not** a PR review — it does not approve, block, or relitigate any individual
pull request.

## Scope and verdict

- **Scope:** `RiddimSoftware/epac` — backend bill version diff ingestion, serving, and
  deployment wiring (the merged Project state on `origin/main`).
- **Score:** 7.5 / 10.0
- **Status:** Healthy (high pass) — no Cardinal Sin, no Hidden Dependency; two surgical
  decoupling follow-ups and one documentation fix filed.
- **Date:** 2026-06-14

## Inputs reconstructed

The Project's originally-named siblings (EPAC-2283, EPAC-2284) were re-scoped and remain in
`Backlog` with no PRs. The actual merged work — the authoritative state scored here — landed
under different issue keys. Reconstructed from `git fetch origin main` + merged commits:

| Layer | Issue | PR | Merge commit |
|---|---|---|---|
| Ingestion: persist clause-level version/diff text | EPAC-2286 | #810 | `d6c3badc` |
| Ingestion: persist clause-level diff data for the route | EPAC-2298 | #814 | `3bbab7b1` |
| Serving: bill version diff endpoint | EPAC-2287 | #811 | `5e2c4a5f` |
| Serving: correct HTTP 404 version checking | EPAC-2299 | #815 | `8e210959` |
| Deployment: expose diff route in manifest + smoke | EPAC-2288 | #812 | `dd1b135b` |
| Deployment: assert app-level 404 in staging smoke | EPAC-2285 | #817 | `2308d21c` |
| Backfill: prove staging diff coverage | EPAC-2289 | #818 | `36ce9216` |

Standards scored against: `arch-team` Project Verification mode, org `clean-architecture.md`,
`linear-standards.md`, repo `CLAUDE.md`, and `docs/architecture/use-case-catalog.md`.

## What is sound

- **Dependency direction holds across both Go services.** Neither `domain` package imports a
  use case, adapter, AWS SDK, or Lambda type (`bills-indexer/internal/domain/domain.go`
  imports only `time`; `bills/internal/domain/domain.go` imports nothing). Use cases depend on
  ports (`BillRepository`, `ManifestLoader`, `IndexDownloader`); adapters implement them; the
  Lambda `main.go` is the composition root.
- **Serving layers are correctly separated.** The `LoadBillVersionDiff` use case owns the
  "unavailable vs. not-found" policy (empty clauses → `nil` → HTTP 204; missing version →
  `ErrVersionNotFound` → 404; missing bill → `ErrBillNotFound` → 404; missing `from`/`to` →
  typed 400). `main.go` stays a thin handler that parses the request, calls the use case, and
  maps typed errors to HTTP. The repository owns all SQLite access.
- **Civic-content provenance is clean** — the binding org rule. XML sections are parsed
  verbatim (only whitespace is collapsed); the LCS diff carries `from_text`/`to_text` through
  unchanged; `change_type` is a structural classification, not generated prose; SQLite stores
  and serves the text verbatim; `HansardAnchorURL` is honestly left `nil` rather than
  fabricated. No summarization, paraphrase, or generated parliamentary text anywhere.
- **Deployment wiring precisely targets the original regression.** `deployment-services.json`
  declares `GET /api/v1/bills/{id}/diff`; the staging smoke's `is_api_gateway_not_found()`
  distinguishes the gateway 404 (`{"message":"Not Found"}`) from application-level responses,
  with dedicated validators for route reachability (400), full payload (200 + non-empty
  clauses), unavailable (204), and unknown bill (app 404). This is the right compensating
  control for a build-time-artifact → serving split where unit tests fake both sides of the
  seam.
- **OpenAPI and the use-case catalog were updated in the implementing PRs.** The serving
  `LoadBillVersionDiff` catalog entry is accurate and complete, with a verbatim-text boundary
  rule.

## Deduction breakdown

| Deduction | Category | Finding | Follow-up |
|---|---|---|---|
| -1.0 | Behavioral Leakage | The clause-diff policy (`DiffClauses` LCS alignment + change classification, `buildDiffs`) lives in the LEGISinfo **source adapter** (`bills-indexer/internal/adapter/legisinfo/fetcher.go`), invoked from `toDomain`. The indexer use-case layer holds no diff policy, though the algorithm is source-format-independent (`domain.VersionSection` → `domain.BillClauseDiff`). | EPAC-2303 |
| -1.0 | Catalog Drift | `docs/architecture/use-case-catalog.md` documents `ComputeBillVersionDiff` as "a use-case policy executed during ingestion," but it ships in the adapter. `ComputeBillVersionDiff` and `IngestBillVersionText` also omit the `Current implementation:` paths every other entry carries, so they can't be traced mechanically. | EPAC-2303 |
| -0.5 | Enforcement Gap | The bills SQLite artifact schema is an implicit, unverified contract between two adapters (indexer `writer.go` → serving `repository.go`). No build-time test crosses that seam; the serving repo masks drift with dynamic column-name fallbacks. As shipped, `bill_versions` lacks `label`/`title`/`chamber` and never populates `published_date`, so served diff `from`/`to` metadata is silently sparse (clauses are fine). Only staging smoke exercises the real contract. | EPAC-2304 |

Total: −2.5 → **7.5 / 10.0**.

### Not deducted (noted)

- Serving `domain` structs carry `json:"…"` tags and are serialized directly as the API body
  (domain doubles as DTO). The domain types are pure Go (no framework *types*), and this is the
  established, repo-wide convention across all bills/members backend domains — the Project
  followed the existing pattern rather than introducing a new violation, so per the migration
  ratchet it is not scored here.

## Layer map

- **Domain:** `Bill`, `BillVersion`, `BillVersionDiff`, `BillClauseDiff`, `VersionSection`,
  `BillDiff` (indexer), `BillCommitteeStage`.
- **Application:** serving — `LoadBillVersionDiff`, `GetBillDepth`, `ListBills`,
  `GetBillCommitteeStage`, `OpenBillsIndex`; ingestion — `IngestBills` /
  `IngestBillVersionText` / `ComputeBillVersionDiff` (the last currently in the adapter — see
  EPAC-2303).
- **Adapters:** `bills/internal/adapter/sqlite/repository.go`, `bills/main.go` handler,
  `bills-indexer/internal/adapter/legisinfo/fetcher.go`,
  `bills-indexer/internal/adapter/sqlite/writer.go`, S3 manifest/index adapters.
- **Frameworks/Drivers:** API Gateway / Lambda runtime, `modernc.org/sqlite`, S3, LEGISinfo /
  parl.ca HTTP + XML.

## Follow-up implementation issues

- [EPAC-2303](https://linear.app/riddimsoftware/issue/EPAC-2303) — Implement
  `ComputeBillVersionDiff` use case in the bills-indexer application layer (resolves the
  Behavioral Leakage + Catalog Drift findings).
- [EPAC-2304](https://linear.app/riddimsoftware/issue/EPAC-2304) — Lock the bills SQLite
  artifact schema with a producer-to-consumer seam test (resolves the Enforcement Gap and the
  sparse version-metadata gap).

Both are non-blocking (`Medium`, `arch`, estimate 4) — the shipped code is correct and
serviceable; these are surgical decoupling and test-hardening improvements, not defects that
block the Project's Human Handoff.

## Process note (not an architecture deduction)

The parent Project's issue membership is drifted: only the two re-scoped planning stubs
(EPAC-2283/2284) were attached to the Project; the issues that actually shipped the work
(EPAC-2286/2287/2288/2298/2299) are not. EPAC-2293 has been attached to the Project as part of
this verification. Reconciling the Project's membership with the merged issues is a Linear
housekeeping task for the human handoff, outside this gate's scope.
