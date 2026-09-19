import Foundation

enum GPX {
    static func xml(_ document: TourDocument) -> String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&apos;")
        }
        let date = ISO8601DateFormatter()
        var body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"BikeNavi\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><name>\(escape(document.title))</name>"
        if document.kind == .ride {
            var lastSegment: Int?
            for point in document.track {
                if lastSegment != point.segment {
                    if lastSegment != nil { body += "</trkseg>" }
                    body += "<trkseg>"; lastSegment = point.segment
                }
                body += "<trkpt lat=\"\(point.coordinate.latitude)\" lon=\"\(point.coordinate.longitude)\">"
                if let altitude = point.coordinate.altitude { body += "<ele>\(altitude)</ele>" }
                body += "<time>\(date.string(from: Date(timeIntervalSince1970: point.timestamp)))</time></trkpt>"
            }
            if lastSegment != nil { body += "</trkseg>" }
        } else {
            body += "<trkseg>"
            for point in document.route?.coordinates ?? [] {
                body += "<trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">"
                if let altitude = point.altitude { body += "<ele>\(altitude)</ele>" }
                body += "</trkpt>"
            }
            body += "</trkseg>"
        }
        return body + "</trk></gpx>"
    }
    static func write(_ document: TourDocument) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BikeNavi-\(document.id.uuidString).gpx")
        try xml(document).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
