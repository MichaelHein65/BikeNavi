import XCTest
@testable import BikeNaviCore

final class BikeRecordingTests: XCTestCase {
    func testSamplesSurviveRestartAndAcknowledgementDoesNotLoseNewData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("test.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ride = UUID(), plan = UUID(), bike = UUID()
        let sample = RecordedBikeSample(rideID: ride, sourcePlanID: plan, segment: 0, position: nil,
            measurement: BikeMeasurement(bikeID: bike, timestamp: 100, batteryPercent: 89))
        do { let store = try LocalStore(url: url); try store.append(sample) }
        let store = try LocalStore(url: url)
        XCTAssertEqual(try store.bikeSamples(rideID: ride, pendingOnly: true), [sample])
        var newer = sample; newer.id = UUID(); newer.measurement.timestamp = 101; newer.segment = 3
        try store.append(newer)
        XCTAssertEqual(try store.lastBikeSegment(rideID: ride), 3)
        try store.acknowledgeBikeSamples([sample.id])
        XCTAssertEqual(try store.bikeSamples(rideID: ride, pendingOnly: true), [newer])
        XCTAssertEqual(try store.bikeSampleCounts(rideID: ride).total, 2)
        var repeatRide = sample; repeatRide.id = UUID(); repeatRide.rideID = UUID()
        try store.append(repeatRide)
        XCTAssertEqual(try store.bikeSamples(rideID: repeatRide.rideID), [repeatRide])
        XCTAssertNil(try store.bikeSamples(rideID: ride).first?.measurement.motorPowerWatts)
        try store.resetBikeUploads()
        XCTAssertEqual(try store.bikeSampleCounts(rideID: ride).pending, 2)
    }

    func testDiscardRemovesMeasurementsAndKeepsDeletionPendingDespiteLateAcknowledgement() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("test.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalStore(url: url)
        var ride = TourDocument(); ride.kind = .ride; ride.recordingState = .paused
        try store.save(ride)
        let sent = try XCTUnwrap(store.record(id: ride.id))
        try store.append(RecordedBikeSample(rideID: ride.id, sourcePlanID: UUID(), segment: 0, position: nil,
            measurement: BikeMeasurement(bikeID: UUID(), timestamp: 100, batteryPercent: 89)))
        try store.discardRide(id: ride.id)
        try store.acknowledge(sent, remote: RemoteRecord(document: ride, revision: 1, deleted: false))
        let deleted = try XCTUnwrap(store.record(id: ride.id))
        XCTAssertTrue(deleted.deleted)
        XCTAssertTrue(deleted.dirty)
        XCTAssertEqual(deleted.revision, 1)
        XCTAssertTrue(deleted.document.track.isEmpty)
        XCTAssertNil(deleted.document.route)
        XCTAssertEqual(try store.bikeSampleCounts(rideID: ride.id).total, 0)
        let plan = TourDocument(); try store.save(plan); try store.discardRide(id: plan.id)
        XCTAssertFalse(try XCTUnwrap(store.record(id: plan.id)).deleted)
    }

    func testPositionMustBeRecentAndInSameRecordingSegment() {
        let point = TrackPoint(coordinate: Coordinate(latitude: 49, longitude: 8), timestamp: 100, accuracy: 5, speed: 0, segment: 0)
        func sample(_ timestamp: Double, _ segment: Int) -> RecordedBikeSample {
            RecordedBikeSample(rideID: UUID(), sourcePlanID: UUID(), segment: segment, position: point,
                measurement: BikeMeasurement(bikeID: UUID(), timestamp: timestamp, riderPowerWatts: 0))
        }
        XCTAssertEqual(sample(110, 0).position, point)
        XCTAssertNil(sample(116, 0).position)
        XCTAssertNil(sample(99, 0).position)
        XCTAssertNil(sample(110, 1).position)
        XCTAssertEqual(sample(110, 0).measurement.riderPowerWatts, 0)
    }
}
