//
//  BackgroundBatteryRefresh.swift
//  ChargeWidget
//

import Foundation

#if canImport(BackgroundTasks) && os(iOS)
import BackgroundTasks

enum BackgroundBatteryRefresh {
    static let taskIdentifier = SharedConstants.backgroundRefreshTaskID

    /// Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule(earliestBeginIn seconds: TimeInterval = 15 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Scheduling can fail if the identifier isn’t listed or the system denies the request.
            #if DEBUG
            print("Failed to schedule BGAppRefreshTask: \(error)")
            #endif
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()

        let operation = Task {
            await BatteryManager.shared.refreshAndSave()
        }

        task.expirationHandler = {
            operation.cancel()
        }

        Task {
            let success = await operation.value
            task.setTaskCompleted(success: success)
        }
    }
}
#endif
