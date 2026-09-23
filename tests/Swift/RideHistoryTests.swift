import XCTest
@testable import BikeNaviCore

final class RideHistoryTests: XCTestCase {
    private func point(_ time: Double, _ longitude: Double, altitude: Double? = nil, segment: Int = 0) -> TrackPoint {
        TrackPoint(coordinate: Coordinate(latitude: 49, longitude: longitude, altitude: altitude), timestamp: time,
                   accuracy: 5, speed: 5, segment: segment)
    }
    private func sample(_ time: Double, mode: Int? = nil, rider: Int? = nil, motor: Int? = nil, segment: Int = 0) -> RecordedBikeSample {
        RecordedBikeSample(rideID: UUID(), sourcePlanID: UUID(), segment: segment, position: nil,
            measurement: BikeMeasurement(bikeID: UUID(), timestamp: time, riderPowerWatts: rider, motorPowerWatts: motor, assistMode: mode))
    }

    func testModeChangesSplitTheLineAndExpireWithoutCrossingPauses() {
        let track = [point(0, 8), point(10, 8.01), point(30, 8.03), point(31, 9, segment: 1), point(35, 9.01, segment: 1)]
        let sections = RideHistory.modeSections(track: track, samples: [sample(5, mode: 3), sample(10, mode: 4)])
        XCTAssertEqual(sections.map(\.mode), [nil, 3, 4, nil, nil])
        XCTAssertEqual(sections[1].coordinates.first!.longitude, 8.005, accuracy: 0.000001)
        XCTAssertEqual(sections[2].coordinates.last!.longitude, 8.025, accuracy: 0.000001)
        XCTAssertEqual(sections.last!.coordinates.first!.longitude, 9)
    }

    func testRecordedElevationsSkipMissingHeightsAndPauseDistance() {
        let track = [point(0, 8, altitude: 100), point(1, 8.001), point(2, 8.002, altitude: 105),
                     point(5, 9, altitude: 110, segment: 1)]
        let result = RideHistory.elevations(track)
        XCTAssertEqual(result.map(\.altitude), [100, 105, 110])
        XCTAssertEqual(result.map(\.run), [0, 1, 2])
        XCTAssertEqual(result[1].distanceKM, result[2].distanceKM)
        XCTAssertGreaterThan(result[1].distanceKM, 0)
    }

    func testSparsePowerPreservesZerosAndSeparatesLongGapsAndPauses() {
        let readings = [sample(0, rider: 0), sample(1, motor: 100), sample(2, rider: 150),
                        sample(20, rider: 120), sample(21, rider: 80, segment: 1)]
        let result = RideHistory.powers(readings, track: [point(0, 8), point(20, 8.01), point(21, 9, segment: 1)])
        let rider = result.filter { $0.source == "Fahrer" }
        XCTAssertEqual(rider.map(\.watts), [0, 150, 120, 80])
        XCTAssertEqual(rider.map(\.run), [0, 0, 1, 2])
        XCTAssertEqual(result.filter { $0.source == "Motor" }.map(\.watts), [100])
        XCTAssertTrue(RideHistory.elevations([]).isEmpty)
        XCTAssertTrue(RideHistory.modeSections(track: [], samples: readings).isEmpty)
    }
}

extension RideHistoryTests {
    func testPowerDistanceMatchesElevationAndInterpolatesWithinSegments() {
        let track = [point(0, 8, altitude: 100), point(10, 8.01, altitude: 105),
                     point(20, 9, altitude: 110, segment: 1), point(30, 9.01, altitude: 115, segment: 1)]
        let readings = [sample(-1, rider: 10), sample(0, rider: 0), sample(5, rider: 100), sample(10, rider: 200),
                        sample(15, rider: 999), sample(20, rider: 50, segment: 1), sample(25, rider: 150, segment: 1),
                        sample(31, rider: 999, segment: 1), sample(25, motor: 999, segment: 2)]
        let result = RideHistory.powers(readings, track: track)
        let elevations = RideHistory.elevations(track)
        XCTAssertEqual(result.map(\.watts), [0, 100, 200, 50, 150])
        XCTAssertEqual(result[0].distanceKM, 0)
        XCTAssertEqual(result[1].distanceKM, elevations[1].distanceKM / 2, accuracy: 0.000001)
        XCTAssertEqual(result[2].distanceKM, elevations[1].distanceKM)
        XCTAssertEqual(result[3].distanceKM, elevations[2].distanceKM)
        XCTAssertEqual(result[4].distanceKM, (elevations[2].distanceKM + elevations[3].distanceKM) / 2, accuracy: 0.000001)
        XCTAssertNotEqual(result[2].run, result[3].run)
        XCTAssertTrue(RideHistory.powers(readings, track: []).isEmpty)
    }
}
