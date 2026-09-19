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
