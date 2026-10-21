import XCTest
@testable import BikeNaviCore

final class CarCompanionTests: XCTestCase {
    private func fixture(_ environment: CarRoadEnvironment = .rural) -> (CalculatedRoute, RouteProgress) {
        let points = (0...40).map { Coordinate(latitude: 49 + Double($0) * 0.001, longitude: 8) }
        let route = CalculatedRoute(id: UUID(), coordinates: points, distance: 4448, duration: 300, ascent: 0, descent: 0,
            maneuvers: [], surfaces: [], warnings: [], provider: "Synthetisches öffentliches Beispiel", calculatedAt: 0,
            carSpeedLimits: [.init(startIndex: 0, endIndex: 20, kilometersPerHour: 130),
                             .init(startIndex: 20, endIndex: 30, kilometersPerHour: 80),
                             .init(startIndex: 30, endIndex: 40, kilometersPerHour: 100)],
            carRoadSections: [.init(startIndex: 0, endIndex: 40, environment: environment)])
        let p = RouteProgress(traveled: 0, remaining: 4448, distanceFromRoute: 0, nextManeuver: nil,
                              distanceToManeuver: 999, snappedPosition: points[0])
        return (route, p)
    }

    func testEnvironmentPreviewThresholdsAndIndependentBoundaryNotice() {
        for (environment, threshold) in [(CarRoadEnvironment.urban, 100.0), (.rural, 500.0), (.divided, 1030.8641975308642)] {
            let (route, original) = fixture(environment); var p = original; var guidance = CarSpeedGuidance()
            let boundary = LocalRouteMetrics.distances(route)[20]
            p.traveled = boundary - threshold - 1
            XCTAssertNil(guidance.update(route: route, progress: p, speed: 200 / 3.6, timestamp: 100, now: 100, active: true))
            p.traveled += 2
            let preview = guidance.update(route: route, progress: p, speed: 200 / 3.6, timestamp: 101, now: 101, active: true, lastAnnouncement: 100)
            XCTAssertEqual(preview?.event, .slower)
            p.traveled = boundary
            let atSign = guidance.update(route: route, progress: p, speed: 80 / 3.6, timestamp: 102, now: 102, active: true)
            XCTAssertEqual(atSign?.text, "Ab hier gilt Tempo 80.")
            XCTAssertNil(guidance.update(route: route, progress: p, speed: 80 / 3.6, timestamp: 103, now: 103, active: true))
        }
    }

