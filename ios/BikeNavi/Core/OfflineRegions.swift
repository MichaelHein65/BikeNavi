import Foundation
import CryptoKit

enum OfflinePOICategory: String, Codable, CaseIterable {
    case water, rest, tourism
    var title: String { switch self { case .water: "Trinkwasser"; case .rest: "Rastplätze"; case .tourism: "Sehenswertes" } }
}
struct OfflinePOI: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: OfflinePOICategory
    var coordinate: Coordinate
    var source: String
    var openingHours: String?
    var title: String { name.isEmpty ? category.title : name }
    var waypoint: Waypoint { Waypoint(name: title, coordinate: coordinate) }
}
struct RegionTilePackage: Codable {
    var schema: Int
    var bytes: Int
    var sha256: String
    var data: Data
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    func verified(id: OfflineTileID) throws -> OfflineGraphTile {
        guard schema == 1, bytes == data.count, bytes <= 32 * 1024 * 1024,
              sha256 == Self.hash(data) else { throw RegionError.invalid }
        let tile = try JSONDecoder().decode(OfflineGraphTile.self, from: data)
        try tile.validate(for: id)
        guard tile.hasCurrentAccessRules, tile.generatedAt > 0,
              (tile.pois ?? []).count <= 20000,
              (tile.pois ?? []).allSatisfy({ (-90...90).contains($0.coordinate.latitude) && (-180...180).contains($0.coordinate.longitude) }) else { throw RegionError.invalid }
        return tile
    }
}
struct OfflineRegion: Codable, Identifiable, Equatable {
    struct File: Codable, Equatable {
        var tile: OfflineTileID; var sha256: String; var bytes: Int; var sourceDate: Double
        var name: String { sha256 + ".json" }
    }
    var schema = 1
    var id: String
    var name: String
    var version: UUID
    var createdAt: Double
    var tiles: [OfflineTileID]
    var files: [File]
    var bytes: Int { files.reduce(0) { $0 + $1.bytes } }
    var oldestSource: Double { files.map(\.sourceDate).min() ?? createdAt }
    static func tiles(center: Coordinate, radius: Int) throws -> [OfflineTileID] {
        guard center.latitude.isFinite, center.longitude.isFinite, abs(center.latitude) < 75,
              abs(center.longitude) < 179, (1...2).contains(radius) else { throw RegionError.invalid }
        let tile = OfflineTileID.at(center)
        return ((tile.y-radius)...(tile.y+radius)).flatMap { y in
            ((tile.x-radius)...(tile.x+radius)).map { OfflineTileID(x: $0, y: y) }
        }
    }
    func validate() throws {
        guard schema == 1, !tiles.isEmpty, tiles.count <= 25, Set(tiles).count == tiles.count,
              tiles.allSatisfy({ (0..<7200).contains($0.x) && (300..<3300).contains($0.y) }),
              files.count <= tiles.count, Set(files.map(\.tile)).count == files.count,
              files.allSatisfy({ tiles.contains($0.tile) && $0.bytes > 0 && $0.bytes <= 32*1024*1024 && $0.sha256.count == 64 && $0.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) }) else { throw RegionError.invalid }
    }
}
enum RegionError: LocalizedError {
    case invalid, space, busy
    var errorDescription: String? {
        switch self {
        case .invalid: "Das Offline-Paket ist unvollständig, beschädigt oder inkompatibel. Die bisherige Region bleibt erhalten."
        case .space: "Für dieses Paket ist nicht genug Speicher frei. Alte Regionen löschen oder einen kleineren Bereich wählen."
        case .busy: "Ein Regionsdownload läuft bereits."
        }
    }
}

