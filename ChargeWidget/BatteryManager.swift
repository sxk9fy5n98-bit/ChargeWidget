//
//  BatteryManager.swift
//  ChargeWidget
//

import Foundation
import CloudKit
import Combine
import WidgetKit

#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#elseif os(macOS)
import IOKit.ps
#endif

@MainActor
final class BatteryManager: ObservableObject {
    static let shared = BatteryManager()

    static let containerIdentifier = "iCloud.com.igncaio.ChargeWidget"
    static let recordType = "DeviceBattery"
    private static let macOSDeviceIDDefaultsKey = "ChargeWidget.macOSDeviceID"

    @Published var records: [DeviceBattery] = []
    @Published var currentBatteryLevel: Double = 0
    @Published var currentDeviceName: String = ""
    @Published var currentDeviceID: String = ""
    @Published var currentIsCharging = false
    @Published var currentIsLowPowerMode = false
    @Published var lastError: String?
    @Published var isLoading = false

    private let container: CKContainer
    private let database: CKDatabase

    private init() {
        container = CKContainer(identifier: Self.containerIdentifier)
        database = container.privateCloudDatabase
        currentDeviceName = Self.localDeviceName()
        currentDeviceID = Self.localDeviceID()
        currentBatteryLevel = Self.readLocalBatteryLevel()
        currentIsCharging = Self.readIsCharging()
        currentIsLowPowerMode = Self.readIsLowPowerMode()
        records = SharedBatteryStore.load()
    }

    // MARK: - Local Battery

