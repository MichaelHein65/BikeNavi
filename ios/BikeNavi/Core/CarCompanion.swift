import Foundation

enum CarSpeechEvent: String, Codable {
    case navigation, slower, overspeed, faster, compliant, offRoute, rerouted, rerouteFailed, arrived
}

struct CarCharacterPack: Codable {
    var characterID: String
    var source: String
    var phrases: [String: [String]]

    func decorate(_ instruction: String, event: CarSpeechEvent, variant: Int) -> String {
        // Two factual sentences (e.g. close successive turns) already fill the budget.
        guard instruction.count <= 150, instruction.filter({ ".!?".contains($0) }).count <= 1,
              !instruction.contains("Danach"), let choices = phrases[event.rawValue], !choices.isEmpty else { return instruction }
        let aside = choices[abs(variant % choices.count)]
        guard aside.count <= 100, aside.split(separator: " ").count <= 16,
              aside.filter({ ".!?".contains($0) }).count == 1,
              aside.last.map({ ".!".contains($0) }) == true,
              !aside.contains(where: { $0.isNumber || $0.isNewline }) else { return instruction }
        return instruction + (instruction.last.map { ".!?".contains($0) } == true ? " " : ". ") + aside
    }
}

struct CarSpeechNotice: Equatable {
    var event: CarSpeechEvent
    var text: String
}

/// Time-based observations use only fresh, accurately matched car fixes.
/// Character generation is never in the real-time path.
struct CarSpeedGuidance {
    private var limit: Double?
    private var lastTime: Double?
    private var overSince: Double?
    private var overStartSpeed = 0.0
    private var lastWarning = -Double.infinity
    private var warned = false
    private var previewKey: String?
    private var lastSpoken = -Double.infinity
    private var transition: (notice: CarSpeechNotice, expires: Double)?

    mutating func update(route: CalculatedRoute, progress: RouteProgress?, speed: Double,
                         timestamp: Double, now: Double, active: Bool, canSpeak: Bool = true) -> CarSpeechNotice? {
        guard active, timestamp.isFinite, now.isFinite, abs(now - timestamp) < 5,
              speed.isFinite, speed >= 0,
              let current = CarNavigation.speedLimit(route: route, progress: progress, active: active), let progress else {
            self = CarSpeedGuidance(); return nil
        }
        guard lastTime.map({ timestamp > $0 }) ?? true else { return nil }
        if let lastTime, timestamp - lastTime >= 5 {
            overSince = nil; limit = nil; transition = nil; warned = false
        }
        lastTime = timestamp
        let kph = speed * 3.6
        if limit != current {
            if let previous = limit {
                if current > previous {
                    transition = (.init(event: .faster, text: "Hier sind bis zu \(Int(current)) Kilometer pro Stunde erlaubt, sofern die Bedingungen passen."), now + 15)
                } else {
                    transition = (.init(event: .slower, text: "Ab hier gilt Tempo \(Int(current))."), now + 15)
                }
            }
            limit = current; overSince = nil; warned = false; lastWarning = -.infinity
        }
        if transition.map({ now > $0.expires }) == true { transition = nil }
        if kph > current, transition?.notice.event == .compliant { transition = nil }
        // A measurement margin avoids GPS chatter; it is not a legal allowance.
        if kph > current + 3 {
            if overSince == nil { overSince = timestamp; overStartSpeed = kph }
        } else {
            if warned && kph <= current {
                transition = (.init(event: .compliant, text: "Tempo angepasst, danke."), now + 10)
                warned = false
            }
            overSince = nil
        }
        guard canSpeak, now - lastSpoken >= 8 else { return nil }
        // A clear deceleration grants a few seconds, never indefinite suppression.
        if let since = overSince, timestamp - since >= 6,
           (overStartSpeed - kph < 4 || timestamp - since >= 12), now - lastWarning >= 25 {
            lastWarning = now; lastSpoken = now; warned = true; transition = nil
            return .init(event: .overspeed, text: "Du fährst weiterhin zu schnell, bitte auf höchstens \(Int(current)) Kilometer pro Stunde reduzieren!")
        }
        if let pending = transition {
            transition = nil; lastSpoken = now
            return pending.notice
        }
        let distances = LocalRouteMetrics.distances(route)
        let sections = (route.carSpeedLimits ?? []).sorted { $0.startIndex < $1.startIndex }
        // Follow only a continuous run of known limits. Never bridge unknown stretches.
        if let currentIndex = sections.firstIndex(where: {
            $0.startIndex >= 0 && $0.endIndex < distances.count && $0.endIndex > $0.startIndex
                && progress.traveled >= distances[$0.startIndex] && progress.traveled < distances[$0.endIndex]
        }) {
            var end = sections[currentIndex].endIndex
            for section in sections.dropFirst(currentIndex + 1) {
                guard section.startIndex == end, section.endIndex > end, section.endIndex < distances.count,
                      section.kilometersPerHour.isFinite, section.kilometersPerHour > 0, section.kilometersPerHour <= 300 else { break }
                end = section.endIndex
                if section.kilometersPerHour == current { continue }
                let gap = distances[section.startIndex] - progress.traveled
                let target = section.kilometersPerHour
                let point = route.coordinates[section.startIndex]
                let key = "\(point.latitude),\(point.longitude),\(target)"
                if target < current, gap > 0, gap <= min(600, max(120, speed * 15)), key != previewKey {
                    previewKey = key; lastSpoken = now
                    return .init(event: .slower, text: "In \(max(10, Int((gap / 10).rounded()) * 10)) Metern gilt Tempo \(Int(target)), bitte rechtzeitig langsamer werden.")
                }
                break
            }
        }
        return nil
    }
}

struct CarDeviationGuidance {
    private var offRoute = false
    private var lastSpoken = -Double.infinity
    mutating func observe(confirmed: Bool, onRoute: Bool, now: Double) -> CarSpeechNotice? {
        if onRoute {
            defer { offRoute = false }
            if offRoute, now - lastSpoken >= 8 {
                lastSpoken = now
                return .init(event: .rerouted, text: "Du bist wieder auf der Route.")
            }
        }
        if confirmed, now - lastSpoken >= 45 {
            offRoute = true; lastSpoken = now
            return .init(event: .offRoute, text: "Du hast die Route verlassen.")
        }
        return nil
    }
}

extension APIClient {
    func carCharacter(previousID: String?) async throws -> CarCharacterPack {
        struct Request: Encodable { var previousID: String? }
        return try await request("/v1/car/character", method: "POST",
                                 body: JSONEncoder().encode(Request(previousID: previousID)), timeout: 35)
    }
}