    func testDividedRoadWithUnknownCurrentLimitStillPreviewsKnownRestriction() {
        var (route, p) = fixture(.divided); var guidance = CarSpeedGuidance()
        route.carSpeedLimits?.removeFirst()
        let boundary = LocalRouteMetrics.distances(route)[20]
        p.traveled = boundary - 1030
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 200 / 3.6, timestamp: 100, now: 100, active: true)?.event, .slower)
        XCTAssertNil(CarNavigation.speedLimit(route: route, progress: p, active: true))
        p.traveled = boundary
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 25, timestamp: 101, now: 101, active: true)?.text, "Ab hier gilt Tempo 80.")
    }

    func testPreviewNeverCrossesOffRoadOrMissingRoadContext() {
        for context in [CarRoadEnvironment.offRoad, .rural] {
            var (route, p) = fixture(.divided); var guidance = CarSpeedGuidance()
            route.carRoadSections = [.init(startIndex: 0, endIndex: 18, environment: .divided),
                                     .init(startIndex: context == .offRoad ? 18 : 19, endIndex: 40, environment: context)]
            p.traveled = LocalRouteMetrics.distances(route)[20] - 500
            XCTAssertNil(guidance.update(route: route, progress: p, speed: 200 / 3.6, timestamp: 100, now: 100, active: true))
        }
    }

    func testEqualLimitProviderSplitDoesNotRestartDistanceOrSpeech() {
        var (route, p) = fixture(.urban); var guidance = CarSpeedGuidance()
        route.carSpeedLimits = [.init(startIndex: 0, endIndex: 1, kilometersPerHour: 50),
                               .init(startIndex: 1, endIndex: 40, kilometersPerHour: 50)]
        p.traveled = 99
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true))
        p.traveled = 120
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 102, now: 102, active: true)?.event, .overspeed)
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 103, now: 103, active: true))
    }

    func testRoadContextSurvivesArchiveRoundTrip() throws {
        let (route, _) = fixture(.divided)
        let data = try JSONEncoder().encode(route)
        XCTAssertEqual(try JSONDecoder().decode(CalculatedRoute.self, from: data), route)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "carRoadSections")
        XCTAssertNil(try JSONDecoder().decode(CalculatedRoute.self, from: JSONSerialization.data(withJSONObject: json)).carRoadSections)
    }

    func testDividedPreviewUsesActualSpeedAndTarget() {
        XCTAssertEqual(CarRoadEnvironment.divided.previewDistance(speed: 200 / 3.6, targetKPH: 80), 1030.8641975308642, accuracy: 0.001)
        XCTAssertLessThan(CarRoadEnvironment.divided.previewDistance(speed: 120 / 3.6, targetKPH: 80), 500)
        XCTAssertGreaterThan(CarRoadEnvironment.divided.previewDistance(speed: 200 / 3.6, targetKPH: 50),
                             CarRoadEnvironment.divided.previewDistance(speed: 200 / 3.6, targetKPH: 80))
    }

    func testOverspeedOccursOnlyAfterEnvironmentDistanceAndOnlyOnce() {
        for environment in [CarRoadEnvironment.urban, .rural, .divided] {
            let (route, original) = fixture(environment); var p = original; var guidance = CarSpeedGuidance()
            let boundary = LocalRouteMetrics.distances(route)[20]
            p.traveled = boundary - 1
            _ = guidance.update(route: route, progress: p, speed: 25, timestamp: 100, now: 100, active: true)
            p.traveled = boundary
            XCTAssertEqual(guidance.update(route: route, progress: p, speed: 25, timestamp: 101, now: 101, active: true)?.event, .slower)
            p.traveled = boundary + environment.overspeedDistance - 1
            for t in 102...110 { XCTAssertNil(guidance.update(route: route, progress: p, speed: 25, timestamp: Double(t), now: Double(t), active: true)) }
            p.traveled += 1
            XCTAssertEqual(guidance.update(route: route, progress: p, speed: 25, timestamp: 111, now: 111, active: true)?.event, .overspeed)
            for t in 112...180 { XCTAssertNil(guidance.update(route: route, progress: p, speed: 25, timestamp: Double(t), now: Double(t), active: true)) }
        }
    }

    func testHigherLimitHasOneShortNoticeWithoutPreview() {
        let (route, original) = fixture(); var p = original; var guidance = CarSpeedGuidance()
        p.traveled = LocalRouteMetrics.distances(route)[30] - 1
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true))
        p.traveled += 1
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 101, now: 101, active: true)?.text,
                       "Ab hier sind bis zu 100 Kilometer pro Stunde erlaubt.")
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 102, now: 102, active: true))
    }

    func testOffRoadAnnouncesOnceWithoutLimitAndDefersForTurn() {
        var (route, p) = fixture(.offRoad); route.carSpeedLimits = nil
        var guidance = CarSpeedGuidance()
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true, canSpeak: false))
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 101, now: 101, active: true)?.event, .offRoad)
        route.carSpeedLimits = [.init(startIndex: 0, endIndex: 40, kilometersPerHour: 30)]
        for t in 102...110 { XCTAssertNil(guidance.update(route: route, progress: p, speed: 60, timestamp: Double(t), now: Double(t), active: true)) }
        XCTAssertNil(guidance.update(route: route, progress: nil, speed: 20, timestamp: 111, now: 111, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 112, now: 112, active: true))
        route.carRoadSections?[0].environment = .urban
        _ = guidance.update(route: route, progress: p, speed: 20, timestamp: 113, now: 113, active: true)
        route.carRoadSections?[0].environment = .offRoad
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 114, now: 114, active: true)?.event, .offRoad)
    }

    func testMissingContextOrLimitsAndUnmatchedOrStaleFixesStaySilent() {
        let (route, original) = fixture(); var p = original; var guidance = CarSpeedGuidance()
        p.traveled = LocalRouteMetrics.distances(route)[20] - 100
        var unknown = route; unknown.carRoadSections = nil
        XCTAssertNil(guidance.update(route: unknown, progress: p, speed: 20, timestamp: 100, now: 100, active: true))
        unknown = route; unknown.carSpeedLimits = nil
        XCTAssertNil(guidance.update(route: unknown, progress: p, speed: 20, timestamp: 101, now: 101, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 102, now: 108, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 103, now: 103, active: false))
        p.snappedPosition = nil
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 104, now: 104, active: true))
        p.snappedPosition = route.coordinates[0]; p.distanceFromRoute = 26
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 105, now: 105, active: true))
    }

    func testMissingLimitIsNotBridgedAndPreviewSurvivesGPSGap() {
        var (route, p) = fixture(); var guidance = CarSpeedGuidance()
        p.traveled = LocalRouteMetrics.distances(route)[20] - 100
        route.carSpeedLimits?[1].startIndex = 21
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true))
        route.carSpeedLimits?[1].startIndex = 20
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 20, timestamp: 101, now: 101, active: true)?.event, .slower)
        XCTAssertNil(guidance.update(route: route, progress: nil, speed: 20, timestamp: 102, now: 102, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 110, now: 110, active: true))
    }

    func testDeferredBoundaryExpiresAndOverspeedRequiresFreshSustainedSpeed() {
        let (route, original) = fixture(); var p = original; var guidance = CarSpeedGuidance()
        p.traveled = LocalRouteMetrics.distances(route)[20] - 1
        _ = guidance.update(route: route, progress: p, speed: 20, timestamp: 100, now: 100, active: true)
        p.traveled += 1
        for t in 101...118 { XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: Double(t), now: Double(t), active: true, canSpeak: false)) }
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 119, now: 119, active: true))
        p.traveled += 200
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 120, now: 120, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 120, now: 120, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 20, timestamp: 121, now: 121, active: true))
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 30, timestamp: 122, now: 122, active: true))
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 30, timestamp: 124, now: 124, active: true)?.event, .overspeed)
    }

    func testTrafficRefreshPreservesDistanceAndWarnedState() {
        var (route, p) = fixture(); var guidance = CarSpeedGuidance()
        let boundary = LocalRouteMetrics.distances(route)[20]
        p.traveled = boundary + 150
        _ = guidance.update(route: route, progress: p, speed: 25, timestamp: 100, now: 100, active: true)
        guidance.rebase(oldProgress: p.traveled, newProgress: 0)
        route.coordinates = Array(route.coordinates[20...]); route.carSpeedLimits = [.init(startIndex: 0, endIndex: 20, kilometersPerHour: 80)]
        route.carRoadSections = [.init(startIndex: 0, endIndex: 20, environment: .rural)]
        p.traveled = 49
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 25, timestamp: 102, now: 102, active: true))
        p.traveled = 50
        XCTAssertEqual(guidance.update(route: route, progress: p, speed: 25, timestamp: 103, now: 103, active: true)?.event, .overspeed)
        guidance.rebase(oldProgress: p.traveled, newProgress: 0); p.traveled = 300
        XCTAssertNil(guidance.update(route: route, progress: p, speed: 25, timestamp: 104, now: 104, active: true))
    }

    func testCharacterUsesUnusedVariantsAndSuppressesDuplicatesAcrossEventsAndPacks() throws {
        var history = CarCharacterSpeechHistory()
        let pack = CarCharacterPack(characterID: "hidden", source: "test", phrases: ["navigation": ["Erster Kommentar.", "Zweiter Kommentar.", "Dritter Kommentar."]])
        let fact = "Geradeaus weiter."
        for (offset, expected) in pack.phrases["navigation"]!.enumerated() {
            XCTAssertEqual(history.decorate(fact, pack: pack, event: .navigation, now: 100 + Double(offset) * 180), fact + " " + expected)
        }
        XCTAssertEqual(history.decorate(fact, pack: pack, event: .navigation, now: 104), fact)
        var restored = try JSONDecoder().decode(CarCharacterSpeechHistory.self, from: JSONEncoder().encode(history))
        let replacement = CarCharacterPack(characterID: "another", source: "template", phrases: ["slower": ["ERSTER Kommentar!", "Neuer Kommentar."]])
        XCTAssertEqual(restored.decorate(fact, pack: replacement, event: .slower, now: 640), fact + " Neuer Kommentar.")
        XCTAssertEqual(restored.decorate(fact, pack: replacement, event: .slower, now: 820), fact)
        XCTAssertEqual(restored.decorate(fact, pack: pack, event: .navigation, now: 1899), fact)
        XCTAssertEqual(restored.decorate(fact, pack: pack, event: .navigation, now: 1900), fact + " Erster Kommentar.")
    }
    func testSuppressedOrInvalidAsideDoesNotConsumeValidVariantAndClockRollbackDoesNotRepeat() {
        var history = CarCharacterSpeechHistory()
        let pack = CarCharacterPack(characterID: "hidden", source: "test", phrases: ["navigation": ["Noch 50 Meter.", "Ein Kommentar."]])
        let twoSentences = "Jetzt rechts. Danach links."
        XCTAssertEqual(history.decorate(twoSentences, pack: pack, event: .navigation, now: 100), twoSentences)
        XCTAssertEqual(history.decorate("Geradeaus.", pack: pack, event: .navigation, now: 101), "Geradeaus. Ein Kommentar.")
        XCTAssertEqual(history.decorate("Geradeaus.", pack: pack, event: .navigation, now: 99), "Geradeaus.")
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
