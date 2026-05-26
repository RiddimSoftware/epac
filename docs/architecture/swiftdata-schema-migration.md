# SwiftData Schema Migration

This document collects the ADRs that govern SwiftData schema evolution and recovery in EPAC. The currently-accepted policy is **ADR-003**; ADR-002 is preserved for audit and is superseded.

---

## ADR-002: SwiftData Schema Migration

**Date:** 2026-04-27
**Status:** Superseded by [ADR-003](#adr-003-destructive-recovery-on-migration-failure)
**Ticket:** EPAC-128

### Convention: every schema change requires a new `SchemaVN`

**Rule:** Any change to a SwiftData `@Model` — adding a property, removing one, renaming one, changing a type, or adding a new model class — requires a new versioned schema enum and a new migration stage in `EpacMigrationPlan`.

**Never** change an existing `SchemaVN` enum after it has shipped in production. Existing versions are immutable; they define what real users' databases look like on disk.

### How to add a new schema version

1. Copy the current latest `SchemaVN` enum in `Model.swift` to a new `SchemaV(N+1)` enum.
2. Make your changes inside `SchemaV(N+1)`.
3. Update the `typealias` block at the top of `Model.swift` to point to `SchemaV(N+1)`.
4. Add a migration stage to `EpacMigrationPlan` in `Migration.swift`:
   - Adding optional properties or new model types → `MigrationStage.lightweight`
   - Adding non-optional properties, renaming, or transforming data → `MigrationStage.custom` with a `didMigrate` closure
5. Add `SchemaV(N+1).self` to `EpacMigrationPlan.schemas`.

### When to use lightweight vs custom migration

| Change | Stage |
|--------|-------|
| New optional property | Lightweight |
| New `@Model` class | Lightweight |
| New non-optional property (needs default) | Custom — set value in `didMigrate` |
| Rename a property | Custom — read old, write new, nil out old |
| Remove a property | Lightweight (SwiftData ignores unknown columns) |
| Change a property type | Custom |

### Migration plan location

`ios/epac/Model/Migration.swift` contains `EpacMigrationPlan`. The `ModelContainer` in `epacApp.swift` initializes with this plan. The plan accumulates all migration stages in chronological order; do not remove old stages.

### Why not destructive migration *(superseded)*

The previous fallback — delete the SQLite files on schema incompatibility — silently destroyed all locally cached Hansard data, votes, and expenditures on every schema update. For a civic app users rely on during active political moments, losing the local cache is a bad experience. Proper migrations preserve data across updates.

> This subsection is the policy that ADR-003 reverses. Retained here for audit. See ADR-003 for the current behaviour.

---

## ADR-003: Destructive recovery on migration failure

**Date:** 2026-05-26
**Status:** Accepted
**Ticket:** EPAC-2118 (docs); follow-up implementation ticket tracks the `makeModelContainer()` code change.
**Supersedes:** [ADR-002](#adr-002-swiftdata-schema-migration) (specifically the "Why not destructive migration" stance; the versioned-`SchemaVN` discipline above is retained unchanged).

### Context

ADR-002 prohibited destructive migration on the grounds that "users rely on the local cache during active political moments." That framing treated cache loss as the worst plausible failure mode. It was incorrect in practice.

Every entity persisted in the SwiftData store is downstream of public open data:

- `ParliamentMember` — Library of Parliament feed
- `Sitting`, `Speech`, `RecordedVote`, `MemberVote` — Hansard XML + OurCommons.ca
- `Bill`, `Petition`, `WrittenQuestion` — OurCommons.ca
- `FiscalMonitorEntry`, `Expenditure` — Treasury Board / proactive disclosure feeds

None of it is user-generated. None of it requires a server round-trip the user authenticates against. The cost of losing the local store is a few seconds of background re-fetch on next launch.

Meanwhile, the failure mode ADR-002 *did* allow has shipped: a migration stage in `EpacMigrationPlan` (V3 → V10) throws, `makeModelContainer()` in `ios/epac/epacApp.swift:44–55` calls `fatalError("Could not create ModelContainer: \(error)")`, and the app dies on launch with no recovery path. Users hit a crash-on-launch loop until they reinstall. This is strictly worse than the cache-loss UX ADR-002 was trying to prevent.

### Decision

On `ModelContainer` initialization failure, EPAC attempts destructive recovery before giving up:

1. Try `ModelContainer(for: Schema(versionedSchema: SchemaV(latest).self), migrationPlan: EpacMigrationPlan.self, …)` — the preserve-data path. The versioned-schema migration ladder remains the primary mechanism.
2. On throw, delete the on-disk SwiftData store at the container URL, including the `-wal` and `-shm` sidecar files.
3. Retry with a fresh store. Background fetches repopulate from upstream open data on first launch.
4. If the retry also throws, *then* `fatalError`. A second throw indicates a non-schema failure (disk full, file permission, simulator state corruption) that destructive recovery cannot solve.

The versioned-`SchemaVN` discipline from ADR-002 is unchanged: every `@Model` change still requires a new schema enum and a new stage in `EpacMigrationPlan`. The migration ladder is the preferred path; destructive recovery is the fallback when the ladder fails at runtime against a real user's on-disk store.

### Rationale

- **All persisted state is reproducible from public open-data sources** on first launch. No user input, no offline-only drafts, no authenticated content lives in the SwiftData store today.
- **A crash-on-launch loop is a worse user experience** than a one-time first-launch re-download. The re-download is observable and bounded; the crash loop is opaque and unbounded.
- **The migration ladder still runs first**, so well-formed migrations preserve data exactly as before. ADR-003 only changes what happens when the ladder itself throws — a path that previously had no recovery at all.
- **The discipline of writing migrations does not relax.** Destructive recovery is a safety net, not a license to skip `SchemaVN` work. Every `@Model` change still goes through the ladder.

### Rejected alternatives

- **Keep ADR-002 and just improve migrations.** Possible in principle, but unbounded in practice. Any future model change can break the migration ladder against some user's on-disk state. The crash loop must not be the failure mode regardless of how careful migrations are.
- **Show a recoverable error UI on migration failure.** Considered. For an app whose entire local state is re-fetchable, this just makes the user perform the wipe manually through an "Are you sure?" screen. Better to recover automatically and re-fetch in the background.
- **Selective wipe** (e.g. wipe only the model types affected by the failed stage). More complex than the value justifies given that everything is re-fetchable anyway. Revisit only if the store grows to include genuinely user-generated content.

### Implementation note

The code change lives in `ios/epac/epacApp.swift`'s `makeModelContainer()`. It must:

- Wrap the existing `try ModelContainer(...)` call in a do/catch.
- On catch, locate the SwiftData store URL, delete the `.sqlite` / `.sqlite-wal` / `.sqlite-shm` files, and retry the same `ModelContainer(...)` call.
- Only `fatalError` if the retry also throws.
- Log both the original error and the wipe action so failed-migration diagnostics survive in TestFlight crash reports.

This work is tracked under a separate implementation ticket so the policy change (this ADR) and the code change land in reviewable, separable PRs.

### When to revisit

ADR-003's rationale rests on "no user-generated content in the SwiftData store." If any of the following becomes true, ADR-003 must be revisited and either made conditional or reverted:

- User-written notes, annotations, or drafts on debates / bills / members are persisted locally.
- Offline-first features write user state to the SwiftData store before sync.
- The store accumulates derived state that is *expensive* (not just slow) to recompute from upstream — e.g. ML embeddings, large summarizations, content the user paid for.
- Authentication or session data is added to the store.

Until one of those is true, destructive recovery is strictly safer than the current crash-on-launch loop.
