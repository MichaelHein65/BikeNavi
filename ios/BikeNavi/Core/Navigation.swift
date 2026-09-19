import Foundation

struct RouteProgress {
    var traveled: Double
    var remaining: Double
    var distanceFromRoute: Double
    var nextManeuver: Maneuver?
    var distanceToManeuver: Double
}

struct RouteTracker {
    private(set) var lastProgress = 0.0
    private(set) var lastTimestamp: Double?

    mutating func update(position: Coordinate, timestamp: Double, route: CalculatedRoute) -> RouteProgress? {
        guard route.coordinates.count > 1 else { return nil }
        let radians = Double.pi / 180
        let scaleX = cos(position.latitude * radians) * 111_320
        let scaleY = 111_320.0
        var cumulative = [0.0]
        for i in 1..<route.coordinates.count {
            cumulative.append(cumulative.last! + route.coordinates[i - 1].distance(to: route.coordinates[i]))
        }
        let elapsed = max(0, timestamp - (lastTimestamp ?? timestamp))
        // A local window avoids jumping to the return leg of a loop. After a long
        // interruption the window grows to permit recovery without fake progress.
        let maximumForward = lastTimestamp == nil ? Double.infinity : max(200, elapsed * 20)
        var best: (distance: Double, progress: Double)?
        for i in 0..<(route.coordinates.count - 1) {
            guard cumulative[i + 1] >= max(0, lastProgress - 150),
                  cumulative[i] <= lastProgress + maximumForward else { continue }
            let a = route.coordinates[i], b = route.coordinates[i + 1]
            let ax = (a.longitude - position.longitude) * scaleX
            let ay = (a.latitude - position.latitude) * scaleY
            let bx = (b.longitude - position.longitude) * scaleX
            let by = (b.latitude - position.latitude) * scaleY
            let dx = bx - ax, dy = by - ay
            let t = min(1, max(0, -(ax * dx + ay * dy) / max(0.0001, dx * dx + dy * dy)))
            let distance = hypot(ax + t * dx, ay + t * dy)
            let progress = cumulative[i] + t * (cumulative[i + 1] - cumulative[i])
            if best == nil || distance < best!.distance - 1 { best = (distance, progress) }
        }
        guard let best else { return nil }
        if best.distance < 60 { lastProgress = best.progress; lastTimestamp = timestamp }
        let next = route.maneuvers.first { m in
            m.coordinateIndex < cumulative.count && cumulative[m.coordinateIndex] > lastProgress + 12
        }
        return RouteProgress(traveled: lastProgress, remaining: max(0, cumulative.last! - lastProgress),
                             distanceFromRoute: best.distance, nextManeuver: next,
                             distanceToManeuver: next.map { max(0, cumulative[$0.coordinateIndex] - lastProgress) } ?? 0)
    }
}

struct NavigationPreviewPoint: Equatable {
    var x: Int
    var y: Int
    var surface: Int
}

struct NavigationPreview: Equatable {
    var points: [NavigationPreviewPoint]
    var currentPointIndex: Int
    var maneuverPointIndex: Int?
    var roads: [NavigationPreviewRoad]
}

struct NavigationPreviewRoad: Equatable {
    var points: [NavigationPreviewRoadPoint]
    var kind: Int
}

struct NavigationPreviewRoadPoint: Equatable {
    var x: Int
    var y: Int
}

