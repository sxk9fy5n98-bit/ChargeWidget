//
//  SharedConstants.swift
//  ChargeWidget
//

import Foundation

enum SharedConstants {
    static let appGroupID = "group.com.igncaio.ChargeWidget"
    static let deviceBatteriesKey = "deviceBatteries"
    static let backgroundRefreshTaskID = "com.igncaio.ChargeWidget.battery-refresh"
    static let backgroundMacActivityID = "com.igncaio.ChargeWidget.battery-refresh-macos"
    static let deviceBatterySubscriptionID = "device-battery-changes"
    static let backgroundBatteryRefreshInterval: TimeInterval = 15 * 60
    static let backgroundBatteryRefreshTolerance: TimeInterval = 5 * 60
    static let staleThreshold: TimeInterval = 2 * 60 * 60
}