    static func localDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(watchOS)
        return WKInterfaceDevice.current().name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown Device"
        #endif
    }

    static func localDeviceID() -> String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? fallbackDeviceID()
        #elseif os(watchOS)
        return WKInterfaceDevice.current().identifierForVendor?.uuidString ?? fallbackDeviceID()
        #elseif os(macOS)
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: macOSDeviceIDDefaultsKey) {
            return saved
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: macOSDeviceIDDefaultsKey)
        return generated
        #else
        return fallbackDeviceID()
        #endif
    }

    private static func fallbackDeviceID() -> String {
        let defaults = UserDefaults.standard
        let key = "ChargeWidget.fallbackDeviceID"
        if let saved = defaults.string(forKey: key) {
            return saved
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }

    static func readLocalBatteryLevel() -> Double {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level < 0 ? 0 : Double(level)

        #elseif os(watchOS)
        let level = WKInterfaceDevice.current().batteryLevel
        return level < 0 ? 0 : Double(level)

        #elseif os(macOS)
        return macOSBatteryLevel()

        #else
        return 0
        #endif
    }

    static func readIsCharging() -> Bool {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
        #elseif os(watchOS)
        let state = WKInterfaceDevice.current().batteryState
        return state == .charging || state == .full
        #elseif os(macOS)
        return macOSIsCharging()
        #else
        return false
        #endif
    }

    static func readIsLowPowerMode() -> Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    #if os(macOS)
    /// Reads battery charge via IOKit Power Sources, using `IOPSGetTimeRemainingEstimate` and power-source descriptions.
    private static func macOSBatteryLevel() -> Double {
        _ = IOPSGetTimeRemainingEstimate()

        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return 0
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int,
                  max > 0
            else {
                continue
            }
            return Double(current) / Double(max)
        }

        return 0
    }

    private static func macOSIsCharging() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return false
        }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let charging = description[kIOPSIsChargingKey] as? Bool {
                return charging
            }
        }
        return false
    }
    #endif

    // MARK: - App Group Persistence

    /// Encodes the DeviceBattery array to JSON and saves it to the shared App Group UserDefaults.
    private func persistRecordsToAppGroup() {
        SharedBatteryStore.save(records)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - CloudKit Retry

    /// Retries CloudKit requests on throttling (`CKError.Code.retryAfterSeconds`) using exponential backoff.
    private func withCloudKitRetry<T>(
        maxAttempts: Int = 6,
        baseDelaySeconds: TimeInterval = 1.0,
        operationDescription: String,
        _ operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?
        while attempt < maxAttempts {
            if Task.isCancelled { throw CancellationError() }
            attempt += 1

            do {
                return try await operation()
            } catch {
                lastError = error

                guard attempt < maxAttempts else { throw error }

                if let ckError = error as? CKError, let serverRetryAfterSeconds = ckError.retryAfterSeconds, serverRetryAfterSeconds > 0 {
                    // CloudKit throttling errors include the server-recommended backoff window.
                    let retryAfter = serverRetryAfterSeconds
                    let exponentialDelay = retryAfter * pow(2.0, Double(attempt - 1))
                    let delaySeconds = min(max(baseDelaySeconds, exponentialDelay), 60)

                    try await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                    continue
                }

                throw error
            }
        }

        throw lastError ?? CancellationError()
    }

    // MARK: - CloudKit Subscriptions

    /// Creates a CKQuerySubscription that delivers silent remote notifications when DeviceBattery records change.
    func ensureDeviceBatterySubscription() async {
        let subscriptionID = SharedConstants.deviceBatterySubscriptionID

        do {
            _ = try await withCloudKitRetry(operationDescription: "subscription lookup") {
                try await database.subscription(for: subscriptionID)
            }
            return
        } catch {
            // Subscription missing — create it below.
        }

        let subscription = CKQuerySubscription(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        notificationInfo.shouldBadge = false
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await withCloudKitRetry(operationDescription: "subscription save") {
                try await database.save(subscription)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Silent Push Handling

    /// Fetches CloudKit data, writes to the App Group, and reloads widgets.
    #if os(iOS)
    func handleSilentCloudKitUpdate() async -> UIBackgroundFetchResult {
        lastError = nil
        let previousIDs = Set(records.map(\.id))
        let previousLevels = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0.batteryLevel) })

        _ = await fetchDeviceBatteries(clearLastError: false)

        if lastError != nil {
            return .failed
        }

        let newIDs = Set(records.map(\.id))
        let levelsChanged = records.contains { previousLevels[$0.id] != $0.batteryLevel }
        if previousIDs != newIDs || levelsChanged {
            return .newData
        }
        return .noData
    }
    #else
    func handleSilentCloudKitUpdate() async -> Bool {
        lastError = nil
        _ = await fetchDeviceBatteries(clearLastError: false)
        return lastError == nil
    }
    #endif

    // MARK: - CloudKit Save

    func saveCurrentBattery(clearLastError: Bool = true) async -> Bool {
        if clearLastError { lastError = nil }
        currentBatteryLevel = Self.readLocalBatteryLevel()
        currentDeviceName = Self.localDeviceName()
        currentDeviceID = Self.localDeviceID()
        currentIsCharging = Self.readIsCharging()
        currentIsLowPowerMode = Self.readIsLowPowerMode()

        let recordID = CKRecord.ID(recordName: currentDeviceID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["deviceID"] = currentDeviceID as CKRecordValue
        record["deviceName"] = currentDeviceName as CKRecordValue
        record["batteryLevel"] = currentBatteryLevel as CKRecordValue
        record["isCharging"] = currentIsCharging as CKRecordValue
        record["isLowPowerMode"] = currentIsLowPowerMode as CKRecordValue
        record["timestamp"] = Date() as CKRecordValue

        do {
            let savedRecord: CKRecord = try await withCloudKitRetry(operationDescription: "modifyRecords(save)") {
                let (saveResults, _) = try await database.modifyRecords(
                    saving: [record],
                    deleting: [],
                    savePolicy: .allKeys,
                    atomically: true
                )
                guard case .success(let saved)? = saveResults[recordID] else {
                    if case .failure(let error)? = saveResults[recordID] {
                        throw error
                    }
                    throw NSError(domain: "ChargeWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: "CloudKit save returned no record"])
                }
                return saved
            }

            let deviceBattery = DeviceBattery(record: savedRecord)
            if let index = records.firstIndex(where: { $0.id == deviceBattery.id }) {
                records[index] = deviceBattery
            } else {
                records.insert(deviceBattery, at: 0)
            }
            records.sort { $0.timestamp > $1.timestamp }
            persistRecordsToAppGroup()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - CloudKit Fetch

    func fetchDeviceBatteries(clearLastError: Bool = true) async -> Bool {
        isLoading = true
        if clearLastError { lastError = nil }
        defer { isLoading = false }

        let query = CKQuery(
            recordType: Self.recordType,
            predicate: NSPredicate(value: true)
        )
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (matchResults, _) = try await withCloudKitRetry(operationDescription: "records(fetch)") {
                try await database.records(
                    matching: query,
                    inZoneWith: nil,
                    desiredKeys: ["deviceID", "deviceName", "batteryLevel", "isCharging", "isLowPowerMode", "timestamp"],
                    resultsLimit: CKQueryOperation.maximumResults
                )
            }

            var fetched: [DeviceBattery] = []
            var didEncounterRecordFailure = false
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    fetched.append(DeviceBattery(record: record))
                case .failure(let error):
                    lastError = error.localizedDescription
                    didEncounterRecordFailure = true
                }
            }
            if didEncounterRecordFailure {
                return false
            }

            records = fetched.sorted { $0.timestamp > $1.timestamp }
            persistRecordsToAppGroup()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func refreshAndSave() async -> Bool {
        lastError = nil
        let saveOK = await saveCurrentBattery(clearLastError: false)
        let fetchOK = await fetchDeviceBatteries(clearLastError: false)
        return saveOK && fetchOK
    }

    func deleteDevice(_ device: DeviceBattery, clearLastError: Bool = true) async -> Bool {
        if clearLastError { lastError = nil }
        let recordID = CKRecord.ID(recordName: device.deviceID)

        do {
            _ = try await withCloudKitRetry(operationDescription: "delete record") {
                try await database.deleteRecord(withID: recordID)
            }
            records.removeAll { $0.id == device.id || $0.deviceID == device.deviceID }
            persistRecordsToAppGroup()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
