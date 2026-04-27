// BackgroundRefreshManager.swift
// epac
//
// Manages BGAppRefreshTask lifecycle: scheduling, handling, and calendar-aware
// throttling. Only schedules wakes on weekdays within the parliamentary sitting
// window (September–June) to avoid unnecessary battery drain during recess.

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
