import Foundation

struct APIError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
}

struct ServerStatus: Codable { var routingAvailable: Bool; var version: String }
struct PlaceName: Decodable { var name: String? }
private struct APIErrorBody: Decodable { var detail: String }

struct APIClient {
    var baseURL: URL
    var token: String

    func request<Response: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Response {
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
        request.timeoutInterval = 90
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError(status: 0, message: "Keine Antwort vom Pi.") }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONDecoder().decode(APIErrorBody.self, from: data).detail) ?? "Der Server konnte die Anfrage nicht verarbeiten (\(http.statusCode))."
            throw APIError(status: http.statusCode, message: detail)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    func route(_ document: TourDocument) async throws -> CalculatedRoute {
        try await request("/v1/route", method: "POST", body: JSONEncoder().encode(
            RouteRequest(waypoints: document.waypoints, profile: document.profile)))
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
