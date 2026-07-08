//
//  AppDelegate.swift
//  ChargeWidget
//

import SwiftUI
import CloudKit
import UserNotifications
import WidgetKit

#if os(iOS)
import UIKit
import BackgroundTasks

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundBatteryRefresh.register()
        BackgroundBatteryRefresh.schedule()

        application.registerForRemoteNotifications()

        Task {
            await BatteryManager.shared.ensureDeviceBatterySubscription()
        }

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundBatteryRefresh.schedule()
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // CloudKit delivers silent pushes via APNs once the device is registered.
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            BatteryManager.shared.lastError = error.localizedDescription
        }
    }

    /// Processes CloudKit silent pushes: fetch, persist to App Group, reload widgets.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification?.subscriptionID == SharedConstants.deviceBatterySubscriptionID
                || notification is CKQueryNotification else {
            completionHandler(.noData)
            return
        }

        Task {
            let result = await BatteryManager.shared.handleSilentCloudKitUpdate()
            completionHandler(result)
        }
    }
}

#elseif os(watchOS)
import WatchKit

final class AppDelegate: NSObject, WKExtensionDelegate {
    private var isSchedulingRefresh = false

    func applicationDidBecomeActive() {
        Task {
            await BatteryManager.shared.ensureDeviceBatterySubscription()
        }
        scheduleApplicationRefresh()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            guard let refreshTask = task as? WKApplicationRefreshBackgroundTask else {
                task.setTaskCompletedWithSnapshot(false)
                continue
            }

            refreshTask.expirationHandler = {
                // Background time is running out; cancel work quickly.
            }

            Task {
                let ok = await BatteryManager.shared.refreshAndSave()
                refreshTask.setTaskCompletedWithSnapshot(false)
                if ok == false {
                    // Keep lastError for the UI when the app next foregrounds.
                }
                scheduleApplicationRefresh()
            }
        }
    }

    private func scheduleApplicationRefresh() {
        guard !isSchedulingRefresh else { return }
        isSchedulingRefresh = true

        WKApplication.shared()
            .scheduleBackgroundRefresh(
                withPreferredDate: Date(timeIntervalSinceNow: SharedConstants.backgroundBatteryRefreshInterval),
                userInfo: nil
            ) { [weak self] error in
                guard let self else { return }
                self.isSchedulingRefresh = false
                if let error {
                    Task { @MainActor in
                        BatteryManager.shared.lastError = error.localizedDescription
                    }
                }
            }
    }
}

#elseif os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var macActivityScheduler: NSBackgroundActivityScheduler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
        Task {
            await BatteryManager.shared.ensureDeviceBatterySubscription()
        }

        scheduleMacBackgroundBatteryRefresh()
    }

    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String: Any]
    ) {
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        guard notification?.subscriptionID == SharedConstants.deviceBatterySubscriptionID
                || notification is CKQueryNotification else {
            return
        }

        Task {
            _ = await BatteryManager.shared.handleSilentCloudKitUpdate()
        }
    }

    private func scheduleMacBackgroundBatteryRefresh() {
        let scheduler = NSBackgroundActivityScheduler(identifier: SharedConstants.backgroundMacActivityID)
        scheduler.repeats = true
        scheduler.interval = SharedConstants.backgroundBatteryRefreshInterval
        scheduler.tolerance = SharedConstants.backgroundBatteryRefreshTolerance

        scheduler.schedule { completion in
            Task { [weak self] in
                guard self != nil else {
                    completion(.deferred)
                    return
                }
                let ok = await BatteryManager.shared.refreshAndSave()
                completion(ok ? .finished : .deferred)
            }
        }
        macActivityScheduler = scheduler
    }
}
#endif
