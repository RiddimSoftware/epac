# SwiftData Schema Migration

## SwiftData Schema Migration (ADR-002)

**Date:** 2026-04-27
**Status:** Superseded by ADR-003
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

### Why not destructive migration

The previous fallback — delete the SQLite files on schema incompatibility — silently destroyed all locally cached Hansard data, votes, and expenditures on every schema update. For a civic app users rely on during active political moments, losing the local cache is a bad experience. Proper migrations preserve data across updates.

## SwiftData Destructive Recovery (ADR-003)

**Date:** 2026-05-26
**Status:** Accepted
**Supersedes:** ADR-002 destructive-migration prohibition
**Follow-up implementation:** [EPAC-2119](https://linear.app/riddimsoftware/issue/EPAC-2119/recover-swiftdata-launch-failures-by-wiping-cache-and-retrying)

### Context

The app has seen a launch crash caused by a failed SwiftData migration. `EpacMigrationPlan` remains the correct first line of defense, but `makeModelContainer()` currently turns any unrecoverable open failure into a `fatalError`, leaving affected users in a crash-on-launch loop until they reinstall the app.

ADR-002 rejected destructive migration because losing locally cached Hansard data, votes, and expenditures seemed worse than forcing migrations to preserve every record. That trade-off changed as the data ownership model became clearer: the current SwiftData store is a cache of authoritative open data, not the source of truth.

### Decision

Keep versioned SwiftData schemas and explicit migration stages as the required path for every intentional model change.

If opening the store with the migration plan fails at launch, delete the local SwiftData cache store and retry container creation once. Destructive recovery is a fallback for an unrecoverable cache-store failure, not a replacement for writing migrations.

### Open-data rationale

Current SwiftData entities are downstream of authoritative sources: Hansard XML, OurCommons.ca records, parliamentary feeds, and derived backend artifacts. After a local wipe, the app can re-fetch and rebuild the cache on first launch. Losing the cache costs a short re-download; staying in a launch-crash loop costs the entire app session and often forces reinstall.

This policy depends on SwiftData remaining a re-fetchable cache. If EPAC later stores user-generated drafts, notes, preferences that are not otherwise persisted, or offline-first records in SwiftData, destructive recovery must become store-scoped, opt-in, or be replaced by a preservation path for those entities.

### Implementation note

EPAC-2119 implements the code change. The intended shape is: try to build the `ModelContainer` with `EpacMigrationPlan`; if that throws, remove the SwiftData SQLite store and sidecar files; retry once; only then use the terminal failure path. The implementation PR should include targeted verification for the first-open failure and retry path.

### When to revisit

- SwiftData begins storing non-re-fetchable user-generated content.
- The app adds offline-first features where local records may be the only copy for meaningful periods.
- Migration failures become common enough that destructive recovery hides a schema-process problem instead of handling rare corrupt or incompatible cache stores.
