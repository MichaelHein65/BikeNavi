import Foundation

enum CyclePreference: String, Codable, CaseIterable {
    case fast, comfortable, quiet
    var title: String { switch self { case .fast: "Schnell"; case .comfortable: "Komfortabel"; case .quiet: "Verkehrsarm" } }
    var explanation: String {
        switch self {
        case .fast: "Kurze Wege als Näherung für eine schnelle Fahrt. Keine Live-Verkehrsdaten; Belag und Höhenwunsch gelten weiterhin."
        case .comfortable: "Bevorzugt bekannte glatte Beläge, Radwege und geringe bekannte Steigungen. Fehlende Angaben bleiben unbekannt."
        case .quiet: "Bevorzugt Radwege und kleinere Straßen anhand der OSM-Straßenklasse. Verkehrsarm ist ein Planungswunsch, keine gemessene Verkehrsbelastung."
        }
    }
}
struct CycleQualitySection: Codable, Equatable {
    var startIndex: Int
    var endIndex: Int
    var roadClass: String?
    var cycleway: Bool?
    var surface: Int
    var incline: Double?
    var source = "OpenStreetMap"
}
enum CycleQuality {
    /// Additive penalties on metres; all >= 0 preserve the A* distance lower bound.
    static func penalty(_ edge: OfflineGraphEdge, preference: CyclePreference?) -> Double {
        switch preference {
        case .none, .fast: return 0
        case .comfortable:
            let surface = [3, 4].contains(edge.surface) ? 0.0 : edge.surface == 0 ? 1.0 : 0.6
            return surface + (edge.cycleway == true ? 0 : 0.2) + (edge.inclineKnown == true ? max(0, edge.incline) / 5 : 0.2)
        case .quiet:
            if edge.cycleway == true { return 0 }
            switch edge.roadClass {
            case "primary", "primary_link", "secondary", "secondary_link": return 4
            case "tertiary", "tertiary_link": return 2
            case "residential", "living_street", "service", "track": return 0.3
            default: return 1
            }
        }
    }
    static func sections(route: CalculatedRoute, graph: OfflineGraph) -> [CycleQualitySection] {
        zip(route.coordinates, route.coordinates.dropFirst()).enumerated().map { i, pair in
            let (a, b) = pair
            let middle = Coordinate(latitude: (a.latitude+b.latitude)/2, longitude: (a.longitude+b.longitude)/2)
            let matches = graph.matches(middle, heading: LocalGeometry.bearing(a,b), maxDistance: 2)
            let edges = matches.map { graph.edges[$0.edge] }.filter { edge in
                guard let from = graph.nodes[edge.from], let to = graph.nodes[edge.to] else { return false }
                return LocalGeometry.project(a, onto: from, to).distance < 2 && LocalGeometry.project(b, onto: from, to).distance < 2
            }
            let edge = Set(edges.map(\.way)).count == 1 ? edges.first : nil
            return CycleQualitySection(startIndex: i, endIndex: i+1, roadClass: edge?.roadClass, cycleway: edge?.cycleway,
                surface: edge?.surface ?? 0, incline: edge?.inclineKnown == true ? edge?.incline : nil)
        }
    }
}
