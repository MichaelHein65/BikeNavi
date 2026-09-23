import Foundation

/// Experimental smartphone notification format, separate from Bosch's official LDI.
/// Field IDs: RobbyPee/Bosch-Smart-System-Ebike-Garmin-Android, BLEdata.md.
/// Frames observed on this bike: 0x30, body length, two-byte ID, optional protobuf scalar.
struct BoschSmartphoneData: Equatable {
    var batteryPercent: Int?
    var riderPowerWatts: Int?
    var motorPowerWatts: Int?
    var assistMode: Int?

    enum DecodeError: Error { case malformed, invalidValue }

    static func decode(_ data: Data) throws -> BoschSmartphoneData {
        let bytes = Array(data)
        var offset = 0
        var result = BoschSmartphoneData()
        while offset < bytes.count {
            guard bytes.count - offset >= 4, [0x10, 0x30].contains(bytes[offset]) else { throw DecodeError.malformed }
            let count = Int(bytes[offset + 1])
            guard count >= 2, count <= bytes.count - offset - 2 else { throw DecodeError.malformed }
            let end = offset + count + 2
            let id = UInt16(bytes[offset + 2]) << 8 | UInt16(bytes[offset + 3])
            defer { offset = end }
            // Non-telemetry response envelopes can share one notification with telemetry.
            guard bytes[offset] == 0x30 else { continue }
            guard [0x8088, 0x985b, 0x985d, 0x9809].contains(id) else { continue }
            // An explicitly received empty scalar message means protobuf's default zero.
            // An absent message remains nil; unrelated notifications cannot invent values.
            var raw: UInt64 = 0
            if count > 2 {
                guard count >= 4, bytes[offset + 4] == 0x08 else { throw DecodeError.malformed }
                var cursor = offset + 5
                var complete = false
                for index in 0..<10 {
                    guard cursor < end else { throw DecodeError.malformed }
                    let byte = bytes[cursor]; cursor += 1
                    guard index < 9 || byte <= 1 else { throw DecodeError.malformed }
                    raw |= UInt64(byte & 0x7f) << (index * 7)
                    if byte & 0x80 == 0 { complete = true; break }
                }
                guard complete, cursor == end else { throw DecodeError.malformed }
            }
            let maximum: UInt64 = id == 0x8088 ? 100 : id == 0x9809 ? 255 : 65535
            guard raw <= maximum else { throw DecodeError.invalidValue }
            switch id {
            case 0x8088: result.batteryPercent = Int(raw)
            case 0x985b: result.riderPowerWatts = Int(raw)
            case 0x985d: result.motorPowerWatts = Int(raw)
            case 0x9809: result.assistMode = Int(raw)
            default: break
            }
        }
        return result
    }
}
