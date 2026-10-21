import SwiftUI

struct EnergyEstimateView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var bike: BikeBluetoothService
    @State private var observations: [EnergyObservation] = []
    @State private var auditText = "Messqualität wird geprüft …"
    @State private var loaded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Akku am Ziel").font(.headline)
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(estimate(now: context.date)).font(.subheadline).accessibilityIdentifier("energyEstimate")
            }
            Text(auditText).font(.caption).foregroundStyle(.secondary)
            Text("Keine nutzbare Wh-Kapazität hinterlegt. Motorleistung ist kein Akku-Energiezähler. Wind, Temperatur und Fahrweise bleiben Unsicherheiten.").font(.caption).foregroundStyle(.secondary)
        }.task(id: state.activeRide?.id) { await audit() }
    }
    private func estimate(now: Date) -> String {
        guard loaded else { return "Noch keine belastbare Prognose" }
        guard bike.connected, bike.batteryReceivedInCurrentConnection, let battery = bike.battery,
              let time = bike.batteryAt, abs(time.timeIntervalSince(now)) <= 30,
              let mode = bike.assistMode, let modeTime = bike.assistModeAt, abs(modeTime.timeIntervalSince(now)) <= 30,
              let id = UserDefaults.standard.string(forKey: "BoschTestBikeIdentifier").flatMap(UUID.init(uuidString:)) else { return "Keine belastbare Prognose · aktuelle Bosch-Daten fehlen" }
        guard let model = EnergyCalibration.fit(observations, bikeID: id, mode: mode, now: now.timeIntervalSince1970) else {
            return "Keine belastbare Prognose · mindestens 8 geeignete Fahrten desselben Bikes und Modus sowie bestandene Prüfung an zurückgehaltenen Fahrten erforderlich"
        }
        guard let route = state.ridingRoute, let progress = state.progress, progress.distanceFromRoute <= 35,
              let heights = route.elevationProfile, heights.count >= 2 else { return "Keine belastbare Prognose · Reststrecke oder Höhenprofil fehlt" }
        let remaining = heights.filter { $0.distance >= progress.traveled }
        let ascent = zip(remaining,remaining.dropFirst()).reduce(0.0) { $0 + max(0,$1.1.altitude-$1.0.altitude) }
        let km = progress.remaining/1000
        guard km > 0, let band = model.remainingPercent(soc: battery, kilometres: km, ascentPerKM: ascent/km) else { return "Keine belastbare Prognose · Gelände außerhalb der Kalibrierung" }
        return "Etwa \(Int(floor(band.lowerBound)))–\(Int(ceil(band.upperBound))) % · empirische Bandbreite aus \(model.trainingCount) Fahrten, geprüft an \(model.holdoutCount) weiteren. Reserve einplanen."
    }
    private func audit() async {
        loaded = false
        #if DEBUG
        if ProcessInfo.processInfo.environment["BIKENAVI_REGION_PREVIEW"] == "1" {
            observations = []; auditText = "Beispieldaten · keine Bosch-Messfahrten"; loaded = true; return
        }
        #endif
        do {
            let result = try await Task.detached(priority: .utility) { () -> ([EnergyObservation], Int) in
                let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                let store = try LocalStore(url: directory.appendingPathComponent("BikeNavi/tours.sqlite"))
                let rides = try store.all().filter { !$0.deleted && $0.document.kind == .ride && $0.document.recordingState == .finished }
                var observations: [EnergyObservation] = []
                for record in rides {
                    try Task.checkCancellation()
                    let samples = try store.bikeSamples(rideID: record.id, limit: 100001)
                    guard samples.count <= 100000 else { continue }
                    if let observation = EnergyAudit.inspect(ride: record.document, samples: samples).observation { observations.append(observation) }
                }
                return (observations,rides.count)
            }.value
            observations = result.0; auditText = "\(result.0.count) von \(result.1) abgeschlossenen Fahrten erfüllen die Messkriterien."; loaded = true
        } catch { auditText = "Lokale Messdaten konnten nicht ausgewertet werden."; loaded = true }
    }
}
