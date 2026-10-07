import XCTest
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
