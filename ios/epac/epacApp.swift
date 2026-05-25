//
//  epacApp.swift
//  epac
//
//  Created by Sunny on 2024-12-08.
//

import BackgroundTasks
import Sentry
import SwiftData
import SwiftUI
import UIKit

enum AppRuntime {
	static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}

private enum SentryConfiguration {
	static let tracesSampleRate: NSNumber = 0.1
}

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
	/// Injected by ContentView once it has created the router.
	var router: NavigationRouter? {
		didSet {
			if let action = coldLaunchAction {
				router?.pendingQuickAction = action
				coldLaunchAction = nil
			}
		}
	}

	var coldLaunchAction: QuickAction?
}

@main
struct epacApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	let sharedModelContainer: ModelContainer
	let fetch: Fetch
	let hansardRepository: any HansardRepository

	private static func makeModelContainer() -> ModelContainer {
		do {
			let usesInMemoryStore = AppRuntime.isRunningTests || AppEnvironment.isMarketingCaptureMode
			return try ModelContainer(
				for: Schema(versionedSchema: SchemaV9.self),
				migrationPlan: EpacMigrationPlan.self,
				configurations: [ModelConfiguration(isStoredInMemoryOnly: usesInMemoryStore)]
			)
		} catch {
			fatalError("Could not create ModelContainer: \(error)")
		}
	}

	@Environment(\.scenePhase) private var scenePhase

	init() {
		let modelContainer = Self.makeModelContainer()
		let fetch = Fetch(modelContainer: modelContainer)
		let swiftDataHansardRepository = SwiftDataHansardRepository(
			modelContext: modelContainer.mainContext,
			fetch: fetch
		)
		self.sharedModelContainer = modelContainer
		self.fetch = fetch
		self.hansardRepository = JurisdictionRoutedHansardRepository(adapters: [
			.federal: swiftDataHansardRepository,
			.saskatchewan: SaskatchewanHansardAdapter(
				persistTranscript: swiftDataHansardRepository.storeTranscript
			)
		])

		guard !AppRuntime.isRunningTests, !AppEnvironment.isMarketingCaptureMode else { return }

		if let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String, !dsn.isEmpty, !dsn.hasPrefix("$(") {
			SentrySDK.start { options in
				options.dsn = "https://\(dsn)"
				options.enableCrashHandler = true
				options.tracesSampleRate = SentryConfiguration.tracesSampleRate
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
			ContentView(
				fetch: fetch,
				hansardRepository: hansardRepository,
				appDelegate: appDelegate
			)
		}
		.modelContainer(sharedModelContainer)
		.onChange(of: scenePhase) { _, newPhase in
			if newPhase == .active && !AppRuntime.isRunningTests && !AppEnvironment.isMarketingCaptureMode {
				// Snapshot the latest-seen bill introduction date so BillsView can mark
				// bills introduced since the previous session as "New" this session.
				if let latestSeen = UserDefaults.standard.object(forKey: "epac.bills.latestSeen") as? Date {
					UserDefaults.standard.set(latestSeen, forKey: "epac.bills.newSince")
				}
				BackgroundRefreshManager.shared.modelContainer = sharedModelContainer
				ReviewRequestManager.shared.recordAppOpen()
				BackgroundRefreshManager.shared.scheduleRefresh()
			}
		}
		#if targetEnvironment(macCatalyst)
		.commands {
			EpacMacCommands(commandCenter: .shared)
		}
		#endif
	}
}

#if targetEnvironment(macCatalyst)
private struct EpacMacCommands: Commands {
	let commandCenter: MacCommandCenter

	var body: some Commands {
		CommandGroup(replacing: .newItem) {}

		CommandGroup(after: .saveItem) {
			Button("Share epac") {
				commandCenter.shareCurrentContext()
			}
			.keyboardShortcut("s", modifiers: [.command, .shift])
		}

		CommandGroup(after: .textEditing) {
			Button("Find") {
				commandCenter.find()
			}
			.keyboardShortcut("f", modifiers: .command)
		}

		CommandMenu("Navigate") {
			Button("Home") { commandCenter.select(.home) }
				.keyboardShortcut("1", modifiers: .command)
			Button("Parliament") { commandCenter.select(.parliament) }
				.keyboardShortcut("2", modifiers: .command)
			Button("Members") { commandCenter.select(.members) }
				.keyboardShortcut("3", modifiers: .command)
			Button("Accountability") { commandCenter.select(.accountability) }
				.keyboardShortcut("4", modifiers: .command)
			Button("Search") { commandCenter.select(.search) }
				.keyboardShortcut("5", modifiers: .command)

			Divider()

			Button("Refresh") {
				commandCenter.refreshContent()
			}
			.keyboardShortcut("r", modifiers: .command)
		}
	}
}
#endif
