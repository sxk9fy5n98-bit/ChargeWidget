//
//  BatteriesWidget.swift
//  ChargeWidgetUI
//

import WidgetKit
import SwiftUI

struct BatteriesEntry: TimelineEntry {
    let date: Date
    let batteries: [DeviceBattery]
}

struct BatteriesProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteriesEntry {
        BatteriesEntry(date: Date(), batteries: Self.sampleBatteries)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatteriesEntry) -> Void) {
        let batteries = SharedBatteryStore.load()
        if context.isPreview && batteries.isEmpty {
            completion(BatteriesEntry(date: Date(), batteries: Self.sampleBatteries))
        } else {
            completion(BatteriesEntry(date: Date(), batteries: batteries))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteriesEntry>) -> Void) {
        let now = Date()
        let batteries = SharedBatteryStore.load()
        let entry = BatteriesEntry(date: now, batteries: batteries)

        // Refresh timeline when the soonest record would cross the 2-hour stale threshold.
        let staleRefresh = batteries
            .map { $0.timestamp.addingTimeInterval(SharedConstants.staleThreshold) }
            .filter { $0 > now }
            .min()
        let nextUpdate = staleRefresh ?? Calendar.current.date(byAdding: .minute, value: 15, to: now)
            ?? now.addingTimeInterval(900)

        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private static let sampleBatteries: [DeviceBattery] = [
        DeviceBattery(id: "1", deviceID: "1", deviceName: "iPhone", batteryLevel: 0.72, isCharging: true, isLowPowerMode: false, timestamp: Date()),
        DeviceBattery(id: "2", deviceID: "2", deviceName: "Apple Watch", batteryLevel: 0.45, isCharging: false, isLowPowerMode: true, timestamp: Date().addingTimeInterval(-3 * 60 * 60)),
        DeviceBattery(id: "3", deviceID: "3", deviceName: "AirPods", batteryLevel: 0.88, isCharging: true, isLowPowerMode: false, timestamp: Date()),
        DeviceBattery(id: "4", deviceID: "4", deviceName: "MacBook Pro", batteryLevel: 0.61, isCharging: false, isLowPowerMode: false, timestamp: Date())
    ]
}

struct BatteriesWidget: Widget {
    let kind = "BatteriesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BatteriesProvider()) { entry in
            BatteriesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Batteries")
        .description("See battery levels for your devices.")
        #if os(iOS) || os(macOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #elseif os(watchOS)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
        #endif
    }
}

struct BatteriesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: BatteriesEntry

    var body: some View {
        if entry.batteries.isEmpty {
            EmptyBatteriesView()
        } else {
            BatteryGridView(batteries: displayedBatteries, columns: columnCount)
        }
    }

    private var columnCount: Int {
        switch family {
        #if os(iOS) || os(macOS)
        case .systemSmall: return 2
        case .systemMedium: return 4
        case .systemLarge: return 4
        #endif
        #if os(watchOS)
        case .accessoryCircular: return 1
        case .accessoryRectangular: return 2
        #endif
        default: return 2
        }
    }

    private var maxItems: Int {
        switch family {
        #if os(iOS) || os(macOS)
        case .systemSmall: return 4
        case .systemMedium: return 4
        case .systemLarge: return 8
        #endif
        #if os(watchOS)
        case .accessoryCircular: return 1
        case .accessoryRectangular: return 2
        #endif
        default: return 4
        }
    }

    private var displayedBatteries: [DeviceBattery] {
        Array(entry.batteries.prefix(maxItems))
    }
}

struct BatteryGridView: View {
    let batteries: [DeviceBattery]
    let columns: Int
    @Environment(\.widgetFamily) private var family

    private var gridItems: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridItems, spacing: 10) {
            ForEach(batteries) { battery in
                BatteryRingCell(battery: battery, family: family)
            }
        }
        .padding(4)
    }
}

struct BatteryRingCell: View {
    let battery: DeviceBattery
    let family: WidgetFamily

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Gauge(value: battery.batteryLevel.clamped(to: 0...1)) {
                    Image(systemName: battery.deviceSymbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ringColor)
                } currentValueLabel: {
                    Text("\(battery.percentageValue)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(battery.isStale ? .secondary : .primary)
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(ringColor)
                .opacity(battery.isStale ? 0.4 : 1.0)

                if battery.isCharging {
                    ZStack {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: boltMetrics.strokeSize, weight: .bold))
                            .foregroundStyle(.black)
                            .offset(x: boltMetrics.strokeOffsetX, y: boltMetrics.strokeOffsetY)
                        Image(systemName: "bolt.fill")
                            .font(.system(size: boltMetrics.fillSize, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: boltMetrics.positionX, y: boltMetrics.positionY)
                }
            }
            .accessibilityLabel(accessibilityText)

            Text(shortName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .opacity(battery.isStale ? 0.5 : 1.0)
        }
        .frame(maxWidth: .infinity)
    }

