//
//  epacApp.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData

@main
struct epacApp: App {
	var sharedModelContainer: ModelContainer = {
		let schema = Schema(versionedSchema: SchemaV2.self)
#if DEBUG
		let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
#else
		let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
#endif

		do {
			return try ModelContainer(for: schema, migrationPlan: MigrationPlan.self, configurations: [modelConfiguration])
		} catch {
			fatalError("Could not create ModelContainer: \(error)")
		}
	}()

	var body: some Scene {
		WindowGroup {
			ContentView(modelContainer: sharedModelContainer)
		}
		.modelContainer(sharedModelContainer)
	}
}

enum MigrationPlan: SchemaMigrationPlan {
	static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
	static var stages: [MigrationStage] {
		[v1tov2]
	}
	static var v1tov2: MigrationStage { MigrationStage.custom(fromVersion: SchemaV1.self, toVersion: SchemaV2.self) { context in
		do {
			try context.delete(model: SchemaV1.SittingCalendar.self)
			try context.delete(model: SchemaV1.Hansard.self)
			try context.delete(model: SchemaV1.OrderOfBusiness.self)
			try context.delete(model: SchemaV1.SubjectOfBusiness.self)
			try context.delete(model: SchemaV1.SpeechMessage.self)
			try context.delete(model: SchemaV1.Speech.self)
			try context.delete(model: SchemaV1.ParliamentMember.self)
		} catch {
			Log.debug("Failed to delete SpeechMessageV1 in migration to v2 \(error.localizedDescription)")
		}
	} didMigrate: { context in

	}
	}
}
