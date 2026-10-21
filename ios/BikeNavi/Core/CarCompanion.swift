import Foundation

enum CarSpeechEvent: String, Codable {
    case offRoad, navigation, slower, overspeed, faster, compliant, offRoute, rerouted, rerouteFailed, arrived
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

/// Shared across events and repertoires; persisted by the app after speech is queued.
struct CarCharacterSpeechHistory: Codable {
    private var spoken: [String: Double] = [:]

    mutating func decorate(_ instruction: String, pack: CarCharacterPack, event: CarSpeechEvent, now: Double) -> String {
        guard now.isFinite else { return instruction }
        // A clock moving backwards must not immediately unlock repeated comments.
        spoken = spoken.filter { now - $0.value < 30 * 60 }
        guard spoken.values.allSatisfy({ now - $0 >= 180 }) else { return instruction }
        for (index, aside) in (pack.phrases[event.rawValue] ?? []).enumerated() {
            let key = aside.lowercased().filter { $0.isLetter || $0.isNumber }
            guard !key.isEmpty, spoken[key] == nil else { continue }
            let decorated = pack.decorate(instruction, event: event, variant: index)
            guard decorated != instruction else { continue }
            spoken[key] = now
            return decorated
        }
        return instruction
    }
}

struct CarSpeechNotice: Equatable {
    var event: CarSpeechEvent
    var text: String
}

/// Independent one-shot phases; commentary throttling is handled by the speech history.
struct CarSpeedGuidance {
    private var limit: Double?
    private var lastTime: Double?
    private var lastTraveled: Double?
    private var overSince: Double?
    private var limitStart = 0.0
    private var warningDistance = 200.0
    private var warned = false
    private var previews: Set<String> = []
    private var offRoad = false
    private var offRoadPending = false
    private var transition: (notice: CarSpeechNotice, expires: Double)?

    /// A traffic refresh starts its geometry at the current position. Keep distance
    /// since the existing limit and the already spoken phases across that refresh.
    mutating func rebase(oldProgress: Double, newProgress: Double) {
        limitStart += newProgress - oldProgress
        lastTraveled = newProgress
    }

