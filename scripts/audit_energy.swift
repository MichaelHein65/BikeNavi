// Compile with Core/*.swift and -lsqlite3. Input is a private local export; output has no coordinates/IDs.
import Foundation
@main enum AuditEnergy {
    struct Input: Decodable { var rides: [TourDocument]; var samples: [RecordedBikeSample] }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Aufruf: audit-energy private-source.json") }
        let input = try JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let grouped = Dictionary(grouping: input.samples, by: \.rideID)
        let audits = input.rides.map { EnergyAudit.inspect(ride: $0, samples: grouped[$0.id] ?? []) }
        let reasons = Dictionary(grouping: audits, by: \.reason).mapValues(\.count)
        let observations = audits.compactMap(\.observation)
        let modes = Set(observations.map { "\($0.bikeID)/\($0.assistMode)" })
        var valid = 0
        for group in modes {
            let relevant = observations.filter { "\($0.bikeID)/\($0.assistMode)" == group }
            if let first = relevant.first, EnergyCalibration.fit(relevant, bikeID: first.bikeID, mode: first.assistMode, now: Date().timeIntervalSince1970) != nil { valid += 1 }
        }
        let output: [String: Any] = ["rides": input.rides.count, "packets": input.samples.count,
            "batteryPackets": input.samples.filter { $0.measurement.batteryPercent != nil }.count,
            "eligible": observations.count, "validatedGroups": valid, "reasons": reasons,
            "capacityWhAvailable": false, "energyCounterAvailable": false]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
