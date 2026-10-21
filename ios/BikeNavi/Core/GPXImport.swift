import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct GPXPointDetails: Codable, Equatable {
    var name: String?
    /// Preserve the source spelling, timezone and fractional seconds.
    var time: String?
}

struct GPXPoint: Codable, Equatable {
    var coordinate: Coordinate
    var details = GPXPointDetails()
}

struct GPXTrackMetadata: Codable, Equatable {
    var kind: String
    var points: [GPXPointDetails]
    var waypoints: [GPXPoint]
}

struct GPXPart: Equatable {
    var name: String
    var kind: String
    var points: [GPXPoint]
}

struct GPXFile: Equatable, Identifiable {
    let id = UUID()
    var name: String
    var parts: [GPXPart]
    var waypoints: [GPXPoint]
    var ignoredExtensions = false

    func document(part index: Int, start: Int, end: Int, reversed: Bool) throws -> TourDocument {
        guard parts.indices.contains(index), start >= 0, end < parts[index].points.count, start < end else {
            throw GPXImportError.message("Wähle mindestens zwei aufeinanderfolgende Punkte eines Abschnitts.")
        }
        let part = parts[index]
        var selected = Array(part.points[start...end])
        if reversed { selected.reverse() }
        let coordinates = selected.map(\.coordinate)
        let distance = zip(coordinates, coordinates.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
        guard distance > 0 else { throw GPXImportError.message("Dieser Abschnitt enthält keine Strecke zwischen unterschiedlichen Punkten.") }
        var ascent = 0.0, descent = 0.0
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            if let a = a.altitude, let b = b.altitude {
                ascent += max(0, b - a); descent += max(0, a - b)
            }
        }
        var document = TourDocument()
        document.title = String((part.name.isEmpty ? name : part.name).prefix(200))
        document.usesAutomaticTitle = false
        document.waypoints = [Waypoint(name: selected.first?.details.name ?? "GPX-Start", coordinate: coordinates[0]),
                              Waypoint(name: selected.last?.details.name ?? "GPX-Ziel", coordinate: coordinates[coordinates.count - 1])]
        document.route = CalculatedRoute(id: UUID(), coordinates: coordinates, distance: distance, duration: distance / 4,
            ascent: ascent, descent: descent, maneuvers: [], surfaces: [],
            warnings: ["Originalspur · keine Abbiegehinweise oder automatische Rückführung. Beläge und Zugänglichkeit unbekannt."],
            provider: GPX.importProvider, calculatedAt: Date().timeIntervalSince1970,
            waypointIndices: [0, coordinates.count - 1],
            gpxTrack: GPXTrackMetadata(kind: part.kind, points: selected.map(\.details), waypoints: waypoints))
        return document
    }
}

enum GPXImportError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

extension GPX {
    static let importProvider = "GPX · Originalspur"
    static let maximumBytes = 16 * 1024 * 1024
    static let maximumPoints = 100_000

    static func read(_ url: URL) throws -> GPXFile {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        // Read a bounded buffer, including files supplied by a document provider.
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        return try parse(data, fallbackName: url.deletingPathExtension().lastPathComponent)
    }

    static func parse(_ data: Data, fallbackName: String = "GPX-Tour") throws -> GPXFile {
        guard data.count <= maximumBytes else { throw GPXImportError.message("Die GPX-Datei ist größer als 16 MiB. Bitte in Etappen aufteilen.") }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GPXImportError.message("Bitte die GPX-Datei als UTF-8 speichern.")
        }
        guard text.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              text.range(of: "<!ENTITY", options: .caseInsensitive) == nil else {
            throw GPXImportError.message("GPX-Dateien mit DTD oder XML-Entitäten werden nicht unterstützt.")
        }
        let delegate = GPXParser(name: String(fallbackName.prefix(200)))
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil, delegate.rootSeen else {
            throw GPXImportError.message(delegate.failure ?? "Die GPX-Datei ist beschädigt oder enthält kein gültiges GPX-Dokument.")
        }
        guard !delegate.file.parts.isEmpty || !delegate.file.waypoints.isEmpty else {
            throw GPXImportError.message("Die GPX-Datei enthält keine Track-, Routen- oder Wegpunkte.")
        }
        return delegate.file
    }
}

