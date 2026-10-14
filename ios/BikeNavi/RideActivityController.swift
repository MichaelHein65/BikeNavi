import ActivityKit
import Foundation

@MainActor
final class RideActivityController {
    var marinePresentation = false
    var carPresentation = false
    var carLookAhead = 500.0
    var carGPSDate: Date?
    private var activity: Activity<RideActivityAttributes>?
    private var lastState: RideActivityAttributes.ContentState?

    func start(tourName: String, route: CalculatedRoute?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        Task {
            for old in Activity<RideActivityAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }
            let state = RideActivityAttributes.ContentState(
                instruction: marinePresentation ? "Deine Spur auf See wird aufgezeichnet" : route == nil ? "Dein Weg wird aufgezeichnet" : "Position auf der Route wird ermittelt",
                distanceMeters: 0,
                remainingMeters: 0,
                symbol: marinePresentation ? "sailboat.fill" : carPresentation ? "car.fill" : "location.north.fill",
                status: marinePresentation ? "Auf See" : carPresentation ? "Autofahrt" : route == nil ? "Freie Fahrt" : "Navigation läuft",
                carNavigation: carPresentation ? true : nil
            )
            do {
                activity = try Activity.request(
                    attributes: RideActivityAttributes(tourName: tourName),
                    content: ActivityContent(state: state, staleDate: carPresentation ? Date().addingTimeInterval(5) : nil),
                    pushType: nil
                )
                lastState = state
            } catch {
                // Navigation and recording must continue even if Live Activities
                // are disabled or temporarily unavailable.
            }
        }
    }

    func restore(tourName: String, route: CalculatedRoute?, paused: Bool) {
        activity = Activity<RideActivityAttributes>.activities.first
        guard activity != nil else { return }
        update(progress: nil, route: route, paused: paused, rerouting: false)
    }

    func update(progress: RouteProgress?, route: CalculatedRoute?, headingDegrees: Double? = nil,
                paused: Bool, rerouting: Bool) {
        guard let activity = activity ?? Activity<RideActivityAttributes>.activities.first else { return }
        self.activity = activity
        var state: RideActivityAttributes.ContentState
        if paused {
            state = .init(instruction: "Fahrt pausiert", distanceMeters: 0,
                          remainingMeters: rounded(progress?.remaining ?? 0), symbol: "pause.fill", status: "Pause")
        } else if marinePresentation {
            state = .init(instruction: "Deine Spur auf See wird aufgezeichnet", distanceMeters: 0,
                          remainingMeters: 0, symbol: "sailboat.fill", status: "Auf See")
        } else if route == nil {
            state = .init(instruction: "Dein Weg wird aufgezeichnet", distanceMeters: 0,
                          remainingMeters: 0, symbol: "location.north.fill", status: "Freie Fahrt")
        } else if rerouting {
            state = .init(instruction: "Route wird angepasst", distanceMeters: 0,
                          remainingMeters: rounded(progress?.remaining ?? 0), symbol: "arrow.triangle.2.circlepath", status: "Neue Route")
        } else if let progress, let maneuver = progress.nextManeuver {
            state = .init(instruction: String(maneuver.instruction.prefix(220)),
                          distanceMeters: rounded(progress.distanceToManeuver),
                          remainingMeters: rounded(progress.remaining),
                          symbol: maneuver.symbol, status: "Nächster Abbieger")
        } else if let progress {
            state = .init(instruction: "Folge der Route bis zum Ziel", distanceMeters: 0,
                          remainingMeters: rounded(progress.remaining), symbol: "flag.checkered", status: "Dem Ziel entgegen")
        } else {
            state = .init(instruction: "Position auf der Route wird ermittelt", distanceMeters: 0,
                          remainingMeters: 0, symbol: "location.north.fill", status: "Navigation läuft")
        }
        state.carNavigation = carPresentation ? true : nil
        if carPresentation, let progress, progress.distanceFromRoute > 35, !paused, !rerouting {
            state = .init(instruction: "Gespeicherte Karte prüfen · Pkw-Neuberechnung benötigt Internet und Pi", distanceMeters: 0,
                remainingMeters: rounded(progress.remaining), symbol: "car.fill", status: "Route verlassen", carNavigation: true)
        }
        if !marinePresentation, var diagramProgress = progress, let route, !carPresentation || diagramProgress.distanceFromRoute <= 35 {
            // Quantization keeps the diagram stable and avoids unnecessary
            // ActivityKit updates for every individual GPS meter.
            diagramProgress.traveled = (diagramProgress.traveled / 15).rounded(.down) * 15
            let diagramHeading = headingDegrees.map { ($0 / 10).rounded() * 10 }
            if let preview = NavigationPreviewBuilder.make(route: route, progress: diagramProgress,
                                                           headingDegrees: diagramHeading, lookAhead: carPresentation ? carLookAhead : 350) {
                state.routePoints = preview.points.map { .init(x: $0.x, y: $0.y, surface: $0.surface) }
                state.currentPointIndex = preview.currentPointIndex
                state.maneuverPointIndex = preview.maneuverPointIndex
                // Eight nearby ways preserve even complex intersections while
                // keeping the complete ActivityKit state safely below 4 KB.
                state.sideRoads = preview.roads.prefix(8).map { road in
                    RideActivityRoad(points: road.points.map { .init(x: $0.x, y: $0.y) }, kind: road.kind)
                }
            }
        }
        guard carPresentation || state != lastState else { return }
        lastState = state
        let staleDate = carPresentation && !paused ? (carGPSDate?.addingTimeInterval(5) ?? Date()) : nil
        Task { await activity.update(ActivityContent(state: state, staleDate: staleDate)) }
    }

    func end() {
        guard let activity = activity ?? Activity<RideActivityAttributes>.activities.first else { return }
        self.activity = nil
        lastState = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func rounded(_ distance: Double) -> Int {
        let step = distance < 100 ? 10.0 : (distance < 500 ? 25.0 : 50.0)
        return Int((max(0, distance) / step).rounded() * step)
    }
}
