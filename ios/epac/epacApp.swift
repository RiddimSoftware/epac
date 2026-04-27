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
		do {
			return try ModelContainer(
				for: Schema(versionedSchema: SchemaV5.self),
				migrationPlan: EpacMigrationPlan.self,
				configurations: [ModelConfiguration(isStoredInMemoryOnly: false)]
			)
		} catch {
			fatalError("Could not create ModelContainer: \(error)")
		}
	}()

	@State private var notificationManager = NotificationManager()
	@Environment(\.scenePhase) private var scenePhase

	init() {
		MetricKitSubscriber.shared.start()
	}

	var body: some Scene {
		WindowGroup {
			ContentView(modelContainer: sharedModelContainer)
				.environment(notificationManager)
		}
		.modelContainer(sharedModelContainer)
		.onChange(of: scenePhase) { oldPhase, newPhase in
			if newPhase == .active {
				ReviewRequestManager.shared.recordAppOpen()
			}
		}
	}
}
