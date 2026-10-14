import Foundation

struct MarineLeg: Equatable, Identifiable {
    let id: Int
    let start: Waypoint
    let end: Waypoint
    let course: Double
    let distance: Double
}

enum MarineNavigation {
    static let routingRevision = 2
    static let outdatedRouteWarning = "Dieser Seeweg wurde ohne die aktuelle Prüfung kartierter Gefahrenstellen berechnet. Vor der Verwendung neu berechnen."
    static func current(_ route: CalculatedRoute?) -> Bool {
        route?.marineRoutingRevision == routingRevision
    }

    static let depthWarning = "EMODnet · nicht zur Navigation geeignet. Grobe Rastertiefen; keine Prüfung von Wasserstand, Hindernissen oder aktueller Befahrbarkeit."
    static let warning = "Wasserweg anhand erfasster OSM-Küsten; erfasste Fahrwasser und empfohlene Kurse werden leicht bevorzugt. Fährlinien erhalten keinen Vorteil. Strömung, Sperrungen und nautische Eignung werden nicht geprüft. Amtliche Seekarten und aktuelle Hinweise prüfen."
    enum Failure: LocalizedError {
        case points, server
        var errorDescription: String? { self == .server ? "Für die Seeweg-Berechnung wird der Pi mit Küsten- und Seewegdaten benötigt. Es wird keine ungeprüfte Direktverbindung verwendet." : "Wähle 2 bis 50 verschiedene Wegpunkte zwischen 85° Süd und 85° Nord für die Kursplanung." }
    }
    static func valid(_ point: Coordinate) -> Bool {
        point.latitude.isFinite && point.longitude.isFinite && abs(point.latitude) <= 85 && abs(point.longitude) <= 180
    }
    /// A straight line on a Mercator chart is a rhumb line with a constant true course.
    static func leg(from a: Waypoint, to b: Waypoint, index: Int = 0) -> MarineLeg {
        let radians = Double.pi / 180
        let p1 = a.coordinate.latitude * radians, p2 = b.coordinate.latitude * radians
        let dp = p2 - p1
        let dl = (b.coordinate.longitude - a.coordinate.longitude) * radians
        let longitude = atan2(sin(dl), cos(dl))
        let psi = log(tan(.pi / 4 + p2 / 2) / tan(.pi / 4 + p1 / 2))
        let q = abs(psi) > 1e-12 ? dp / psi : cos(p1)
        let course = (atan2(longitude, psi) / radians + 360).truncatingRemainder(dividingBy: 360)
        return MarineLeg(id: index, start: a, end: b, course: course,
                         distance: 6_371_000 * hypot(dp, q * longitude))
    }
    static func legs(_ points: [Waypoint]) -> [MarineLeg] {
        guard points.count >= 2, points.allSatisfy({ valid($0.coordinate) }) else { return [] }
        return (1..<points.count).map { leg(from: points[$0-1], to: points[$0], index: $0) }
    }
    static func navigationPoints(_ document: TourDocument) -> [Waypoint] {
        guard document.profile.mode == .sea else { return [] }
        return navigationPoints(waypoints: document.waypoints, route: document.route)
    }
    static func navigationPoints(waypoints: [Waypoint], route: CalculatedRoute?) -> [Waypoint] {
        guard let route, route.provider == "Seeweg · OSM-Wasserwege", route.coordinates.allSatisfy(valid) else { return [] }
        let names = Dictionary(zip(route.waypointIndices ?? [], waypoints.map(\.name)), uniquingKeysWith: { first, _ in first })
        return route.coordinates.enumerated().map { Waypoint(name: names[$0.offset] ?? "Kurswechsel \($0.offset+1)", coordinate: $0.element) }
    }
    static func nextWaypoint(current: Int, points: [Waypoint], position: Coordinate, accuracy: Double,
                             timestamp: Double, now: Double) -> Int {
        guard points.indices.contains(current), valid(position), accuracy.isFinite, (0...25).contains(accuracy),
              now - timestamp >= -1, now - timestamp <= 5 else { return current }
        // Only the current target can be reached; distant intermediate points are never skipped.
        return position.distance(to: points[current].coordinate) <= 30 ? current + 1 : current
    }
    static func remainingDistance(points: [Waypoint], target: Int, position: Coordinate) -> Double? {
        guard !points.isEmpty, target >= 1, target <= points.count, valid(position) else { return nil }
        if target == points.count { return 0 }
        let start = points[target-1].coordinate, end = points[target].coordinate
        // ETA only near the current leg, never across a large deviation or by skipping a waypoint.
        let radians = Double.pi / 180
        func project(_ c: Coordinate) -> (Double, Double) {
            (c.longitude * radians * cos(position.latitude * radians) * 6_371_000,
             log(tan(Double.pi / 4 + c.latitude * radians / 2)) * cos(position.latitude * radians) * 6_371_000)
        }
        let a = project(start), b = project(end), p = project(position)
        let dx = b.0-a.0, dy = b.1-a.1
        let t = min(1, max(0, ((p.0-a.0)*dx+(p.1-a.1)*dy)/max(0.0001, dx*dx+dy*dy)))
        guard hypot(p.0-a.0-t*dx, p.1-a.1-t*dy) <= 100 else { return nil }
        let toTarget = leg(from: Waypoint(name: "GPS", coordinate: position), to: points[target]).distance
        return toTarget + legs(Array(points[target...])).reduce(0) { $0 + $1.distance }
    }
    static func setting(_ value: Double, range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite && range.contains(value) ? value : fallback
    }
    static func travelTime(distance: Double, speedKnots: Double) -> Double? {
        guard distance.isFinite, distance >= 0, speedKnots.isFinite, (0.5...50).contains(speedKnots) else { return nil }
        return distance / (speedKnots * 1852 / 3600)
    }
    static func cog(course: Double?, speed: Double?, timestamp: Double?, accuracy: Double?, now: Double) -> Double? {
        guard let course, let speed, let timestamp, let accuracy, course.isFinite, (0..<360).contains(course),
              speed.isFinite, speed >= 0.5, accuracy.isFinite, (0...50).contains(accuracy),
              now - timestamp >= -1, now - timestamp <= 5 else { return nil }
        return course
    }
    static func course(_ value: Double) -> String {
        String(format: "%03.0f°", value.rounded().truncatingRemainder(dividingBy: 360))
    }
    static func distance(_ metres: Double) -> String {
        (metres / 1852).formatted(.number.precision(.fractionLength(metres < 18.52 ? 3 : metres < 1852 ? 2 : 1)).locale(Locale(identifier: "de_DE"))) + " sm"
    }
    static func speed(_ metresPerSecond: Double) -> String { number(metresPerSecond * 3600 / 1852) + " kn" }
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE")))
    }
    static func position(_ point: Coordinate) -> String {
        func component(_ value: Double, positive: String, negative: String) -> String {
            let totalMinutes = (abs(value) * 6000).rounded() / 100
            let degrees = Int(totalMinutes / 60), minutes = totalMinutes - Double(degrees * 60)
            let text = (minutes < 10 ? "0" : "") + String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), minutes)
            return "\(degrees)° \(text)′ \(value >= 0 ? positive : negative)"
        }
        return component(point.latitude, positive: "N", negative: "S") + "   " + component(point.longitude, positive: "E", negative: "W")
    }
}
