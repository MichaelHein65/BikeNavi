import Foundation

struct Coordinate: Codable, Equatable, Hashable {
    var latitude: Double
    var longitude: Double
    var altitude: Double?

    func distance(to other: Coordinate) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((other.latitude - latitude) * r / 2), 2)
            + cos(latitude * r) * cos(other.latitude * r)
            * pow(sin((other.longitude - longitude) * r / 2), 2)
        return 6_371_000 * 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }
}

struct Waypoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var coordinate: Coordinate

    var needsPlaceName: Bool {
        ["", "Kartenpunkt", "Mein Standort"].contains(name.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var tourTitleName: String {
        shortTourTitleName(savedPlaces: [])
    }

    func shortTourTitleName(savedPlaces: [SavedPlace]) -> String {
        if let favourite = savedPlaces.min(by: {
            $0.coordinate.distance(to: coordinate) < $1.coordinate.distance(to: coordinate)
        }), favourite.coordinate.distance(to: coordinate) <= 100 {
            return String(favourite.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        }
        if needsPlaceName {
            return String(format: "%.2f, %.2f", locale: Locale(identifier: "en_US_POSIX"), coordinate.latitude, coordinate.longitude)
        }
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let concise = cleaned.split(separator: ",", maxSplits: 1).first.map(String.init) ?? cleaned
        return String(concise.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
    }
}

struct SavedPlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var coordinate: Coordinate
    var createdAt = Date().timeIntervalSince1970

    var waypoint: Waypoint { Waypoint(name: name, coordinate: coordinate) }
}

enum Bike: String, Codable, CaseIterable {
    case touring, gravel, mountain, road
    var title: String {
        switch self {
        case .touring: "Tourenrad"
        case .gravel: "Gravelbike"
        case .mountain: "Mountainbike"
        case .road: "Rennrad"
        }
    }
}

enum SurfacePreference: String, Codable, CaseIterable {
    case any, preferPaved, pavedOnly
    var title: String {
        switch self {
        case .any: "Schotter erlaubt"
        case .preferPaved: "Befestigte Wege bevorzugen"
        case .pavedOnly: "Nur bekannte befestigte Wege"
        }
    }
}

struct RidingProfile: Codable, Equatable {
    var bike: Bike = .touring
    var electric = true
    var surface: SurfacePreference = .any
    var gentleHills = false
    var title: String { (electric ? "E-" : "") + bike.title }
}

struct Maneuver: Codable, Equatable {
    var instruction: String
    var distance: Double
    var coordinateIndex: Int
    var type: Int
    var symbol: String {
        switch type {
        case 0, 2, 4: "arrow.turn.up.left"
        case 1, 3, 5: "arrow.turn.up.right"
        case 7, 8: "arrow.trianglehead.2.clockwise.rotate.90"
        case 9: "arrow.uturn.down"
        case 10: "flag.checkered"
        default: "arrow.up"
        }
    }
}

struct SurfaceSummary: Codable, Equatable {
    var name: String
    var distance: Double
    var percentage: Double
}

enum SurfaceKind: String, CaseIterable, Identifiable {
    case paved, paving, gravel, natural, other, unknown
    var id: String { rawValue }
    init(code: Int) {
        switch code {
        case 1, 3, 4: self = .paved
        case 5, 14, 18: self = .paving
        case 8, 9, 10: self = .gravel
        case 2, 11, 12, 15, 16, 17: self = .natural
        case 6, 7, 13: self = .other
        default: self = .unknown
        }
    }
    var title: String {
        switch self {
        case .paved: "Befestigt"
        case .paving: "Pflaster"
        case .gravel: "Schotter"
        case .natural: "Unbefestigt"
        case .other: "Sonstige"
        case .unknown: "Unbekannt"
        }
    }
}

struct RouteSurfaceSection: Codable, Equatable {
    var startIndex: Int
    var endIndex: Int
    var surface: Int
    var kind: SurfaceKind { SurfaceKind(code: surface) }
}

struct CalculatedRoute: Codable, Identifiable, Equatable {
    var id: UUID
    var coordinates: [Coordinate]
    var distance: Double
    var duration: Double
    var ascent: Double
    var descent: Double
    var maneuvers: [Maneuver]
    var surfaces: [SurfaceSummary]
    var warnings: [String]
    var provider: String
    var calculatedAt: Double
    // Older saved routes contain only totals, which cannot locate a surface on the map.
    var surfaceSections: [RouteSurfaceSection]?

    var coloredSections: [RouteSurfaceSection] {
        guard coordinates.count > 1 else { return [] }
        let unknown = RouteSurfaceSection(startIndex: 0, endIndex: coordinates.count - 1, surface: 0)
        guard let surfaceSections, !surfaceSections.isEmpty else { return [unknown] }
        var result: [RouteSurfaceSection] = []
        var cursor = 0
        for section in surfaceSections {
            guard section.startIndex >= cursor, section.endIndex > section.startIndex,
                  section.endIndex < coordinates.count else { return [unknown] }
            if section.startIndex > cursor {
                result.append(RouteSurfaceSection(startIndex: cursor, endIndex: section.startIndex, surface: 0))
            }
            result.append(section)
            cursor = section.endIndex
        }
        if cursor < coordinates.count - 1 {
            result.append(RouteSurfaceSection(startIndex: cursor, endIndex: coordinates.count - 1, surface: 0))
        }
        return result
    }
}

struct TrackPoint: Codable, Equatable {
    var coordinate: Coordinate
    var timestamp: Double
    var accuracy: Double
    var speed: Double
    var segment: Int
}

enum DocumentKind: String, Codable { case plan, ride }
enum RecordingState: String, Codable { case none, recording, paused, finished }

enum PlanningLocation {
    static func isUsable(timestamp: Double, accuracy: Double, now: Double) -> Bool {
        accuracy >= 0 && accuracy <= 100 && abs(now - timestamp) <= 15
    }
}

struct TourDocument: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: DocumentKind = .plan
    var title = "Meine nächste Tour"
    // Missing in older documents; their non-default titles remain user-owned.
    var usesAutomaticTitle: Bool?
    var awaitingStart: Bool?
    var createdAt = Date().timeIntervalSince1970
    var updatedAt = Date().timeIntervalSince1970
    var waypoints: [Waypoint] = []
    var profile = RidingProfile()
    var route: CalculatedRoute?
    var track: [TrackPoint] = []
    var startedAt: Double?
    var endedAt: Double?
    var movingDuration = 0.0
    var recordingState: RecordingState = .none

    var isAwaitingStart: Bool { awaitingStart == true }
    var startPoint: Waypoint? { isAwaitingStart ? nil : waypoints.first }
    var destinationPoint: Waypoint? { (isAwaitingStart || waypoints.count >= 2) ? waypoints.last : nil }
    var canCalculateRoute: Bool { !isAwaitingStart && waypoints.count >= 2 }

    mutating func setStart(_ point: Waypoint) {
        if isAwaitingStart || waypoints.isEmpty { waypoints.insert(point, at: 0) }
        else { waypoints[0] = point }
        awaitingStart = nil
    }

    mutating func setDestination(_ point: Waypoint, currentPosition: Coordinate?) {
        if waypoints.isEmpty {
            waypoints = [point]
            awaitingStart = true
        } else if destinationPoint == nil {
            waypoints.append(point)
        } else {
            waypoints[waypoints.count - 1] = point
        }
        if let currentPosition { _ = completeAutomaticStart(currentPosition) }
    }

    @discardableResult
    mutating func reverseWaypoints() -> Bool {
        guard canCalculateRoute else { return false }
        waypoints.reverse()
        return true
    }

    @discardableResult
    mutating func completeAutomaticStart(_ coordinate: Coordinate) -> Bool {
        guard isAwaitingStart, !waypoints.isEmpty else { return false }
        setStart(Waypoint(name: "Mein Standort", coordinate: coordinate))
        return true
    }

    mutating func updateAutomaticTitle(savedPlaces: [SavedPlace] = []) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .plan,
              usesAutomaticTitle ?? (trimmed.isEmpty || trimmed == "Meine nächste Tour") else { return }
        usesAutomaticTitle = true
        guard let start = startPoint, let destination = destinationPoint else {
            title = "Meine nächste Tour"
            return
        }
        title = "\(start.shortTourTitleName(savedPlaces: savedPlaces)) → \(destination.shortTourTitleName(savedPlaces: savedPlaces))"
    }

    mutating func rename(to value: String) {
        usesAutomaticTitle = false
        title = String(value.prefix(200))
    }

    mutating func finishRenaming() {
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { usesAutomaticTitle = true }
        updateAutomaticTitle()
    }

    // A late place-name lookup must never rename a replaced or moved waypoint.
    @discardableResult
    mutating func resolveName(_ name: String, for original: Waypoint) -> Bool {
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !cleaned.isEmpty,
              let index = waypoints.firstIndex(where: { $0.id == original.id && $0.coordinate == original.coordinate && $0.needsPlaceName }) else { return false }
        waypoints[index].name = cleaned
        updateAutomaticTitle()
        return true
    }

    var recordedDistance: Double {
        zip(track, track.dropFirst()).reduce(0) { sum, pair in
            sum + (pair.0.segment == pair.1.segment ? pair.0.coordinate.distance(to: pair.1.coordinate) : 0)
        }
    }

    func asNewPlan() -> TourDocument {
        var result = self
        result.id = UUID()
        result.kind = .plan
        result.title += " · Kopie"
        result.usesAutomaticTitle = false
        result.createdAt = Date().timeIntervalSince1970
        result.updatedAt = result.createdAt
        result.track = []
        result.startedAt = nil
        result.endedAt = nil
        result.movingDuration = 0
        result.recordingState = .none
        return result
    }
}

struct SavedRecord: Codable, Identifiable {
    var document: TourDocument
    var revision = 0
    var dirty = true
    var deleted = false
    var mutationID = UUID()
    var id: UUID { document.id }
}

struct RemoteRecord: Codable {
    var document: TourDocument
    var revision: Int
    var deleted: Bool
}

struct ChangePage: Codable {
    var records: [RemoteRecord]
    var cursor: Int
    var hasMore: Bool
}

struct Mutation: Codable {
    var mutationID: UUID
    var baseRevision: Int
    var deleted: Bool
    var document: TourDocument
}

struct RouteRequest: Codable {
    var waypoints: [Waypoint]
    var profile: RidingProfile
}

enum Format {
    static func distance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
