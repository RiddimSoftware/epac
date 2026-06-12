# Lobbying-index intermediate-artifact contract (EPAC-2228)

**Status:** Implemented
**Subsystem:** `backend/lobbying-index/`
**Date:** 2026-06-04
**Source of truth:** `backend/lobbying-index/internal/adapter/s3/s3.go`, `backend/lobbying-index/main.go`
**Related:** [EPAC-2226](https://linear.app/riddimsoftware/issue/EPAC-2226/extract-pipeline-orchestration-out-of-maingo-into-a-phase-dispatch) (phase dispatch), [EPAC-2227](https://linear.app/riddimsoftware/issue/EPAC-2227) (per-phase split), [EPAC-2230/2231](https://linear.app/riddimsoftware/issue/EPAC-2231) (state machine + IAM), [EPAC-1905 S3 artifact migration plan](./s3-artifact-migration-plan.md)

## Why

The lobbying index is built in phases. Under Step Functions each phase is a
separate Lambda invocation with its own ephemeral `/tmp`, so the working SQLite
database cannot simply live in `/tmp` across the pipeline — it must be
**externalised to S3 between states** so phase N+1 can read what phase N wrote.
This note defines that intermediate-artifact contract: the keys, the lifecycle,
the integrity check, the re-run semantics, and the sequencing assumption the
design depends on.

The download path itself (`Store.DownloadIntermediate`) and the phase router
that drives it landed in EPAC-2227 and EPAC-2226. This note is the
"define and document" half of EPAC-2228 and describes the contract as actually
implemented.

## Keys

The S3 `Store` resolves a prefix (env `LOBBYING_INDEX_PREFIX`, default
`lobbying-index/v1`). Three kinds of object live under it. Path segments are
constants, not inline strings:

| Object | Key (default prefix) | Constant / origin | Role |
|---|---|---|---|
| Per-phase intermediate | `lobbying-index/v1/tmp/<PhaseName>.sqlite` | `intermediateSegment = "tmp"` + phase name | In-flight working DB handed from one phase to the next |
| Published artifact | `lobbying-index/v1/index.sqlite` | written by `finalizeArtifact` | Final SQLite artifact backend readers consume |
| Manifest | `lobbying-index/v1/manifest.json` | `Store.Write` | Metadata (sha256, size, table counts) for the published artifact |

`Store.IntermediateKey(phaseKey)` builds the per-phase key and rejects empty or
path-separator-bearing phase names. The intermediate `tmp/` namespace is strictly
distinct from the published `index.sqlite` key, so a half-finished run can never
be observed as the published artifact.

> **Design note — per-phase keys vs. a single working key.** EPAC-2228 originally
> proposed one canonical `<prefix>/work/index.sqlite` working key. The
> implemented design instead gives each phase its **own** intermediate key
> (`tmp/<PhaseName>.sqlite`) and has each phase download its *predecessor's*
> output. This is functionally equivalent for the strictly-sequential pipeline
> and has two advantages: every phase boundary is independently addressable for
> debugging/replay, and a re-driven phase reads a stable predecessor object while
> overwriting only its own. The single-working-key framing in the ticket is
> superseded by this note.

## Phase order and lifecycle

The linear pipeline order (`phaseOrder` in `main.go`):

```
IngestOCLData
  → BuildMPLobbyingTables
  → BuildOrganizationTables
  → BuildBillContextTables
  → PreBakeMinisterCommunications
  → Finalize
```

Each Lambda invocation runs one phase, selected by the `PHASE` env var, through
this template (`runtimeConfig.downloadPriorPhase` / `uploadPhaseOutput`):

1. **Hydrate.** If the phase has a predecessor, remove any stale local
   `dbPath`, then `DownloadIntermediate(predecessor, dbPath)` — pull the
   predecessor's `tmp/<predecessor>.sqlite` to the local working file.
   `IngestOCLData` has no predecessor and starts from an empty `/tmp`.
2. **Execute.** Run the phase's use case(s) against the local `dbPath`.
3. **Persist.** `UploadIntermediate(dbPath, phase)` — push the mutated working
   DB to this phase's own `tmp/<phase>.sqlite` for the next phase to consume.

`Finalize` hydrates from `PreBakeMinisterCommunications`, then promotes the
working DB to the published `index.sqlite` key and writes `manifest.json`
(`finalizeArtifact`). It does not write a `tmp/Finalize.sqlite`.

A `PHASE=all` escape hatch runs every phase in one invocation against a single
local `/tmp` file (no intermediate round-trips) and publishes the same final
artifact + manifest. It is for **local development only**; production Step
Functions invokes the named phases.

## Integrity

Every upload stamps `content-hash-sha256` object metadata (`UploadIntermediate`
reuses `Upload`, which sets it). `DownloadIntermediate` streams the body to the
local file while recomputing SHA-256, then compares the recomputed hash against
the object's `content-hash-sha256` metadata. A **mismatch is a hard error** —
the phase fails rather than mutating a torn or partially-propagated DB, which
lets Step Functions retry cleanly.

> **Current leniency.** If the object carries *no* `content-hash-sha256`
> metadata, `DownloadIntermediate` returns the computed hash without comparison
> ("callers decide whether to enforce"). In the current pipeline every
> intermediate is written by `UploadIntermediate`, which always sets the
> metadata, so in practice every hop is verified. If a stricter "metadata must
> be present" guarantee is ever required, tighten that branch in `s3.go`.

## Idempotency / re-run

Writes use overwrite (`PutObject`) semantics — there is no append. `downloadPriorPhase`
also removes any stale local file before downloading. A re-driven phase therefore
reads its predecessor's stable intermediate, recomputes from it, and overwrites
its own intermediate key. Re-running a phase cannot append-on-rerun or accumulate
state across retries.

## Concurrency / sequencing assumption

**Phases are strictly sequential in the state machine** (`phaseOrder`). No two
phases mutate the same key concurrently, and each phase reads exactly one
predecessor object. Correctness of the Bill / Org / Minister phases — which all
build on the same upstream DB — depends on this single-threaded ordering.

> If a future design fans phases out in parallel, this contract must be
> revisited. Per-phase keys mean parallel branches would at least write *distinct*
> objects (no lost-update on a shared key), but a parallel topology would still
> need an explicit join/merge step to reconcile branch outputs into one DB before
> `Finalize`. Do not introduce a parallel branch without that merge step.

## Boundary rule

The SQLite-on-S3 staging detail does **not** leak into any `internal/usecase`
phase type. Use cases still receive a local `dbPath` and remain oblivious to S3.
Only the outer router (`main.go`) knows the artifact lives in S3 between
invocations, and it reaches S3 only through the `Store` adapter — never via a raw
`awss3.GetObject`/`PutObject` call. The AWS SDK stays isolated behind the
adapter's `Client` interface, keeping the dependency arrow pointing inward.
EPAC-2235 adds a structural test enforcing this no-S3-in-usecase boundary.
