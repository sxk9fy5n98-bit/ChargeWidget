//
//  ContentView.swift
//  ChargeWidget
//
//  Created by Jose Ignacio Montivero on 8/7/2026.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var batteryManager = BatteryManager.shared
    @State private var cachedDevices: [DeviceBattery] = SharedBatteryStore.load()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { _ = await batteryManager.refreshAndSave() }
                    } label: {
                        Label("Force Sync", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Section("Devices") {
                    if batteryManager.isLoading && cachedDevices.isEmpty {
                        ProgressView("Loading…")
                    } else if cachedDevices.isEmpty {
                        ContentUnavailableView(
                            "No Records",
                            systemImage: "battery.0",
                            description: Text("Run Force Sync to load batteries from CloudKit.")
                        )
                    } else {
                        ForEach(cachedDevices) { record in
                            DeviceBatteryRow(record: record)
                        }
                        .onDelete(perform: deleteRows)
                    }
                }

                if let error = batteryManager.lastError {
                    Section("Connection Error") {
                        Label(error, systemImage: "icloud.slash")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("ChargeWidget")
            .refreshable {
                _ = await batteryManager.fetchDeviceBatteries()
            }
            .onReceive(batteryManager.$records) { records in
                cachedDevices = records
            }
            .task {
                batteryManager.currentBatteryLevel = BatteryManager.readLocalBatteryLevel()
                batteryManager.currentDeviceName = BatteryManager.localDeviceName()
                _ = await batteryManager.fetchDeviceBatteries()
                cachedDevices = SharedBatteryStore.load()
            }
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        let devices = offsets.compactMap { idx in
            cachedDevices.indices.contains(idx) ? cachedDevices[idx] : nil
        }
        guard devices.isEmpty == false else { return }

        Task {
            for device in devices {
                _ = await batteryManager.deleteDevice(device, clearLastError: false)
            }
            cachedDevices = SharedBatteryStore.load()
        }
    }
}

struct DeviceBatteryRow: View {
    let record: DeviceBattery

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: record.deviceSymbolName)
                .font(.title3)
                .foregroundStyle(record.isLowPowerMode ? .yellow : batteryColor(for: record.batteryLevel))

            VStack(alignment: .leading, spacing: 3) {
                Text(record.deviceName)
                    .font(.headline)
                Text(record.isCharging ? "Charging" : "Not Charging")
                    .font(.caption)
                    .foregroundStyle(record.isCharging ? .green : .secondary)
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
        .accessibilityLabel("\(record.deviceName), \(record.percentageText), \(record.isCharging ? "charging" : "not charging")")
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
