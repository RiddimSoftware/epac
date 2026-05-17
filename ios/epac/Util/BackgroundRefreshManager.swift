// BackgroundRefreshManager.swift
// epac
//
// Manages BGAppRefreshTask lifecycle: scheduling and handling.
// Schedules a wake at least 1 hour from now; iOS throttles actual execution
// based on device usage patterns.

import BackgroundTasks
import SwiftData

@MainActor
final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()

    static let taskIdentifier = "net.dinglebox.cabinetdoor.refresh"

    var modelContainer: ModelContainer?

    private init() {}

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        // Wake at least 1 hour from now; iOS throttles actual execution.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
        Log.debug("BackgroundRefreshManager: scheduled next refresh")
    }

    func handle(_ task: BGAppRefreshTask) {
        guard let container = modelContainer else {
            task.setTaskCompleted(success: false)
            return
        }

        // Schedule next wake before doing any work (required by Apple).
        scheduleRefresh()

        let refreshTask = Task {
            let fetch = Fetch(modelContainer: container)
            await fetch.backgroundRefresh()
            await HansardSubjectsRefresh.shared.refresh()
            Log.debug("BackgroundRefreshManager: refresh complete")
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        Task {
            await refreshTask.value
            task.setTaskCompleted(success: !refreshTask.isCancelled)
        }
    }
}
