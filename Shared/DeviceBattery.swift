//
//  DeviceBattery.swift
//  ChargeWidget
//

import Foundation
import CloudKit

struct DeviceBattery: Identifiable, Hashable, Codable {
    let id: String
    let deviceID: String
    let deviceName: String
    let batteryLevel: Double
    let isCharging: Bool
    let isLowPowerMode: Bool
    let timestamp: Date

    init(
        id: String,
        deviceID: String,
        deviceName: String,
        batteryLevel: Double,
        isCharging: Bool,
        isLowPowerMode: Bool,
        timestamp: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isLowPowerMode = isLowPowerMode
        self.timestamp = timestamp
    }

    init(record: CKRecord) {
        id = record.recordID.recordName
        deviceID = record["deviceID"] as? String ?? record.recordID.recordName
        deviceName = record["deviceName"] as? String ?? "Unknown"
        batteryLevel = record["batteryLevel"] as? Double ?? 0
        isCharging = record["isCharging"] as? Bool ?? false
        isLowPowerMode = record["isLowPowerMode"] as? Bool ?? false
        timestamp = record["timestamp"] as? Date ?? Date()
    }

    // Backward-compatible decoding for older cached JSON that may not include new keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? id
        deviceName = try container.decode(String.self, forKey: .deviceName)
        batteryLevel = try container.decode(Double.self, forKey: .batteryLevel)
        isCharging = try container.decodeIfPresent(Bool.self, forKey: .isCharging) ?? false
        isLowPowerMode = try container.decodeIfPresent(Bool.self, forKey: .isLowPowerMode) ?? false
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    var percentageText: String {
        "\(Int((batteryLevel * 100).rounded()))%"
    }

    var percentageValue: Int {
        Int((batteryLevel * 100).rounded())
    }

    /// True when the last sync is older than two hours (matches Apple’s dimmed Batteries treatment).
    var isStale: Bool {
        Date().timeIntervalSince(timestamp) > SharedConstants.staleThreshold
    }

    /// SF Symbol chosen to mirror Apple’s Batteries widget device glyphs.
    var deviceSymbolName: String {
        let name = deviceName.lowercased()
        if name.contains("watch") || name.contains("ultra") {
            return "applewatch"
        }
        if name.contains("ipad") {
            return "ipad"
        }
        if name.contains("iphone") || name.contains("phone") {
            return "iphone"
        }
        if name.contains("airpod") {
            return "airpods"
        }
        if name.contains("mac") || name.contains("book") || name.contains("imac") {
            return "laptopcomputer"
        }
        return "battery.100.percent"
    }
}
