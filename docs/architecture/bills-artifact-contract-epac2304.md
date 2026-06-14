# Bills SQLite Artifact Contract (EPAC-2304)

**Status:** Accepted for v1
**Last updated:** 2026-06-14
**Decision owner:** Riddim Software

## Decision

The bills SQLite artifact is the contract between two separate Go binaries:

- **Producer:** the bills-indexer writer, `backend/bills-indexer/internal/adapter/sqlite/writer.go`. It creates the schema and writes the rows.
- **Consumer:** the bills serving repository, `backend/bills/internal/adapter/sqlite/repository.go`. It opens the artifact read-only and serves `/api/v1/bills` routes from it.

The served `BillVersion` is single-sourced from what the producer actually writes. For each version the indexer records a publication **stage** name and a canonical viewer **URL** (`html_url`) — nothing else. The served contract is therefore exactly:

| Served field | Source column | Notes |
|---|---|---|
| `id` | `bill_versions.id` | |
| `label` | `bill_versions.stage` | The indexer has no separate label column; the publication-type name *is* the label. |
| `stage` | `bill_versions.stage` | Same value as `label`. |
| `source_url` | `bill_versions.html_url` | The producer's canonical viewer URL. |

The previously-served `title`, `chamber`, and `published_on` fields were **dropped** from the domain model (`backend/bills/internal/domain/domain.go`) and from `backend/openapi/openapi.json`. The indexer never wrote those columns, so they were always empty in responses (and silently omitted via `omitempty`). Removing them does not change any byte iOS receives at runtime — iOS already decodes every version field as optional and coerces empty to nil.

`label` and `stage` deliberately carry the same value until the producer gains a distinct label datum. Keeping `label` (rather than dropping it as redundant) preserves the field iOS currently renders.

## Why not populate the dropped fields instead?

The alternative was to make the indexer persist `chamber`, a real `published_date`, and an explicit `label`/`title`. The indexer's per-publication source data (LEGISinfo `publicationJSON`) carries only the publication type name and id; there is no authoritative chamber, title, or publication date to map from. Inventing those values would violate the project rule that civic content must trace to an authoritative source. Trimming the contract to what the producer can faithfully supply is the honest single-sourcing.

## How the contract is locked

`TestBillsArtifactSeam` (`backend/bills/artifact_seam_test.go`) is a build-time seam test:

1. It serializes a representative batch and drives the **real** producer binary in offline fixture mode (`BILLS_FIXTURE_BATCH`, see `backend/bills-indexer/main.go`) to write a real `bills.db`.
2. It opens that file with the **real** serving repository and asserts `ListBills`, `GetBillDepth`, and `GetBillVersionDiff` return the promised columns populated — no reliance on NULL fallbacks.

The two adapters are `internal` to separate Go modules, so the test imports neither into the other; the only thing shared across the seam is the on-disk SQLite file, exactly as in production. The test runs in CI via the `backend-tests` job (`Run bills tests` step in `.github/workflows/pr-build.yml`), so schema drift now fails at build time instead of at staging smoke or in production.

Because the serving repository now reads fixed column projections, the dynamic column-name fallbacks (`columnExpr`/`firstColumn`/`tableColumns`/`orderExpr`) that previously masked drift have been removed.

## Known limitation — bill amendments (recommended follow-up)

The served `BillAmendment` has the same shape of latent gap, and it is **out of scope** for this version-contract work. The indexer's `bill_amendments` table records `event_id`, `stage_name`, `amendment_note_id`, `amendment_count`, and `source_url`; the served `BillAmendment` declares `number`, `title`, `status`, `stage`, `sponsor_name`, `proposed_on`, and `text`. Only `id` and `source_url` overlap, so the serving repository now reads exactly those two with fixed SQL (`billAmendments`) — identical to what production already returned, but without dead fallbacks.

The served amendment field set still over-promises in `openapi.json`. Reconciling it (either trimming those fields or enriching the indexer to populate `amendment_count`/`stage_name`) is a separate contract decision that also touches the iOS amendments panel. It should be filed as a follow-up against the bills serving + bills-indexer adapters; this document and the `billAmendments` comment are the breadcrumb.
