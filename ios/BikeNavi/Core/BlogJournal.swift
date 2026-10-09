import Foundation
import ImageIO

struct BlogPoint: Codable, Identifiable, Equatable {
    var id = UUID()
    var rideID: UUID
    var coordinate: Coordinate
    var capturedAt = Date().timeIntervalSince1970
    var title: String
    var note: String
    /// Re-encoded, scaled JPEG. Original photo metadata is never uploaded.
    var photo: Data?
    var sortOrder: Double?
    /// Last acknowledged Pi revision; offline edits retain this base revision.
    var revision: Int = 0

    static func ordered(_ points: [BlogPoint]) -> [BlogPoint] {
        points.sorted {
            let a = $0.sortOrder ?? $0.capturedAt, b = $1.sortOrder ?? $1.capturedAt
            return a == b ? $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() : a < b
        }
    }

    enum CodingKeys: String, CodingKey { case id, rideID, coordinate, capturedAt, title, note, photo, sortOrder, revision }

    init(id: UUID = UUID(), rideID: UUID, coordinate: Coordinate, capturedAt: Double = Date().timeIntervalSince1970,
         title: String, note: String, photo: Data? = nil, sortOrder: Double? = nil, revision: Int = 0) {
        self.id = id; self.rideID = rideID; self.coordinate = coordinate; self.capturedAt = capturedAt
        self.title = title; self.note = note; self.photo = photo; self.sortOrder = sortOrder; self.revision = revision
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); rideID = try c.decode(UUID.self, forKey: .rideID)
        coordinate = try c.decode(Coordinate.self, forKey: .coordinate); capturedAt = try c.decode(Double.self, forKey: .capturedAt)
        title = try c.decode(String.self, forKey: .title); note = try c.decode(String.self, forKey: .note)
        photo = try c.decodeIfPresent(Data.self, forKey: .photo); sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    }
}

enum BlogPhotoLocation {
    /// Read the original image before re-encoding strips its metadata.
    static func coordinate(in data: Data) -> Coordinate? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double,
              let latRef = gps[kCGImagePropertyGPSLatitudeRef as String] as? String,
              let lonRef = gps[kCGImagePropertyGPSLongitudeRef as String] as? String,
              ["N", "S"].contains(latRef), ["E", "W"].contains(lonRef),
              lat.isFinite, lon.isFinite, (0...90).contains(lat), (0...180).contains(lon) else { return nil }
        return Coordinate(latitude: latRef == "S" ? -lat : lat, longitude: lonRef == "W" ? -lon : lon)
    }
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

struct BlogGenerationProgress: Decodable, Equatable {
    var generationID: UUID
    var rideID: UUID
    var phase: String
    var startedAt: Double
    var updatedAt: Double
    var draftID: UUID?
    var message: String?
    var connectionInterrupted = false

    enum CodingKeys: String, CodingKey { case generationID, rideID, phase, startedAt, updatedAt, draftID, message }

    var isRunning: Bool { !["completed", "failed", "unreachable"].contains(phase) }
    var step: Int {
        switch phase {
        case "analysing": return 1
        case "researching": return 2
        case "writing": return 3
        case "saving", "downloading", "completed": return 4
        default: return 0
        }
    }
    var title: String {
        switch phase {
        case "synchronizing": return "Fahrt und Blog-Orte übertragen …"
        case "analysing": return "Bilder und Karten vorbereiten …"
        case "researching": return "Ortsquellen recherchieren …"
        case "writing": return "Deinen Blog schreiben …"
        case "saving": return "Neue Blogfassung speichern …"
        case "downloading": return "Blogfassung aufs iPhone laden …"
        case "completed": return "Dein Blog ist fertig."
        case "unreachable": return "Pi-Auftrag gerade nicht erreichbar."
        case "failed": return "Blogerstellung fehlgeschlagen."
        default: return "Auf Rückmeldung vom Pi warten …"
        }
    }
}
