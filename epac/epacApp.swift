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
		let schema = Schema([
			Item.self,
		])
		let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

		do {
			return try ModelContainer(for: schema, configurations: [modelConfiguration])
		} catch {
			fatalError("Could not create ModelContainer: \(error)")
		}
	}()

	private var model = Model()
	private var downloader = Downloader()
	var body: some Scene {
		WindowGroup {
			ContentView()
				.environmentObject(downloader)
		}
		.modelContainer(sharedModelContainer)
	}
}
