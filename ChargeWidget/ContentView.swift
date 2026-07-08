//
//  ContentView.swift
//  ChargeWidget
//
//  Created by Jose Ignacio Montivero on 8/7/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var batteryManager = BatteryManager.shared

    private var batteryPercentFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter
    }

    var body: some View {
        NavigationStack {
            List {
                Section("This Device") {
                    HStack {
                        Label(batteryManager.currentDeviceName, systemImage: "laptopcomputer.and.iphone")
                        Spacer()
                        Text(batteryPercentFormatter.string(from: NSNumber(value: batteryManager.currentBatteryLevel)) ?? "—")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Section("Synced Devices") {
                    if batteryManager.isLoading && batteryManager.records.isEmpty {
                        ProgressView("Loading…")
                    } else if batteryManager.records.isEmpty {
                        ContentUnavailableView(
                            "No Records",
                            systemImage: "battery.0",
                            description: Text("Save this device’s battery level to CloudKit to see it here.")
                        )
                    } else {
                        ForEach(batteryManager.records) { record in
                            DeviceBatteryRow(record: record)
                        }
                    }
                }

                if let error = batteryManager.lastError {
                    Section("CloudKit Connection") {
                        ContentUnavailableView(
                            "Sync Failed",
                            systemImage: "icloud.slash",
                            description: Text(error)
                        )

                        Button {
                            Task { _ = await batteryManager.refreshAndSave() }
                        } label: {
                            Label("Retry Sync", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("ChargeWidget")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { _ = await batteryManager.refreshAndSave() }
                    } label: {
                        Label("Save & Refresh", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { _ = await batteryManager.fetchDeviceBatteries() }
                    } label: {
                        Label("Fetch", systemImage: "icloud.and.arrow.down")
                    }
                }
            }
            .refreshable {
                _ = await batteryManager.fetchDeviceBatteries()
            }
            .task {
                batteryManager.currentBatteryLevel = BatteryManager.readLocalBatteryLevel()
                batteryManager.currentDeviceName = BatteryManager.localDeviceName()
                _ = await batteryManager.fetchDeviceBatteries()
            }
        }
    }
}

struct DeviceBatteryRow: View {
    let record: DeviceBattery

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.deviceName)
                    .font(.headline)
                Text(record.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(record.percentageText)
                .font(.title3.monospacedDigit().weight(.semibold))
                .foregroundStyle(batteryColor(for: record.batteryLevel))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.deviceName), \(record.percentageText)")
    }

    private func batteryColor(for level: Double) -> Color {
        switch level {
        case ..<0.2: return .red
        case ..<0.4: return .orange
        default: return .green
        }
    }
}

#Preview {
    ContentView()
}
