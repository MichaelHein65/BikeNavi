import Foundation

enum GPX {
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    static func xml(_ file: GPXFile) -> String {
        func point(_ point: GPXPoint, tag: String) -> String {
            var xml = "<\(tag) lat=\"\(point.coordinate.latitude)\" lon=\"\(point.coordinate.longitude)\">"
            if let altitude = point.coordinate.altitude { xml += "<ele>\(altitude)</ele>" }
            if let time = point.details.time { xml += "<time>\(escape(time))</time>" }
            if let name = point.details.name { xml += "<name>\(escape(name))</name>" }
            return xml + "</\(tag)>"
        }
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"BikeNavi\" xmlns=\"http://www.topografix.com/GPX/1/1\"><metadata><name>\(escape(file.name))</name></metadata>"
        for waypoint in file.waypoints { xml += point(waypoint, tag: "wpt") }
        // GPX 1.1 orders all routes before tracks.
        for part in file.parts.filter({ $0.kind == "rte" }) {
            xml += "<rte><name>\(escape(part.name))</name>"
            for item in part.points { xml += point(item, tag: "rtept") }
            xml += "</rte>"
        }
        for part in file.parts.filter({ $0.kind == "trk" }) {
            xml += "<trk><name>\(escape(part.name))</name><trkseg>"
            for item in part.points { xml += point(item, tag: "trkpt") }
            xml += "</trkseg></trk>"
        }
        return xml + "</gpx>"
    }
    static func xml(_ document: TourDocument) -> String {
        if document.kind == .plan, let route = document.route, let metadata = route.gpxTrack {
            let points = route.coordinates.enumerated().map { index, coordinate in
                GPXPoint(coordinate: coordinate, details: metadata.points.indices.contains(index) ? metadata.points[index] : GPXPointDetails())
            }
            return xml(GPXFile(name: document.title, parts: [GPXPart(name: document.title, kind: metadata.kind, points: points)], waypoints: metadata.waypoints))
        }
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
