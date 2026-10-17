import XCTest
@testable import BikeNaviCore

final class CarCompanionTests: XCTestCase {
    private func fixture() -> (CalculatedRoute, RouteProgress) {
        let points = (0...10).map { Coordinate(latitude: 49 + Double($0) * 0.001, longitude: 8) }
        let route = CalculatedRoute(id: UUID(), coordinates: points, distance: 1112, duration: 100, ascent: 0, descent: 0,
            maneuvers: [], surfaces: [], warnings: [], provider: "Synthetisches öffentliches Beispiel", calculatedAt: 0,
            carSpeedLimits: [.init(startIndex: 0, endIndex: 4, kilometersPerHour: 80),
                             .init(startIndex: 4, endIndex: 7, kilometersPerHour: 50),
                             .init(startIndex: 7, endIndex: 10, kilometersPerHour: 100)])
        var p = RouteProgress(traveled: 300, remaining: 812, distanceFromRoute: 0, nextManeuver: nil, distanceToManeuver: 999)
        p.snappedPosition = points[3]
        return (route, p)
    }
    func testPreviewReductionAndHigherLimitAtBoundaryOnly() {
        let (route, p) = fixture(); var guidance = CarSpeedGuidance()
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true)?.event, .slower)
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 101, now: 101, active: true))
        var later = p; later.traveled = LocalRouteMetrics.distances(route)[4]
        for time in 102...110 { _ = guidance.update(route: route, progress: later, speed: 13, timestamp: Double(time), now: Double(time), active: true) }
        later.traveled = LocalRouteMetrics.distances(route)[7] - 1
        XCTAssertNil(guidance.update(route: route, progress: later, speed: 13, timestamp: 111, now: 111, active: true))
        later.traveled += 1
        XCTAssertNil(guidance.update(route: route, progress: later, speed: 13, timestamp: 112, now: 112, active: true, canSpeak: false))
        for time in 113...115 { _ = guidance.update(route: route, progress: later, speed: 13, timestamp: Double(time), now: Double(time), active: true, canSpeak: false) }
        XCTAssertEqual(guidance.update(route: route, progress: later, speed: 13, timestamp: 116, now: 116, active: true)?.event, .faster)
    }
    func testPersistentOverspeedEscalatesAndAcknowledgesCompliance() {
        let (route, original) = fixture(); var p = original; p.traveled = 500
        var guidance = CarSpeedGuidance()
        for t in 100...105 { XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: Double(t), now: Double(t), active: true)) }
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 106, now: 106, active: true)?.event, .overspeed)
        for t in 107...130 { XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: Double(t), now: Double(t), active: true)) }
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 131, now: 131, active: true)?.event, .overspeed)
        for t in 132...138 { XCTAssertNil(guidance.update(route: route, progress: p, speed: 13, timestamp: Double(t), now: Double(t), active: true)) }
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 13, timestamp: 139, now: 139, active: true)?.event, .compliant)
    }
    func testDeferredComplianceIsCancelledIfSpeedRisesAgain() {
        let (route, original) = fixture(); var p = original; p.traveled = 500
        var guidance = CarSpeedGuidance()
        for t in 100...106 { _ = guidance.update(route: route, progress: p, speed: 20, timestamp: Double(t), now: Double(t), active: true) }
        for t in 107...113 { _ = guidance.update(route: route, progress: p, speed: 13, timestamp: Double(t), now: Double(t), active: true, canSpeak: false) }
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 114, now: 114, active: true))
    }
    func testDecelerationGetsBriefGraceButNoUnlimitedExemption() {
        let (route, original) = fixture(); var p = original; p.traveled = 500
        var guidance = CarSpeedGuidance()
        for t in 100...111 {
            XCTAssertNil(guidance.update(route: route, progress: p, speed: t < 103 ? 25 : 20, timestamp: Double(t), now: Double(t), active: true))
        }
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 112, now: 112, active: true)?.event, .overspeed)
    }
    func testStaleOffRouteInactiveUnknownAndDuplicateSamplesDoNotWarn() {
        let (route, original) = fixture(); var p = original
        var guidance = CarSpeedGuidance()
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 100, now: 106, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 100, now: 100, active: false))
        p.snappedPosition = nil
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 100, now: 100, active: true))
        p = original; p.traveled = 500
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 100, now: 100, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 100, now: 100, active: true))
        var unknown = route; unknown.carSpeedLimits = nil
        XCTAssertNil(guidance.update(route: unknown, progress: p, speed: 30, timestamp: 101, now: 101, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 102, now: 102, active: true))
    }
    func testPreviewDoesNotBridgeMissingLimitAndUrgentTurnsDeferSpeech() {
        var (route, p) = fixture(); var guidance = CarSpeedGuidance()
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true, canSpeak: false))
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 101, now: 101, active: true)?.event, .slower)
        guidance = CarSpeedGuidance(); route.carSpeedLimits?[1].startIndex = 5
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true))
        p.distanceFromRoute = 26
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 101, now: 101, active: true))
    }
    func testCharacterPreservesFactsAndTwoSentenceBudget() {
        let pack = CarCharacterPack(characterID: "hidden", source: "test", phrases: ["slower": ["Meine Schaltkreise seufzen."]])
        XCTAssertEqual(pack.decorate("Ab hier gilt Tempo 50.", event: .slower, variant: 0), "Ab hier gilt Tempo 50. Meine Schaltkreise seufzen.")
        XCTAssertEqual(pack.decorate("Jetzt rechts. Danach links.", event: .slower, variant: 0), "Jetzt rechts. Danach links.")
    }
    func testDeviationHasCooldownAndReturnReaction() {
        var guidance = CarDeviationGuidance()
        XCTAssertNil(guidance.observe(confirmed: false, onRoute: false, now: 100))
        XCTAssertEqual(guidance.observe(confirmed: true, onRoute: false, now: 101)?.event, .offRoute)
        XCTAssertNil(guidance.observe(confirmed: true, onRoute: false, now: 110))
        XCTAssertEqual(guidance.observe(confirmed: true, onRoute: false, now: 146)?.event, .offRoute)
        XCTAssertEqual(guidance.observe(confirmed: false, onRoute: true, now: 155)?.event, .rerouted)
        XCTAssertNil(guidance.observe(confirmed: false, onRoute: true, now: 165))
    }
}