    mutating func update(route: CalculatedRoute, progress: RouteProgress?, speed: Double,
                         timestamp: Double, now: Double, active: Bool, canSpeak: Bool = true,
                         lastAnnouncement: Double = -.infinity) -> CarSpeechNotice? {
        guard active, timestamp.isFinite, now.isFinite, abs(now - timestamp) < 5,
              speed.isFinite, speed >= 0, let progress, progress.traveled.isFinite,
              progress.snappedPosition != nil, progress.distanceFromRoute <= 25 else {
            lastTime = nil; overSince = nil; transition = nil
            return nil
        }
        guard lastTime.map({ timestamp > $0 }) ?? true else { return nil }
        let continuous = lastTime.map { timestamp - $0 < 5 } ?? false
        if !continuous { overSince = nil; transition = nil }
        lastTime = timestamp
        defer { lastTraveled = progress.traveled }
        let environment = CarNavigation.environment(route: route, progress: progress)
        if environment == .offRoad {
            if !offRoad { offRoadPending = true }
            offRoad = true; limit = nil; overSince = nil; transition = nil
            if canSpeak && offRoadPending {
                offRoadPending = false
                return .init(event: .offRoad, text: "Wir sind jetzt Off-Road unterwegs.")
            }
            return nil
        }
        offRoad = false; offRoadPending = false
        guard let environment else { limit = nil; overSince = nil; transition = nil; return nil }
        guard let current = CarNavigation.speedLimit(route: route, progress: progress, active: active) else {
            limit = nil; overSince = nil; transition = nil
            // On divided roads a known upcoming restriction also matters when
            // the current limit is absent (e.g. an unrestricted motorway).
            // Do not claim that the current road is legally unrestricted.
            guard environment == .divided, canSpeak else { return nil }
            let distances = LocalRouteMetrics.distances(route)
            if let next = (route.carSpeedLimits ?? []).sorted(by: { $0.startIndex < $1.startIndex }).first(where: {
                $0.startIndex >= 0 && $0.endIndex < distances.count && $0.endIndex > $0.startIndex
                    && distances[$0.startIndex] > progress.traveled
            }), next.kilometersPerHour < speed * 3.6 {
                return preview(next, route: route, progress: progress, environment: environment, speed: speed)
            }
            return nil
        }
        let distances = LocalRouteMetrics.distances(route)
        let sections = (route.carSpeedLimits ?? []).sorted { $0.startIndex < $1.startIndex }
        guard let index = sections.firstIndex(where: {
            $0.startIndex >= 0 && $0.endIndex < distances.count && $0.endIndex > $0.startIndex
                && progress.traveled >= distances[$0.startIndex] && progress.traveled < distances[$0.endIndex]
        }) else { return nil }
        if limit != current {
            let crossed = lastTraveled.map { $0 < distances[sections[index].startIndex] } ?? false
            if continuous, limit != nil || crossed {
                let higher = limit.map { current > $0 } ?? false
                transition = (.init(event: higher ? .faster : .slower,
                    text: higher ? "Ab hier sind bis zu \(Int(current)) Kilometer pro Stunde erlaubt." : "Ab hier gilt Tempo \(Int(current))."), now + 15)
            }
            // Equal adjacent sections belong to the same limit, including provider splits.
            var first = index
            while first > 0, sections[first - 1].endIndex == sections[first].startIndex,
                  sections[first - 1].kilometersPerHour == current { first -= 1 }
            limitStart = distances[sections[first].startIndex]
            warningDistance = environment.overspeedDistance
            limit = current; overSince = nil; warned = false
        }
        if transition.map({ now > $0.expires }) == true { transition = nil }
        let kph = speed * 3.6
        // Measurement margin and two fresh seconds reject isolated GPS spikes.
        if kph > current + 3 {
            if overSince == nil { overSince = timestamp }
        } else { overSince = nil }
        guard canSpeak else { return nil }
        if let pending = transition {
            transition = nil
            return pending.notice
        }
        if !warned, progress.traveled - limitStart >= warningDistance,
           let since = overSince, timestamp - since >= 2 {
            warned = true
            return .init(event: .overspeed, text: "Du fährst zu schnell, bitte auf höchstens \(Int(current)) Kilometer pro Stunde reduzieren!")
        }
        // Preview only the next different, contiguous known limit. Never look
        // through missing limits or into an off-road/unknown road environment.
        var end = sections[index].endIndex
        for section in sections.dropFirst(index + 1) {
            guard section.startIndex == end, section.endIndex > end, section.endIndex < distances.count,
                  section.kilometersPerHour.isFinite, section.kilometersPerHour > 0, section.kilometersPerHour <= 300 else { break }
            end = section.endIndex
            if section.kilometersPerHour == current { continue }
            if section.kilometersPerHour < current {
                return preview(section, route: route, progress: progress, environment: environment, speed: speed)
            }
            break
        }
        return nil
    }

    private mutating func preview(_ section: CarSpeedLimit, route: CalculatedRoute, progress: RouteProgress,
                                  environment: CarRoadEnvironment, speed: Double) -> CarSpeechNotice? {
        let distances = LocalRouteMetrics.distances(route)
        let target = section.kilometersPerHour
        guard target.isFinite, target > 0, target <= 300 else { return nil }
        let boundary = distances[section.startIndex]
        let gap = boundary - progress.traveled
        // Every metre to the restriction must have known road context, with no off-road detour.
        var covered = progress.traveled
        for road in route.carRoadSections ?? [] {
            guard road.startIndex >= 0, road.endIndex > road.startIndex, road.endIndex < distances.count else { return nil }
            let start = distances[road.startIndex], end = distances[road.endIndex]
            if end <= covered { continue }
            guard start <= covered, road.environment != .offRoad else { return nil }
            covered = end
            if covered > boundary { break }
        }
        guard covered > boundary, gap > 0, gap <= environment.previewDistance(speed: speed, targetKPH: target) else { return nil }
        let point = route.coordinates[section.startIndex]
        let key = "\(point.latitude),\(point.longitude),\(target)"
        guard !previews.contains(key) else { return nil }
        previews.insert(key)
        return .init(event: .slower, text: "In \(max(10, Int((gap / 10).rounded()) * 10)) Metern gilt Tempo \(Int(target)), bitte rechtzeitig langsamer werden.")
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
