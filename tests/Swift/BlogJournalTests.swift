import XCTest
import ImageIO
import CoreGraphics
@testable import BikeNaviCore

final class BlogJournalTests: XCTestCase {
    private func fixture() throws -> (LocalStore, TourDocument) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("test.sqlite")
        let store = try LocalStore(url: url)
        var ride = TourDocument()
        ride.kind = .ride
        ride.recordingState = .finished
        try store.save(ride)
        return (store, ride)
    }

    func testOfflinePhotoRoundtripAcknowledgementAndReset() throws {
        let (store, ride) = try fixture()
        let photo = Data([0xff, 0xd8, 0xff, 0xd9])
        let point = BlogPoint(rideID: ride.id, coordinate: .init(latitude: 49.41, longitude: 8.68), title: "Beispiel", note: "Am Fluss", photo: photo)
        try store.appendBlogPoint(point)
        XCTAssertEqual(try store.blogPoints(rideID: ride.id, pendingOnly: true), [point])
        XCTAssertEqual(try store.blogPointCounts(rideID: ride.id).total, 1)
        XCTAssertEqual(try store.blogPointCounts(rideID: ride.id).pending, 1)
        XCTAssertEqual(try JSONDecoder().decode(BlogPoint.self, from: JSONEncoder().encode(point)).photo, photo)
        try store.appendBlogPoint(point, uploaded: true)
        XCTAssertTrue(try store.blogPoints(rideID: ride.id, pendingOnly: true).isEmpty)
        XCTAssertEqual(try store.blogPointCounts(rideID: ride.id).pending, 0)
        try store.resetBlogUploads()
        XCTAssertEqual(try store.blogPoints(rideID: ride.id, pendingOnly: true).count, 1)
    }

    func testConflictCopiesJournalWithNewIDsAndDeletionRemovesIt() throws {
        let (store, ride) = try fixture()
        let point = BlogPoint(rideID: ride.id, coordinate: .init(latitude: 49.41, longitude: 8.68), title: "Beispiel", note: "Pause")
        try store.appendBlogPoint(point)
        try store.preserveConflict(try XCTUnwrap(store.record(id: ride.id)))
        let copy = try XCTUnwrap(store.all().first { $0.id != ride.id })
        let copied = try XCTUnwrap(store.blogPoints(rideID: copy.id).first)
        XCTAssertNotEqual(copied.id, point.id)
        XCTAssertEqual(copied.rideID, copy.id)
        XCTAssertEqual(copied.note, point.note)
        try store.discardRide(id: ride.id)
        XCTAssertTrue(try store.blogPoints(rideID: ride.id).isEmpty)
        XCTAssertEqual(try store.blogPoints(rideID: copy.id).count, 1)
    }

    func testDeleteRemovesEveryLocalHTMLExportForTheRide() throws {
        let (store, ride) = try fixture()
        let first = BlogDraft(id: UUID(), rideID: ride.id, createdAt: 1, html: "Beispiel 1", warnings: [], mode: "template", sourceCount: 0)
        let second = BlogDraft(id: UUID(), rideID: ride.id, createdAt: 2, html: "Beispiel 2", warnings: [], mode: "template", sourceCount: 0)
        let urls = try [first.export(), second.export()]
        try store.saveBlogDraft(second)
        try store.deleteBlogData(rideID: ride.id)
        for url in urls { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertNil(try store.blogDraft(rideID: ride.id))
    }

    func testEditInsertReorderPreserveIDsAndPendingContent() throws {
        let (store, ride) = try fixture()
        let a = BlogPoint(rideID: ride.id, coordinate: .init(latitude: 49.41, longitude: 8.68), capturedAt: 10, title: "A", note: "Alt")
        let b = BlogPoint(rideID: ride.id, coordinate: a.coordinate, capturedAt: 20, title: "B", note: "Zweiter")
        try store.appendBlogPoint(a, uploaded: true); try store.appendBlogPoint(b, uploaded: true)
        let added = BlogPoint(rideID: ride.id, coordinate: a.coordinate, capturedAt: 1000, title: "Nachtrag", note: "Später ergänzt")
        try store.saveBlogPoint(added, at: 1)
        XCTAssertEqual(try store.blogPoints(rideID: ride.id).map(\.title), ["A", "Nachtrag", "B"])
        var edit = try XCTUnwrap(store.blogPoints(rideID: ride.id).first)
        edit.title = "Korrigiert"; edit.note = "Neue Notiz"
        try store.saveBlogPoint(edit, at: 2)
        XCTAssertEqual(try store.blogPoints(rideID: ride.id).map(\.title), ["Nachtrag", "B", "Korrigiert"])
        XCTAssertEqual(try store.blogPoints(rideID: ride.id).last?.id, a.id)
        // The cursor download of an old version must preserve the local correction.
        try store.appendBlogPoint(a, uploaded: true)
        XCTAssertEqual(try store.blogPoints(rideID: ride.id).last?.note, "Neue Notiz")
        XCTAssertEqual(try store.blogPoints(rideID: ride.id, pendingOnly: true).count, 3)
    }

    func testAcknowledgementDuringAnotherOfflineEditRetainsPendingRevision() throws {
        let (store, ride) = try fixture()
        let point = BlogPoint(rideID: ride.id, coordinate: .init(latitude: 49.41, longitude: 8.68), title: "Ort", note: "Alt")
        try store.saveBlogPoint(point, at: 0)
        let sent = try XCTUnwrap(store.blogPoints(rideID: ride.id).first)
        var changed = sent; changed.note = "Während Upload geändert"
        try store.saveBlogPoint(changed, at: 0)
        var remote = sent; remote.revision = 1
        try store.acknowledgeBlogPoint(sent, remote: remote)
        let pending = try XCTUnwrap(store.blogPoints(rideID: ride.id, pendingOnly: true).first)
        XCTAssertEqual(pending.note, changed.note); XCTAssertEqual(pending.revision, 1)
        remote = pending; remote.revision = 2
        try store.acknowledgeBlogPoint(pending, remote: remote)
        XCTAssertTrue(try store.blogPoints(rideID: ride.id, pendingOnly: true).isEmpty)
    }

    func testOpenEditorCannotOverwriteChangedStationButAllowsAcknowledgement() throws {
        let (store, ride) = try fixture()
        let point = BlogPoint(rideID: ride.id, coordinate: .init(latitude: 49.41, longitude: 8.68), title: "Ort", note: "Alt", sortOrder: 0)
        try store.appendBlogPoint(point, uploaded: true)
        var remote = point; remote.revision = 1
        try store.appendBlogPoint(remote, uploaded: true)
        var edit = point; edit.note = "Formulareingabe"
        try store.saveBlogPoint(edit, at: 0, original: point)
        let saved = try XCTUnwrap(store.blogPoints(rideID: ride.id).first)
        var other = saved; other.note = "Zwischenzeitliche Änderung"
        try store.saveBlogPoint(other, at: 0)
        XCTAssertThrowsError(try store.saveBlogPoint(edit, at: 0, original: saved))
        XCTAssertEqual(try store.blogPoints(rideID: ride.id).first?.note, other.note)
    }

    func testLegacyPointDecodesWithoutOrderOrRevision() throws {
        let (store, ride) = try fixture()
        let point = BlogPoint(rideID: ride.id, coordinate: .init(latitude: 49.41, longitude: 8.68), title: "Alt", note: "Notiz")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(point)) as? [String: Any])
        json.removeValue(forKey: "revision"); json.removeValue(forKey: "sortOrder")
        let legacy = try JSONDecoder().decode(BlogPoint.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(legacy.revision, 0); XCTAssertNil(legacy.sortOrder)
        try store.appendBlogPoint(legacy)
        XCTAssertEqual(try store.blogPoints(rideID: ride.id), [point])
    }

    func testPhotoGPSBeforeReencodingAndMissingGPS() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        func jpeg(_ gps: [String: Any]?) throws -> Data {
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
            let properties: [String: Any] = gps.map { [kCGImagePropertyGPSDictionary as String: $0] } ?? [:]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return data as Data
        }
        let gps: [String: Any] = [kCGImagePropertyGPSLatitude as String: 49.41, kCGImagePropertyGPSLatitudeRef as String: "S",
                                 kCGImagePropertyGPSLongitude as String: 8.68, kCGImagePropertyGPSLongitudeRef as String: "W"]
        XCTAssertEqual(BlogPhotoLocation.coordinate(in: try jpeg(gps)), .init(latitude: -49.41, longitude: -8.68))
        XCTAssertNil(BlogPhotoLocation.coordinate(in: try jpeg(nil)))
        XCTAssertNil(BlogPhotoLocation.coordinate(in: Data("kein Foto".utf8)))
        var invalid = gps; invalid[kCGImagePropertyGPSLatitude as String] = 91.0
        XCTAssertNil(BlogPhotoLocation.coordinate(in: try jpeg(invalid)))
    }

    func testCursorAndExportPersist() throws {
        let (store, ride) = try fixture()
        try store.setBlogCursor(30, rideID: ride.id)
        XCTAssertEqual(try store.blogCursor(rideID: ride.id), 30)
        let draft = BlogDraft(id: UUID(), rideID: ride.id, createdAt: 1, html: "<!doctype html><html lang=\"de\">Beispiel</html>", warnings: [], mode: "template", sourceCount: 0)
        try store.saveBlogDraft(draft)
        XCTAssertEqual(try store.blogDraft(rideID: ride.id)?.html, draft.html)
        let file = try draft.export()
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try String(contentsOf: file), draft.html)
        try store.resetBlogUploads()
        XCTAssertEqual(try store.blogCursor(rideID: ride.id), 0)
    }
}
