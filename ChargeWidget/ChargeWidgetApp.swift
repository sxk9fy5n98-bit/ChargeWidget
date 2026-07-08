//
//  ChargeWidgetApp.swift
//  ChargeWidget
//
//  Created by Jose Ignacio Montivero on 8/7/2026.
//

import SwiftUI
import CloudKit

#if os(watchOS)
import WatchKit
#endif

@main
struct ChargeWidgetApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(watchOS)
    @WKExtensionDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                Task {
                    await BatteryManager.shared.ensureDeviceBatterySubscription()
                    _ = await BatteryManager.shared.refreshAndSave()
                }
            case .background:
                #if os(iOS)
                BackgroundBatteryRefresh.schedule()
                #endif
            default:
                break
            }
        }
    }
}
