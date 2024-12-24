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
		let schema = Schema([
			SittingCalendar.self,
			Hansard.self,
			OrderOfBusiness.self,
			SubjectOfBusiness.self,
			ParliamentMember.self,
			Speech.self,
			SpeechMessage.self
		])
		#if DEBUG
		let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
		#else
		let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
		#endif

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
