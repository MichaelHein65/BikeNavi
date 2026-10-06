import Foundation

/// WGS84 latitude/longitude input. Never guesses between distinct valid interpretations.
enum CoordinateParser {
    enum Result: Equatable {
        case coordinate(Coordinate)
        case invalid
        case ambiguous
        case notCoordinate
    }

    static func parse(_ input: String) -> Result {
        var text = input.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .notCoordinate }
        // A lone number can be a postal code and must still reach normal place search.
        if text.allSatisfy({ $0.isNumber }) { return .notCoordinate }
        guard text.count <= 512 else { return .notCoordinate }
        for (old, new) in [("−", "-"), ("–", "-"), ("º", "°"), ("′", "'"),
                           ("’", "'"), ("‘", "'"), ("″", "\""), ("“", "\""), ("”", "\""),
                           ("\u{00a0}", " "), ("\u{202f}", " "), ("\u{200b}", "")] {
            text = text.replacingOccurrences(of: old, with: new)
        }
        let explicit = text.hasPrefix("GEO:")
        if explicit { text = String(text.dropFirst(4)) }
        if text.hasPrefix("("), text.hasSuffix(")") { text = String(text.dropFirst().dropLast()) }
        let allowed = CharacterSet(charactersIn: "0123456789+−-.,;:/|°'\"NSEWO ").union(.whitespacesAndNewlines)
        guard text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return explicit ? .invalid : .notCoordinate
        }
        guard text.contains(where: { $0.isNumber }) else { return .notCoordinate }
        var candidates = [Coordinate]()
        var bestComponentCount = Int.max
        // A boundary can be punctuation, whitespace, or directly beside a hemisphere.
        for index in text.indices.dropFirst() {
            let before = text[text.index(before: index)]
            let after = text[index]
            let separators = ",;/|"
            let directions = "NSEWO"
            guard before.isWhitespace || after.isWhitespace || separators.contains(before)
                    || separators.contains(after) || directions.contains(before) || directions.contains(after) else { continue }
            let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;/|"))
            let left = String(text[..<index]).trimmingCharacters(in: trim)
            let right = String(text[index...]).trimmingCharacters(in: trim)
            guard let a = component(left), let b = component(right) else { continue }
            let reversed = a.axis == .longitude || b.axis == .latitude
            let lat = reversed ? b : a
            let lon = reversed ? a : b
            guard lat.axis != .longitude, lon.axis != .latitude,
                  abs(lat.value) <= 90, abs(lon.value) <= 180 else { continue }
            // Prefer two plain decimal values over interpreting their digits as bare minutes.
            let componentCount = a.count + b.count
            guard componentCount <= bestComponentCount else { continue }
            if componentCount < bestComponentCount { candidates = []; bestComponentCount = componentCount }
            let coordinate = Coordinate(latitude: lat.value, longitude: lon.value)
            if !candidates.contains(where: { abs($0.latitude - coordinate.latitude) < 1e-10 && abs($0.longitude - coordinate.longitude) < 1e-10 }) {
                candidates.append(coordinate)
            }
        }
        if candidates.count > 1 { return .ambiguous }
        if let coordinate = candidates.first { return .coordinate(coordinate) }
        return .invalid
    }

    private enum Axis { case latitude, longitude }
    private struct Component { var value: Double; var axis: Axis?; var count: Int }

    private static func component(_ input: String) -> Component? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let directions = "NSEWO"
        var hemisphere: Character?
        if let first = text.first, directions.contains(first) {
            hemisphere = first; text.removeFirst()
        } else if let last = text.last, directions.contains(last) {
            hemisphere = last; text.removeLast()
        }
        // Decimal punctuation may be surrounded by copied spaces; other spaces separate D/M/S.
        text = text.replacingOccurrences(of: #"\s*([.,])\s*"#, with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = #"[0-9]+(?:[.,][0-9]+)?"#
        let pattern = "^([+-]?" + number + #")(?:\s*[°:]\s*|\s+)("# + number + #")(?:\s*[':]\s*|\s+)("# + number + #")\s*"?$"#
        let minutesPattern = "^([+-]?" + number + #")(?:\s*[°:]\s*|\s+)("# + number + #")\s*'?$"#
        let degreesPattern = "^([+-]?" + number + #")\s*°?$"#
        let matches = [pattern, minutesPattern, degreesPattern].compactMap { pattern -> NSTextCheckingResult? in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        }
        guard let match = matches.first else { return nil }
        var parts = [Double]()
        for i in 1..<match.numberOfRanges {
            if let range = Range(match.range(at: i), in: text),
               let value = Double(text[range].replacingOccurrences(of: ",", with: ".")) { parts.append(value) }
        }
        guard let degrees = parts.first else { return nil }
        // Fractions are only valid on the last component, minutes/seconds must be below 60.
        guard parts.dropFirst().allSatisfy({ $0 >= 0 && $0 < 60 }),
              parts.dropLast().allSatisfy({ $0.rounded(.towardZero) == $0 }) else { return nil }
        let negative = text.hasPrefix("-")
        if let hemisphere {
            if negative && !"SW".contains(hemisphere) { return nil }
            if text.hasPrefix("+") && "SW".contains(hemisphere) { return nil }
        }
        let sign = negative || hemisphere.map({ "SW".contains($0) }) == true ? -1.0 : 1.0
        let value = sign * (abs(degrees) + (parts.count > 1 ? parts[1] / 60 : 0) + (parts.count > 2 ? parts[2] / 3600 : 0))
        return Component(value: value, axis: hemisphere.map { "NS".contains($0) ? .latitude : .longitude }, count: parts.count)
    }
}