actor OfflineRegionStore {
    static let shared = OfflineRegionStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BikeNavi/Regions"))
    let directory: URL
    let budget: Int
    private var busy = false
    init(directory: URL, budget: Int = 250*1024*1024) { self.directory = directory; self.budget = budget }
    private func path(_ name: String) -> URL { directory.appendingPathComponent(name) }
    private func safe(_ id: String) throws { guard !id.isEmpty, id.count < 80, id.allSatisfy({ "0123456789-".contains($0) }) else { throw RegionError.invalid } }
    func list() throws -> [OfflineRegion] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "region" }.map { url in
                let region = try JSONDecoder().decode(OfflineRegion.self, from: Data(contentsOf: url))
                try region.validate(); return region
            }.sorted { $0.name < $1.name }
    }
    private func read(_ file: OfflineRegion.File) throws -> OfflineGraphTile {
        let url = path(file.name)
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) == file.bytes else { throw RegionError.invalid }
        return try RegionTilePackage(schema: 1, bytes: file.bytes, sha256: file.sha256, data: Data(contentsOf: url)).verified(id: file.tile)
    }
    func graph(_ region: OfflineRegion) throws -> OfflineGraph {
        try region.validate()
        guard region.files.count == region.tiles.count else { throw RegionError.invalid }
        var tiles: [OfflineGraphTile] = []
        var nodeCount = 0, edgeCount = 0
        for file in region.files {
            let tile = try read(file)
            nodeCount += tile.nodes.count; edgeCount += tile.edges.count
            guard nodeCount <= 100000, edgeCount <= 200000 else { throw LocalRoutingError.tooLarge }
            tiles.append(tile)
        }
        let graph = try OfflineGraph(tiles: tiles, regional: true)
        guard graph.nodes.count <= 50000, graph.edges.count <= 100000 else { throw LocalRoutingError.tooLarge }
        return graph
    }
    func covering(_ coordinates: [Coordinate]) throws -> OfflineGraph? {
        guard !coordinates.isEmpty else { return nil }
        let needed = Set(coordinates.map { OfflineTileID.at($0) })
        for region in try list() where needed.isSubset(of: Set(region.tiles)) { return try graph(region) }
        return nil
    }
    func pois(_ region: OfflineRegion) throws -> [OfflinePOI] {
        var found: [String: OfflinePOI] = [:]
        for file in region.files { for poi in try read(file).pois ?? [] { found[poi.id] = poi } }
        return found.values.sorted { $0.id < $1.id }
    }
    private func room(_ bytes: Int) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let used = urls.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let free = (try FileManager.default.attributesOfFileSystem(forPath: directory.path)[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        guard used + bytes <= budget, free > Int64(bytes + 50*1024*1024) else { throw RegionError.space }
    }
    /// Resume verified chunks, build a complete replacement, then switch the manifest atomically.
    func download(name: String, tiles: [OfflineTileID], refresh: Bool = false,
                  fetch: @Sendable (OfflineTileID, Bool) async throws -> RegionTilePackage,
                  progress: @Sendable (Int, Int) async -> Void) async throws -> OfflineRegion {
        guard !busy else { throw RegionError.busy }; busy = true; defer { busy = false }
        let sorted = tiles.sorted()
        guard let first = sorted.first, let last = sorted.last else { throw RegionError.invalid }
        let id = "\(first.x)-\(first.y)-\(last.x)-\(last.y)"
        try safe(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stageURL = path(id + (refresh ? "-update.stage" : ".stage"))
        var stage = (try? JSONDecoder().decode(OfflineRegion.self, from: Data(contentsOf: stageURL))) ??
            OfflineRegion(id: id, name: String(name.prefix(100)), version: UUID(), createdAt: Date().timeIntervalSince1970, tiles: sorted, files: [])
        try stage.validate()
        guard stage.tiles == sorted else { throw RegionError.invalid }
        for (index, tile) in sorted.enumerated() {
            try Task.checkCancellation()
            await progress(index, sorted.count)
            if let file = stage.files.first(where: { $0.tile == tile }), (try? read(file)) != nil { continue }
            let package = try await fetch(tile, refresh)
            let decoded = try package.verified(id: tile)
            let file = OfflineRegion.File(tile: tile, sha256: package.sha256, bytes: package.bytes, sourceDate: decoded.generatedAt)
            if (try? read(file)) == nil { try room(package.bytes); try package.data.write(to: path(file.name), options: .atomic) }
            stage.files.removeAll { $0.tile == tile }; stage.files.append(file)
            try JSONEncoder().encode(stage).write(to: stageURL, options: .atomic)
        }
        let complete = try graph(stage)
        try Task.checkCancellation()
        let style = try Self.mapStyle(complete)
        try room(style.count)
        let styleURL = path(stage.version.uuidString + ".style")
        try style.write(to: styleURL, options: .atomic)
        try JSONEncoder().encode(stage).write(to: path(id + ".region"), options: .atomic)
        try? FileManager.default.removeItem(at: stageURL)
        try? collectUnused()
        await progress(sorted.count, sorted.count)
        return stage
    }
    func styleURL(_ region: OfflineRegion) throws -> URL {
        let url = path(region.version.uuidString + ".style")
        guard FileManager.default.fileExists(atPath: url.path) else { throw RegionError.invalid }
        return url
    }
    func delete(_ region: OfflineRegion) throws {
        guard !busy else { throw RegionError.busy }; try safe(region.id)
        for suffix in [".region", ".stage", "-update.stage"] { if FileManager.default.fileExists(atPath: path(region.id + suffix).path) { try FileManager.default.removeItem(at: path(region.id + suffix)) } }
        try collectUnused()
    }
    func pendingDownloads() throws -> Int {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "stage" }.count
    }
    func discardPendingDownloads() throws {
        guard !busy else { throw RegionError.busy }
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where file.pathExtension == "stage" {
            try FileManager.default.removeItem(at: file)
        }
        try collectUnused()
    }
    private func collectUnused() throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let manifests = try urls.filter { ["region", "stage"].contains($0.pathExtension) }.map { url -> OfflineRegion in
            let region = try JSONDecoder().decode(OfflineRegion.self, from: Data(contentsOf: url)); try region.validate(); return region
        }
        let pinned = Set(manifests.flatMap { $0.files.map(\.name) + [$0.version.uuidString + ".style"] })
        for url in urls where ["json", "style"].contains(url.pathExtension) && !pinned.contains(url.lastPathComponent) { try FileManager.default.removeItem(at: url) }
    }
    static func mapStyle(_ graph: OfflineGraph) throws -> Data {
        var seen: Set<String> = []
        let features: [[String: Any]] = graph.edges.compactMap { edge in
            let key = "\(min(edge.from,edge.to))-\(max(edge.from,edge.to))-\(edge.way)"
            guard seen.insert(key).inserted, let a = graph.nodes[edge.from], let b = graph.nodes[edge.to] else { return nil }
            return ["type": "Feature", "properties": [:], "geometry": ["type": "LineString", "coordinates": [[a.longitude,a.latitude],[b.longitude,b.latitude]]]]
        }
        return try JSONSerialization.data(withJSONObject: ["version": 8, "name": "Offline-Wegenetz · © OpenStreetMap contributors (ODbL)",
            "sources": ["roads": ["type": "geojson", "attribution": "© <a href='https://www.openstreetmap.org/copyright'>OpenStreetMap contributors</a> · ODbL", "data": ["type": "FeatureCollection", "features": features]]],
            "layers": [["id": "paper", "type": "background", "paint": ["background-color": "#f5f2e8"]],
                       ["id": "roads", "type": "line", "source": "roads", "paint": ["line-color": "#899b88", "line-width": 2]]]])
    }
}

extension APIClient {
    func regionTile(_ tile: OfflineTileID, refresh: Bool) async throws -> RegionTilePackage {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? "/v1/region-tiles/\(tile.x)/\(tile.y)" : baseURL.path + "/v1/region-tiles/\(tile.x)/\(tile.y)"
        components.queryItems = [URLQueryItem(name: "refresh", value: refresh ? "true" : "false")]
        guard let url = components.url else { throw RegionError.invalid }
        var request = URLRequest(url: url); request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (stream, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw RegionError.invalid }
        guard http.statusCode == 200 else { throw APIError(status: http.statusCode, message: "Regionsdownload fehlgeschlagen (\(http.statusCode)). Bereits geladene Kacheln bleiben erhalten.") }
        let limit = 45*1024*1024
        guard response.expectedContentLength <= limit else { throw RegionError.space }
        var data = Data()
        for try await byte in stream {
            guard data.count < limit else { throw RegionError.space }
            data.append(byte)
        }
        return try JSONDecoder().decode(RegionTilePackage.self, from: data)
    }
}
