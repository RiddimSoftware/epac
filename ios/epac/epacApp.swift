//
//  epacApp.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct epacApp: App {
	var sharedModelContainer: ModelContainer = {
		let schema = Schema(versionedSchema: SchemaV5.self)
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
	@Environment(\.scenePhase) private var scenePhase

	init() {
		MetricKitSubscriber.shared.start()

		BGTaskScheduler.shared.register(
			forTaskWithIdentifier: BackgroundRefreshManager.taskIdentifier,
			using: nil
		) { task in
			guard let refreshTask = task as? BGAppRefreshTask else {
				task.setTaskCompleted(success: false)
				return
			}
			Task { @MainActor in
				BackgroundRefreshManager.shared.handle(refreshTask)
			}
		}
	}

	var body: some Scene {
		WindowGroup {
			ContentView(modelContainer: sharedModelContainer)
				.environment(notificationManager)
		}
		.modelContainer(sharedModelContainer)
		.onChange(of: scenePhase) { oldPhase, newPhase in
			if newPhase == .active {
				BackgroundRefreshManager.shared.modelContainer = sharedModelContainer
				ReviewRequestManager.shared.recordAppOpen()
				BackgroundRefreshManager.shared.scheduleRefresh()
			}
		}
	}
}
