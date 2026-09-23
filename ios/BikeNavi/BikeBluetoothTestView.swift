import SwiftUI

struct BikeBluetoothTestView: View {
    @EnvironmentObject private var probe: BikeBluetoothService
    var body: some View {
        Form {
            Section {
                Label("Bosch Kiox 500", systemImage: "bicycle").font(.headline)
                Text(probe.status)
                if !probe.connected { Button("Erneut suchen") { probe.retry() } }
            } header: { Text("Dein Bike") } footer: {
                Text("Bike einschalten und iPhone in die Nähe legen. Falls kein Bike erscheint, kurz in Bosch Flow verbinden und den Test erneut starten.")
            }
            if !probe.candidates.isEmpty {
                Section("Gefundene Bikes") {
                    ForEach(probe.candidates) { candidate in
                        Button { probe.connect(candidate.id) } label: {
                            VStack(alignment: .leading) {
                                Text(candidate.name)
                                Text(candidate.source).font(.caption).foregroundStyle(.secondary)
                            }
                        }.disabled(!probe.running)
                    }
                }
            }
            Section("Messwerte") {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let batteryFresh = probe.connected && probe.batteryReceivedInCurrentConnection && probe.batteryAt.map { context.date.timeIntervalSince($0) < 30 } == true
                    let powerFresh = probe.connected && probe.powerAt.map { context.date.timeIntervalSince($0) < 15 } == true
                    let motorFresh = probe.connected && probe.motorPowerAt.map { context.date.timeIntervalSince($0) < 15 } == true
                    let modeFresh = probe.connected && probe.assistModeAt.map { context.date.timeIntervalSince($0) < 15 } == true
                    VStack(spacing: 12) {
                        LabeledContent("Akku", value: batteryFresh ? "\(probe.battery ?? 0) %" : probe.battery.map { "Zuletzt \($0) %" } ?? "Nicht verfügbar")
                        LabeledContent("Fahrerleistung", value: powerFresh ? "\(probe.riderPower ?? 0) W" : "Nicht verfügbar")
                        LabeledContent("Fahrmodus") {
                            if modeFresh, let code = probe.assistMode {
                                Text(BikeTelemetryDisplay.modeName(code))
                                    .foregroundStyle(BikeTelemetryView.modeColor(code) ?? Theme.ink)
                                    .padding(.horizontal, code == 0 ? 3 : 0)
                                    .background(code == 0 ? Color.white.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 3))
                            } else { Text("Nicht verfügbar") }
                        }
                        LabeledContent("Motorleistung", value: motorFresh ? "\(probe.motorPower ?? 0) W" : "Nicht verfügbar")
                    }
                }
                LabeledContent("Empfangene Datenpakete", value: "\(probe.packets)")
                LabeledContent("Smartphone-Datenpakete", value: "\(probe.rawPackets)")
                if let date = probe.batteryAt {
                    LabeledContent("Letzter Akkumesswert", value: date.formatted(date: .omitted, time: .standard))
                }
                Text("Die Werte dieses Tests kommen direkt per Bluetooth vom Bike.").font(.footnote).foregroundStyle(.secondary)
                Text("Die Bezeichnung der Fahrstufen gleichen wir noch mit deinem Kiox ab. Leistungswerte sind noch nicht während einer Fahrt geprüft.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Testprotokoll") {
                ShareLink(item: probe.logURL) { Label("Protokoll teilen", systemImage: "square.and.arrow.up") }
                ForEach(Array(probe.messages.suffix(12).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Bike-Verbindung")
        .onAppear { probe.monitor(true, for: .diagnostics) }
        .onDisappear { probe.monitor(false, for: .diagnostics) }
    }
}
