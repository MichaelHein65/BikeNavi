import Foundation

/// Presentation rules keep missing, expired and explicitly measured zero values distinct.
struct BikeTelemetryDisplay {
    let battery: String
    let mode: String
    let modeCode: Int?
    let riderPower: String
    let motorPower: String
    let batteryIsCurrent: Bool
    let batteryReceivedAt: Date?

    static func modeName(_ code: Int) -> String {
        let names = ["OFF", "ECO", "TOUR+", "AUTO", "TURBO"]
        return names.indices.contains(code) ? names[code] : "STUFE \(code)"
    }

    init(connected: Bool, battery: Int?, batteryAt: Date?, mode: Int?, modeAt: Date?,
         riderPower: Int?, riderPowerAt: Date?, motorPower: Int?, motorPowerAt: Date?, now: Date,
         batteryReceivedInCurrentConnection: Bool = true) {
        func fresh(_ date: Date?, within seconds: TimeInterval) -> Bool {
            guard connected, let date else { return false }
            return (0..<seconds).contains(now.timeIntervalSince(date))
        }
        self.battery = battery != nil && batteryAt != nil ? "\(battery!) %" : "—"
        batteryIsCurrent = battery != nil && batteryReceivedInCurrentConnection && fresh(batteryAt, within: 30)
        batteryReceivedAt = battery == nil ? nil : batteryAt
        modeCode = fresh(modeAt, within: 15) ? mode : nil
        self.mode = modeCode.map(Self.modeName) ?? "—"
        self.riderPower = riderPower != nil && fresh(riderPowerAt, within: 15) ? "\(riderPower!) W" : "—"
        self.motorPower = motorPower != nil && fresh(motorPowerAt, within: 15) ? "\(motorPower!) W" : "—"
    }
}
