import Foundation

/// Open Location Code (WGS84), including short codes resolved near an explicit locality.
/// Specification: https://github.com/google/open-location-code/blob/main/Documentation/Specification/specification.md
struct PlusCode: Equatable {
    private static let alphabet = Array("23456789CFGHJMPQRVWX")
    let code: String
    let locality: String
    let missing: Int
    var isShort: Bool { missing > 0 }

    init?(_ input: String) {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s*\+\s*"#, with: "+", options: .regularExpression)
        let pieces = normalized.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let first = pieces.first else { return nil }
        let code = first.uppercased()
        let halves = code.split(separator: "+", omittingEmptySubsequences: false)
        guard halves.count == 2, [0, 2, 4, 6, 8].contains(halves[0].count),
              halves[1].count != 1, halves[1].count <= 7 else { return nil }
        let digits = Array(halves.joined())
        guard digits.allSatisfy({ Self.alphabet.contains($0) || $0 == "0" }) else { return nil }
        if let padding = digits.firstIndex(of: "0") {
            guard halves[0].count == 8, halves[1].isEmpty, padding >= 2, padding.isMultiple(of: 2),
                  digits[padding...].allSatisfy({ $0 == "0" }) else { return nil }
        } else {
            guard digits.count >= 2 else { return nil }
        }
        if halves[0].count == 8 {
            guard let lat = Self.alphabet.firstIndex(of: digits[0]), lat < 9,
                  let lon = Self.alphabet.firstIndex(of: digits[1]), lon < 18 else { return nil }
        }
        self.code = code
        locality = pieces.count > 1 ? String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        missing = 8 - halves[0].count
    }

    func coordinate(near reference: Coordinate? = nil) -> Coordinate? {
        var complete = code
        var resolution = 0.0
        if isShort {
            guard let reference, reference.latitude.isFinite, reference.longitude.isFinite,
                  abs(reference.latitude) <= 90, abs(reference.longitude) <= 180 else { return nil }
            var lat = min(reference.latitude, 90 - 1e-10) + 90
            var lon = (reference.longitude == 180 ? -180 : reference.longitude) + 180
            var prefix = ""
            var place = 20.0
            for _ in 0..<(missing / 2) {
                let latDigit = min(19, Int(floor(lat / place)))
                let lonDigit = min(19, Int(floor(lon / place)))
                prefix.append(Self.alphabet[latDigit]); prefix.append(Self.alphabet[lonDigit])
                lat -= Double(latDigit) * place; lon -= Double(lonDigit) * place
                place /= 20
            }
            complete = prefix + code
            resolution = pow(20, 2 - Double(missing) / 2)
        }
        let digits = complete.filter { $0 != "+" && $0 != "0" }.compactMap { Self.alphabet.firstIndex(of: $0) }
        var lat = -90.0, lon = -180.0, latSize = 20.0, lonSize = 20.0
        let pairs = min(digits.count, 10)
        for index in stride(from: 0, to: pairs, by: 2) {
            if index > 0 { latSize /= 20; lonSize /= 20 }
            lat += Double(digits[index]) * latSize
            lon += Double(digits[index + 1]) * lonSize
        }
        for digit in digits.dropFirst(10) {
            latSize /= 5; lonSize /= 4
            lat += Double(digit / 4) * latSize; lon += Double(digit % 4) * lonSize
        }
        lat += latSize / 2; lon += lonSize / 2
        if isShort, let reference {
            if lat - reference.latitude > resolution / 2, lat - resolution >= -90 { lat -= resolution }
            else if reference.latitude - lat > resolution / 2, lat + resolution <= 90 { lat += resolution }
            let refLon = reference.longitude == 180 ? -180 : reference.longitude
            if lon - refLon > resolution / 2 { lon -= resolution }
            else if refLon - lon > resolution / 2 { lon += resolution }
        }
        if lon < -180 { lon += 360 }
        if lon >= 180 { lon -= 360 }
        return Coordinate(latitude: lat, longitude: lon)
    }

    /// Return every locality candidate for selection rather than silently picking the first town.
    func places(search: (String) async throws -> [Waypoint]) async throws -> [Waypoint] {
        if !isShort, let coordinate = coordinate() { return [Waypoint(name: code, coordinate: coordinate)] }
        guard !locality.isEmpty else { return [] }
        return try await search(locality).compactMap { place in
            guard let coordinate = coordinate(near: place.coordinate) else { return nil }
            return Waypoint(name: "\(code) · \(place.name)", coordinate: coordinate)
        }
    }
}
