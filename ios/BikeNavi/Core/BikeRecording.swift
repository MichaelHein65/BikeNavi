import Foundation

/// Sparse measurements: nil means this packet did not contain that value.
/// Timestamp is reception time on the phone; position retains its own GPS timestamp.
struct BikeMeasurement: Codable, Equatable {
    var bikeID: UUID
    var timestamp: Double
    var batteryPercent: Int?
    var riderPowerWatts: Int?
    var motorPowerWatts: Int?
    var assistMode: Int?
    var cadenceRPM: Int?
    var speedKPH: Double?
    var chargerConnected: Bool?
}

struct RecordedBikeSample: Codable, Equatable, Identifiable {
    var id = UUID()
    var rideID: UUID
    var sourcePlanID: UUID
    var segment: Int
    var position: TrackPoint?
    var measurement: BikeMeasurement

    init(rideID: UUID, sourcePlanID: UUID, segment: Int, position: TrackPoint?, measurement: BikeMeasurement) {
        self.rideID = rideID
        self.sourcePlanID = sourcePlanID
        self.segment = segment
        self.measurement = measurement
        // Never attach an old position or bridge a pause to a fresh measurement.
        self.position = position.flatMap {
            let age = measurement.timestamp - $0.timestamp
            return $0.segment == segment && age >= 0 && age <= 15 ? $0 : nil
        }
    }
}

struct BikeSampleBatch: Codable { var samples: [RecordedBikeSample] }
struct BikeSampleReceipt: Codable { var accepted: [UUID] }
