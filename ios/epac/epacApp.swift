//
//  epacApp.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import SwiftUI
import SwiftData
import BackgroundTasks
import Sentry

@main
struct epacApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

	var sharedModelContainer: ModelContainer = {
		do {
			return try ModelContainer(
				for: Schema(versionedSchema: SchemaV6.self),
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
		if let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String, !dsn.isEmpty, !dsn.hasPrefix("$(") {
			SentrySDK.start { options in
				options.dsn = dsn
				options.enableCrashHandler = true
				options.tracesSampleRate = 0.1
			}
		}

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
			ContentView(modelContainer: sharedModelContainer, appDelegate: appDelegate)
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
