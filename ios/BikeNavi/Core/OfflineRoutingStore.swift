import Foundation

/// Immutable tile versions plus an atomically replaced route manifest. A failed
/// refresh cannot damage the last complete offline package, even after restart.
actor OfflineRoutingStore {
    struct Entry: Codable { var id: OfflineTileID; var file: String }
    private var prepared: (graph: OfflineGraph, entries: [Entry])?
    private var downloads: [UUID: [Entry]] = [:]
    let directory: URL
    init(directory: URL) { self.directory = directory }
    private func manifest(_ route: CalculatedRoute) -> URL { directory.appendingPathComponent(route.id.uuidString + ".manifest") }
    private func read(_ entry: Entry) throws -> OfflineGraphTile {
        guard !entry.file.contains("/"), entry.file.hasPrefix(entry.id.key + ".") || entry.file.hasPrefix(entry.id.key + "-") else { throw LocalRoutingError.noData }
        let url = directory.appendingPathComponent(entry.file)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 32 * 1024 * 1024 else { throw LocalRoutingError.tooLarge }
        let tile = try JSONDecoder().decode(OfflineGraphTile.self, from: Data(contentsOf: url))
        try tile.validate(for: entry.id)
        return tile
    }
    /// Evict only files not referenced by a completed package or active download.
    /// Existing offline packages remain intact; an old moving window becomes
    /// reclaimable only after its replacement manifest was committed.
    private func makeRoom(for bytes: Int) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        var pinned = Set(downloads.values.flatMap { $0 }.map(\.file))
        pinned.formUnion(prepared?.entries.map(\.file) ?? [])
        for file in files where file.pathExtension == "manifest" {
            // A corrupt manifest must not silently cause deletion of its data.
            let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: file))
            pinned.formUnion(entries.map(\.file))
        }
        var used = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        let candidates = files.filter { $0.pathExtension == "json" && !pinned.contains($0.lastPathComponent) }
            .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for file in candidates where used + bytes > 250 * 1024 * 1024 {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try FileManager.default.removeItem(at: file)
            used -= size
        }
        guard used + bytes <= 250 * 1024 * 1024 else { throw LocalRoutingError.tooLarge }
    }

    private func latest(_ id: OfflineTileID) -> Entry {
        let ref = directory.appendingPathComponent(id.key + ".ref")
        return Entry(id: id, file: (try? String(contentsOf: ref, encoding: .utf8)) ?? id.key + ".json")
    }
    func load(route: CalculatedRoute) throws -> OfflineGraph {
        let entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: manifest(route)))
        return try OfflineGraph(tiles: entries.map { try read($0) })
    }
    /// Planning never waits for the local navigation window when a server is configured.
    func calculate(document: TourDocument, api: APIClient?,
                   progress: @Sendable (Int, Int) async -> Void) async throws -> CalculatedRoute {
        if let api { return try await api.route(document, includeContext: false) }
        return try await plan(document: document, api: nil, progress: progress).0
    }

    func prepareNeighborhood(route: CalculatedRoute, center: Coordinate, api: APIClient?, refresh: Bool = false,
                             progress: @Sendable (Int, Int) async -> Void) async throws -> OfflineGraph {
        try await prepare(route: route, api: api, refresh: refresh,
                          ids: OfflineTileID.neighborhood(center), progress: progress)
    }

    func plan(document: TourDocument, api: APIClient?,
              progress: @Sendable (Int, Int) async -> Void) async throws -> (CalculatedRoute, OfflineGraph) {
        guard document.profile.mode == .cycling else { throw LocalRoutingError.walkingRequiresServer }
        let seed = CalculatedRoute(id: UUID(), coordinates: document.waypoints.map(\.coordinate), distance: 0,
            duration: 0, ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [],
            provider: "Wegenetz", calculatedAt: Date().timeIntervalSince1970)
        defer { try? FileManager.default.removeItem(at: manifest(seed)) }
        let initialIDs = try OfflineTileID.corridor(seed.coordinates)
        let width = initialIDs.map(\.x).max()! - initialIDs.map(\.x).min()!
        let height = initialIDs.map(\.y).max()! - initialIDs.map(\.y).min()!
        let dx = width >= height ? 0 : 1
        let dy = width >= height ? 1 : 0
        var ids = initialIDs
        var completed: (route: CalculatedRoute, graph: OfflineGraph, entries: Data)?
        // Try each side of the corridor separately before loading a whole ring.
        // Dense city maps can exceed the graph budget when both sides are loaded,
        // although either side alone already contains a usable detour.
        for attempt in 0...4 {
            try Task.checkCancellation()
            switch attempt {
            case 1: ids = try OfflineTileID.extended(initialIDs, dx: -dx, dy: -dy)
            case 2: ids = try OfflineTileID.extended(initialIDs, dx: dx, dy: dy)
            case 3: ids = try OfflineTileID.expanded(initialIDs)
            case 4: ids = try OfflineTileID.expanded(ids)
            default: break
            }
            let graph: OfflineGraph
            let entries: Data
            if let prepared, (api == nil || prepared.graph.hasCurrentAccessRules), Set(ids).isSubset(of: prepared.graph.tiles) {
                graph = prepared.graph
                entries = try JSONEncoder().encode(prepared.entries)
                await progress(ids.count, ids.count)
            } else {
                do {
                    graph = try await prepare(route: seed, api: api, ids: ids, progress: progress)
                    entries = try Data(contentsOf: manifest(seed))
                } catch LocalRoutingError.tooLarge where attempt == 1 || attempt == 2 {
                    continue
                } catch LocalRoutingError.noData where attempt == 1 || attempt == 2 {
                    // The opposite side may already be available offline.
                    continue
                }
            }
            let work = Task.detached(priority: .userInitiated) { try LocalRouter.plan(graph: graph, document: document) }
            do {
                let route = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                completed = (route, graph, entries)
                break
            } catch LocalRoutingError.noConnection where attempt < 4 {
                continue
            }
        }
        guard let (route, graph, entries) = completed else { throw LocalRoutingError.noConnection }
        try Task.checkCancellation()
        // Complete ways may extend beyond their source tile. Do not claim that
        // navigation is prepared where the surrounding map was never loaded.
        if !Set(route.coordinates.map { OfflineTileID.at($0) }).isSubset(of: graph.tiles) {
            let complete = try await prepare(route: route, api: api, progress: progress)
            return (route, complete)
        }
        try entries.write(to: manifest(route), options: .atomic)
        return (route, graph)
    }
    func prepare(route: CalculatedRoute, api: APIClient?, refresh: Bool = false,
                 progress: @Sendable (Int, Int) async -> Void) async throws -> OfflineGraph {
        try await prepare(route: route, api: api, refresh: refresh,
                          ids: OfflineTileID.corridor(route.coordinates), progress: progress)
    }
    private func prepare(route: CalculatedRoute, api: APIClient?, refresh: Bool = false,
                         ids: [OfflineTileID], progress: @Sendable (Int, Int) async -> Void) async throws -> OfflineGraph {
        if refresh { prepared = nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !refresh, let complete = try? load(route: route),
           (api == nil || complete.hasCurrentAccessRules), Set(ids) == complete.tiles {
            await progress(ids.count, ids.count)
            return complete
        }
        let downloadID = UUID()
        downloads[downloadID] = []
        defer { downloads.removeValue(forKey: downloadID) }
        var tiles: [OfflineGraphTile] = [], entries: [Entry] = []
        for (i,id) in ids.enumerated() {
            try Task.checkCancellation()
            await progress(i, ids.count)
            var entry = latest(id)
            let cached = try? read(entry)
            let tile: OfflineGraphTile
            if let cached, !refresh, api == nil || cached.hasCurrentAccessRules { tile = cached }
            else {
                guard let api else { throw LocalRoutingError.noData }
                var downloaded: OfflineGraphTile?
                for attempt in 0..<3 {
                    do {
                        downloaded = try await api.request("/v1/offline-tiles/\(id.x)/\(id.y)" + (refresh ? "?refresh=true" : ""), timeout: 100)
                        break
                    } catch {
                        let retryable = (error as? APIError).map { [429, 502, 503, 504].contains($0.status) } ?? (error is URLError)
                        guard retryable, attempt < 2, !Task.isCancelled else { throw error }
                        try await Task.sleep(for: .seconds(2 * (attempt + 1)))
                    }
                }
                guard let downloaded else { throw LocalRoutingError.noData }
                tile = downloaded
                try Task.checkCancellation()
                try tile.validate(for: id)
                let data = try JSONEncoder().encode(tile)
                try makeRoom(for: data.count)
                entry.file = id.key + "-" + UUID().uuidString + ".json"
                try data.write(to: directory.appendingPathComponent(entry.file), options: .atomic)
                try Data(entry.file.utf8).write(to: directory.appendingPathComponent(id.key + ".ref"), options: .atomic)
            }
            tiles.append(tile); entries.append(entry)
            downloads[downloadID] = entries
        }
        let graph: OfflineGraph
        do {
            graph = try OfflineGraph(tiles: tiles)
        } catch LocalRoutingError.inconsistentData where !refresh && api != nil {
            // One complete refresh for legacy/unresolvable snapshots. Keep the
            // last route manifest intact if this also fails.
            return try await prepare(route: route, api: api, refresh: true, ids: ids, progress: progress)
        }
        try Task.checkCancellation()
        try JSONEncoder().encode(entries).write(to: manifest(route), options: .atomic)
        prepared = (graph, entries)
        await progress(ids.count, ids.count)
        return graph
    }
}
