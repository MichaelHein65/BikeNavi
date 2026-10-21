import Foundation

struct EnergyObservation: Codable {
    var rideID: UUID
    var bikeID: UUID
    var endedAt: Double
    var kilometres: Double
    var drop: Double
    var ascentPerKM: Double
    var assistMode: Int
    var rate: Double { drop / kilometres }
}
struct EnergyAudit {
    var observation: EnergyObservation?
    var reason: String
    static func inspect(ride: TourDocument, samples: [RecordedBikeSample]) -> Self {
        func reject(_ reason: String) -> Self { Self(observation: nil, reason: reason) }
        guard ride.profile.mode == .cycling, ride.profile.electric, ride.recordingState == .finished else { return reject("Keine abgeschlossene E-Bike-Fahrt") }
        let sorted = samples.filter { $0.rideID == ride.id }.sorted { $0.measurement.timestamp < $1.measurement.timestamp }
        let bikes = Set(sorted.map { $0.measurement.bikeID })
        guard bikes.count == 1, let bikeID = bikes.first else { return reject("Bike-Zuordnung fehlt oder wechselt") }
        guard !sorted.contains(where: { $0.measurement.chargerConnected == true }) else { return reject("Ladeereignis") }
        let battery = sorted.filter { $0.measurement.batteryPercent != nil }
        guard battery.count >= 4, let first = battery.first, let last = battery.last,
              last.measurement.timestamp - first.measurement.timestamp >= 600 else { return reject("Zu wenige Akku-Stützstellen") }
        for (a,b) in zip(battery, battery.dropFirst()) {
            guard b.measurement.batteryPercent! <= a.measurement.batteryPercent! + 1,
                  b.measurement.timestamp - a.measurement.timestamp <= 1800 else { return reject("Akkuanstieg oder Messlücke über 30 Minuten") }
        }
        let drop = Double(first.measurement.batteryPercent! - last.measurement.batteryPercent!)
        guard drop >= 5 else { return reject("Akkuabnahme unter 5 Prozentpunkten") }
        let track = ride.track.filter { $0.timestamp >= first.measurement.timestamp && $0.timestamp <= last.measurement.timestamp }
        guard track.count >= 20, track.allSatisfy({ $0.accuracy >= 0 && $0.accuracy <= 25 }),
              track.first!.timestamp - first.measurement.timestamp <= 30,
              last.measurement.timestamp - track.last!.timestamp <= 30 else { return reject("GPS-Abdeckung oder Genauigkeit unzureichend") }
        var distance = 0.0, ascent = 0.0
        guard track.allSatisfy({ $0.coordinate.altitude?.isFinite == true }) else { return reject("Gemessene Höhen fehlen") }
        var anchor = track.first!.coordinate.altitude!
        for (a,b) in zip(track, track.dropFirst()) {
            let dt = b.timestamp-a.timestamp
            guard a.segment == b.segment, dt > 0, dt <= 60 else { return reject("GPS-Lücke oder Pausenwechsel im Akkubereich") }
            let metres = a.coordinate.distance(to: b.coordinate)
            guard metres / dt <= 25 else { return reject("Unplausibler GPS-Sprung") }
            distance += metres
            let height = b.coordinate.altitude!
            if abs(height-anchor) >= 3 { ascent += max(0,height-anchor); anchor = height }
        }
        guard distance >= 5000, distance >= ride.recordedDistance * 0.8 else { return reject("Zu kurze oder unvollständige Messstrecke") }
        let modes = sorted.filter { $0.measurement.assistMode != nil && $0.measurement.timestamp >= first.measurement.timestamp && $0.measurement.timestamp <= last.measurement.timestamp }
        var duration: [Int: Double] = [:]
        for (a,b) in zip(modes, modes.dropFirst()) {
            let dt = b.measurement.timestamp-a.measurement.timestamp
            if dt >= 0 && dt <= 30 { duration[a.measurement.assistMode!, default: 0] += dt }
        }
        guard let dominant = duration.max(by: { $0.value < $1.value }),
              dominant.value >= (last.measurement.timestamp-first.measurement.timestamp)*0.9 else { return reject("Fahrmodus wechselt oder ist nicht ausreichend belegt") }
        return Self(observation: EnergyObservation(rideID: ride.id, bikeID: bikeID, endedAt: last.measurement.timestamp,
            kilometres: distance/1000, drop: drop, ascentPerKM: ascent/(distance/1000), assistMode: dominant.key), reason: "Für Kalibrierung geeignet")
    }
}
struct EnergyCalibration {
    var lowerRate: Double
    var upperRate: Double
    var medianRate: Double
    var minAscentPerKM: Double
    var maxAscentPerKM: Double
    var trainingCount: Int
    var holdoutCount: Int
    var meanAbsoluteError: Double
    var coverage: Double
    static func fit(_ observations: [EnergyObservation], bikeID: UUID, mode: Int, now: Double) -> Self? {
        var ids: Set<UUID> = []
        let usable = observations.filter {
            $0.bikeID == bikeID && $0.assistMode == mode && now-$0.endedAt >= 0 && now-$0.endedAt <= 180*86400 &&
            $0.rate.isFinite && $0.rate > 0 && $0.ascentPerKM.isFinite && $0.ascentPerKM >= 0 && ids.insert($0.rideID).inserted
        }.sorted { $0.endedAt < $1.endedAt }
        guard usable.count >= 8 else { return nil }
        let holdoutCount = max(3, usable.count/4)
        let training = Array(usable.dropLast(holdoutCount)), holdout = Array(usable.suffix(holdoutCount))
        let rates = training.map(\.rate).sorted(), median = rates[rates.count/2]
        // Observed training envelope plus 20% and quantisation allowance; not a confidence interval.
        let low = max(0.01, rates.first!*0.8-0.1), high = rates.last!*1.2+0.1
        let coverage = Double(holdout.filter { (low...high).contains($0.rate) }.count)/Double(holdout.count)
        let mae = holdout.map { abs($0.rate-median) }.reduce(0,+)/Double(holdout.count)
        guard coverage >= 0.8, mae <= max(0.5, median*0.35) else { return nil }
        return Self(lowerRate: low, upperRate: high, medianRate: median,
            minAscentPerKM: training.map(\.ascentPerKM).min()!, maxAscentPerKM: training.map(\.ascentPerKM).max()!,
            trainingCount: training.count, holdoutCount: holdout.count, meanAbsoluteError: mae, coverage: coverage)
    }
    func remainingPercent(soc: Int, kilometres: Double, ascentPerKM: Double) -> ClosedRange<Double>? {
        guard (0...100).contains(soc), kilometres.isFinite, kilometres >= 0, ascentPerKM.isFinite,
              ascentPerKM >= max(0,minAscentPerKM-5), ascentPerKM <= maxAscentPerKM+5 else { return nil }
        return max(0,Double(soc)-kilometres*upperRate)...max(0,Double(soc)-kilometres*lowerRate)
    }
}
