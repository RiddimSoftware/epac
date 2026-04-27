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
        #expect(schemas.count == 5)
        // Confirm the ordering: V3 < V4 < V5 < V6 < V7
        let v3 = SchemaV3.versionIdentifier
        let v4 = SchemaV4.versionIdentifier
        let v5 = SchemaV5.versionIdentifier
        let v6 = SchemaV6.versionIdentifier
        let v7 = SchemaV7.versionIdentifier
        #expect(v3 < v4)
        #expect(v4 < v5)
        #expect(v5 < v6)
        #expect(v6 < v7)
        // Confirm the plan lists them in the same order
        #expect(schemas[0] == SchemaV3.self)
        #expect(schemas[1] == SchemaV4.self)
        #expect(schemas[2] == SchemaV5.self)
        #expect(schemas[3] == SchemaV6.self)
        #expect(schemas[4] == SchemaV7.self)
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
            for: Schema(versionedSchema: SchemaV7.self),
            migrationPlan: EpacMigrationPlan.self,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        // Basic sanity: the container exposes the expected model types
        let context = ModelContext(container)
        let members = try context.fetch(FetchDescriptor<ParliamentMember>())
        #expect(members.isEmpty)
        let questions = try context.fetch(FetchDescriptor<WrittenQuestion>())
        #expect(questions.isEmpty)
        let fiscalEntries = try context.fetch(FetchDescriptor<FiscalMonitorEntry>())
        #expect(fiscalEntries.isEmpty)
    }
}
