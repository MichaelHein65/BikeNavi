import Foundation

/// Bosch LDI V1.0, 2026-05-01. Only documented fields; absent fields are not zero.
struct BoschLiveData: Equatable {
    var batteryPercent: Int?
    var riderPowerWatts: Int?
    var cadenceRPM: Int?
    var speedKPH: Double?
    var chargerConnected: Bool?

    enum DecodeError: Error { case malformed, invalidValue }

    static func decode(_ data: Data) throws -> BoschLiveData {
        let bytes = Array(data)
        var offset = 0
        func varint() throws -> UInt64 {
            var result: UInt64 = 0
            for index in 0..<10 {
                guard offset < bytes.count else { throw DecodeError.malformed }
                let byte = bytes[offset]; offset += 1
                guard index < 9 || byte <= 1 else { throw DecodeError.malformed }
                result |= UInt64(byte & 0x7f) << (index * 7)
                if byte & 0x80 == 0 { return result }
            }
            throw DecodeError.malformed
        }
        func skip(_ count: Int) throws {
            guard count >= 0, count <= bytes.count - offset else { throw DecodeError.malformed }
            offset += count
        }
        var value = BoschLiveData()
        while offset < bytes.count {
            let tag = try varint(), field = tag >> 3, wire = tag & 7
            guard field > 0, field <= 0x1fffffff else { throw DecodeError.malformed }
            if [1, 2, 5, 10, 22].contains(field), wire != 0 { throw DecodeError.malformed }
            switch wire {
            case 0:
                let raw = try varint()
                switch field {
                case 1:
                    guard raw <= 65535 else { throw DecodeError.invalidValue }
                    value.speedKPH = Double(raw) / 100
                case 2:
                    let signed = Int32(truncatingIfNeeded: raw)
                    guard (-32768...32767).contains(signed) else { throw DecodeError.invalidValue }
                    // A negative cadence sentinel is unavailable, not pedaling backwards.
                    value.cadenceRPM = signed >= 0 ? Int(signed) : nil
                case 5:
                    guard raw <= 65535 else { throw DecodeError.invalidValue }
                    value.riderPowerWatts = Int(raw)
                case 10:
                    guard raw <= 100 else { throw DecodeError.invalidValue }
                    value.batteryPercent = Int(raw)
                case 22: value.chargerConnected = raw != 0
                default: break
                }
            case 1: try skip(8)
            case 2:
                let length = try varint()
                guard length <= UInt64(bytes.count - offset) else { throw DecodeError.malformed }
                try skip(Int(length))
            case 5: try skip(4)
            default: throw DecodeError.malformed
            }
        }
        return value
    }
}
