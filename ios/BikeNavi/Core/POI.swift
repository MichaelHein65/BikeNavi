import Foundation

enum POICategory: String, Codable, CaseIterable, Identifiable {
    case fuel, supermarket, airport, station, beach, parking
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fuel: "Tankstelle"
        case .supermarket: "Supermarkt"
        case .airport: "Flughafen"
        case .station: "Bahnhof"
        case .beach: "Strand"
        case .parking: "Parkplatz"
        }
    }
    var symbol: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .supermarket: "basket.fill"
        case .airport: "airplane"
        case .station: "tram.fill"
        case .beach: "beach.umbrella.fill"
        case .parking: "parkingsign.circle.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .fuel: "Diesel vergleichen"
        case .supermarket: "Für unterwegs"
        case .airport: "Zum Abflug"
        case .station: "Gut ankommen"
        case .beach: "Ans Wasser"
        case .parking: "Auto abstellen"
        }
    }
}

struct POIRouteContext: Codable {
    var coordinates: [Coordinate]
    var progress: Double
    var pending: [Waypoint]
    var bearing: Double?
}

struct POISearchRequest: Codable {
    var category: POICategory
    var center: Coordinate
    var radius: Int
    var profile: RidingProfile
    var context: POIRouteContext?
}

struct POIPlace: Codable, Identifiable {
    var id: String
    var name: String
    var coordinate: Coordinate
    var country: String
    var dieselPrice: Double?
    var isOpen: Bool?
    var address: String
    var openingHours: String?
    var source: String
    var sourceURL: String
    var priceTimestamp: Double?
    var fetchedAt: Double
    var drivingDistance: Double
    var drivingSeconds: Double
    var detourSeconds: Double?
    var airDistance: Double?
    var waypoint: Waypoint { Waypoint(name: name, coordinate: coordinate) }
    var priceLabel: String {
        guard let dieselPrice, dieselPrice.isFinite, dieselPrice >= 0.1 else { return "Preis nicht verfügbar" }
        return dieselPrice.formatted(.number.precision(.fractionLength(3))) + " €/l"
    }
}

struct POISearchResult: Codable {
    var items: [POIPlace]
    var unpriced: [POIPlace]
    var notices: [String]
    var scope: String
    var searchedAt: Double
}

struct POIStopRequest: Encodable {
    var search: POISearchRequest
    var stop: Waypoint
}

struct POIStopResponse: Decodable {
    var route: CalculatedRoute
    var drivingDistance: Double
    var drivingSeconds: Double
    var detourSeconds: Double?
}

extension APIClient {
    func searchPOIs(_ search: POISearchRequest) async throws -> POISearchResult {
        do {
            return try await request("/v1/pois/search", method: "POST", body: JSONEncoder().encode(search), timeout: 95)
        } catch let error as APIError where error.status == 404 {
            throw APIError(status: 404, message: "Der Pi kennt die Ortesuche noch nicht. Bitte das Backend aktualisieren.")
        }
    }
    func routeToPOI(_ stop: Waypoint, search: POISearchRequest) async throws -> POIStopResponse {
        try await request("/v1/pois/route", method: "POST", body: JSONEncoder().encode(POIStopRequest(search: search, stop: stop)), timeout: 85)
    }
}
