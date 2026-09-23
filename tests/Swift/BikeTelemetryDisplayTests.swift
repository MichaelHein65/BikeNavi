import XCTest
@testable import BikeNaviCore

final class BikeTelemetryDisplayTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshMeasurementsIncludeRealZeroPowerAndNamedMode() {
        let display = make(connected: true, battery: 89, mode: 3, rider: 0, motor: 240, age: 1)
        XCTAssertEqual(display.battery, "89 %")
        XCTAssertTrue(display.batteryIsCurrent)
        XCTAssertEqual(display.mode, "AUTO")
        XCTAssertEqual(display.modeCode, 3)
        XCTAssertEqual(display.riderPower, "0 W")
        XCTAssertEqual(display.motorPower, "240 W")
    }

    func testMissingFieldsDoNotBecomeZeros() {
        let display = make(connected: true, battery: nil, mode: nil, rider: nil, motor: nil, age: 0)
        XCTAssertEqual(display.battery, "—")
        XCTAssertFalse(display.batteryIsCurrent)
        XCTAssertNil(display.batteryReceivedAt)
        XCTAssertEqual(display.mode, "—")
        XCTAssertEqual(display.riderPower, "—")
        XCTAssertEqual(display.motorPower, "—")
    }

    func testDisconnectionHidesFastMetricsAndKeepsBatteryOnlyAsLastReading() {
        let display = make(connected: false, battery: 89, mode: 3, rider: 160, motor: 250, age: 1)
        XCTAssertEqual(display.battery, "89 %")
        XCTAssertFalse(display.batteryIsCurrent)
        XCTAssertEqual(display.batteryReceivedAt, now.addingTimeInterval(-1))
        XCTAssertEqual(display.mode, "—")
        XCTAssertEqual(display.riderPower, "—")
        XCTAssertEqual(display.motorPower, "—")
    }

    func testReadingsExpireEvenWhileBluetoothRemainsConnected() {
        let display = make(connected: true, battery: 89, mode: 3, rider: 160, motor: 250, age: 30)
        XCTAssertFalse(display.batteryIsCurrent)
        XCTAssertEqual(display.battery, "89 %")
        XCTAssertEqual(display.mode, "—")
        XCTAssertEqual(display.riderPower, "—")
        XCTAssertEqual(display.motorPower, "—")
        let partial = make(connected: true, battery: 89, mode: 3, rider: 160, motor: 250, age: 15)
        XCTAssertTrue(partial.batteryIsCurrent)
        XCTAssertEqual(partial.riderPower, "—")
    }

    func testConfiguredBikeModesAndUnknownValues() {
        for (code, name) in ["OFF", "ECO", "TOUR+", "AUTO", "TURBO"].enumerated() {
            XCTAssertEqual(make(connected: true, battery: nil, mode: code, rider: nil, motor: nil, age: 1).mode, name)
        }
        XCTAssertEqual(make(connected: true, battery: nil, mode: 8, rider: nil, motor: nil, age: 1).mode, "STUFE 8")
        XCTAssertNil(make(connected: false, battery: nil, mode: 3, rider: nil, motor: nil, age: 1).modeCode)
    }

    private func make(connected: Bool, battery: Int?, mode: Int?, rider: Int?, motor: Int?, age: TimeInterval) -> BikeTelemetryDisplay {
        let date = now.addingTimeInterval(-age)
        return BikeTelemetryDisplay(connected: connected, battery: battery, batteryAt: date,
            mode: mode, modeAt: date, riderPower: rider, riderPowerAt: date,
            motorPower: motor, motorPowerAt: date, now: now)
    }
}
