import Foundation

struct RouteElevationSample: Codable, Equatable {
    var distance: Double
    var altitude: Double
}

struct ElevationResponse: Decodable {
    var altitudes: [Double]
    var source: String
}

/// Samples follow the existing route by travelled distance, including long edges.
/// The routing geometry and all maneuver/surface indices remain unchanged.
enum RouteElevation {
    struct Request: Encodable { var coordinates: [Coordinate] }
    struct Sampling {
        var coordinates: [Coordinate]
        var distances: [Double]
    }
    enum Failure: Error { case invalidGeometry, invalidResponse }

    static func sample(_ route: CalculatedRoute) throws -> Sampling {
        guard route.coordinates.count >= 2,
              route.coordinates.allSatisfy({ $0.latitude.isFinite && $0.longitude.isFinite
                  && (-90...90).contains($0.latitude) && (-180...180).contains($0.longitude) }) else {
            throw Failure.invalidGeometry
        }
        let cumulative = LocalRouteMetrics.distances(route)
        guard let length = cumulative.last, length.isFinite, length > 0 else { throw Failure.invalidGeometry }
        // Approximately 30 m, at most 2,000 vertices (provider limit).
        let intervals = Int(min(1999, max(1, ceil(length / 30))))
        var result = Sampling(coordinates: [], distances: [])
        var edge = 0
        for i in 0...intervals {
            let distance = length * Double(i) / Double(intervals)
            while edge < cumulative.count - 2 && cumulative[edge + 1] <= distance { edge += 1 }
            let a = route.coordinates[edge], b = route.coordinates[edge + 1]
            let t = min(1, max(0, (distance - cumulative[edge]) / max(0.000001, cumulative[edge + 1] - cumulative[edge])))
            result.coordinates.append(Coordinate(latitude: a.latitude + (b.latitude-a.latitude)*t,
                                                  longitude: a.longitude + (b.longitude-a.longitude)*t))
            result.distances.append(distance)
        }
        return result
    }

    static func applying(_ response: ElevationResponse, sampling: Sampling, to route: CalculatedRoute) throws -> CalculatedRoute {
        let expected = try sample(route)
        guard sampling.coordinates == expected.coordinates,
              response.altitudes.count == sampling.distances.count, response.altitudes.count >= 2,
              response.altitudes.allSatisfy({ $0.isFinite && (-500...9000).contains($0) }),
              !response.source.isEmpty, response.source.count <= 200,
              sampling.distances == expected.distances else { throw Failure.invalidResponse }
        // Three-sample smoothing suppresses DEM raster noise; keep endpoints.
        let raw = response.altitudes
        let heights = raw.indices.map { i in
            i == 0 || i == raw.count-1 ? raw[i] : (raw[i-1] + raw[i] + raw[i+1]) / 3
        }
        let profile = zip(sampling.distances, heights).map { RouteElevationSample(distance: $0, altitude: $1) }
        var result = route
        result.elevationProfile = profile
        result.elevationSource = response.source
        let totals = totals(profile)
        result.ascent = totals.ascent
        result.descent = totals.descent
        // Keep heights at original vertices for GPX export without changing indices.
        let distances = LocalRouteMetrics.distances(route)
        var index = 0
        for i in result.coordinates.indices {
            while index < profile.count-2 && profile[index+1].distance < distances[i] { index += 1 }
            let a = profile[index], b = profile[index+1]
            let t = min(1, max(0, (distances[i]-a.distance) / (b.distance-a.distance)))
            result.coordinates[i].altitude = a.altitude + (b.altitude-a.altitude)*t
        }
        result.warnings.removeAll { $0 == "Höhenwerte und Fahrzeit sind lokal nur eingeschränkt verfügbar." }
        return result
    }

    static func totals(_ samples: [RouteElevationSample]) -> (ascent: Double, descent: Double) {
        guard let first = samples.first else { return (0, 0) }
        var anchor = first.altitude, ascent = 0.0, descent = 0.0
        for (i, point) in samples.enumerated().dropFirst() {
            let delta = point.altitude - anchor
            // Accumulate gradual slopes, ignore fluctuations below 3 m.
            if abs(delta) >= 3 || i == samples.count-1 {
                ascent += max(0, delta); descent += max(0, -delta)
                anchor = point.altitude
            }
        }
        return (ascent, descent)
    }
}

extension CalculatedRoute {
    var hasElevation: Bool {
        coordinates.count >= 2 && coordinates.allSatisfy { point in
            point.altitude.map { $0.isFinite && (-500...9000).contains($0) } ?? false
        }
    }
    var elevationSamples: [RouteElevationSample] {
        guard hasElevation else { return [] }
        if let elevationProfile { return elevationProfile }
        let distances = LocalRouteMetrics.distances(self)
        return coordinates.enumerated().compactMap { i, point in
            point.altitude.map { RouteElevationSample(distance: distances[i], altitude: $0) }
        }
    }
    var elevationDescription: String {
        if let elevationSource {
            return "Geländehöhen: \(elevationSource). Geglättete Schätzwerte; Brücken und Tunnel können abweichen. Fahrzeit grob geschätzt."
        }
        return hasElevation ? "Höhen und Fahrzeit sind Schätzwerte aus den verfügbaren Kartendaten."
            : "Für diese Route sind noch keine Höhendaten gespeichert. Zum Laden wird eine Verbindung zum Pi benötigt."
    }
}
