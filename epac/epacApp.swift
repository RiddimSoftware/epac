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
			SittingCalendar.self,
			Hansard.self,
			OrderOfBusiness.self,
			SubjectOfBusiness.self,
			ParliamentMember.self,
			Speech.self,
			SpeechMessage.self,
			Constituency.self
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