/// Namespace-aware, bounded streaming parser. Unknown extension subtrees are ignored,
/// never interpreted as ordinary GPX points.
private final class GPXParser: NSObject, XMLParserDelegate {
    var file: GPXFile
    var failure: String?
    var rootSeen = false
    private var namespace = ""
    private var stack: [String] = []
    private var text = ""
    private var point: GPXPoint?
    private var points: [GPXPoint] = []
    private var pathName = ""
    private var segment = 0
    private var count = 0
    private let date = ISO8601DateFormatter()
    private let fractional = ISO8601DateFormatter()

    init(name: String) {
        file = GPXFile(name: name.isEmpty ? "GPX-Tour" : name, parts: [], waypoints: [])
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    private func fail(_ parser: XMLParser, _ message: String) {
        failure = message; parser.abortParsing()
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let uri = namespaceURI ?? ""
        if stack.isEmpty {
            guard !rootSeen, elementName == "gpx", ["", "http://www.topografix.com/GPX/1/1", "http://www.topografix.com/GPX/1/0"].contains(uri),
                  [nil, "1.0", "1.1"].contains(attributes["version"]) else {
                fail(parser, "Erwartet wird eine GPX-Datei der Version 1.0 oder 1.1."); return
            }
            namespace = uri; rootSeen = true
        }
        stack.append(uri == namespace ? elementName : "#foreign")
        text = ""
        guard stack.count <= 32 else { fail(parser, "Die GPX-Datei ist zu tief verschachtelt."); return }
        if elementName == "extensions" || uri != namespace { file.ignoredExtensions = true }
        let path = stack.joined(separator: "/")
        if path == "gpx/trk" || path == "gpx/rte" { pathName = ""; segment = 0; points = [] }
        if path == "gpx/trk/trkseg" { points = []; segment += 1 }
        if ["gpx/wpt", "gpx/rte/rtept", "gpx/trk/trkseg/trkpt"].contains(path) {
            count += 1
            guard count <= GPX.maximumPoints, file.waypoints.count < 1000 || path != "gpx/wpt" else {
                fail(parser, "Maximal 100.000 Punkte und 1.000 Wegpunkte pro Datei. Bitte die Datei aufteilen."); return
            }
            guard let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init),
                  lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else {
                fail(parser, "Ein GPX-Punkt hat fehlende oder ungültige Koordinaten."); return
            }
            point = GPXPoint(coordinate: Coordinate(latitude: lat, longitude: lon))
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard text.utf8.count + string.utf8.count <= 16_384 else {
            fail(parser, "Ein Textfeld der GPX-Datei ist zu lang."); return
        }
        text += string
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: value) }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let path = stack.joined(separator: "/")
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if (path == "gpx/metadata/name" || path == "gpx/name") && !value.isEmpty { file.name = String(value.prefix(200)) }
        if path == "gpx/trk/name" || path == "gpx/rte/name" { pathName = String(value.prefix(200)) }
        let parent = stack.dropLast().joined(separator: "/")
        if ["gpx/wpt", "gpx/rte/rtept", "gpx/trk/trkseg/trkpt"].contains(parent), namespaceURI ?? "" == namespace {
            switch elementName {
            case "ele":
                guard let altitude = Double(value), altitude.isFinite, abs(altitude) <= 100_000 else {
                    fail(parser, "Ein GPX-Punkt hat eine ungültige Höhe."); return
                }
                point?.coordinate.altitude = altitude
            case "time":
                guard value.count <= 64, date.date(from: value) != nil || fractional.date(from: value) != nil else {
                    fail(parser, "Ein GPX-Punkt hat einen ungültigen ISO-8601-Zeitstempel."); return
                }
                point?.details.time = value
            case "name":
                guard value.count <= 300 else { fail(parser, "Ein GPX-Punktname ist länger als 300 Zeichen."); return }
                point?.details.name = value
            default: break
            }
        }
        if ["gpx/wpt", "gpx/rte/rtept", "gpx/trk/trkseg/trkpt"].contains(path), let point {
            if path == "gpx/wpt" { file.waypoints.append(point) } else { points.append(point) }
            self.point = nil
        }
        if path == "gpx/trk/trkseg" || path == "gpx/rte" {
            guard file.parts.count < 1000 else { fail(parser, "Die GPX-Datei enthält mehr als 1.000 Abschnitte."); return }
            let base = pathName.isEmpty ? file.name : pathName
            file.parts.append(GPXPart(name: base,
                                     kind: path == "gpx/rte" ? "rte" : "trk", points: points))
            points = []
        }
        if !stack.isEmpty { stack.removeLast() }
        text = ""
    }
}

extension CalculatedRoute {
    var isGPXTrack: Bool { gpxTrack != nil || provider == GPX.importProvider }
}
