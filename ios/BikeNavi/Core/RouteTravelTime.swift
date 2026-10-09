import Foundation

/// Shared movement-time estimate for online/offline routes and navigation.
/// Pauses are not predicted; descending never raises the agreed base speeds.
struct RouteTravelTime {
    private struct Leg {
        var distance: Double
        var seconds: Double
    }
    private var legs: [Leg]
    var total: Double { legs.reduce(0) { $0 + $1.seconds } }

    static func speedKPH(surface: SurfaceKind, walking: Bool) -> Double {
        if walking { return 4 }
        switch surface {
        case .paved: return 20
        case .paving: return 16
        case .gravel: return 12
        case .natural, .other: return 8
        case .unknown: return 12
        }
    }

    init(route: CalculatedRoute, profile: RidingProfile) {
        guard route.coordinates.count > 1 else { legs = []; return }
        let lengths = zip(route.coordinates, route.coordinates.dropFirst()).map { $0.distance(to: $1) }
        let geometryDistance = lengths.reduce(0, +)
        let scale = route.distance > 0 && geometryDistance > 0 ? route.distance / geometryDistance : 1
        var surfaces = Array(repeating: SurfaceKind.unknown, count: lengths.count)
        for section in route.coloredSections {
            for index in section.startIndex..<section.endIndex { surfaces[index] = section.kind }
        }
        let elevations = route.coordinates.map(\.altitude)
        let completeElevation = elevations.allSatisfy { $0?.isFinite == true }
        let rises = zip(elevations, elevations.dropFirst()).map { max(0, ($1 ?? 0) - ($0 ?? 0)) }
        let measuredAscent = rises.reduce(0, +)
        let ascent = route.ascent > 0 ? route.ascent : (completeElevation ? measuredAscent : 0)
        legs = lengths.indices.map { index in
            let walking = profile.mode == .hiking || route.walkingStartIndex.map { index >= $0 } == true
            let speed = Self.speedKPH(surface: surfaces[index], walking: walking) / 3.6
            // Distribute the provider's smoothed ascent along known climbs.
            // Without complete elevations, distribute it by distance instead.
            let rise = completeElevation && measuredAscent > 0
                ? ascent * rises[index] / measuredAscent
                : ascent * lengths[index] / max(1, geometryDistance)
            let climbingMetresPerHour = walking ? 300.0 : (profile.electric ? 600.0 : 400.0)
            return Leg(distance: lengths[index], seconds: lengths[index] * scale / speed + rise * 3600 / climbingMetresPerHour)
        }
    }

    /// Progress uses geometric metres, as RouteTracker does. Slow surfaces and
    /// climbs already passed must not slow down the remaining route again.
    func remaining(after traveled: Double) -> Double {
        var passed = max(0, traveled)
        var seconds = 0.0
        for leg in legs {
            guard leg.distance > 0 else { continue }
            let fraction = min(1, passed / leg.distance)
            seconds += leg.seconds * (1 - fraction)
            passed = max(0, passed - leg.distance)
        }
        return seconds
    }
}
