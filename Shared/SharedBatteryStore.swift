//
//  SharedBatteryStore.swift
//  ChargeWidget
//

import Foundation

enum SharedBatteryStore {
    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedConstants.appGroupID)
    }

    static func save(_ batteries: [DeviceBattery]) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(batteries)
            defaults.set(data, forKey: SharedConstants.deviceBatteriesKey)
        } catch {
            assertionFailure("Failed to encode DeviceBattery array: \(error)")
        }
    }

    static func load() -> [DeviceBattery] {
        guard let data = defaults?.data(forKey: SharedConstants.deviceBatteriesKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([DeviceBattery].self, from: data)
        } catch {
            return []
        }
    }
}
