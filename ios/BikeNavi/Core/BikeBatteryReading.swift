import Foundation

struct BikeBatteryReading: Codable, Equatable {
    let bikeID: UUID
    let percent: Int
    let sampledAt: Date

    func isValid(for id: UUID, now: Date = Date()) -> Bool {
        bikeID == id && (0...100).contains(percent) && sampledAt.timeIntervalSince1970 > 0 && sampledAt <= now
    }

    /// One-time migration of genuine measurements already recorded by the early prototype.
    /// Only packets within an explicitly identified connection belong to that bike.
    static func recover(from logs: [Data], for bikeID: UUID, now: Date = Date()) -> BikeBatteryReading? {
        var connectedBike: UUID?
        var latest: BikeBatteryReading?
        for log in logs {
            for line in log.split(separator: 0x0a) {
                guard let item = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let event = item["event"] as? String else { continue }
                if ["start", "stopped", "disconnected"].contains(event) { connectedBike = nil }
                if event == "connecting" || event == "connected" {
                    connectedBike = (item["id"] as? String).flatMap(UUID.init(uuidString:))
                }
                guard connectedBike == bikeID, let timestamp = item["timestamp"] as? Double,
                      let hex = item["hex"] as? String, hex.count <= 4096, hex.count.isMultiple(of: 2) else { continue }
                var bytes: [UInt8] = []
                var index = hex.startIndex
                while index < hex.endIndex {
                    let end = hex.index(index, offsetBy: 2)
                    guard let byte = UInt8(hex[index..<end], radix: 16) else { break }
                    bytes.append(byte); index = end
                }
                guard bytes.count * 2 == hex.count else { continue }
                let percent: Int?
                if event == "smartphone_data", (item["uuid"] as? String)?.lowercased() == "00000011-eaa2-11e9-81b4-2a2ae2dbcce4" {
                    percent = try? BoschSmartphoneData.decode(Data(bytes)).batteryPercent
                } else if event == "live_data" {
                    percent = try? BoschLiveData.decode(Data(bytes)).batteryPercent
                } else { continue }
                guard let percent else { continue }
                let sample = BikeBatteryReading(bikeID: bikeID, percent: percent, sampledAt: Date(timeIntervalSince1970: timestamp))
                if sample.isValid(for: bikeID, now: now), latest == nil || sample.sampledAt > latest!.sampledAt { latest = sample }
            }
        }
        return latest
    }
}
