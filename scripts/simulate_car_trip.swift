import Foundation

/// Runs the shipping navigation core on the Mac with synthetic fixes and a real Pi repertoire.
/// No device location, saved tour, car control or remote routing is involved.
@main
struct SimulateCarTrip {
    struct LiveReport: Decodable { var pack: CarCharacterPack }
    struct Moment: Codable {
        var second: Int
        var meters: Double
        var speedKPH: Double
        var limitKPH: Double?
        var offRoute: Bool
        var event: String?
        var speech: String?
    }
    static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: simulate_car_trip live.json output.json") }
        let reports = try JSONDecoder().decode([LiveReport].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard let pack = reports.first?.pack, pack.source == "openai" else { fatalError("A real Pi/OpenAI repertoire is required") }
        let points = (0...90).map { Coordinate(latitude: 49.4146 + Double($0) * 0.00009, longitude: 8.6815) }
        let route = CalculatedRoute(id: UUID(), coordinates: points, distance: 901, duration: 95, ascent: 0, descent: 0,
            maneuvers: [], surfaces: [], warnings: [], provider: "SIMULATION · erfundene Geometrie und Limits", calculatedAt: 0,
            carSpeedLimits: [.init(startIndex: 0, endIndex: 25, kilometersPerHour: 50),
                             .init(startIndex: 25, endIndex: 80, kilometersPerHour: 30),
                             .init(startIndex: 80, endIndex: 90, kilometersPerHour: 50)])
        let distances = LocalRouteMetrics.distances(route)
        var speed = CarSpeedGuidance(), deviation = CarDeviationGuidance(), policy = ReroutePolicy(), tracker = RouteTracker()
        var traveled = 0.0, moments: [Moment] = [], lastSpeech = -Double.infinity
        var history = CarCharacterSpeechHistory()
        for second in 0...100 {
            let kph: Double = second < 18 ? 48 : second < 57 ? 42 : second < 70 ? 28 : 45
            if second > 0 { traveled = min(distances.last! - 1, traveled + kph / 3.6) }
            let index = min(points.count - 2, distances.lastIndex(where: { $0 <= traveled }) ?? 0)
            let fraction = (traveled - distances[index]) / (distances[index + 1] - distances[index])
            var position = Coordinate(latitude: points[index].latitude + fraction * (points[index + 1].latitude - points[index].latitude), longitude: points[index].longitude)
            let isOffRoute = (77...90).contains(second)
            if isOffRoute { position.longitude += 0.0015 }
            let now = 1000 + Double(second)
            guard let progress = tracker.update(position: position, timestamp: now, route: route, heading: 0, accuracy: 5, carNavigation: true) else { fatalError("Missing route match") }
            let confirmed = policy.observe(distanceFromRoute: progress.distanceFromRoute, timestamp: now, accuracy: 5, now: now)
            var notice = deviation.observe(confirmed: confirmed, onRoute: progress.snappedPosition != nil && progress.distanceFromRoute <= 25, now: now)
            if let speedNotice = speed.update(route: route, progress: progress, speed: kph / 3.6,
                timestamp: now, now: now, active: true, canSpeak: notice == nil, lastAnnouncement: lastSpeech) { notice = speedNotice }
            let speech = notice.map { history.decorate($0.text, pack: pack, event: $0.event, now: now) }
            if notice != nil { lastSpeech = now }
            moments.append(.init(second: second, meters: traveled, speedKPH: kph,
                limitKPH: CarNavigation.speedLimit(route: route, progress: progress, active: true),
                offRoute: isOffRoute, event: notice?.event.rawValue, speech: speech))
        }
        let events = moments.compactMap(\.event)
        print(moments.filter { $0.event != nil }.map { "\($0.second):\($0.event!)" }); fflush(stdout)
        for required in ["slower", "overspeed", "compliant", "offRoute", "rerouted"] {
            guard events.contains(required) else { fatalError("Missing simulation event: \(required)") }
        }
        guard events.filter({ $0 == "overspeed" }).count >= 2 else { fatalError("No persistent overspeed reminder") }
        guard !events.contains("faster"), events.filter({ $0 == "slower" }).count == 1 else {
            fatalError("Frequent limit changes bypassed the quiet period")
        }
        // Immediate instructions must remain factual and suppress secondary speech.
        var turns = CarVoiceGuidance()
        let maneuver = Maneuver(instruction: "Rechts abbiegen", distance: 0, coordinateIndex: 4, type: 1)
        let progress = RouteProgress(traveled: 30, remaining: 100, distanceFromRoute: 0, nextManeuver: maneuver, distanceToManeuver: 15, snappedPosition: points[3])
        guard turns.announcement(progress: progress, speed: 10, following: nil, now: 2000)?.hasPrefix("Jetzt:") == true else { fatalError("Immediate turn missing") }
        var inactive = CarSpeedGuidance()
        for second in 0...15 {
            guard inactive.update(route: route, progress: progress, speed: 30, timestamp: Double(second), now: Double(second), active: false) == nil else { fatalError("Spoken while paused") }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(moments).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        print("101 simulierte Sekunden, \(Int(traveled)) m, \(events.count) Ansagen; echte Pi-Texte, Rolle bleibt geheim.")
        print("Geprüft: Vorwarnung, gedrosselte Limitwechsel, wiederholte Überschreitung, Tempo angepasst, Abweichung, Rückkehr, Abbiegepriorität, Pause.")
    }
}
