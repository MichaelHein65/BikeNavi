import ActivityKit
import Foundation

struct RideActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var instruction: String
        var distanceMeters: Int
        var remainingMeters: Int
        var symbol: String
        var status: String
    }

    var tourName: String
}

enum RideActivityFormat {
    static func distance(_ meters: Int) -> String {
        if meters < 1_000 { return "\(max(0, meters)) m" }
        let kilometers = Double(meters) / 1_000
        return kilometers < 10 ? String(format: "%.1f km", kilometers) : "\(Int(kilometers.rounded())) km"
    }
}
