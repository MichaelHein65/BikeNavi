import Foundation

struct RideModeSection: Equatable {
    var coordinates: [Coordinate]
    var mode: Int?
}

struct RideElevationPoint: Identifiable {
    var id: Int
    var distanceKM: Double
    var altitude: Double
    var run: Int
}

struct RidePowerPoint: Identifiable {
    var id: Int
    var distanceKM: Double
    var watts: Int
    var source: String
    var run: Int
}

/// Reconstructs the recorded ride without bridging pauses or inventing missing readings.
enum RideHistory {
    static func elevations(_ track: [TrackPoint]) -> [RideElevationPoint] {
        var distance = 0.0
        var run = 0
        var result: [RideElevationPoint] = []
        for (index, point) in track.enumerated() {
            if index > 0 {
                let previous = track[index - 1]
                if previous.segment == point.segment { distance += previous.coordinate.distance(to: point.coordinate) }
                else { run += 1 }
            }
            guard let altitude = point.coordinate.altitude, altitude.isFinite else { run += 1; continue }
            result.append(.init(id: index, distanceKM: distance / 1000, altitude: altitude, run: run))
        }
        return result
    }

    static func powers(_ samples: [RecordedBikeSample], track: [TrackPoint]) -> [RidePowerPoint] {
        // Use the same cumulative GPS distance as the recorded elevation profile.
        // Match only within a recording segment; never infer distance across a pause.
        var distance = 0.0
        var positions: [Int: [(time: Double, distanceKM: Double)]] = [:]
        for (index, point) in track.enumerated() {
            if index > 0, track[index - 1].segment == point.segment {
                distance += track[index - 1].coordinate.distance(to: point.coordinate)
            }
            positions[point.segment, default: []].append((point.timestamp, distance / 1000))
        }
        func distanceKM(for sample: RecordedBikeSample) -> Double? {
            guard let points = positions[sample.segment], let first = points.first, let last = points.last else { return nil }
            let time = sample.measurement.timestamp
            guard time >= first.time, time <= last.time else { return nil }
            var low = 0
            var high = points.count
            while low < high {
                let middle = (low + high) / 2
                if points[middle].time < time { low = middle + 1 } else { high = middle }
            }
            let next = points[low]
            if next.time == time || low == 0 { return next.distanceKM }
            let previous = points[low - 1]
            let fraction = (time - previous.time) / (next.time - previous.time)
            return previous.distanceKM + fraction * (next.distanceKM - previous.distanceKM)
        }
        let sorted = samples.sorted { $0.measurement.timestamp < $1.measurement.timestamp }
        var result: [RidePowerPoint] = []
        for source in ["Fahrer", "Motor"] {
            var previous: RecordedBikeSample?
            var run = 0
            for sample in sorted {
                let measurement = sample.measurement
                guard let watts = source == "Fahrer" ? measurement.riderPowerWatts : measurement.motorPowerWatts else { continue }
                guard let distanceKM = distanceKM(for: sample) else {
                    run += 1
                    previous = nil
                    continue
                }
                if let previous, previous.segment != sample.segment || measurement.timestamp - previous.measurement.timestamp > 15 { run += 1 }
                result.append(.init(id: result.count, distanceKM: distanceKM,
                                    watts: watts, source: source, run: run))
                previous = sample
            }
        }
        return result
    }

    static func modeSections(track: [TrackPoint], samples: [RecordedBikeSample]) -> [RideModeSection] {
        let modes = Dictionary(grouping: samples.filter { $0.measurement.assistMode != nil }, by: \.segment)
        var result: [RideModeSection] = []
        for segment in Dictionary(grouping: track, by: \.segment).keys.sorted() {
            let points = track.filter { $0.segment == segment }.sorted { $0.timestamp < $1.timestamp }
            let readings = (modes[segment] ?? []).sorted { $0.measurement.timestamp < $1.measurement.timestamp }
            var cursor = 0
            var last: RecordedBikeSample?
            var section: RideModeSection?
            for (a, b) in zip(points, points.dropFirst()) {
                guard b.timestamp > a.timestamp else { continue }
                while cursor < readings.count && readings[cursor].measurement.timestamp <= a.timestamp {
                    last = readings[cursor]; cursor += 1
                }
                var time = a.timestamp
                func coordinate(_ time: Double) -> Coordinate {
                    let fraction = (time - a.timestamp) / (b.timestamp - a.timestamp)
                    return Coordinate(latitude: a.coordinate.latitude + fraction * (b.coordinate.latitude - a.coordinate.latitude),
                                      longitude: a.coordinate.longitude + fraction * (b.coordinate.longitude - a.coordinate.longitude))
                }
                while time < b.timestamp {
                    let nextReading = cursor < readings.count ? readings[cursor].measurement.timestamp : Double.infinity
                    let expiry = last.map { $0.measurement.timestamp + 15 } ?? -Double.infinity
                    let end = min(b.timestamp, nextReading, expiry > time ? expiry : Double.infinity)
                    let mode = expiry > time ? last?.measurement.assistMode : nil
                    if section?.mode == mode, section != nil {
                        section?.coordinates.append(coordinate(end))
                    } else {
                        if let section { result.append(section) }
                        section = RideModeSection(coordinates: [coordinate(time), coordinate(end)], mode: mode)
                    }
                    time = end
                    if nextReading == time { last = readings[cursor]; cursor += 1 }
                }
            }
            if let section { result.append(section) }
        }
        return result
    }
}
