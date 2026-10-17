import XCTest
import CoreLocation
import UIKit
import AVFoundation
@testable import BikeNavi

private final class CarRouteProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> Data)?
    static var responseDelay: TimeInterval = 0
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "car-test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.handler!(request)
            if Self.responseDelay > 0 { Thread.sleep(forTimeInterval: Self.responseDelay) }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}

private final class TestNavigationAudioRouting: NavigationAudioRouting {
    var usesCarPlay = false
    var handsFreeInputID: String?
    var category: AVAudioSession.Category?
    var options: AVAudioSession.CategoryOptions = []
    var calls: [String] = []
    var failInput = false
    func configure(_ category: AVAudioSession.Category, options: AVAudioSession.CategoryOptions) throws {
        self.category = category; self.options = options; calls.append(category == .playAndRecord ? "phone" : "playback")
    }
    func activate() throws { calls.append("activate") }
    func preferInput(_ identifier: String?) throws {
        calls.append(identifier ?? "clear")
        if failInput && identifier != nil { throw APIError(status: 0, message: "Disconnected") }
    }
    func deactivate() throws { calls.append("deactivate") }
}

final class CarRideTests: XCTestCase {
    func testCarSpeechSelectsPhoneChannelAndReleasesItAfterwards() throws {
        let routing = TestNavigationAudioRouting(); routing.handsFreeInputID = "public-hfp-example"
        let audio = NavigationAudio(routing: routing)
        XCTAssertTrue(try audio.activate(handsFreePreferred: true))
        XCTAssertEqual(routing.calls, ["phone", "activate", "public-hfp-example"])
        XCTAssertTrue(routing.options.contains(.allowBluetoothHFP))
        XCTAssertFalse(routing.options.contains(.allowBluetoothA2DP))
        audio.release()
        XCTAssertEqual(Array(routing.calls.suffix(3)), ["clear", "deactivate", "playback"])
        XCTAssertFalse(audio.active)
    }

    func testCarSpeechPreservesCarPlayAndHandlesMissingOrDisconnectedHFP() throws {
        let carPlay = TestNavigationAudioRouting(); carPlay.usesCarPlay = true; carPlay.handsFreeInputID = "ignored-hfp"
        let audio = NavigationAudio(routing: carPlay)
        XCTAssertFalse(try audio.activate(handsFreePreferred: true))
        XCTAssertEqual(carPlay.calls, ["playback", "activate"])
        audio.release()
        let disconnected = TestNavigationAudioRouting()
        let other = NavigationAudio(routing: disconnected)
        XCTAssertFalse(try other.activate(handsFreePreferred: true))
        XCTAssertEqual(disconnected.category, .playback)
        other.release()
        disconnected.handsFreeInputID = "gone"; disconnected.failInput = true
        XCTAssertThrowsError(try other.activate(handsFreePreferred: true))
        XCTAssertFalse(other.active)
        XCTAssertEqual(Array(disconnected.calls.suffix(2)), ["deactivate", "playback"])
    }

