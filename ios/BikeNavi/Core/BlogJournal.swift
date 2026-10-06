import Foundation

struct BlogPoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var rideID: UUID
    var coordinate: Coordinate
    var capturedAt = Date().timeIntervalSince1970
    var title: String
    var note: String
    /// Re-encoded, scaled JPEG. Original photo metadata is never uploaded.
    var photo: Data?
}

struct BlogPointPage: Decodable {
    var points: [BlogPoint]
    var cursor: Int
    var hasMore: Bool
}

struct BlogDraft: Codable, Identifiable {
    var id: UUID
    var rideID: UUID
    var createdAt: Double
    var html: String
    var warnings: [String]
    var mode: String
    var sourceCount: Int

    func export() throws -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BikeNavi/BlogExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("BikeNavi-Blog-\(rideID.uuidString)-\(id.uuidString).html")
        try Data(html.utf8).write(to: url, options: .atomic)
        return url
    }
}
