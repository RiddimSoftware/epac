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
		let schema = Schema(versionedSchema: SchemaV3.self)
		let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
		do {
			return try ModelContainer(for: schema, configurations: [modelConfiguration])
		} catch {
			// Destructive migration: delete existing data if schema is incompatible
			let url = modelConfiguration.url
			let fileManager = FileManager.default
			try? fileManager.removeItem(at: url)
			try? fileManager.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-shm"))
			try? fileManager.removeItem(at: url.deletingPathExtension().appendingPathExtension("sqlite-wal"))
			do {
				return try ModelContainer(for: schema, configurations: [modelConfiguration])
			} catch {
				fatalError("Could not create ModelContainer: \(error)")
			}
		}
	}()

	@State private var notificationManager = NotificationManager()

	var body: some Scene {
		WindowGroup {
			ContentView(modelContainer: sharedModelContainer)
				.environment(notificationManager)
		}
		.modelContainer(sharedModelContainer)
	}
}
