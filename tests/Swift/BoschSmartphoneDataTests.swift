import XCTest
@testable import BikeNaviCore

final class BoschSmartphoneDataTests: XCTestCase {
    func testModeNotificationObservedOnOwnBike() throws {
        let value = try BoschSmartphoneData.decode(Data([0x30, 4, 0x98, 9, 8, 3]))
        XCTAssertEqual(value.assistMode, 3)
        XCTAssertNil(value.batteryPercent)
        XCTAssertNil(value.riderPowerWatts)
        XCTAssertNil(value.motorPowerWatts)
    }

    func testBatteryNotificationObservedWhileChargingOwnBike() throws {
        let value = try BoschSmartphoneData.decode(Data([0x30, 4, 0x80, 0x88, 8, 0x58]))
        XCTAssertEqual(value.batteryPercent, 88)
        XCTAssertNil(value.motorPowerWatts)
        XCTAssertNil(value.riderPowerWatts)
    }

    func testConcatenatedBatteryAndPowerReferenceExamples() throws {
        let value = try BoschSmartphoneData.decode(Data([
            0x30, 4, 0x80, 0x88, 8, 89,
            0x30, 5, 0x98, 0x5b, 8, 0xb2, 4,
            0x30, 5, 0x98, 0x5d, 8, 0xf6, 1
        ]))
        XCTAssertEqual(value.batteryPercent, 89)
        XCTAssertEqual(value.riderPowerWatts, 562)
        XCTAssertEqual(value.motorPowerWatts, 246)
        XCTAssertNil(value.assistMode)
    }

    func testExplicitZeroDiffersFromMissingValue() throws {
        let value = try BoschSmartphoneData.decode(Data([0x30, 2, 0x98, 0x5b, 0x30, 2, 0x98, 0x5d, 0x30, 2, 0x98, 9]))
        XCTAssertEqual(value.riderPowerWatts, 0)
        XCTAssertEqual(value.motorPowerWatts, 0)
        XCTAssertEqual(value.assistMode, 0)
        XCTAssertNil(value.batteryPercent)
        XCTAssertEqual(try BoschSmartphoneData.decode(Data()), BoschSmartphoneData())
    }

    func testUnknownRealChargingFramesRemainUnknown() throws {
        let value = try BoschSmartphoneData.decode(Data([
            0x30, 5, 0x80, 0xe2, 8, 0xb6, 0x11,
            0x30, 5, 0x80, 0x8b, 8, 0xda, 3
        ]))
        XCTAssertEqual(value, BoschSmartphoneData())
    }

    func testCorruptAndTruncatedRecordsAreRejected() {
        let bad: [[UInt8]] = [
            [0x30, 4, 0x80, 0x88, 8], [0x30, 1, 0x80],
            [0x30, 4, 0x80, 0x88, 8, 101], [0x30, 4, 0x98, 9, 8, 0x80],
            [0x30, 4, 0x98, 9, 0x10, 1], [0x30, 5, 0x98, 9, 8, 1, 0],
            [0x31, 4, 0x98, 9, 8, 1], [0x30, 3, 0x98, 9, 8],
            [0x30, 4, 0x98, 9, 8, 1, 0x30]
        ]
        for bytes in bad { XCTAssertThrowsError(try BoschSmartphoneData.decode(Data(bytes))) }
    }

    func testObservedResponseEnvelopeDoesNotMasqueradeAsTelemetry() throws {
        let value = try BoschSmartphoneData.decode(Data([
            0x10, 6, 2, 1, 0, 0, 2, 3, 0x30, 5, 0x21, 6, 0xc0, 0x80, 0x55,
            0x30, 4, 0x98, 9, 8, 1
        ]))
        XCTAssertEqual(value.assistMode, 1)
        XCTAssertNil(value.batteryPercent)
    }
}
