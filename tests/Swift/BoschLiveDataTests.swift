import XCTest
@testable import BikeNaviCore

final class BoschLiveDataTests: XCTestCase {
    func testRealStationaryBikePacketFromSeptember20() throws {
        let hex = "0800100028004800505558dbbcbfd50660c6ca4b880101a80100b00101b80100c00100c80101"
        let bytes = stride(from: 0, to: hex.count, by: 2).map { index -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: index)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        let value = try BoschLiveData.decode(Data(bytes))
        XCTAssertEqual(value.batteryPercent, 85)
        XCTAssertEqual(value.riderPowerWatts, 0)
        XCTAssertEqual(value.cadenceRPM, 0)
        XCTAssertEqual(value.speedKPH, 0)
        XCTAssertEqual(value.chargerConnected, true)
    }

    func testBatteryAndPowerWithUnknownFields() throws {
        // 85%, 200 W, 90 rpm, 25 km/h, charger connected; future fields skipped.
        let bytes: [UInt8] = [0x50, 85, 0x28, 0xc8, 0x01, 0x10, 90, 0x08, 0xc4, 0x13,
                             0xb0, 0x01, 1, 0x9a, 0x06, 3, 1, 2, 3]
        let value = try BoschLiveData.decode(Data(bytes))
        XCTAssertEqual(value.batteryPercent, 85)
        XCTAssertEqual(value.riderPowerWatts, 200)
        XCTAssertEqual(value.cadenceRPM, 90)
        XCTAssertEqual(value.speedKPH, 25)
        XCTAssertEqual(value.chargerConnected, true)
    }

    func testPartialUpdateDoesNotInventBatteryOrPower() throws {
        let value = try BoschLiveData.decode(Data([0x10, 0]))
        XCTAssertNil(value.batteryPercent)
        XCTAssertNil(value.riderPowerWatts)
        XCTAssertEqual(value.cadenceRPM, 0)
        XCTAssertEqual(try BoschLiveData.decode(Data([0x50, 0])).batteryPercent, 0)
    }

    func testInvalidAndTruncatedPayloadsAreRejected() {
        for bytes: [UInt8] in [[0x50, 101], [0x50, 0x80], [0x52, 0], [0], [0x9a, 0x06, 4, 1],
                              [0x50] + Array(repeating: 0xff, count: 10)] {
            XCTAssertThrowsError(try BoschLiveData.decode(Data(bytes)))
        }
    }

    func testSignedCadenceSentinelIsNotHugeUnsignedValue() throws {
        let minusOne: [UInt8] = [0x10] + Array(repeating: 0xff, count: 9) + [0x01]
        XCTAssertNil(try BoschLiveData.decode(Data(minusOne)).cadenceRPM)
    }
}