/// Produces a compact, direction-up route diagram for glanceable navigation.
/// Coordinates are normalized to a 1,000 × 1,000 drawing area so the result
/// can be sent to a Live Activity without map tiles or network access.
enum NavigationPreviewBuilder {
    static func make(route: CalculatedRoute, progress: RouteProgress,
                     headingDegrees: Double? = nil) -> NavigationPreview? {
        guard route.coordinates.count > 1 else { return nil }
        var cumulative = [0.0]
        for index in 1..<route.coordinates.count {
            cumulative.append(cumulative[index - 1] + route.coordinates[index - 1].distance(to: route.coordinates[index]))
        }
        guard let total = cumulative.last, total > 1 else { return nil }
        let traveled = min(total, max(0, progress.traveled))
        let start = max(0, traveled - 50)
        let end = min(total, traveled + 350)
        guard end - start > 1 else { return nil }

        var distances = (0...24).map { start + (end - start) * Double($0) / 24 }
        distances.append(traveled)
        var maneuverDistance: Double?
        if let index = progress.nextManeuver?.coordinateIndex, cumulative.indices.contains(index) {
            maneuverDistance = cumulative[index]
            if let maneuverDistance, (start...end).contains(maneuverDistance) { distances.append(maneuverDistance) }
        }
        distances.sort()
        distances = distances.reduce(into: []) { values, value in
            if values.last.map({ abs($0 - value) > 0.2 }) ?? true { values.append(value) }
        }

        let anchor = interpolated(at: traveled, coordinates: route.coordinates, cumulative: cumulative).coordinate
        let fallbackHeading = routeHeading(at: traveled, coordinates: route.coordinates, cumulative: cumulative)
        let selectedHeading: Double
        if let headingDegrees, headingDegrees.isFinite, headingDegrees >= 0 { selectedHeading = headingDegrees }
        else { selectedHeading = fallbackHeading }
        let heading = selectedHeading * .pi / 180
        let cosLatitude = cos(anchor.latitude * .pi / 180)
        let sections = route.coloredSections
        let project: (Coordinate) -> (x: Double, y: Double) = { coordinate in
            let east = (coordinate.longitude - anchor.longitude) * cosLatitude * 111_320
            let north = (coordinate.latitude - anchor.latitude) * 111_320
            let across = east * cos(heading) - north * sin(heading)
            let forward = east * sin(heading) + north * cos(heading)
            return (across, -forward)
        }
        var samples: [(x: Double, y: Double, surface: Int)] = []
        for distance in distances {
            let item = interpolated(at: distance, coordinates: route.coordinates, cumulative: cumulative)
            let projected = project(item.coordinate)
            let segment = min(max(0, item.segmentIndex), route.coordinates.count - 2)
            let surface = sections.first(where: { segment >= $0.startIndex && segment < $0.endIndex })?.surface ?? 0
            samples.append((projected.x, projected.y, surface))
        }
        guard !samples.isEmpty else { return nil }
        let minY = samples.map(\.y).min() ?? 0
        let maxY = samples.map(\.y).max() ?? 1
        let maxX = max(1, samples.map { abs($0.x) }.max() ?? 1)
        let scale = min(420 / maxX, 820 / max(1, maxY - minY))
        let points = samples.map {
            NavigationPreviewPoint(
                x: min(950, max(50, Int((500 + $0.x * scale).rounded()))),
                y: min(950, max(50, Int((80 + ($0.y - minY) * scale).rounded()))),
                surface: $0.surface
            )
        }
        let currentIndex = distances.indices.min(by: {
            abs(distances[$0] - traveled) < abs(distances[$1] - traveled)
        }) ?? 0
        let maneuverIndex = maneuverDistance.flatMap { distance -> Int? in
            guard (start...end).contains(distance) else { return nil }
            return distances.indices.min(by: {
                abs(distances[$0] - distance) < abs(distances[$1] - distance)
            })
        }
        let context = progress.nextManeuver.flatMap { maneuver in
            route.intersectionContexts?.first(where: { $0.coordinateIndex == maneuver.coordinateIndex })
        }
        let roads = context?.roads.compactMap { road -> NavigationPreviewRoad? in
            let roadPoints = road.coordinates.map { coordinate -> NavigationPreviewRoadPoint in
                let value = project(coordinate)
                return NavigationPreviewRoadPoint(x: Int((500 + value.x * scale).rounded()),
                                                  y: Int((80 + (value.y - minY) * scale).rounded()))
            }
            return roadPoints.count > 1 ? NavigationPreviewRoad(points: roadPoints, kind: road.kind) : nil
        } ?? []
        return NavigationPreview(points: points, currentPointIndex: currentIndex,
                                 maneuverPointIndex: maneuverIndex, roads: roads)
    }

    private static func interpolated(at distance: Double, coordinates: [Coordinate],
                                     cumulative: [Double]) -> (coordinate: Coordinate, segmentIndex: Int) {
        let value = min(cumulative.last ?? 0, max(0, distance))
        let upper = cumulative.firstIndex(where: { $0 >= value }) ?? cumulative.count - 1
        let lower = max(0, upper - 1)
        guard upper != lower else { return (coordinates[lower], lower) }
        let length = max(0.001, cumulative[upper] - cumulative[lower])
        let fraction = (value - cumulative[lower]) / length
        let a = coordinates[lower], b = coordinates[upper]
        return (Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                           longitude: a.longitude + (b.longitude - a.longitude) * fraction,
                           altitude: nil), lower)
    }

    private static func routeHeading(at distance: Double, coordinates: [Coordinate], cumulative: [Double]) -> Double {
        let before = interpolated(at: max(0, distance - 8), coordinates: coordinates, cumulative: cumulative).coordinate
        let after = interpolated(at: min(cumulative.last ?? distance, distance + 8), coordinates: coordinates, cumulative: cumulative).coordinate
        let east = (after.longitude - before.longitude) * cos(before.latitude * .pi / 180)
        let north = after.latitude - before.latitude
        return atan2(east, north) * 180 / .pi
    }
}

/// Avoid reacting to ordinary GPS drift or a brief detour. A new route is
/// requested only after the rider has been at least 80 m away for 10 seconds;
/// requests are then limited to one every 90 seconds.
struct ReroutePolicy {
    private(set) var offRouteSince: Double?
    private(set) var lastRerouteAt: Double?
    static let deviation = 80.0
    static let confirmationDuration = 10.0
    static let cooldown = 90.0

    mutating func observe(distanceFromRoute: Double, timestamp: Double) -> Bool {
        guard distanceFromRoute.isFinite, timestamp.isFinite else { return false }
        guard distanceFromRoute >= Self.deviation else {
            offRouteSince = nil
            return false
        }
        if offRouteSince == nil { offRouteSince = timestamp }
        guard timestamp - (offRouteSince ?? timestamp) >= Self.confirmationDuration,
              timestamp - (lastRerouteAt ?? -.infinity) >= Self.cooldown else { return false }
        lastRerouteAt = timestamp
        offRouteSince = nil
        return true
    }
}

enum TrackFilter {
    static func accepts(_ point: TrackPoint, after previous: TrackPoint?, now: Double) -> Bool {
        guard point.accuracy >= 0, point.accuracy <= 50,
              abs(now - point.timestamp) < 15,
              (-90...90).contains(point.coordinate.latitude),
              (-180...180).contains(point.coordinate.longitude) else { return false }
        guard let previous, previous.segment == point.segment else { return true }
        let elapsed = point.timestamp - previous.timestamp
        guard elapsed >= 3 else { return false }
        let distance = previous.coordinate.distance(to: point.coordinate)
        // Avoid impossible GPS jumps while leaving ordinary cycling speeds intact.
        return distance / elapsed < 35 && (distance >= 3 || elapsed >= 20)
    }
}
