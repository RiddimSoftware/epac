//
//  Migration.swift
//  epac
//

import SwiftData

enum EpacMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [migrateV3toV4, migrateV4toV5, migrateV5toV6]
    }

    // Custom stage: V4 added contact fields to ParliamentMember, including the
    // non-optional `contactFetched: Bool`. SwiftData can't infer a default for
    // non-optional properties during lightweight migration, so didMigrate sets
    // it explicitly on all pre-existing records.
    static let migrateV3toV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self,
        toVersion: SchemaV4.self,
        willMigrate: nil,
        didMigrate: { context in
            let members = try context.fetch(FetchDescriptor<SchemaV4.ParliamentMember>())
            for member in members {
                member.contactFetched = false
            }
            try context.save()
        }
    )

    // Lightweight stage: V5 adds RecordedVote and MemberVote. Adding new model
    // types with no removal or rename is always a safe lightweight migration.
    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SchemaV4.self,
        toVersion: SchemaV5.self
    )

    // Lightweight stage: V6 adds WrittenQuestion. Pure new table, no existing
    // model changes.
    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SchemaV5.self,
        toVersion: SchemaV6.self
    )
}
