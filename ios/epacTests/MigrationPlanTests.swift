import Testing
import SwiftData
import Foundation
@testable import epac

// Tests for EpacMigrationPlan structural correctness.
//
// True end-to-end migration tests (V3 SQLite file → V5 container) require a
// real on-disk store pre-seeded with the old schema metadata; that can't be
// done in an in-memory unit test. What we CAN verify here:
//   • the schemas array is in the required chronological order
//   • the stages count is schemas.count – 1 (one stage per schema boundary)
//   • a ModelContainer initialized with the plan succeeds on an empty store
struct MigrationPlanTests {

    @Test func schemasAreInChronologicalOrder() {
        let schemas = EpacMigrationPlan.schemas
        #expect(schemas.count == 3)
        // Confirm the ordering: V3 < V4 < V5
        let v3 = SchemaV3.versionIdentifier
        let v4 = SchemaV4.versionIdentifier
        let v5 = SchemaV5.versionIdentifier
        #expect(v3 < v4)
        #expect(v4 < v5)
        // Confirm the plan lists them in the same order
        #expect(schemas[0] == SchemaV3.self)
        #expect(schemas[1] == SchemaV4.self)
        #expect(schemas[2] == SchemaV5.self)
    }

    @Test func stagesCountIsOnePerSchemaBoundary() {
        let stages = EpacMigrationPlan.stages
        let schemas = EpacMigrationPlan.schemas
        // There must be exactly (schemas.count - 1) stages
        #expect(stages.count == schemas.count - 1)
    }

    @Test func modelContainerWithMigrationPlanSucceeds() throws {
        // Verifies that epacApp's container initialisation doesn't throw on an empty store.
        // Uses an in-memory configuration so tests don't touch disk.
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV5.self),
            migrationPlan: EpacMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        // Basic sanity: the container exposes the expected model types
        let context = ModelContext(container)
        let members = try context.fetch(FetchDescriptor<ParliamentMember>())
        #expect(members.isEmpty)
    }
}
