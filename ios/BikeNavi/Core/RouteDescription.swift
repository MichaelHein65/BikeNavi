import Foundation
import CryptoKit

struct RouteDescriptionRequest: Codable {
    var planID: UUID
    var title: String
    var waypoints: [Waypoint]
    var profile: RidingProfile
    var route: CalculatedRoute

    init?(plan: TourDocument) {
        guard plan.kind == .plan, let route = plan.route, plan.waypoints.count >= 2 else { return nil }
        planID = plan.id; title = plan.title; waypoints = plan.waypoints
        profile = plan.profile; self.route = route
    }

    var fingerprint: String {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return SHA256.hash(data: try encoder.encode(self)).map { String(format: "%02x", $0) }.joined()
        }
    }
}

struct RouteDescriptionReport: Codable {
    var planID: UUID
    var routeID: UUID
    var createdAt: Double
    var html: String
    var mode: String
    var sourceCount: Int
    var imageCount: Int
    var warnings: [String]
    var highlights: [RouteDescriptionHighlight]? = nil

    var exportHTML: String {
        html.replacingOccurrences(of: "<a class='add-highlight' href='bikenavi-highlight://insert/[0-9a-fA-F-]+'>[^<]*</a>", with: "", options: .regularExpression)
    }
}

struct RouteDescriptionHighlight: Codable, Identifiable {
    var id: UUID
    var title: String
    var coordinate: Coordinate
    var routeDistance: Double
    var startWaypointID: UUID
    var endWaypointID: UUID
    var startWaypointCoordinate: Coordinate? = nil
    var endWaypointCoordinate: Coordinate? = nil
}

enum RouteDescriptionInsertion {
    static func inserting(_ highlight: RouteDescriptionHighlight, into plan: TourDocument,
                          referenceIndices: [String: Int]? = nil) throws -> TourDocument {
        func failure(_ message: String) -> APIError { APIError(status: 0, message: message) }
        guard plan.kind == .plan, let route = plan.route, route.coordinates.count >= 2,
              let start = plan.waypoints.firstIndex(where: { $0.id == highlight.startWaypointID }),
              let end = plan.waypoints.firstIndex(where: { $0.id == highlight.endWaypointID }), start < end else {
            throw failure("Die Ziele wurden geändert. Bitte eine neue Routenbeschreibung erstellen.")
        }
        guard plan.waypoints.count < 50 else { throw failure("Eine Tour kann höchstens 50 Ziele enthalten.") }
        if let coordinate = highlight.startWaypointCoordinate, coordinate.distance(to: plan.waypoints[start].coordinate) > 5 {
            throw failure("Das Abschnittsziel wurde verschoben. Bitte eine neue Routenbeschreibung erstellen.")
        }
        if let coordinate = highlight.endWaypointCoordinate, coordinate.distance(to: plan.waypoints[end].coordinate) > 5 {
            throw failure("Das Abschnittsziel wurde verschoben. Bitte eine neue Routenbeschreibung erstellen.")
        }
        guard highlight.coordinate.latitude.isFinite, abs(highlight.coordinate.latitude) <= 90,
              highlight.coordinate.longitude.isFinite, abs(highlight.coordinate.longitude) <= 180 else {
            throw failure("Der Highlight-Standort ist ungültig.")
        }
        guard !plan.waypoints.contains(where: { $0.id == highlight.id || $0.coordinate.distance(to: highlight.coordinate) < 5 }) else {
            throw failure("Dieser Ort ist bereits in deiner Tour eingeplant.")
        }
        var indices = route.waypointIndices ?? []
        if indices.count != plan.waypoints.count || indices != indices.sorted() || indices.contains(where: { $0 < 0 || $0 >= route.coordinates.count }) {
            indices = [0]
            for point in plan.waypoints.dropFirst().dropLast() {
                let lower = indices.last!
                let index = (lower..<route.coordinates.count).min { route.coordinates[$0].distance(to: point.coordinate) < route.coordinates[$1].distance(to: point.coordinate) }!
                indices.append(index)
            }
            indices.append(route.coordinates.count - 1)
        }
        var cumulative = [0.0]
        for i in 1..<route.coordinates.count { cumulative.append(cumulative.last! + route.coordinates[i - 1].distance(to: route.coordinates[i])) }
        let lo = referenceIndices?[highlight.startWaypointID.uuidString] ?? indices[start]
        let hi = referenceIndices?[highlight.endWaypointID.uuidString] ?? indices[end]
        guard lo >= 0, hi < route.coordinates.count, lo < hi else { throw failure("Der passende Streckenabschnitt ist zu kurz. Bitte die Route erneut berechnen.") }
        let xScale = cos(highlight.coordinate.latitude * .pi / 180) * 111_195
        var best = (gap: Double.infinity, distance: 0.0)
        for i in lo..<hi {
            let a = route.coordinates[i], b = route.coordinates[i + 1]
            let ax = (a.longitude - highlight.coordinate.longitude) * xScale
            let ay = (a.latitude - highlight.coordinate.latitude) * 111_195
            let dx = (b.longitude - a.longitude) * xScale, dy = (b.latitude - a.latitude) * 111_195
            let t = min(1, max(0, -(ax * dx + ay * dy) / max(0.0001, dx * dx + dy * dy)))
            let gap = hypot(ax + t * dx, ay + t * dy)
            if gap < best.gap { best = (gap, cumulative[i] + t * (cumulative[i + 1] - cumulative[i])) }
        }
        guard best.gap <= 1000 else { throw failure("Dieses Highlight liegt nicht mehr im Umfeld des passenden Streckenabschnitts. Bitte die Beschreibung erneuern.") }
        // Project existing inserted stops continuously; nearest vertices would
        // misorder two highlights on the same long geometry segment.
        func position(of coordinate: Coordinate) -> Double {
            let scale = cos(coordinate.latitude * .pi / 180) * 111_195
            var result = (gap: Double.infinity, distance: 0.0)
            for i in lo..<hi {
                let a = route.coordinates[i], b = route.coordinates[i + 1]
                let ax = (a.longitude - coordinate.longitude) * scale, ay = (a.latitude - coordinate.latitude) * 111_195
                let dx = (b.longitude - a.longitude) * scale, dy = (b.latitude - a.latitude) * 111_195
                let t = min(1, max(0, -(ax * dx + ay * dy) / max(0.0001, dx * dx + dy * dy)))
                let gap = hypot(ax + t * dx, ay + t * dy)
                if gap < result.gap { result = (gap, cumulative[i] + t * (cumulative[i + 1] - cumulative[i])) }
            }
            return result.distance
        }
        let position = ((start + 1)..<end).first { position(of: plan.waypoints[$0].coordinate) > best.distance + 1 } ?? end
        var updated = plan
        updated.waypoints.insert(Waypoint(id: highlight.id, name: highlight.title, coordinate: highlight.coordinate), at: position)
        updated.route = nil
        return updated
    }
}

