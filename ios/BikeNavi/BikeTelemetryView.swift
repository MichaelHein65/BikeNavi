import SwiftUI

struct BikeTelemetryView: View {
    var compact = false
    @EnvironmentObject private var bike: BikeBluetoothService
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showConnection = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let display = BikeTelemetryDisplay(connected: bike.connected, battery: bike.battery, batteryAt: bike.batteryAt,
                mode: bike.assistMode, modeAt: bike.assistModeAt, riderPower: bike.riderPower, riderPowerAt: bike.powerAt,
                motorPower: bike.motorPower, motorPowerAt: bike.motorPowerAt, now: context.date,
                batteryReceivedInCurrentConnection: bike.batteryReceivedInCurrentConnection)
            VStack(alignment: .leading, spacing: compact ? 2 : 12) {
                if !compact { connectionButton }
                HStack(spacing: 6) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading, spacing: compact ? 6 : 12) {
                        metric("Bike-Akku", display.battery, id: "bikeBattery", subdued: !display.batteryIsCurrent)
                        metric("Fahrmodus", display.mode, id: "bikeMode", color: Self.modeColor(display.modeCode))
                        metric("Fahrer", display.riderPower, id: "bikeRiderPower")
                        metric("Motor", display.motorPower, id: "bikeMotorPower")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if compact { connectionButton }
                }
                if !display.batteryIsCurrent, let date = display.batteryReceivedAt {
                    Text("Akku zuletzt \(date.formatted(date: Calendar.current.isDateInToday(date) ? .omitted : .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(Theme.secondaryInk)
                } else if !bike.connected {
                    Text(compact ? "Bike nicht verbunden" : "Bike einschalten. Bei Bedarf kurz in Bosch Flow verbinden.")
                        .font(.caption2).foregroundStyle(Theme.secondaryInk)
                } else if display.batteryReceivedAt == nil {
                    Text("Bike verbunden – warte auf Daten. Falls nach kurzer Zeit nichts erscheint: Bosch Flow kurz öffnen und zurückkehren.")
                        .font(.caption2).foregroundStyle(Theme.secondaryInk)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 0 : 14)
        .background(Theme.accent.opacity(compact ? 0 : 0.07), in: RoundedRectangle(cornerRadius: 16))
        .sheet(isPresented: $showConnection) {
            NavigationStack {
                BikeBluetoothTestView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showConnection = false } } }
            }
        }
    }

    private var connectionButton: some View {
        let receiving = bike.connected && bike.lastTelemetryAt.map { Date().timeIntervalSince($0) < 15 } == true
        let indicator = receiving ? Theme.accent : bike.connected ? Color.orange : Color.secondary
        return Button { showConnection = true } label: {
            Group {
                if compact {
                    VStack(spacing: 3) {
                        Image(systemName: "bicycle").font(.body)
                        Circle().fill(indicator).frame(width: 5, height: 5)
                    }.frame(width: 44, height: 44)
                } else {
                    HStack {
                        Label("Dein Bike", systemImage: "bicycle").font(.subheadline.bold())
                        Spacer(minLength: 8)
                        Circle().fill(indicator).frame(width: 6, height: 6)
                        Text(receiving ? "Live-Daten" : bike.connected ? "Warte auf Daten" : "Verbinden").font(.caption)
                        Image(systemName: "chevron.right").font(.caption2.bold())
                    }
                }
            }.foregroundStyle(Theme.ink).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel("Bike-Verbindung")
            .accessibilityValue(receiving ? "Live-Daten" : bike.connected ? "Verbunden, warte auf Daten" : "Nicht verbunden")
            .accessibilityIdentifier("bikeConnection")
    }

    static func modeColor(_ code: Int?) -> Color? {
        switch code {
        case 0: return .black
        case 1: return .green
        case 2: return .blue
        case 3: return .purple
        case 4: return .red
        default: return nil
        }
    }

    private func metric(_ title: String, _ value: String, id: String, subdued: Bool = false, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                .foregroundStyle(color ?? (subdued ? Theme.secondaryInk : Theme.ink))
                .padding(.horizontal, color == .black ? 3 : 0)
                .background(color == .black ? Color.white.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 3))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value == "—" ? "Nicht verfügbar" : subdued ? "Zuletzt \(value)" : value)
        .accessibilityIdentifier(id)
    }
}
