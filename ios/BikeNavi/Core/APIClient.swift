import Foundation

struct APIError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }

    static func message(status: Int, body: Data) -> String {
        if let detail = try? JSONDecoder().decode(APIErrorBody.self, from: body).detail {
            return detail
        }
        if let response = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let issues = response["detail"] as? [[String: Any]],
           let issue = issues.first {
            let location = issue["loc"] as? [String] ?? []
            if location.contains("travelMode"), issue["input"] as? String == "car" {
                return "Der Pi kennt den Auto-Modus noch nicht. Bitte das Backend aktualisieren."
            }
            if let description = issue["msg"] as? String, !description.isEmpty {
                return "Der Server hat die Anfrage abgelehnt: \(description)"
            }
        }
        return "Der Server konnte die Anfrage nicht verarbeiten (\(status))."
    }
}

struct ServerStatus: Codable { var routingAvailable: Bool; var version: String; var gpxImportAvailable: Bool?; var cyclePlanningAvailable: Bool? }
struct PlaceName: Decodable { var name: String? }
private struct APIErrorBody: Decodable { var detail: String }

struct APIClient {
    var baseURL: URL
    var token: String

    func request<Response: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 90) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError(status: 0, message: "Die Serveradresse ist ungültig.")
        }
        let relative = URLComponents(string: path)!
        components.path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? relative.path : baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).withLeadingSlash + relative.path
        components.queryItems = relative.queryItems
        guard let url = components.url else { throw APIError(status: 0, message: "Die Serveradresse ist ungültig.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: 0, message: "Keine Antwort vom Pi.") }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError(status: http.statusCode, message: APIError.message(status: http.statusCode, body: data))
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func elevations(_ coordinates: [Coordinate]) async throws -> ElevationResponse {
        try await request("/v1/elevation", method: "POST", body: JSONEncoder().encode(
            RouteElevation.Request(coordinates: coordinates)), timeout: 35)
    }

    func route(_ document: TourDocument, timeout: TimeInterval = 90, includeContext: Bool = true, startBearing: Double? = nil) async throws -> CalculatedRoute {
        var route: CalculatedRoute = try await request("/v1/route" + (includeContext ? "" : "?include_context=false"), method: "POST", body: JSONEncoder().encode(
            RouteRequest(waypoints: document.waypoints, profile: document.profile, startBearing: startBearing)), timeout: timeout)
        route.duration = RouteTravelTime(route: route, profile: document.profile).total
        return route
    }

    func search(_ text: String, near coordinate: Coordinate?) async throws -> [Waypoint] {
        var c = URLComponents()
        c.path = "/v1/search"
        c.queryItems = [URLQueryItem(name: "q", value: text)]
        if let coordinate {
            c.queryItems! += [URLQueryItem(name: "lat", value: String(coordinate.latitude)),
                             URLQueryItem(name: "lon", value: String(coordinate.longitude))]
        }
        return try await request(c.string!)
    }

    func send(_ record: SavedRecord) async throws -> RemoteRecord {
        try await request("/v1/mutations", method: "POST", body: JSONEncoder().encode(
            Mutation(mutationID: record.mutationID, baseRevision: record.revision,
                     deleted: record.deleted, document: record.document)))
    }

    func placeName(at coordinate: Coordinate) async throws -> PlaceName {
        var c = URLComponents()
        c.path = "/v1/place-name"
        c.queryItems = [URLQueryItem(name: "lat", value: String(coordinate.latitude)),
                        URLQueryItem(name: "lon", value: String(coordinate.longitude))]
        return try await request(c.string!)
    }
}

private extension String { var withLeadingSlash: String { "/" + self } }