struct RouteDescriptionJob: Codable {
    var generationID: UUID
    var planID: UUID
    var phase: String
    var message: String?
    var report: RouteDescriptionReport?
    var running: Bool { !["completed", "failed", "interrupted"].contains(phase) }
    var statusText: String {
        switch phase {
        case "analysing": return "Pi analysiert Abschnitte und Gelände …"
        case "researching": return "Highlights am Wegesrand werden recherchiert …"
        case "images": return "Passende Bilder werden gesucht …"
        case "writing": return "Deine Routenbeschreibung entsteht …"
        case "saving": return "Beschreibung wird gespeichert …"
        case "completed": return "Routenbeschreibung fertig"
        default: return message ?? "Routenbeschreibung konnte nicht erstellt werden."
        }
    }
}

struct SavedRouteDescription: Codable {
    var planID: UUID
    var routeID: UUID? = nil
    var fingerprint: String
    var job: RouteDescriptionJob
    var report: RouteDescriptionReport?
    var reportFingerprint: String?
    var requestRoute: CalculatedRoute? = nil
    var reportRoute: CalculatedRoute? = nil
    var requestWaypointIndices: [String: Int]? = nil
    var reportWaypointIndices: [String: Int]? = nil

    func matches(_ plan: TourDocument) -> Bool {
        guard let request = RouteDescriptionRequest(plan: plan), report?.planID == plan.id,
              report?.routeID == request.route.id else { return false }
        return reportFingerprint == (try? request.fingerprint)
    }

    func requestMatches(_ plan: TourDocument) -> Bool {
        guard planID == plan.id, let request = RouteDescriptionRequest(plan: plan) else { return false }
        return fingerprint == (try? request.fingerprint)
    }

    func needsCreationOnOpen(_ plan: TourDocument) -> Bool {
        !matches(plan) && !requestMatches(plan)
    }
}

extension APIClient {
    func startRouteDescription(_ request: RouteDescriptionRequest, generationID: UUID) async throws -> RouteDescriptionJob {
        try await self.request("/v1/route-description-jobs?generation_id=\(generationID.uuidString)", method: "POST", body: JSONEncoder().encode(request), timeout: 30)
    }

    func routeDescriptionJob(_ id: UUID) async throws -> RouteDescriptionJob {
        try await request("/v1/route-description-jobs/\(id.uuidString)", timeout: 30)
    }
}
