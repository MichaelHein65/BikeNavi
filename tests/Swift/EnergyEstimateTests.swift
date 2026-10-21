import XCTest
@testable import BikeNaviCore

final class EnergyEstimateTests: XCTestCase {
    func testChronologicalWholeRideHoldoutAndExtrapolationGate() {
        let bike = UUID(), now = Date().timeIntervalSince1970
        var observations = (0..<8).map { i in EnergyObservation(rideID: UUID(), bikeID: bike, endedAt: now-Double(8-i)*86400,
            kilometres: 10, drop: 10, ascentPerKM: 10, assistMode: 2) }
        let calibration = EnergyCalibration.fit(observations, bikeID: bike, mode: 2, now: now)
        XCTAssertEqual(calibration?.trainingCount, 5); XCTAssertEqual(calibration?.holdoutCount, 3)
        XCTAssertEqual(calibration?.coverage, 1); XCTAssertEqual(calibration?.meanAbsoluteError, 0)
        XCTAssertNotNil(calibration?.remainingPercent(soc: 50, kilometres: 10, ascentPerKM: 12))
        XCTAssertNil(calibration?.remainingPercent(soc: 50, kilometres: 10, ascentPerKM: 100))
        XCTAssertNil(EnergyCalibration.fit(Array(observations.prefix(7)), bikeID: bike, mode: 2, now: now))
        XCTAssertNil(EnergyCalibration.fit(observations, bikeID: UUID(), mode: 2, now: now))
        XCTAssertNil(EnergyCalibration.fit(observations, bikeID: bike, mode: 3, now: now))
        observations[7].drop = 90 // Future holdout must not widen the training envelope.
        XCTAssertNil(EnergyCalibration.fit(observations, bikeID: bike, mode: 2, now: now))
    }
    func testRepeatedRideCannotLeakAcrossSplit() {
        let bike = UUID(), id = UUID(), now = Date().timeIntervalSince1970
        let repeated = (0..<12).map { i in EnergyObservation(rideID: id, bikeID: bike, endedAt: now-Double(i)*86400, kilometres: 10, drop: 10, ascentPerKM: 0, assistMode: 1) }
        XCTAssertNil(EnergyCalibration.fit(repeated, bikeID: bike, mode: 1, now: now))
    }
    func testAuditRejectsSparseChargedAndMissingAltitude() {
        var ride = TourDocument(); ride.kind = .ride; ride.recordingState = .finished
        XCTAssertNil(EnergyAudit.inspect(ride: ride, samples: []).observation)
        let bike = UUID(), start = Date().timeIntervalSince1970-2000
        ride.track = (0...100).map { i in TrackPoint(coordinate: Coordinate(latitude: 49, longitude: 8+Double(i)*0.001, altitude: 100), timestamp: start+Double(i)*10, accuracy: 5, speed: 7, segment: 0) }
        let samples = (0...100).map { i in RecordedBikeSample(rideID: ride.id, sourcePlanID: ride.id, segment: 0, position: ride.track[i],
            measurement: BikeMeasurement(bikeID: bike, timestamp: start+Double(i)*10, batteryPercent: 80-i/10, assistMode: 2)) }
        XCTAssertNotNil(EnergyAudit.inspect(ride: ride, samples: samples).observation)
        var charged = samples; charged[50].measurement.chargerConnected = true
        XCTAssertEqual(EnergyAudit.inspect(ride: ride, samples: charged).reason, "Ladeereignis")
        ride.track[5].coordinate.altitude = nil
        XCTAssertEqual(EnergyAudit.inspect(ride: ride, samples: samples).reason, "Gemessene Höhen fehlen")
    }
}
