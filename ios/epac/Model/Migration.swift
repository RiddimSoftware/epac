//
//  Migration.swift
//  epac
//

import SwiftData

enum EpacMigrationPlan: SchemaMigrationPlan {
	static var schemas: [any VersionedSchema.Type] {
		[SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self, SchemaV10.self]
	}

	static var stages: [MigrationStage] {
		[migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7, migrateV7toV8, migrateV8toV9, migrateV9toV10]
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

    // Lightweight stage: V7 adds FiscalMonitorEntry. Pure new table, no
    // existing model changes.
	static let migrateV6toV7 = MigrationStage.lightweight(
		fromVersion: SchemaV6.self,
		toVersion: SchemaV7.self
	)

    // Lightweight stage: V8 adds CabinetPosition. Pure new table, no
    // existing model changes.
	static let migrateV7toV8 = MigrationStage.lightweight(
		fromVersion: SchemaV7.self,
		toVersion: SchemaV8.self
	)

	// Custom stage: V9 makes ParliamentMember jurisdiction-aware and switches
	// uniqueness to a stored directoryKey so federal and provincial members can
	// coexist without name collisions.
	static let migrateV8toV9 = MigrationStage.custom(
		fromVersion: SchemaV8.self,
		toVersion: SchemaV9.self,
		willMigrate: nil,
		didMigrate: { context in
			let members = try context.fetch(FetchDescriptor<SchemaV9.ParliamentMember>())
			for member in members {
				member.jurisdiction = .federal
				member.directoryKey = SchemaV9.ParliamentMember.directoryKey(
					name: member.name,
					jurisdiction: member.jurisdiction
				)
			}
			try context.save()
		}
	)

	// Custom stage: V10 adds jurisdiction string to RecordedVote and MemberVote.
	static let migrateV9toV10 = MigrationStage.custom(
		fromVersion: SchemaV9.self,
		toVersion: SchemaV10.self,
		willMigrate: nil,
		didMigrate: { context in
			let votes = try context.fetch(FetchDescriptor<SchemaV10.RecordedVote>())
			for vote in votes {
				vote.jurisdiction = Jurisdiction.federal.rawValue
			}
			let memberVotes = try context.fetch(FetchDescriptor<SchemaV10.MemberVote>())
			for memberVote in memberVotes {
				memberVote.jurisdiction = Jurisdiction.federal.rawValue
			}
			try context.save()
		}
	)
}