    private var accessibilityText: String {
        let powerState = battery.isLowPowerMode ? ", low power mode" : ""
        let chargingState = battery.isCharging ? ", charging" : ""
        let base = "\(battery.deviceName), \(battery.percentageText)\(chargingState)\(powerState)"
        return battery.isStale ? "\(base), outdated" : base
    }

    private var shortName: String {
        let parts = battery.deviceName.split(separator: " ")
        if parts.count > 2 {
            return parts.suffix(2).joined(separator: " ")
        }
        return battery.deviceName
    }

    private var ringColor: Color {
        if battery.isLowPowerMode {
            return Color.yellow
        }
        let base: Color
        switch battery.batteryLevel {
        case ..<0.2: base = .red
        case ..<0.3: base = .orange
        default: base = .green
        }
        return battery.isStale ? base.opacity(0.45) : base
    }

    private var boltMetrics: BoltMetrics {
        switch family {
        #if os(iOS) || os(macOS)
        case .systemSmall:
            return BoltMetrics(
                fillSize: 7.5,
                strokeSize: 8.7,
                positionX: 2.0,
                positionY: -1.2,
                strokeOffsetX: 0.5,
                strokeOffsetY: 0.5
            )
        case .systemMedium:
            return BoltMetrics(
                fillSize: 8.0,
                strokeSize: 9.2,
                positionX: 2.3,
                positionY: -1.6,
                strokeOffsetX: 0.55,
                strokeOffsetY: 0.55
            )
        case .systemLarge:
            return BoltMetrics(
                fillSize: 8.4,
                strokeSize: 9.6,
                positionX: 2.6,
                positionY: -1.8,
                strokeOffsetX: 0.6,
                strokeOffsetY: 0.6
            )
        #endif
        #if os(watchOS)
        case .accessoryCircular:
            return BoltMetrics(
                fillSize: 7.4,
                strokeSize: 8.6,
                positionX: 2.0,
                positionY: -1.3,
                strokeOffsetX: 0.5,
                strokeOffsetY: 0.5
            )
        case .accessoryRectangular:
            return BoltMetrics(
                fillSize: 7.8,
                strokeSize: 9.0,
                positionX: 2.2,
                positionY: -1.5,
                strokeOffsetX: 0.55,
                strokeOffsetY: 0.55
            )
        #endif
        default:
            return BoltMetrics(
                fillSize: 8.0,
                strokeSize: 9.2,
                positionX: 2.3,
                positionY: -1.6,
                strokeOffsetX: 0.55,
                strokeOffsetY: 0.55
            )
        }
    }
}

private struct BoltMetrics {
    let fillSize: CGFloat
    let strokeSize: CGFloat
    let positionX: CGFloat
    let positionY: CGFloat
    let strokeOffsetX: CGFloat
    let strokeOffsetY: CGFloat
}

struct EmptyBatteriesView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "battery.0.percent")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Batteries")
                .font(.headline)
            Text("Open ChargeWidget to sync device battery levels.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#Preview("Medium", as: .systemMedium) {
    BatteriesWidget()
} timeline: {
    BatteriesEntry(
        date: .now,
        batteries: [
            DeviceBattery(id: "1", deviceID: "1", deviceName: "iPhone", batteryLevel: 0.72, isCharging: true, isLowPowerMode: false, timestamp: .now),
            DeviceBattery(id: "2", deviceID: "2", deviceName: "Apple Watch", batteryLevel: 0.45, isCharging: false, isLowPowerMode: true, timestamp: .now.addingTimeInterval(-3 * 60 * 60)),
            DeviceBattery(id: "3", deviceID: "3", deviceName: "AirPods", batteryLevel: 0.18, isCharging: false, isLowPowerMode: false, timestamp: .now),
            DeviceBattery(id: "4", deviceID: "4", deviceName: "MacBook Pro", batteryLevel: 0.61, isCharging: false, isLowPowerMode: false, timestamp: .now)
        ]
    )
}

#Preview("Empty", as: .systemMedium) {
    BatteriesWidget()
} timeline: {
    BatteriesEntry(date: .now, batteries: [])
}