    func testRealAudioSessionAcceptsPhonePromptConfigurationAndReturnsToPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        // Simulator can validate the category/mode contract, not Bluetooth or car wake-up.
        try session.setCategory(.playAndRecord, mode: .voicePrompt, options: [.allowBluetoothHFP, .defaultToSpeaker, .duckOthers, .interruptSpokenAudioAndMixWithOthers])
        XCTAssertEqual(session.category, .playAndRecord)
        XCTAssertEqual(session.mode, .voicePrompt)
        let audio = NavigationAudio()
        _ = try audio.activate(handsFreePreferred: true)
        XCTAssertEqual(session.category, .playback)
        audio.release()
        XCTAssertFalse(audio.active)
    }

    @MainActor
    func testCarGPSDoesNotRequireMovementAndModeChangesRestoreCyclingFilter() {
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        defer { unsetenv("BIKENAVI_START_LOCATION_TEST") }
        let manager = CLLocationManager()
        let location = LocationService(manager: manager)
        location.setRiding(true)
        XCTAssertEqual(manager.distanceFilter, 5)
        location.setCarNavigation(true)
        XCTAssertEqual(manager.distanceFilter, kCLDistanceFilterNone)
        location.setRiding(false); location.setRiding(true); location.setMarineNavigation(false)
        XCTAssertEqual(manager.distanceFilter, kCLDistanceFilterNone)
        location.setCarNavigation(false)
        XCTAssertEqual(manager.distanceFilter, 5)
        location.setMarineNavigation(true)
        XCTAssertEqual(manager.distanceFilter, kCLDistanceFilterNone)
        location.setRiding(false)
    }

    @MainActor
    func testStationaryPOISearchWaitsForRealFreshFixWithoutAddingTrack() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let position = state.plan.route!.coordinates[0]
        fix(state, position: position, timestamp: Date().addingTimeInterval(-6), speed: 0)
        state.startRide()
        let trackCount = state.activeRide?.track.count
        XCTAssertFalse(state.carGPSIsFresh)
        let search = Task { try await state.preparedPOISearch(category: .supermarket, duringRide: true, timeout: 2) }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(state.carGPSIsFresh)
        fix(state, position: position, timestamp: Date(), speed: 0)
        let request = try await search.value
        XCTAssertTrue(state.carGPSIsFresh)
        XCTAssertEqual(request.center.latitude, position.latitude)
        XCTAssertNotNil(request.context)
        XCTAssertNil(state.carHeading)
        XCTAssertEqual(state.activeRide?.track.count, trackCount)
    }

    @MainActor
    func testPOISearchDoesNotInventFixOnTimeoutOrUseItAfterCancellation() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory) }
        let original = state.plan
        do {
            _ = try await state.preparedPOISearch(category: .parking, duringRide: false, timeout: 0)
            XCTFail("A stale location must not be accepted")
        } catch { XCTAssertTrue(error.localizedDescription.contains("GPS")) }
        let search = Task { try await state.preparedPOISearch(category: .parking, duringRide: false) }
        search.cancel()
        do { _ = try await search.value; XCTFail("Cancelled search must not proceed") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(state.plan, original)
        XCTAssertNil(state.activeRide)
        // A marked planning start is independent of GPS.
        let request = try await state.preparedPOISearch(category: .parking, duringRide: false, origin: "start", timeout: 0)
        XCTAssertEqual(request.center.latitude, original.waypoints[0].coordinate.latitude)
    }

    func testNavigationVoicePrefersBestInstalledQualityAndHonorsExplicitChoice() {
        let installed = NavigationVoice.available
        let automatic = NavigationVoice.selected("")
        if let best = installed.first {
            XCTAssertEqual(automatic?.identifier, best.identifier)
            XCTAssertEqual(automatic?.quality.rawValue, installed.map { $0.quality.rawValue }.max())
            XCTAssertEqual(NavigationVoice.selected("removed-voice")?.identifier, best.identifier)
        }
        if let chosen = installed.last {
            XCTAssertEqual(NavigationVoice.selected(chosen.identifier)?.identifier, chosen.identifier)
        }
    }

    func testEddyEloquenceAndNoveltyNeverOverrideNormalSpeech() {
        let voices: [NavigationVoice.Candidate] = [
            .init(identifier: "com.apple.eloquence.de-DE.Eddy", name: "Eddy", quality: 1),
            .init(identifier: "other-eddy", name: "Eddy", quality: 3),
            .init(identifier: "com.apple.eloquence.other", name: "Legacy", quality: 3),
            .init(identifier: "effect", name: "Effekt", quality: 3, novelty: true),
            .init(identifier: "anna", name: "Anna", quality: 3)
        ]
        XCTAssertEqual(NavigationVoice.ranked(voices).map(\.identifier), ["anna"])
        for saved in ["", "com.apple.eloquence.de-DE.Eddy", "effect", "other-eddy"] {
            XCTAssertEqual(NavigationVoice.selectedIdentifier(saved, candidates: voices), "anna")
        }
        XCTAssertNil(NavigationVoice.selectedIdentifier("com.apple.eloquence.de-DE.Eddy", candidates: Array(voices.dropLast())))
    }

    func testOnlyPremiumAndAvailableSiriVoicesRemainAndChoicePersists() {
        let standard = NavigationVoice.Candidate(identifier: "standard", name: "Anna", quality: 1)
        let enhanced = NavigationVoice.Candidate(identifier: "enhanced", name: "Anna", quality: 2)
        let anna = NavigationVoice.Candidate(identifier: "anna-premium", name: "Anna", quality: 3)
        let petra = NavigationVoice.Candidate(identifier: "petra-premium", name: "Petra", quality: 3)
        let siri = NavigationVoice.Candidate(identifier: "com.apple.ttsbundle.siri_female_de-DE", name: "Siri", quality: 1)
        let foreign = NavigationVoice.Candidate(identifier: "foreign", name: "English", language: "en-US", quality: 3)
        let voices = [standard, enhanced, petra, siri, anna, foreign]
        XCTAssertEqual(Set(NavigationVoice.ranked(voices).map(\.identifier)), ["anna-premium", "petra-premium", siri.identifier])
        XCTAssertEqual(NavigationVoice.selectedIdentifier("", candidates: voices), "anna-premium")
        XCTAssertEqual(NavigationVoice.selectedIdentifier("petra-premium", candidates: voices), "petra-premium")
        XCTAssertEqual(NavigationVoice.selectedIdentifier(siri.identifier, candidates: voices), siri.identifier)
        XCTAssertEqual(NavigationVoice.selectedIdentifier("standard", candidates: voices), "anna-premium")
        XCTAssertEqual(NavigationVoice.selectedIdentifier("anna-premium", candidates: [petra, siri]), "petra-premium")
        XCTAssertEqual(NavigationVoice.selectedIdentifier("", candidates: [siri, enhanced]), siri.identifier)
        XCTAssertNil(NavigationVoice.selectedIdentifier("", candidates: [standard, enhanced, foreign]))
    }

    @MainActor
    func testNavigationVoiceChoiceIsRestoredAfterAppStateRestart() throws {
        let saved = UserDefaults.standard.string(forKey: "navigationVoiceID")
        defer { UserDefaults.standard.set(saved, forKey: "navigationVoiceID") }
        let (first, directory) = try state()
        defer { cleanup(directory) }
        first.navigationVoiceID = "explicit-test-choice"
        let restored = AppState(store: first.store)
        XCTAssertEqual(restored.navigationVoiceID, "explicit-test-choice")
        restored.navigationVoiceID = ""
        XCTAssertEqual(UserDefaults.standard.string(forKey: "navigationVoiceID"), "")
    }

    @MainActor
    func testTrafficRefreshKeepsOriginalAndOpenStopsAndThrottles() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let now = Date()
        state.plan.route?.carTraffic = .init(fetchedAt: now.timeIntervalSince1970 - 400, delaySeconds: 0, sections: [])
        let original = state.plan
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-token"
        URLProtocol.registerClass(CarRouteProtocol.self)
        var calls = 0
        CarRouteProtocol.handler = { _ in
            calls += 1
            var route = original.route!; route.id = UUID()
            route.carTraffic = .init(fetchedAt: Date().timeIntervalSince1970, delaySeconds: 30, sections: [])
            return try JSONEncoder().encode(route)
        }
        fix(state, position: original.waypoints[0].coordinate, timestamp: now, speed: 0)
        state.startRide()
        fix(state, position: original.waypoints[0].coordinate, timestamp: Date(), speed: 0)
        for _ in 0..<40 {
            if state.activeRide?.localNavigation?.carRoute != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(state.activeRide?.localNavigation?.carRoute?.carTraffic?.delaySeconds, 30)
        XCTAssertEqual(state.activeRide?.route, original.route)
        XCTAssertEqual(CarNavigation.pending(ride: state.activeRide!), [1, 2])
        state.refreshCarTraffic()
        XCTAssertEqual(calls, 1)
        state.togglePause(); state.refreshCarTraffic()
        XCTAssertEqual(calls, 1)
        state.discardRide()
    }

    @MainActor
    func testTrafficFailureAndPauseNeverReplaceSavedRoute() async throws {
        for pause in [false, true] {
            let (state, directory) = try state()
            defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
            state.plan.route?.carTraffic = .init(fetchedAt: Date().timeIntervalSince1970 - 400, delaySeconds: 0, sections: [])
            let original = state.plan.route!
            state.serverURL = "https://car-test.invalid"; state.token = "synthetic-token"
            URLProtocol.registerClass(CarRouteProtocol.self)
            var calls = 0
            CarRouteProtocol.handler = { request in
                // Pausing also starts archive sync. Count only traffic route requests.
                guard request.url?.path == "/v1/route" else { throw URLError(.cancelled) }
                calls += 1
                if !pause { throw URLError(.notConnectedToInternet) }
                var updated = original; updated.id = UUID()
                updated.carTraffic?.fetchedAt = Date().timeIntervalSince1970
                return try JSONEncoder().encode(updated)
            }
            CarRouteProtocol.responseDelay = pause ? 0.3 : 0
            fix(state, position: original.coordinates[0], timestamp: Date(), speed: 0)
            state.startRide()
            fix(state, position: original.coordinates[0], timestamp: Date(), speed: 0)
            for _ in 0..<20 {
                if calls > 0 { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            if pause { state.togglePause() }
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(state.ridingRoute?.id, original.id)
            XCTAssertNil(state.activeRide?.localNavigation?.carRoute)
            XCTAssertEqual(state.activeRide?.route, original)
            if !pause { XCTAssertNotNil(state.carTrafficError) }
            state.refreshCarTraffic()
            XCTAssertEqual(calls, 1)
            state.discardRide()
        }
    }

    @MainActor
    func testPOISearchInEveryModePreservesProfileAndActiveRide() throws {
        for mode in TravelMode.allCases {
            let (state, directory) = try state()
            defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
            state.plan.profile.mode = mode
            state.plan.route = nil
            let plan = state.plan
            let search = try state.poiSearch(category: .supermarket, duringRide: false, origin: "destination")
            XCTAssertEqual(search.profile, plan.profile)
            XCTAssertEqual(search.center, plan.destinationPoint?.coordinate)
            XCTAssertNil(search.context)
            fix(state, position: plan.waypoints[0].coordinate, timestamp: Date(), speed: 0)
            state.startRide()
            let ride = try XCTUnwrap(state.activeRide)
            let live = try state.poiSearch(category: .beach, duringRide: true)
            XCTAssertEqual(live.profile, ride.profile)
            XCTAssertEqual(live.center.distance(to: plan.waypoints[0].coordinate), 0, accuracy: 0.01)
            XCTAssertNil(live.context)
            state.savePlace(Waypoint(name: "Öffentliches POI-Beispiel", coordinate: search.center))
            XCTAssertEqual(state.activeRide, ride)
            XCTAssertEqual(state.plan, plan)
            XCTAssertTrue(state.savedPlaces.contains { $0.coordinate == search.center })
            state.discardRide()
        }
    }
    @MainActor
    func testCharacterIsCarOnlyAndDisableRejectsLateResponse() async throws {
        let (state, directory) = try state()
        let originalPack = UserDefaults.standard.data(forKey: "carCharacterPack")
        defer { UserDefaults.standard.set(originalPack, forKey: "carCharacterPack"); cleanup(directory) }
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-token"
        URLProtocol.registerClass(CarRouteProtocol.self)
        let response = CarCharacterPack(characterID: "public-character-test", source: "openai",
            phrases: ["slower": ["Meine Schaltkreise seufzen."]])
        var calls = 0
        CarRouteProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/car/character")
            calls += 1
            return try JSONEncoder().encode(response)
        }
        state.plan.profile.mode = .cycling
        state.carCharacterEnabled = true
        state.prepareCarCharacter()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(calls, 0)
        state.plan.profile.mode = .car
        state.prepareCarCharacter()
        for _ in 0..<40 {
            if !state.carCharacterLoading { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(state.carCharacterStatus.contains("KI-Texte"))
        let stored = UserDefaults.standard.data(forKey: "carCharacterPack")
        XCTAssertEqual(try JSONDecoder().decode(CarCharacterPack.self, from: XCTUnwrap(stored)).characterID, response.characterID)
        CarRouteProtocol.responseDelay = 0.2
        state.prepareCarCharacter()
        state.carCharacterEnabled = false
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(state.carCharacterLoading)
        XCTAssertEqual(UserDefaults.standard.data(forKey: "carCharacterPack"), stored)
        let again = AppState(store: try LocalStore(url: directory.appendingPathComponent("reload.sqlite")))
        XCTAssertFalse(again.carCharacterEnabled)
    }

    @MainActor
    private func state() throws -> (AppState, URL) {
        setenv("BIKENAVI_START_LOCATION_TEST", "ready", 1)
        setenv("BIKENAVI_SERVER", "", 1)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(store: try LocalStore(url: directory.appendingPathComponent("car.sqlite")))
        state.voice = false
        state.carCharacterEnabled = false
        let points = (0...4).map { Coordinate(latitude: 49.414601 + Double($0) * 0.001, longitude: 8.681496) }
        var plan = TourDocument(); plan.title = "Öffentliche synthetische Pkw-Prüfung"; plan.profile.mode = .car
        plan.waypoints = [0, 2, 4].map { Waypoint(name: "Beispielpunkt", coordinate: points[$0]) }
        plan.route = CalculatedRoute(id: UUID(), coordinates: points, distance: 445, duration: 90, ascent: 0, descent: 0,
            maneuvers: [], surfaces: [], warnings: [], provider: "Synthetisches Pkw-Beispiel", calculatedAt: 0,
            waypointIndices: [0, 2, 4], carTimeSections: [.init(startIndex: 0, endIndex: 4, seconds: 90)])
        state.plan = plan
        return (state, directory)
    }
    private func cleanup(_ directory: URL) {
        UserDefaults.standard.removeObject(forKey: "carCharacterEnabled")
        unsetenv("BIKENAVI_START_LOCATION_TEST"); unsetenv("BIKENAVI_SERVER")
        try? FileManager.default.removeItem(at: directory)
        CarRouteProtocol.handler = nil; CarRouteProtocol.responseDelay = 0; URLProtocol.unregisterClass(CarRouteProtocol.self)
    }
    @MainActor
    private func fix(_ state: AppState, position: Coordinate, timestamp: Date, speed: Double = 40) {
        state.location.locationManager(CLLocationManager(), didUpdateLocations: [CLLocation(coordinate: position.cl,
            altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5, course: -1, speed: speed, timestamp: timestamp)])
    }
    @MainActor
    func testHighwayRecordingPauseRestoreAndFreeDriveNeverCaptureBikeData() throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan, points = plan.route!.coordinates, now = Date()
        fix(state, position: points[0], timestamp: now.addingTimeInterval(-4))
        state.startRide()
        let id = try XCTUnwrap(state.activeRide?.id)
        fix(state, position: points[2], timestamp: now)
        XCTAssertEqual(state.activeRide?.track.count, 2)
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [2])
        state.recordBikeMeasurement(BikeMeasurement(bikeID: UUID(), timestamp: now.timeIntervalSince1970, batteryPercent: 50))
        XCTAssertEqual(try state.store.bikeSampleCounts(rideID: id).total, 0)
        state.togglePause()
        unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: state.store); restored.restoreLocalRouting()
        XCTAssertEqual(restored.activeRide?.profile.mode, .car)
        XCTAssertEqual(restored.activeRide?.localNavigation?.carPendingWaypointOrdinals, [2])
        XCTAssertEqual(restored.ridingRoute?.id, plan.route?.id)
        XCTAssertEqual(restored.activeRide?.recordingState, .paused)
        restored.finishRide()
        XCTAssertEqual(try restored.store.all().first { $0.id == id }?.document.recordingState, .finished)
        XCTAssertEqual(state.plan, plan)
        // A free drive inherits the mode but no planned stops or route.
        state.discardRide(); state.plan.route = nil
        fix(state, position: points[0], timestamp: Date())
        state.startRide()
        XCTAssertEqual(state.activeRide?.profile.mode, .car)
        XCTAssertEqual(state.activeRide?.title, "Freie Autofahrt")
        XCTAssertNil(state.activeRide?.route)
        XCTAssertEqual(state.activeRide?.waypoints, [])
    }
    @MainActor
    func testAutomaticCarReroutePreservesStopsAndOriginalPlanAcrossRestart() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan, now = Date()
        fix(state, position: plan.route!.coordinates[0], timestamp: now.addingTimeInterval(-4))
        state.startRide()
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        let called = expectation(description: "Car route requested")
        CarRouteProtocol.handler = { call in
            let body: Data
            if let data = call.httpBody { body = data }
            else {
                let stream = try XCTUnwrap(call.httpBodyStream); stream.open(); defer { stream.close() }
                var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }
                body = data
            }
            let request = try JSONDecoder().decode(RouteRequest.self, from: body)
            XCTAssertEqual(request.profile.mode, .car)
            XCTAssertEqual(Array(request.waypoints.dropFirst()), Array(plan.waypoints.dropFirst()))
            let points = request.waypoints.map(\.coordinate)
            let route = CalculatedRoute(id: UUID(), coordinates: points, distance: 400, duration: 50, ascent: 0, descent: 0,
                maneuvers: [], surfaces: [], warnings: [], provider: "openrouteservice · Pkw", calculatedAt: 0,
                waypointIndices: [0, 1, 2], carTimeSections: [.init(startIndex: 0, endIndex: 2, seconds: 50)])
            called.fulfill()
            return try JSONEncoder().encode(route)
        }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        let off = Coordinate(latitude: plan.route!.coordinates[0].latitude, longitude: 8.683496)
        for seconds in [-2.0, 1.0, 3.0] { fix(state, position: off, timestamp: now.addingTimeInterval(seconds)) }
        await fulfillment(of: [called], timeout: 8)
        for _ in 0..<50 {
            if state.activeRide?.localNavigation?.carRoute != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let replacement = try XCTUnwrap(state.activeRide?.localNavigation?.carRoute)
        XCTAssertNotEqual(replacement.id, plan.route?.id)
        XCTAssertEqual(state.plan, plan)
        XCTAssertEqual(state.activeRide?.route?.id, plan.route?.id)
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2])
        state.togglePause(); unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: state.store); restored.restoreLocalRouting()
        XCTAssertEqual(restored.ridingRoute?.id, replacement.id)
        XCTAssertEqual(restored.activeRide?.route?.id, plan.route?.id)
    }

    @MainActor
    func testPOIInsertionPreservesPlanTrackPendingStopsAndRestart() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan
        fix(state, position: plan.route!.coordinates[0], timestamp: Date())
        state.startRide()
        fix(state, position: plan.route!.coordinates[0], timestamp: Date().addingTimeInterval(0.01), speed: 0)
        let track = state.activeRide!.track
        let stop = Waypoint(name: "Synthetischer Tankstopp", coordinate: plan.route!.coordinates[1])
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        CarRouteProtocol.handler = { call in
            XCTAssertEqual(call.url?.path, "/v1/pois/route")
            let points = [plan.route!.coordinates[0], stop.coordinate] + plan.waypoints.dropFirst().map(\.coordinate)
            let route = CalculatedRoute(id: UUID(), coordinates: points, distance: 445, duration: 120, ascent: 0, descent: 0,
                maneuvers: [], surfaces: [], warnings: [], provider: "Synthetische POI-Prüfung", calculatedAt: 0,
                waypointIndices: [0, 1, 2, 3], carTimeSections: [.init(startIndex: 0, endIndex: 3, seconds: 120)])
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(route))
            return try JSONSerialization.data(withJSONObject: ["route": encoded, "drivingDistance": 111, "drivingSeconds": 30, "detourSeconds": 30])
        }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        try await state.addPOIToRide(stop)
        XCTAssertEqual(state.plan, plan)
        XCTAssertEqual(state.activeRide?.track, track)
        XCTAssertEqual(state.activeRide?.waypoints.map(\.name), [plan.waypoints[0].name, stop.name, plan.waypoints[1].name, plan.waypoints[2].name])
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2, 3])
        XCTAssertEqual(state.activeRide?.localNavigation?.carPOIStopID, stop.id)
        XCTAssertNil(state.activeRide?.asNewPlan().route)
        state.togglePause()
        unsetenv("BIKENAVI_START_LOCATION_TEST")
        let restored = AppState(store: state.store); restored.restoreLocalRouting()
        XCTAssertEqual(restored.activeRide?.localNavigation?.carPOIStopID, stop.id)
        XCTAssertEqual(restored.ridingRoute?.id, state.ridingRoute?.id)
        XCTAssertEqual(restored.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2, 3])
        state.togglePause()
        fix(state, position: plan.route!.coordinates[0], timestamp: Date(), speed: 0)
        CarRouteProtocol.handler = { call in
            guard call.url?.path == "/v1/route" else { throw URLError(.unsupportedURL) }
            return try JSONEncoder().encode(plan.route!)
        }
        try await state.removePOIStop()
        XCTAssertEqual(state.activeRide?.waypoints, plan.waypoints)
        XCTAssertEqual(state.activeRide?.localNavigation?.carPendingWaypointOrdinals, [1, 2])
        XCTAssertNil(state.pendingPOIStop)
        XCTAssertEqual(state.plan, plan)
    }

    @MainActor
    func testFailedPOIInsertionAndStaleGPSLeaveRideUnchanged() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        fix(state, position: state.plan.route!.coordinates[0], timestamp: Date())
        state.startRide()
        fix(state, position: state.plan.route!.coordinates[0], timestamp: Date().addingTimeInterval(0.01))
        let before = state.activeRide
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        CarRouteProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        do {
            try await state.addPOIToRide(Waypoint(name: "Beispiel", coordinate: state.plan.route!.coordinates[1]))
            XCTFail("Anfahrt darf bei Netzfehler nicht übernommen werden")
        } catch { }
        XCTAssertEqual(state.activeRide, before)
        state.location.denied = true
        XCTAssertThrowsError(try state.poiSearch(category: .fuel, duringRide: true))
    }

    @MainActor
    func testPOIResponseCannotReplaceRideAfterPause() async throws {
        let (state, directory) = try state()
        defer { cleanup(directory); UIApplication.shared.isIdleTimerDisabled = false }
        let plan = state.plan
        fix(state, position: plan.route!.coordinates[0], timestamp: Date())
        state.startRide()
        fix(state, position: plan.route!.coordinates[0], timestamp: Date().addingTimeInterval(0.01), speed: 0)
        let called = expectation(description: "POI request started")
        state.serverURL = "https://car-test.invalid"; state.token = "synthetic-test"
        CarRouteProtocol.responseDelay = 0.3
        CarRouteProtocol.handler = { call in
            guard call.url?.path == "/v1/pois/route" else { throw URLError(.unsupportedURL) }
            called.fulfill()
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.route!))
            return try JSONSerialization.data(withJSONObject: ["route": encoded, "drivingDistance": 111, "drivingSeconds": 30])
        }
        XCTAssertTrue(URLProtocol.registerClass(CarRouteProtocol.self))
        let request = Task { try await state.addPOIToRide(Waypoint(name: "Beispiel", coordinate: plan.route!.coordinates[1])) }
        await fulfillment(of: [called], timeout: 5)
        state.togglePause()
        let paused = state.activeRide
        do { try await request.value; XCTFail("Verspätete Antwort darf die pausierte Fahrt nicht ersetzen") } catch { }
        XCTAssertEqual(state.activeRide, paused)
        XCTAssertEqual(state.plan, plan)
    }
}
