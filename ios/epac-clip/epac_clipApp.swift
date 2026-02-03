//
//  epac_clipApp.swift
//  epac-clip
//
//  Created by Sunny on 2024-12-22.
//

import SwiftUI
import SwiftData

@main
struct epac_clipApp: App {
	var sharedModelContainer: ModelContainer = {
		let schema = Schema(versionedSchema: SchemaV3.self)
		let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

		do {
			return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
