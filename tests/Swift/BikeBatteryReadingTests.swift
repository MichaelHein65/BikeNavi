import XCTest
@testable import BikeNaviCore

final class BikeBatteryReadingTests: XCTestCase {
    let bikeID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let now = Date(timeIntervalSince1970: 1_000)

    func testRecoveryKeepsNewestOwnBikeMeasurementAcrossReconnects() throws {
        let log = """
        {"event":"connecting","id":"\(bikeID)"}
        {"event":"smartphone_data","uuid":"00000011-EAA2-11E9-81B4-2A2AE2DBCCE4","timestamp":100,"hex":"300480880858"}
        {"event":"smartphone_data","uuid":"00000011-EAA2-11E9-81B4-2A2AE2DBCCE4","timestamp":200,"hex":"300480880859"}
        {"event":"start"}
        {"event":"connecting","id":"\(bikeID)"}
        {"event":"empty_live_data","timestamp":300}
        """
        let reading = try XCTUnwrap(BikeBatteryReading.recover(from: [Data(log.utf8)], for: bikeID, now: now))
        XCTAssertEqual(reading.percent, 89)
        XCTAssertEqual(reading.sampledAt, Date(timeIntervalSince1970: 200))
        let restored = try JSONDecoder().decode(BikeBatteryReading.self, from: JSONEncoder().encode(reading))
        XCTAssertEqual(restored, reading)
        XCTAssertFalse(restored.isValid(for: UUID(), now: now))
    }

    func testPacketsWithoutIdentifiedBikeOrWithBadValuesAreNotRecovered() {
        let log = """
        {"event":"smartphone_data","uuid":"00000011-EAA2-11E9-81B4-2A2AE2DBCCE4","timestamp":100,"hex":"300480880859"}
        {"event":"connecting","id":"\(bikeID)"}
        {"event":"smartphone_data","uuid":"00000011-EAA2-11E9-81B4-2A2AE2DBCCE4","timestamp":200,"hex":"300480880865"}
        {"event":"smartphone_data","uuid":"00000011-EAA2-11E9-81B4-2A2AE2DBCCE4","timestamp":2000,"hex":"300480880859"}
        {"event":"smartphone_data","uuid":"00000011-EAA2-11E9-81B4-2A2AE2DBCCE4","timestamp":200,"hex":"zz"}
        """
        XCTAssertNil(BikeBatteryReading.recover(from: [Data(log.utf8)], for: bikeID, now: now))
    }

    func testRecentlyRestoredBatteryIsStillMarkedAsLastKnown() {
        let display = BikeTelemetryDisplay(connected: true, battery: 89, batteryAt: now,
            mode: nil, modeAt: nil, riderPower: nil, riderPowerAt: nil, motorPower: nil, motorPowerAt: nil,
            now: now, batteryReceivedInCurrentConnection: false)
        XCTAssertEqual(display.battery, "89 %")
        XCTAssertFalse(display.batteryIsCurrent)
    }
}
