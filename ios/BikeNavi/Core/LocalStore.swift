import Foundation
import SQLite3

final class LocalStore {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw failure() }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("CREATE TABLE IF NOT EXISTS documents (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS bike_samples (id TEXT PRIMARY KEY, ride_id TEXT NOT NULL, payload BLOB NOT NULL, uploaded INTEGER NOT NULL DEFAULT 0)")
        try execute("CREATE INDEX IF NOT EXISTS bike_samples_pending ON bike_samples(ride_id, uploaded)")
        try execute("CREATE TABLE IF NOT EXISTS places (id TEXT PRIMARY KEY, payload BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
    }

    deinit { sqlite3_close(db) }

    private func failure() -> NSError {
        NSError(domain: "BikeNavi.Storage", code: 1,
                userInfo: [NSLocalizedDescriptionKey: db.map { String(cString: sqlite3_errmsg($0)) } ?? "Lokaler Speicher nicht verfügbar."])
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    func all() throws -> [SavedRecord] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM documents", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        var values: [SavedRecord] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            values.append(try decoder.decode(SavedRecord.self, from: data))
        }
        return values.sorted { $0.document.updatedAt > $1.document.updatedAt }
    }

    func put(_ record: SavedRecord) throws {
        let data = try encoder.encode(record)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO documents(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, record.id.uuidString, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func record(id: UUID) throws -> SavedRecord? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM documents WHERE id=?", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, transient)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
        return try decoder.decode(SavedRecord.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0))))
    }

    func save(_ document: TourDocument) throws {
        var record = try record(id: document.id) ?? SavedRecord(document: document)
        record.document = document
        record.document.updatedAt = Date().timeIntervalSince1970
        record.dirty = true
        record.mutationID = UUID()
        try put(record)
    }

    /// Keep only a sync tombstone so previously uploaded paused rides disappear on the Pi too.
    func discardRide(id: UUID) throws {
        guard var record = try record(id: id), record.document.kind == .ride else { return }
        var tombstone = TourDocument(id: id)
        tombstone.kind = .ride
        tombstone.title = "Verworfene Fahrt"
        tombstone.recordingState = .finished
        record.document = tombstone
        record.deleted = true
        record.dirty = true
        record.mutationID = UUID()
        try execute("BEGIN IMMEDIATE")
        do {
            try put(record)
            try execute("DELETE FROM bike_samples WHERE ride_id='\(id.uuidString)'")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func acknowledge(_ sent: SavedRecord, remote: RemoteRecord) throws {
        guard var local = try record(id: sent.id) else { return }
        local.revision = remote.revision
        if local.mutationID == sent.mutationID { local.dirty = false }
        try put(local)
    }

    // A concurrent edit is preserved as a separate local plan/ride, including its
    // geometry and track. The original ID is free to receive the server version.
    func preserveConflict(_ record: SavedRecord) throws {
        var copy = record.document
        copy.id = UUID()
        copy.title += " · lokale Fassung"
        copy.usesAutomaticTitle = false
        try execute("BEGIN IMMEDIATE")
        do {
            try put(SavedRecord(document: copy))
            for var sample in try bikeSamples(rideID: record.id, limit: Int.max) {
                sample.id = UUID()
                sample.rideID = copy.id
                try append(sample)
            }
            var original = record
            original.dirty = false
            try put(original)
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func merge(_ remote: RemoteRecord) throws {
        if let local = try record(id: remote.document.id) {
            guard !local.dirty, remote.revision >= local.revision else { return }
        }
        try put(SavedRecord(document: remote.document, revision: remote.revision,
                            dirty: false, deleted: remote.deleted))
    }

    func append(_ sample: RecordedBikeSample) throws {
        let data = try encoder.encode(sample)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO bike_samples(id,ride_id,payload) VALUES(?,?,?)", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sample.id.uuidString, -1, transient)
        sqlite3_bind_text(statement, 2, sample.rideID.uuidString, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func bikeSamples(rideID: UUID, pendingOnly: Bool = false, limit: Int = 500) throws -> [RecordedBikeSample] {
        var statement: OpaquePointer?
        let sql = "SELECT payload FROM bike_samples WHERE ride_id=?" + (pendingOnly ? " AND uploaded=0" : "") + " ORDER BY rowid LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, rideID.uuidString, -1, transient)
        sqlite3_bind_int(statement, 2, Int32(clamping: limit))
        var samples: [RecordedBikeSample] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return samples }
            guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
            samples.append(try decoder.decode(RecordedBikeSample.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))))
        }
    }

    func acknowledgeBikeSamples(_ ids: [UUID]) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for id in ids {
                // UUID strings contain no SQL metacharacters.
                try execute("UPDATE bike_samples SET uploaded=1 WHERE id='\(id.uuidString)'")
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    func lastBikeSegment(rideID: UUID) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM bike_samples WHERE ride_id=? ORDER BY rowid DESC LIMIT 1", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, rideID.uuidString, -1, transient)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return 0 }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
        return try decoder.decode(RecordedBikeSample.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))).segment
    }

    func bikeSampleCounts(rideID: UUID) throws -> (total: Int, pending: Int) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*), COALESCE(SUM(1-uploaded),0) FROM bike_samples WHERE ride_id=?", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, rideID.uuidString, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw failure() }
        return (Int(sqlite3_column_int64(statement, 0)), Int(sqlite3_column_int64(statement, 1)))
    }

    func resetBikeUploads() throws { try execute("UPDATE bike_samples SET uploaded=0") }

    func places() throws -> [SavedPlace] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT payload FROM places", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        var values: [SavedPlace] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw failure() }
            values.append(try decoder.decode(SavedPlace.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))))
        }
        return values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func save(_ place: SavedPlace) throws {
        let data = try encoder.encode(place)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO places(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, place.id.uuidString, -1, transient)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func delete(_ place: SavedPlace) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM places WHERE id=?", -1, &statement, nil) == SQLITE_OK else { throw failure() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, place.id.uuidString, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    var cursor: Int {
        get {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT value FROM metadata WHERE key='cursor'", -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
    }

    func setCursor(_ value: Int) throws {
        try execute("INSERT INTO metadata(key,value) VALUES('cursor',\(max(0, value))) ON CONFLICT(key) DO UPDATE SET value=excluded.value")
    }
}
