import SwiftUI
import CoreLocation
import Security
import AVFoundation

enum Keychain {
    private static let service = "de.michaelhein.BikeNavi"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server-token",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ value: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "server-token"]
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, rhs in rhs } as CFDictionary, nil)
            guard added == errSecSuccess else { throw APIError(status: Int(added), message: "Zugangsschlüssel konnte nicht im Schlüsselbund gespeichert werden.") }
        } else if status != errSecSuccess {
            throw APIError(status: Int(status), message: "Zugangsschlüssel konnte nicht gespeichert werden.")
        }
    }
}

@MainActor
final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var coordinate: Coordinate?
    @Published var denied = false
    @Published var accuracy: Double?
    @Published var failureMessage: String?
    var onLocation: ((CLLocation) -> Void)?
    var onAuthorizationChange: (() -> Void)?
    var onHeadingChange: (() -> Void)?
    private var latestHeading: CLHeading?
    var navigationHeading: Double? {
        let now = Date().timeIntervalSince1970
        let compass = latestHeading.flatMap {
            NavigationHeading.compass(trueHeading: $0.trueHeading, magneticHeading: $0.magneticHeading,
                                      accuracy: $0.headingAccuracy, timestamp: $0.timestamp.timeIntervalSince1970, now: now)
        }
        return NavigationHeading.select(course: latestSample?.course, speed: latestSample?.speed,
                                        timestamp: latestSample?.timestamp.timeIntervalSince1970,
                                        compass: compass, now: now)
    }
    private var lastTimestamp: Double?
    private(set) var latestSample: CLLocation?
    var freshCoordinate: Coordinate? {
        guard !denied, let timestamp = lastTimestamp, let accuracy,
              PlanningLocation.isUsable(timestamp: timestamp, accuracy: accuracy, now: Date().timeIntervalSince1970) else { return nil }
        return coordinate
    }
    private let manager = CLLocationManager()
    private var activeRide = false
    private var marineNavigation = false
    private var carNavigation = false
    func setCarNavigation(_ enabled: Bool) {
        guard carNavigation != enabled else { return }
        carNavigation = enabled
        manager.activityType = enabled ? .automotiveNavigation : marineNavigation ? .otherNavigation : .fitness
        manager.desiredAccuracy = enabled ? kCLLocationAccuracyBestForNavigation : kCLLocationAccuracyBest
    }
    func setMarineNavigation(_ enabled: Bool) {
        marineNavigation = enabled
        manager.activityType = enabled ? .otherNavigation : carNavigation ? .automotiveNavigation : .fitness
        manager.distanceFilter = activeRide && !enabled ? 5 : kCLDistanceFilterNone
        updateHeadingMonitoring()
    }
    private var authorizationStatus: CLAuthorizationStatus {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BIKENAVI_MARINE_PREVIEW"] == "1" || ProcessInfo.processInfo.environment["BIKENAVI_CAR_PREVIEW"] == "1" { return .authorizedWhenInUse }
        if let scenario = ProcessInfo.processInfo.environment["BIKENAVI_START_LOCATION_TEST"] {
            return scenario == "denied" ? .denied : .authorizedWhenInUse
        }
        #endif
        return manager.authorizationStatus
    }

    override init() {
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.environment["BIKENAVI_MARINE_PREVIEW"] == "1" || ProcessInfo.processInfo.environment["BIKENAVI_CAR_PREVIEW"] == "1" { return }
        if ProcessInfo.processInfo.environment["BIKENAVI_START_LOCATION_TEST"] != nil {
            coordinate = Coordinate(latitude: 49.414601, longitude: 8.681496)
            accuracy = 5
            lastTimestamp = Date().timeIntervalSince1970 - 120
            return
        }
        #endif
        manager.delegate = self
        manager.activityType = .fitness
        manager.headingFilter = 3
        // The app supports portrait only: use the top edge as the forward direction.
        manager.headingOrientation = .portrait
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
    }
    func request() {
        failureMessage = nil
        denied = authorizationStatus == .denied || authorizationStatus == .restricted
        #if DEBUG
        if ProcessInfo.processInfo.environment["BIKENAVI_START_LOCATION_TEST"] != nil || ProcessInfo.processInfo.environment["BIKENAVI_MARINE_PREVIEW"] == "1" || ProcessInfo.processInfo.environment["BIKENAVI_CAR_PREVIEW"] == "1" { return }
        #endif
        if authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            // Planning often happens while standing still. A movement filter can
            // otherwise leave the last fix older than our 15-second freshness limit.
            manager.distanceFilter = activeRide && !marineNavigation ? 5 : kCLDistanceFilterNone
            if !activeRide && freshCoordinate == nil { manager.stopUpdatingLocation() }
            manager.startUpdatingLocation()
            updateHeadingMonitoring()
        }
    }
    /// A stationary ride uses a movement filter; explicitly renew the fix for a journal stop.
    func journalCoordinate(timeout: TimeInterval = 15) async throws -> Coordinate {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BIKENAVI_BLOG_STALE_LOCATION"] == "delayed", let example = coordinate {
            lastTimestamp = Date().timeIntervalSince1970 - 120
            Task {
                try? await Task.sleep(for: .seconds(2))
                let sample = CLLocation(coordinate: .init(latitude: example.latitude, longitude: example.longitude),
                                        altitude: example.altitude ?? 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
                self.locationManager(CLLocationManager(), didUpdateLocations: [sample])
            }
        }
        #endif
        request()
        guard !denied else { throw APIError(status: 0, message: "Bitte den Standortzugriff in den iPhone-Einstellungen erlauben.") }
        if let freshCoordinate { return freshCoordinate }
        #if DEBUG
        let simulated = ProcessInfo.processInfo.environment["BIKENAVI_START_LOCATION_TEST"] != nil
        #else
        let simulated = false
        #endif
        if !simulated {
            manager.stopUpdatingLocation()
            manager.distanceFilter = kCLDistanceFilterNone
            manager.startUpdatingLocation()
        }
        defer { if !simulated { manager.distanceFilter = activeRide && !marineNavigation ? 5 : kCLDistanceFilterNone } }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(Int(timeout * 1000)))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let freshCoordinate { return freshCoordinate }
            if denied { throw APIError(status: 0, message: "Bitte den Standortzugriff in den iPhone-Einstellungen erlauben.") }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw APIError(status: 0, message: "Noch keine aktuelle GPS-Position. Foto und Notiz bleiben im Formular erhalten. Bitte den Standort erneut übernehmen.")
    }

    func setRiding(_ active: Bool) {
        activeRide = active
        manager.distanceFilter = active && !marineNavigation ? 5 : kCLDistanceFilterNone
        manager.allowsBackgroundLocationUpdates = active
        manager.showsBackgroundLocationIndicator = active
        updateHeadingMonitoring()
        if active { request() }
    }
    private func updateHeadingMonitoring() {
        let authorized = authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
        if activeRide && !marineNavigation && authorized && CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        } else {
            manager.stopUpdatingHeading()
            latestHeading = nil
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard activeRide else { return }
        latestHeading = newHeading
        // Propagate rotations independently of GPS fixes and recorded track points.
        onHeadingChange?()
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        denied = authorizationStatus == .denied || authorizationStatus == .restricted
        onAuthorizationChange?()
        updateHeadingMonitoring()
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        denied = authorizationStatus == .denied || authorizationStatus == .restricted
        failureMessage = "Der Standort ist derzeit nicht verfügbar. Die App wartet weiter auf GPS; du kannst auch einen Start auf der Karte wählen."
        onAuthorizationChange?()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && abs(location.timestamp.timeIntervalSinceNow) < 15 {
            denied = authorizationStatus == .denied || authorizationStatus == .restricted
            failureMessage = nil
            coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                    altitude: location.verticalAccuracy >= 0 ? location.altitude : nil)
            accuracy = location.horizontalAccuracy
            lastTimestamp = location.timestamp.timeIntervalSince1970
            latestSample = location
            onLocation?(location)
        }
    }
}

final class NavigationSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var ownsAudioSession = false
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { release(synthesizer) }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { release(synthesizer) }
    private func release(_ synthesizer: AVSpeechSynthesizer) {
        DispatchQueue.main.async { [weak self, weak synthesizer] in
            guard let self, self.ownsAudioSession, synthesizer?.isSpeaking != true else { return }
            self.ownsAudioSession = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var plan = TourDocument() {
        didSet {
            if plan.id != oldValue.id || plan.route?.id != oldValue.route?.id { cancelRideStart() }
            if plan.profile.mode != oldValue.profile.mode {
                if plan.profile.mode == .sea { selectedMapStyle = .seamap }
                else if oldValue.profile.mode == .sea && activeRide?.profile.mode != .sea { selectedMapStyle = .standard }
                updateMarineMode()
            }
        }
    }
    @Published private(set) var waitingForRideLocation = false
    private var rideStartTask: Task<Void, Never>?
    func cancelRideStart() {
        rideStartTask?.cancel()
        rideStartTask = nil
        waitingForRideLocation = false
    }
    func becameActive() { location.request() }
    @Published private(set) var applicationMode: TravelMode?
    var hasConflictingApplicationRide: Bool {
        guard let applicationMode, let activeRide else { return false }
        return activeRide.profile.mode != applicationMode
    }
    var workspaceSupportsBike: Bool { (applicationMode ?? plan.profile.mode).supportsBike }
    var activeRideSupportsBike: Bool { activeRide?.profile.mode.supportsBike == true }
    var isWalkingSection: Bool {
        guard let ride = activeRide else { return plan.profile.mode == .hiking }
        if ride.profile.mode == .hiking { return true }
        guard ride.profile.mode == .bikeAndHike, let route = ridingRoute, let index = route.walkingStartIndex,
              route.coordinates.indices.contains(index), let progress else { return false }
        return progress.traveled >= LocalRouteMetrics.distances(route)[index]
    }
    var applicationMapStyles: [MapStyle] {
        let mode = applicationMode ?? plan.profile.mode
        return MapStyle.allCases.filter { $0 != .seamap || mode == .sea }
    }
    private func workspacePlanKey(_ mode: TravelMode) -> String { "applicationPlan." + mode.rawValue }
    private func defaultMapStyle(_ mode: TravelMode) -> MapStyle {
        mode == .sea ? .seamap : mode == .hiking ? .topographic : .standard
    }
    func chooseApplication(_ mode: TravelMode) {
        cancelRideStart()
        if applicationMode != nil || currentRecord != nil || !plan.waypoints.isEmpty { guard savePlan() else { return } }
        cancelElevation()
        routeTask?.cancel(); routeCalculationID = nil; calculating = false
        preparationTask?.cancel(); preparationID = nil; preparingLocalRouting = false
        nameTask?.cancel(); requestedStartPlanID = nil; routeWhenReady = false
        preparedGraph = nil; preparedRouteID = nil; planningError = nil; selectedPoint = nil; mapFocus = nil
        let preferred = UserDefaults.standard.string(forKey: workspacePlanKey(mode)).flatMap(UUID.init(uuidString:))
        plan = ApplicationWorkspace.plan(mode: mode, current: plan, records: records, preferredID: preferred)
        applicationMode = mode
        selectedMapStyle = defaultMapStyle(mode)
        mapRevision = UUID()
        tab = 0
        savePlan()
        if plan.isAwaitingStart { requestAutomaticStart() }
        else { prepareLocalRouting() }
    }
    func returnToHome() {
        cancelRideStart()
        guard savePlan() else { return }
        applicationMode = nil
        stopObservingSystemVolume()
    }
    func resumeApplicationRide() {
        guard let ride = activeRide else { return }
        chooseApplication(ride.profile.mode)
        guard applicationMode == ride.profile.mode else { return }
        tab = 1
    }
    @Published var records: [SavedRecord] = []
    @Published var savedPlaces: [SavedPlace] = []
    @Published var activeRide: TourDocument? {
        didSet { updateScreenAwake(); updateMarineMode() }
    }
    private var sceneActive = true
    @Published var progress: RouteProgress?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var loadingElevation = false
    @Published var elevationError: String?
    private var elevationTask: Task<Void, Never>?
    private var elevationRequestID: UUID?
    @Published var calculating = false
    @Published var planningError: String?
    @Published var blogGeneration: [UUID: BlogGenerationProgress] = [:]
    private var blogGenerationTasks: [UUID: Task<BlogDraft, Error>] = [:]
    @Published var rerouting = false
    @Published var waypointSkipProposal: [Int] = []
    private var declinedWaypointSkips: Set<Int> = []
    var waypointSkipNames: String {
        guard let ride = activeRide else { return "" }
        return waypointSkipProposal.filter { ride.waypoints.indices.contains($0) }
            .map { ride.waypoints[$0].name }.joined(separator: ", ")
    }

    @Published var localRoutingStatus = "Lokale Rückführung noch nicht vorbereitet"
    @Published var preparingLocalRouting = false
    @Published var preparedRouteID: UUID?
    @Published var localRideStatus: String?
    @Published var navigationRoute: CalculatedRoute?
    @Published var carLookAhead = 450.0
    private var carZoom = CarAutoZoom()
    private var carVoice = CarVoiceGuidance()
    private var carRerouteAttempt = -Double.infinity
    private var carArrivalAnnounced = false
    var carGPSIsFresh: Bool {
        guard !location.denied, let sample = location.latestSample else { return false }
        return abs(sample.timestamp.timeIntervalSinceNow) < 5 && sample.horizontalAccuracy >= 0 && sample.horizontalAccuracy <= 25
    }
    var carHeading: Double? {
        guard carGPSIsFresh, let sample = location.latestSample, sample.speed >= 1, sample.course >= 0 else { return nil }
        return sample.course
    }
    func carMapStyleURL(dark: Bool) -> String {
        (selectedMapStyle == .standard || selectedMapStyle == .seamap) && dark ? MapStyle.dark.url(customURL: customMapStyleURL) : selectedMapStyle == .seamap ? MapStyle.standard.url(customURL: customMapStyleURL) : mapStyleURL
    }
    private var preparedGraph: OfflineGraph?
    private var rideGraph: OfflineGraph?
    private var neighborhoodTask: Task<Void, Never>?
    private var neighborhoodRequestID: UUID?
    private var neighborhoodRideID: UUID?
    private var neighborhoodAttempt: TimeInterval = 0

    private var preparationTask: Task<Void, Never>?
    private var preparationID: UUID?
    private var originalTracker = RouteTracker()
    private let offlineRouting = OfflineRoutingStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BikeNavi/OfflineRouting"))
    var localRoutingReady: Bool { plan.route != nil && preparedRouteID == plan.route?.id }
    var ridingRoute: CalculatedRoute? { navigationRoute ?? activeRide?.route }
    @Published var synchronizing = false
    @Published var tab = 0
    @Published var mapFocus: Coordinate?
    @Published var mapRevision = UUID()
    @Published var selectedPoint: Coordinate?
    @Published var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @Published var token = Keychain.read()
    @Published var showWaterDepths = UserDefaults.standard.bool(forKey: "showWaterDepths") {
        didSet { UserDefaults.standard.set(showWaterDepths, forKey: "showWaterDepths") }
    }
    @Published var boatDraft = MarineNavigation.setting(UserDefaults.standard.double(forKey: "boatDraft"), range: 0.1...20, fallback: 2) {
        didSet {
            guard boatDraft.isFinite, (0.1...20).contains(boatDraft) else { boatDraft = oldValue; return }
            UserDefaults.standard.set(boatDraft, forKey: "boatDraft")
            if boatDraft != oldValue, plan.profile.mode == .sea {
                plan.profile.boatDraft = boatDraft
                invalidateRoute(showErrorAlert: false)
            }
        }
    }
    @Published var boatSpeedKnots = MarineNavigation.setting(UserDefaults.standard.double(forKey: "boatSpeedKnots"), range: 0.5...50, fallback: 4) {
        didSet {
            guard boatSpeedKnots.isFinite, (0.5...50).contains(boatSpeedKnots) else { boatSpeedKnots = oldValue; return }
            UserDefaults.standard.set(boatSpeedKnots, forKey: "boatSpeedKnots")
            if boatSpeedKnots != oldValue, plan.profile.mode == .sea {
                plan.profile.boatSpeedKnots = boatSpeedKnots
                savePlan()
            }
        }
    }
    // A map style changes appearance; the home tile determines the application.
    @Published var selectedMapStyle: MapStyle = .standard
    var isMarinePresentation: Bool { (activeRide?.profile.mode ?? plan.profile.mode) == .sea }
    private var marineModeActive = false
    private func updateMarineMode() {
        location.setCarNavigation((activeRide?.profile.mode ?? plan.profile.mode) == .car)
        rideActivity.carPresentation = (activeRide?.profile.mode ?? plan.profile.mode) == .car
        guard marineModeActive != isMarinePresentation else { return }
        marineModeActive = isMarinePresentation
        location.setMarineNavigation(isMarinePresentation)
        rideActivity.marinePresentation = isMarinePresentation
        if isMarinePresentation {
            cancelRerouting(); cancelNeighborhood(); progress = nil; localRideStatus = nil
        }
    }
    var marineTargetIndex: Int { activeRide?.localNavigation?.marineNextWaypointIndex ?? 1 }
    @Published var customMapStyleURL = UserDefaults.standard.string(forKey: "mapStyleURL") ?? "" {
        didSet { UserDefaults.standard.set(customMapStyleURL, forKey: "mapStyleURL") }
    }
    var mapStyleURL: String { selectedMapStyle.url(customURL: customMapStyleURL) }
    var canDownloadMapStyle: Bool { offlineMapsAllowed && selectedMapStyle == .custom }
    @Published var offlineMapsAllowed = UserDefaults.standard.bool(forKey: "offlineMapsAllowed")
    @Published var voice = true { didSet { if !voice { speech.stopSpeaking(at: .immediate) } } }
    private let volumePreview = AVSpeechSynthesizer()
    private var volumePreviewTask: Task<Void, Never>?
    private var systemVolumeObservation: NSKeyValueObservation?

    func observeSystemVolume() {
        guard tab == 3, systemVolumeObservation == nil else { return }
        systemVolumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            guard change.oldValue != change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.tab == 3, self.systemVolumeObservation != nil else { return }
                self.previewSystemVolume()
            }
        }
    }

    func stopObservingSystemVolume() {
        systemVolumeObservation?.invalidate()
        systemVolumeObservation = nil
        stopVolumePreview()
    }

    func previewSystemVolume() {
        stopVolumePreview()
        // System volume changes replace the previous preview instead of queuing speech.
        volumePreviewTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.speech.stopSpeaking(at: .immediate)
            let utterance = AVSpeechUtterance(string: "Eine kleine Schnecke sitzt an einer Hecke. Krabbelt hin und her, freut sich dabei sehr.")
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            utterance.volume = 1
            self.volumePreview.speak(utterance)
        }
    }

    func stopVolumePreview() {
        volumePreviewTask?.cancel()
        volumePreviewTask = nil
        volumePreview.stopSpeaking(at: .immediate)
    }
    let location = LocationService()
    let store: LocalStore
    @Published var routeDescriptions: [UUID: SavedRouteDescription] = [:]
    private var routeDescriptionTasks: [UUID: Task<Void, Never>] = [:]

    func insertRouteDescriptionHighlight(_ id: UUID) async throws -> String {
        guard let report = routeDescriptions[plan.id]?.report, report.planID == plan.id,
              let highlight = report.highlights?.first(where: { $0.id == id }) else {
            throw APIError(status: 0, message: "Dieses Highlight gehört nicht zur geöffneten Planung.")
        }
        while true {
            let snapshot = plan
            guard snapshot.id == report.planID else {
                throw APIError(status: 0, message: "Die geöffnete Planung wurde gewechselt.")
            }
            var referencePlan = snapshot
            referencePlan.route = routeDescriptions[snapshot.id]?.reportRoute ?? snapshot.route
            let referenceIndices = routeDescriptions[snapshot.id]?.reportRoute != nil ? routeDescriptions[snapshot.id]?.reportWaypointIndices : nil
            let updated = try await Task.detached(priority: .userInitiated) { [referencePlan] in
                try RouteDescriptionInsertion.inserting(highlight, into: referencePlan, referenceIndices: referenceIndices)
            }.value
            guard plan.id == snapshot.id else { throw APIError(status: 0, message: "Die geöffnete Planung wurde gewechselt.") }
            // A simultaneous selection or routing response must never lose another goal.
            if plan.waypoints != snapshot.waypoints || plan.profile != snapshot.profile || plan.route?.id != snapshot.route?.id { continue }
            var latest = updated
            latest.title = plan.title
            latest.usesAutomaticTitle = plan.usesAutomaticTitle
            try store.save(latest)
            plan = latest
            mapFocus = highlight.coordinate
            invalidateRoute(showErrorAlert: false)
            return highlight.title
        }
    }

    func openRouteDescription() async throws {
        resumeRouteDescription()
        guard api != nil, !calculating, let request = RouteDescriptionRequest(plan: plan) else { return }
        let id = plan.id
        let fingerprint = try request.fingerprint
        guard routeDescriptions[id]?.needsCreationOnOpen(plan) ?? true else { return }
        // Finish observing an older accepted Pi job before submitting this route.
        if let task = routeDescriptionTasks[id] { await task.value }
        try Task.checkCancellation()
        guard plan.id == id, !calculating,
              (try? RouteDescriptionRequest(plan: plan)?.fingerprint) == fingerprint,
              routeDescriptions[id]?.needsCreationOnOpen(plan) ?? true else { return }
        try startRouteDescription()
    }

    func startRouteDescription() throws {
        guard let api else { throw APIError(status: 0, message: "Bitte zuerst den Pi unter Einstellungen verbinden.") }
        guard !calculating, let request = RouteDescriptionRequest(plan: plan) else {
            throw APIError(status: 0, message: "Bitte zuerst eine Route mit Start und Ziel berechnen.")
        }
        let id = request.planID
        guard routeDescriptionTasks[id] == nil else { return }
        let previous = try routeDescriptions[id] ?? store.routeDescription(planID: id)
        let fingerprint = try request.fingerprint
        if let previous, previous.job.running { resumeRouteDescription(); return }
        if let previous, previous.job.phase == "interrupted", previous.fingerprint == fingerprint {
            followRouteDescription(previous, api: api, request: nil)
            return
        }
        let saved = SavedRouteDescription(planID: id, routeID: request.route.id, fingerprint: fingerprint,
            job: RouteDescriptionJob(generationID: UUID(), planID: id, phase: "analysing"),
            report: previous?.report, reportFingerprint: previous?.reportFingerprint,
            requestRoute: request.route, reportRoute: previous?.reportRoute,
            requestWaypointIndices: request.route.waypointIndices?.count == request.waypoints.count && Set(request.waypoints.map(\.id)).count == request.waypoints.count
                ? Dictionary(uniqueKeysWithValues: zip(request.waypoints.map { $0.id.uuidString }, request.route.waypointIndices!)) : nil,
            reportWaypointIndices: previous?.reportWaypointIndices)
        try store.saveRouteDescription(saved)
        routeDescriptions[id] = saved
        followRouteDescription(saved, api: api, request: request)
    }

    func resumeRouteDescription() {
        let id = plan.id
        do {
            if routeDescriptions[id] == nil { routeDescriptions[id] = try store.routeDescription(planID: id) }
            if plan.route == nil, !calculating, let saved = routeDescriptions[id], saved.reportRoute != nil,
               plan.waypoints.contains(where: { point in saved.report?.highlights?.contains(where: { $0.id == point.id }) == true }) {
                invalidateRoute(showErrorAlert: false)
            }
            guard let saved = routeDescriptions[id], saved.job.running || saved.job.phase == "interrupted", let api, routeDescriptionTasks[id] == nil else { return }
            followRouteDescription(saved, api: api, request: nil)
        } catch { errorMessage = error.localizedDescription }
    }

    private func followRouteDescription(_ initial: SavedRouteDescription, api: APIClient, request: RouteDescriptionRequest?) {
        let id = initial.planID
        routeDescriptionTasks[id] = Task { @MainActor in
            defer { routeDescriptionTasks[id] = nil }
            var saved = initial
            do {
                var job = initial.job
                if let request { job = try await api.startRouteDescription(request, generationID: initial.job.generationID) }
                else { job = try await api.routeDescriptionJob(initial.job.generationID) }
                while true {
                    guard job.planID == id, job.generationID == initial.job.generationID else {
                        throw APIError(status: 502, message: "Der Pi hat eine Beschreibung zu einer anderen Planung geliefert.")
                    }
                    saved.job = job
                    if job.phase == "completed" {
                        guard let report = job.report, report.planID == id,
                              initial.routeID == nil || report.routeID == initial.routeID else {
                            throw APIError(status: 502, message: "Die fertige Routenbeschreibung ist unvollständig.")
                        }
                        saved.report = report
                        saved.reportFingerprint = initial.fingerprint
                        saved.reportRoute = initial.requestRoute
                        saved.requestRoute = nil
                        saved.reportWaypointIndices = initial.requestWaypointIndices
                        saved.requestWaypointIndices = nil
                        saved.job.report = nil
                    }
                    try Task.checkCancellation()
                    try store.saveRouteDescription(saved)
                    routeDescriptions[id] = saved
                    if !job.running { return }
                    try await Task.sleep(for: .seconds(2))
                    job = try await api.routeDescriptionJob(initial.job.generationID)
                }
            } catch {
                if Task.isCancelled { return }
                saved.report = initial.report
                saved.reportFingerprint = initial.reportFingerprint
                saved.reportRoute = initial.reportRoute
                saved.requestRoute = initial.requestRoute
                saved.reportWaypointIndices = initial.reportWaypointIndices
                saved.requestWaypointIndices = initial.requestWaypointIndices
                saved.job.phase = (error as? APIError).map { $0.status == 0 ? "interrupted" : "failed" } ?? "interrupted"
                saved.job.message = error.localizedDescription
                try? store.saveRouteDescription(saved)
                routeDescriptions[id] = saved
            }
        }
    }
    private var routeTask: Task<Void, Never>?
    private var routeCalculationID: UUID?
    private var rerouteTask: Task<Void, Never>?
    private var rerouteRequestID: UUID?
    private var nameTask: Task<Void, Never>?
    private var requestedStartPlanID: UUID?
    private var routeWhenReady = false
    private var tracker = RouteTracker()
    private var reroutePolicy = ReroutePolicy()
    private var lastAnnouncement: Int?
    private var segment = 0
    private let speech = AVSpeechSynthesizer()
    private let navigationSpeechDelegate = NavigationSpeechDelegate()
    private let rideActivity = RideActivityController()
    #if DEBUG
    private var marinePreviewTask: Task<Void, Never>?
    private func marinePreviewLocation(origin: Coordinate) -> CLLocation {
        let now = Date()
        var position = origin
        var course: Double = -1
        var speed: Double = 0
        if let ride = activeRide, let started = ride.startedAt {
            var distance = max(0, now.timeIntervalSince1970 - started) * 3
            let points = MarineNavigation.navigationPoints(ride)
            let legs = MarineNavigation.legs(points)
            let radians: Double = Double.pi / 180
            for leg in legs {
                if distance > leg.distance { distance -= leg.distance; position = leg.end.coordinate; continue }
                let fraction: Double = leg.distance > 0 ? distance / leg.distance : 0
                let startLatitude = leg.start.coordinate.latitude * radians
                let endLatitude = leg.end.coordinate.latitude * radians
                let y1 = log(tan(Double.pi / 4 + startLatitude / 2))
                let y2 = log(tan(Double.pi / 4 + endLatitude / 2))
                let mercator = y1 + (y2-y1)*fraction
                position.latitude = (2 * atan(exp(mercator)) - Double.pi/2) / radians
                let longitudeDelta = leg.end.coordinate.longitude - leg.start.coordinate.longitude
                position.longitude = leg.start.coordinate.longitude + longitudeDelta*fraction
                course = leg.course; speed = 3
                break
            }
        }
        return CLLocation(coordinate: position.cl, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                          course: course, speed: speed, timestamp: now)
    }
    #endif

    init(store: LocalStore) {
        self.store = store
        speech.delegate = navigationSpeechDelegate
        UserDefaults.standard.removeObject(forKey: "speechVolume")
        reload()
        if let idString = UserDefaults.standard.string(forKey: "currentPlan"),
           let id = UUID(uuidString: idString), let saved = records.first(where: { $0.id == id && !$0.deleted }) {
            plan = saved.document
        }
        if var unfinished = records.first(where: { $0.document.kind == .ride && [.recording, .paused].contains($0.document.recordingState) })?.document {
            unfinished.recordingState = .paused
            activeRide = unfinished
            segment = max(unfinished.track.last?.segment ?? 0, (try? store.lastBikeSegment(rideID: unfinished.id)) ?? 0) + 1
            try? store.save(unfinished)
            rideActivity.restore(tourName: unfinished.title, route: unfinished.route, paused: true)
            notice = "Deine letzte Fahrt ist gespeichert. Du kannst sie fortsetzen oder beenden."
        }
        location.onLocation = { [weak self] sample in self?.receive(sample) }
        location.onAuthorizationChange = { [weak self] in self?.objectWillChange.send() }
        location.onHeadingChange = { [weak self] in self?.objectWillChange.send() }
        #if DEBUG
        if let url = ProcessInfo.processInfo.environment["BIKENAVI_SERVER"] {
            serverURL = url
            token = ProcessInfo.processInfo.environment["BIKENAVI_TOKEN"] ?? token
        }
        if let value = ProcessInfo.processInfo.environment["BIKENAVI_PLAN_ID"], let id = UUID(uuidString: value),
           let preview = records.first(where: { $0.id == id && !$0.deleted }) {
            plan = preview.document
            UserDefaults.standard.set(value, forKey: "currentPlan")
        }
        if ProcessInfo.processInfo.environment["BIKENAVI_MARINE_PREVIEW"] == "1",
           plan.id.uuidString == "960E36CE-B7A2-48B4-B49A-6DA189641DAD", let origin = plan.startPoint?.coordinate {
            if activeRide?.sourcePlanID != plan.id { activeRide = nil; notice = nil }
            marinePreviewTask = Task { [weak self] in
                for _ in 0..<300 {
                    guard let self else { return }
                    let sample = marinePreviewLocation(origin: origin)
                    location.locationManager(CLLocationManager(), didUpdateLocations: [sample])
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
        }
        // Explicit standstill fixture for documentation; excluded from Release builds.
        if let value = ProcessInfo.processInfo.environment["BIKENAVI_PREVIEW_LOCATION"] {
            let values = value.split(separator: ",").compactMap { Double($0) }
            if values.count == 2, (-90...90).contains(values[0]), (-180...180).contains(values[1]) {
                let sample = CLLocation(coordinate: .init(latitude: values[0], longitude: values[1]),
                                        altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5,
                                        course: 90, speed: 0, timestamp: Date())
                location.locationManager(CLLocationManager(), didUpdateLocations: [sample])
            }
        }
        if ProcessInfo.processInfo.environment["BIKENAVI_START_LOCATION_TEST"] != nil {
            // Synthetic public coordinates, only for deterministic simulator regression tests.
            let a = Coordinate(latitude: 49.414601, longitude: 8.681496)
            let b = Coordinate(latitude: 49.415, longitude: 8.682)
            plan = TourDocument()
            plan.title = "Standorttest · Beispieltour"
            plan.waypoints = [Waypoint(name: "Beispielstart", coordinate: a), Waypoint(name: "Beispielziel", coordinate: b)]
            plan.route = CalculatedRoute(id: UUID(), coordinates: [a, b], distance: 60, duration: 30,
                ascent: 0, descent: 0, maneuvers: [], surfaces: [], warnings: [], provider: "Beispieldaten", calculatedAt: 0)
            if ProcessInfo.processInfo.environment["BIKENAVI_FREE_RIDE_TEST"] == "1" {
                plan.route = nil
            }
            activeRide = nil
            location.denied = true // Simulate a stale error from a previous callback.
            selectedMapStyle = .standard
            serverURL = ""
            return
        }
        if ProcessInfo.processInfo.environment["BIKENAVI_CAR_PREVIEW"] == "1" {
            guard let url = Bundle.main.url(forResource: "heidelberg-car-route", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let route = try? JSONDecoder().decode(CalculatedRoute.self, from: data),
                  let origin = route.coordinates.first, let destination = route.coordinates.last else {
                errorMessage = "Die öffentliche Auto-Beispielroute fehlt."; return
            }
            let heading = route.coordinates.dropFirst().first(where: { origin.distance(to: $0) > 1 })
                .map { LocalGeometry.bearing(origin, $0) } ?? 0
            plan = TourDocument()
            plan.title = "Heidelberg · Auto-Beispiel"
            plan.profile.mode = .car
            plan.waypoints = [Waypoint(name: "Beispielstart Heidelberg", coordinate: origin), Waypoint(name: "Beispielziel Neuenheim", coordinate: destination)]
            plan.route = route
            activeRide = nil; serverURL = ""; token = ""; selectedMapStyle = .standard
            if ProcessInfo.processInfo.environment["BIKENAVI_POI_PREVIEW"] == "1" {
                serverURL = "https://127.0.0.1:18446"
                token = "public-poi-example-token"
                if let rawMode = ProcessInfo.processInfo.environment["BIKENAVI_POI_MODE"], let mode = TravelMode(rawValue: rawMode), mode != .car {
                    plan.profile.mode = mode
                    plan.title = "POI · öffentliches UI-Beispiel"
                    plan.route = nil
                    selectedMapStyle = defaultMapStyle(mode)
                }
            }
            notice = nil; voice = false
            marinePreviewTask = Task { [weak self] in
                for _ in 0..<300 {
                    guard let self else { return }
                    let sample = CLLocation(coordinate: origin.cl, altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5,
                        course: heading, speed: plan.profile.mode == .car ? 14 : 0, timestamp: Date())
                    location.locationManager(CLLocationManager(), didUpdateLocations: [sample])
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                }
            }
            return
        }
        if ProcessInfo.processInfo.environment["BIKENAVI_CONFIGURE"] == "1" {
            Task { await saveSettings() }
        }
        #endif
        if plan.isAwaitingStart { Task { requestAutomaticStart() } }
        else if plan.waypoints.count >= 2 { Task { refreshPlanName() } }
    }

    func restoreLocalRouting() {
        if plan.profile.mode == .sea && plan.route != nil && (plan.route?.marineDraft != boatDraft || !MarineNavigation.current(plan.route)) { invalidateRoute(showErrorAlert: false) }
        if activeRide?.profile.mode == .sea || (activeRide == nil && plan.profile.mode == .sea) { selectedMapStyle = .seamap }
        if let ride = activeRide, let route = ride.route {
            navigationRoute = ride.profile.mode == .car ? (ride.localNavigation?.carRoute ?? route) : LocalRouteMetrics.combined(original: route, state: ride.localNavigation, profile: ride.profile)
            tracker = RouteTracker(lastProgress: ride.localNavigation?.routeProgress ?? 0, lastTimestamp: Date().timeIntervalSince1970)
            originalTracker = RouteTracker(lastProgress: ride.localNavigation?.originalProgress ?? 0, lastTimestamp: Date().timeIntervalSince1970)
            if ride.profile.mode == .cycling {
            Task {
                do {
                    let graph = try await offlineRouting.load(route: route)
                    guard activeRide?.id == ride.id else { return }
                    rideGraph = graph
                    if route.needsLocalSurfaceRepair, Set(route.coordinates.map { OfflineTileID.at($0) }).isSubset(of: graph.tiles), var current = activeRide, current.id == ride.id {
                        current.route = route.repairingLocalSurfaces(graph: graph)
                        try store.save(current)
                        activeRide = current
                        navigationRoute = LocalRouteMetrics.combined(original: current.route!, state: current.localNavigation, profile: current.profile)
                    }
                    localRideStatus = nil
                } catch { if activeRide?.id == ride.id { localRideStatus = "Lokale Rückführung noch nicht vorbereitet" } }
            }
            } else {
                rideGraph = nil
                localRideStatus = ride.profile.mode == .sea ? nil : ride.profile.mode == .car ? CarNavigation.onlineNotice : "Gespeicherte Wanderroute · keine lokale Rückführung"
            }
        }
        prepareLocalRouting()
    }

    private func reportPreparation(id: UUID, done: Int, total: Int) {
        guard preparationID == id else { return }
        localRoutingStatus = "Wegenetz: \(done) von \(total) Bereichen gespeichert"
    }

    func prepareLocalRouting(refresh: Bool = false) {
        loadPlanElevation()
        guard plan.profile.mode == .cycling else {
            preparationTask?.cancel(); preparationID = nil; preparingLocalRouting = false
            preparedGraph = nil; preparedRouteID = nil
            localRoutingStatus = plan.profile.mode == .sea ? "Wasserweg gespeichert · Seekarte benötigt Internet" : plan.profile.mode == .car ? CarNavigation.onlineNotice : "Wanderroute offline gespeichert · keine lokale Rückführung"
            return
        }
        guard let route = plan.route, let center = location.freshCoordinate ?? route.coordinates.first else { return }
        if preparedRouteID == route.id && !refresh { return }
        preparationTask?.cancel()
        let id = UUID()
        preparationID = id
        preparingLocalRouting = true
        localRoutingStatus = "Wegenetz wird vorbereitet …"
        let api = api
        preparationTask = Task {
            defer { if preparationID == id { preparingLocalRouting = false } }
            do {
                let graph = try await offlineRouting.prepareNeighborhood(route: route, center: center, api: api, refresh: refresh) { [weak self] done, total in
                    await self?.reportPreparation(id: id, done: done, total: total)
                }
                guard !Task.isCancelled, preparationID == id, plan.route?.id == route.id else { return }
                if let current = plan.route, current.needsLocalSurfaceRepair,
                   Set(current.coordinates.map { OfflineTileID.at($0) }).isSubset(of: graph.tiles) {
                    plan.route = current.repairingLocalSurfaces(graph: graph)
                    savePlan()
                }
                preparedGraph = graph
                preparedRouteID = route.id
                localRoutingStatus = "Rückführung im geladenen 3-km-Umkreis bereit"

            } catch {
                guard !Task.isCancelled, preparationID == id else { return }
                localRoutingStatus = (localRoutingReady ? "Gespeichertes Wegenetz weiterhin bereit. Aktualisierung ausstehend: " : "Lokale Rückführung nicht bereit: ") + error.localizedDescription
            }
        }
    }

    private func cancelElevation() {
        elevationTask?.cancel()
        elevationRequestID = nil
        loadingElevation = false
        elevationError = nil
    }

    func loadPlanElevation() {
        guard plan.profile.mode != .sea && plan.profile.mode != .car else { return }
        guard let route = plan.route, !route.hasElevation, !loadingElevation else { return }
        guard let api else {
            elevationError = "Verbinde den Pi, um die Höhendaten zu laden."
            return
        }
        let planID = plan.id
        let requestID = UUID()
        elevationRequestID = requestID
        loadingElevation = true
        elevationError = nil
        elevationTask = Task {
            defer {
                if elevationRequestID == requestID { loadingElevation = false; elevationRequestID = nil }
            }
            do {
                let sampling = try RouteElevation.sample(route)
                let response = try await api.elevations(sampling.coordinates)
                guard !Task.isCancelled, elevationRequestID == requestID,
                      plan.id == planID, let current = plan.route, current.id == route.id else { return }
                let elevated = try RouteElevation.applying(response, sampling: sampling, to: current)
                plan.route = elevated
                savePlan()
                await sync()
            } catch {
                guard !Task.isCancelled, elevationRequestID == requestID,
                      plan.id == planID, plan.route?.id == route.id else { return }
                if let apiError = error as? APIError {
                    elevationError = apiError.message
                } else if error is URLError {
                    elevationError = "Der Pi ist gerade nicht erreichbar. Die Route bleibt nutzbar. Prüfe die Verbindung und versuche es erneut."
                } else {
                    elevationError = "Die empfangenen Höhendaten passen nicht vollständig zur Route. Die Route bleibt nutzbar; versuche es erneut."
                }
            }
        }
    }

    var api: APIClient? {
        guard let url = URL(string: serverURL), url.scheme == "https", url.host != nil, !token.isEmpty else { return nil }
        return APIClient(baseURL: url, token: token)
    }
    var currentRecord: SavedRecord? { records.first { $0.id == plan.id } }
    var automaticStartMessage: String? {
        guard plan.isAwaitingStart else { return nil }
        return location.denied
            ? "Dein Ziel ist gespeichert. Erlaube den Standortzugriff in den iPhone-Einstellungen oder wähle einen Start auf der Karte."
            : (location.failureMessage ?? "Dein Ziel ist gespeichert. Dein aktueller Standort wird als Start ermittelt. Danach startet die Planung automatisch.")
    }

    func reload() {
        do {
            records = try store.all()
        } catch { errorMessage = error.localizedDescription }
        // Load places independently: an unreadable tour must not hide saved places.
        do {
            savedPlaces = try store.places()
        } catch {
            errorMessage = "Deine gespeicherten Orte konnten nicht geladen werden. " + error.localizedDescription
        }
    }
    func savePlace(name: String, coordinate: Coordinate) {
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !cleaned.isEmpty else { errorMessage = "Gib dem gespeicherten Ort einen Namen."; return }
        guard !savedPlaces.contains(where: { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame && $0.coordinate.distance(to: coordinate) < 10 }) else { return }
        do {
            try store.save(SavedPlace(name: cleaned, coordinate: coordinate))
            reload()
            refreshTitleForSavedPlaces()
        } catch { errorMessage = error.localizedDescription }
    }
    func savePlace(_ waypoint: Waypoint) { savePlace(name: waypoint.name, coordinate: waypoint.coordinate) }
    func renamePlace(_ place: SavedPlace, to name: String) {
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !cleaned.isEmpty else { errorMessage = "Gib dem gespeicherten Ort einen Namen."; return }
        do {
            var revised = place
            revised.name = cleaned
            try store.save(revised)
            reload()
            refreshTitleForSavedPlaces()
        } catch { errorMessage = error.localizedDescription }
    }
    func deletePlace(_ place: SavedPlace) {
        do { try store.delete(place); reload(); refreshTitleForSavedPlaces() } catch { errorMessage = error.localizedDescription }
    }
    private func refreshTitleForSavedPlaces() {
        let oldTitle = plan.title
        plan.updateAutomaticTitle(savedPlaces: savedPlaces)
        if plan.title != oldTitle { savePlan() }
    }
    @discardableResult
    func savePlan() -> Bool {
        do {
            plan.updateAutomaticTitle(savedPlaces: savedPlaces)
            var snapshot = plan
            if snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { snapshot.title = "Meine nächste Tour" }
            try store.save(snapshot)
            UserDefaults.standard.set(plan.id.uuidString, forKey: "currentPlan")
            UserDefaults.standard.set(plan.id.uuidString, forKey: workspacePlanKey(plan.profile.mode))
            reload()
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func renamePlan(to value: String) {
        plan.rename(to: value)
        savePlan()
    }
    func finishRenamingPlan() {
        plan.finishRenaming()
        savePlan()
    }
    func refreshPlanName() {
        nameTask?.cancel()
        savePlan()
        guard let api, plan.canCalculateRoute,
              let start = plan.waypoints.first, let destination = plan.waypoints.last else { return }
        let endpoints = [start, destination].filter(\.needsPlaceName)
        guard !endpoints.isEmpty else { return }
        let planID = plan.id
        nameTask = Task {
            for point in endpoints {
                guard !Task.isCancelled else { return }
                // Name lookup is optional: offline planning and routing keep working.
                guard let result = try? await api.placeName(at: point.coordinate),
                      !Task.isCancelled, plan.id == planID else { continue }
                if let name = result.name, plan.resolveName(name, for: point) { savePlan() }
            }
            if !Task.isCancelled { await sync() }
        }
    }
    func addPoint(_ point: Waypoint, role: PointRole) {
        switch role {
        case .start:
            requestedStartPlanID = nil
            plan.setStart(point)
        case .destination:
            routeWhenReady = true
            plan.setDestination(point, currentPosition: location.freshCoordinate)
        case .via:
            plan.waypoints.insert(point, at: max(0, plan.waypoints.count - 1))
        }
        mapFocus = point.coordinate
        invalidateRoute()
        if plan.isAwaitingStart { requestAutomaticStart() }
        calculateRouteWhenReady()
    }

    /// Adds a place without making the person choose a technical point type.
    /// The first selected place becomes the destination; later places are added
    /// before it, preserving the existing destination.
    func addPlaceToTour(_ point: Waypoint) {
        let role: PointRole = plan.destinationPoint == nil ? .destination : .via
        addPoint(point, role: role)
    }
    func addSavedPlace(_ place: SavedPlace, role: PointRole) {
        routeWhenReady = true
        addPoint(place.waypoint, role: role)
        if plan.isAwaitingStart {
            notice = "Ziel gewählt. Dein aktueller Standort wird noch als Start ermittelt."
        }
    }
    private func calculateRouteWhenReady() {
        guard routeWhenReady, plan.canCalculateRoute else { return }
        routeWhenReady = false
        routeTask?.cancel()
        routeTask = Task { await calculateRoute() }
    }
    func useCurrentLocation() {
        requestedStartPlanID = plan.id
        location.request()
        guard let coordinate = location.freshCoordinate else {
            notice = location.denied ? "Bitte Standortzugriff in den iPhone-Einstellungen erlauben oder einen Start auf der Karte wählen." : "Standort wird ermittelt und anschließend als Start übernommen."
            return
        }
        addPoint(Waypoint(name: "Mein Standort", coordinate: coordinate), role: .start)
    }
    func reversePlan() {
        guard plan.reverseWaypoints() else {
            errorMessage = "Zum Umkehren werden ein Start und ein Ziel benötigt."
            return
        }
        mapFocus = plan.startPoint?.coordinate
        invalidateRoute()
    }
    private func requestAutomaticStart() {
        guard plan.isAwaitingStart else { return }
        location.request()
        if let coordinate = location.freshCoordinate, plan.completeAutomaticStart(coordinate) {
            invalidateRoute()
        }
    }
    func invalidateRoute(showErrorAlert: Bool = true) {
        cancelElevation()
        planningError = nil
        preparationTask?.cancel()
        preparationID = nil
        preparingLocalRouting = false
        routeTask?.cancel()
        routeCalculationID = nil
        calculating = false
        plan.route = nil
        if plan.waypoints.isEmpty { plan.awaitingStart = nil }
        refreshPlanName()
        guard plan.canCalculateRoute else { calculating = false; return }
        routeTask = Task {
            do { try await Task.sleep(for: .milliseconds(650)); await calculateRoute(showErrorAlert: showErrorAlert) } catch { }
        }
    }
    private func reportPlanning(id: UUID, done: Int, total: Int) {
        guard routeCalculationID == id else { return }
        localRoutingStatus = done < total ? "Wegedaten: \(done) von \(total) Bereichen geladen" : "Das iPhone berechnet die Route …"
    }
    func calculateRoute(showErrorAlert: Bool = true) async {
        guard plan.canCalculateRoute else { return }
        cancelElevation()
        preparationTask?.cancel(); preparationID = nil; preparingLocalRouting = false
        if plan.profile.mode == .sea {
            plan.profile.boatDraft = boatDraft
            plan.profile.boatSpeedKnots = boatSpeedKnots
        }
        let snapshot = plan
        planningError = nil
        let calculationID = UUID()
        routeCalculationID = calculationID
        localRoutingStatus = "Die Route wird berechnet …"
        calculating = true
        defer {
            if routeCalculationID == calculationID {
                calculating = false
                routeCalculationID = nil
            }
        }
        do {
            let route = try await offlineRouting.calculate(document: snapshot, api: api) { [weak self] done, total in
                await self?.reportPlanning(id: calculationID, done: done, total: total)
            }
            guard !Task.isCancelled, routeCalculationID == calculationID, snapshot.id == plan.id,
                  snapshot.waypoints.map(\.coordinate) == plan.waypoints.map(\.coordinate),
                  snapshot.profile == plan.profile else { return }
            plan.route = route
            preparedGraph = nil
            preparedRouteID = nil
            localRoutingStatus = snapshot.profile.mode == .sea ? "Kurse und Wegpunkte bereit" : "Route bereit · lokales Umfeld wird geladen"
            mapRevision = UUID()
            savePlan()
            prepareLocalRouting()
            calculating = false
            await sync()
        } catch {
            if !Task.isCancelled, routeCalculationID == calculationID {
                let message: String
                switch error as? LocalRoutingError {
                case .noConnection: message = "Im geladenen Wegenetz wurde keine passende Route gefunden. Prüfe Start, Ziel und die gewählten Wegbeläge."
                case .timedOut: message = "Die Routenberechnung hat ihr Suchlimit erreicht. Versuche es mit einem Zwischenziel erneut."
                default: message = error.localizedDescription
                }
                planningError = message
                if showErrorAlert { errorMessage = message }
            }
        }
    }
    func newPlan() {
        cancelElevation()
        planningError = nil
        preparationTask?.cancel()
        preparationID = nil
        preparingLocalRouting = false
        savePlan()
        routeTask?.cancel()
        routeCalculationID = nil
        nameTask?.cancel()
        requestedStartPlanID = nil
        routeWhenReady = false
        calculating = false
        plan = ApplicationWorkspace.newPlan(mode: applicationMode ?? plan.profile.mode, profile: plan.profile)
        savePlan()
    }
    func resetPlan() {
        cancelElevation()
        planningError = nil
        preparationTask?.cancel()
        preparationID = nil
        preparingLocalRouting = false
        routeTask?.cancel()
        routeCalculationID = nil
        nameTask?.cancel()
        requestedStartPlanID = nil
        routeWhenReady = false
        calculating = false
        let previousID = plan.id
        plan = ApplicationWorkspace.newPlan(mode: applicationMode ?? plan.profile.mode, profile: plan.profile)
        plan.id = previousID
        selectedPoint = nil
        mapFocus = nil
        mapRevision = UUID()
        savePlan()
    }
    func open(_ document: TourDocument) {
        cancelElevation()
        savePlan()
        routeTask?.cancel()
        routeCalculationID = nil
        calculating = false
        requestedStartPlanID = nil
        routeWhenReady = false
        planningError = nil
        plan = document.kind == .ride ? document.asNewPlan() : document
        applicationMode = plan.profile.mode
        selectedMapStyle = defaultMapStyle(plan.profile.mode)
        savePlan()
        mapRevision = UUID()
        refreshPlanName()
        if plan.isAwaitingStart { requestAutomaticStart() }
        if plan.profile.mode == .sea && (plan.route?.marineDraft != boatDraft || !MarineNavigation.current(plan.route)) { invalidateRoute(showErrorAlert: false) }
        else { prepareLocalRouting() }
        tab = 0
    }

    func delete(_ record: SavedRecord) {
        guard activeRide?.id != record.id else { errorMessage = "Bitte die aktive Fahrt zuerst beenden."; return }
        do {
            var deleted = record
            deleted.deleted = true
            deleted.dirty = true
            deleted.mutationID = UUID()
            try store.put(deleted)
            try store.deleteBlogData(rideID: record.id)
            routeDescriptionTasks[record.id]?.cancel()
            routeDescriptions[record.id] = nil
            try store.deleteRouteDescription(planID: record.id)
            if plan.id == record.id {
                cancelElevation()
                routeTask?.cancel()
                nameTask?.cancel()
                calculating = false
                plan = ApplicationWorkspace.newPlan(mode: applicationMode ?? plan.profile.mode, profile: plan.profile)
                UserDefaults.standard.removeObject(forKey: "currentPlan")
                UserDefaults.standard.removeObject(forKey: workspacePlanKey(plan.profile.mode))
            }
            reload()
            Task { await sync() }
        } catch { errorMessage = error.localizedDescription }
    }

    func recordBikeMeasurement(_ measurement: BikeMeasurement) {
        guard !isMarinePresentation, let ride = activeRide, ride.profile.mode.supportsBike, !isWalkingSection, ride.recordingState == .recording else { return }
        do {
            try store.append(RecordedBikeSample(rideID: ride.id, sourcePlanID: ride.sourcePlanID ?? ride.id,
                segment: segment, position: ride.track.last, measurement: measurement))
        } catch {
            // Stop rather than silently continuing a ride whose data cannot be saved.
            var paused = ride
            paused.recordingState = .paused
            activeRide = paused
            segment += 1
            cancelNeighborhood(); location.setRiding(false)

            try? store.save(paused)
            rideActivity.update(progress: progress, route: paused.route, paused: true, rerouting: false)
            errorMessage = "Bike-Daten konnten nicht gespeichert werden. Die Fahrt wurde pausiert: " + error.localizedDescription
        }
    }

    func sync() async {
        guard !synchronizing, let api else { return }
        let planAtStart = plan
        synchronizing = true
        defer { synchronizing = false; reload() }
        do {
            for record in try store.all() where record.dirty {
                if record.document.recordingState == .recording {
                    let pendingPoints = try store.blogPoints(rideID: record.id, pendingOnly: true)
                    if pendingPoints.isEmpty { continue }
                }
                do {
                    let response = try await api.send(record)
                    try store.acknowledge(record, remote: response)
                } catch let error as APIError where error.status == 409 {
                    let current = try store.all().first { $0.id == record.id } ?? record
                    try store.preserveConflict(current)
                    try store.setCursor(0)
                    notice = "Zwei Fassungen gefunden. Deine Änderungen wurden als lokale Fassung erhalten."
                }
            }
            // Completed/paused rides are sent first, then immutable measurements in small batches.
            // A retry sends the same IDs; the Pi acknowledges only durable inserts.
            for record in try store.all() where !record.dirty && !record.deleted && record.document.kind == .ride {
                while true {
                    let samples = try store.bikeSamples(rideID: record.id, pendingOnly: true)
                    if samples.isEmpty { break }
                    let receipt: BikeSampleReceipt = try await api.request("/v1/bike-samples", method: "POST",
                        body: JSONEncoder().encode(BikeSampleBatch(samples: samples)))
                    guard Set(receipt.accepted) == Set(samples.map(\.id)) else {
                        throw APIError(status: 0, message: "Der Pi hat die Bike-Daten noch nicht vollständig bestätigt.")
                    }
                    try store.acknowledgeBikeSamples(receipt.accepted)
                }
            }
            // A recording snapshot is sent when a blog point needs its parent ride.
            // New GPS samples can keep the document dirty while its points upload.
            for record in try store.all() where !record.deleted && record.document.kind == .ride && record.revision > 0 {
                for point in try store.blogPoints(rideID: record.id, pendingOnly: true) {
                    let remote: BlogPoint = try await api.request("/v1/blog-points/\(point.id.uuidString)", method: "PUT", body: JSONEncoder().encode(point))
                    try store.acknowledgeBlogPoint(point, remote: remote)
                }
            }
            var hasMore = true
            while hasMore {
                let page: ChangePage = try await api.request("/v1/changes?after=\(store.cursor)")
                for remote in page.records {
                    try store.merge(remote)
                    if remote.deleted, try store.record(id: remote.document.id)?.deleted == true { try store.deleteBlogData(rideID: remote.document.id) }
                }
                try store.setCursor(page.cursor)
                hasMore = page.hasMore
            }
            for record in try store.all() where !record.deleted && record.document.kind == .ride && record.revision > 0 {
                var more = true
                while more {
                    let page: BlogPointPage = try await api.request("/v1/rides/\(record.id.uuidString)/blog-points?after=\(try store.blogCursor(rideID: record.id))")
                    for point in page.points { try store.appendBlogPoint(point, uploaded: true) }
                    try store.setBlogCursor(page.cursor, rideID: record.id)
                    more = page.hasMore
                }
            }
            if plan == planAtStart,
               let latest = try store.all().first(where: { $0.id == plan.id && !$0.dirty && !$0.deleted }) {
                plan = latest.document
                if plan.route?.id != planAtStart.route?.id { prepareLocalRouting() }
            }
        } catch { notice = "Lokal gespeichert · Abgleich ausstehend: \(error.localizedDescription)" }
    }
    func saveSettings() async {
        do {
            guard api != nil else { throw APIError(status: 0, message: "Bitte eine HTTPS-Serveradresse und den BikeNavi-Zugangsschlüssel eintragen.") }
            if UserDefaults.standard.string(forKey: "serverURL") != serverURL {
                try store.setCursor(0)
                try store.resetBikeUploads()
                try store.resetBlogUploads()
                // A different server has its own revision history. Preserve all local documents.
                for var record in try store.all() { record.revision = 0; record.dirty = true; record.mutationID = UUID(); try store.put(record) }
            }
            try Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
            token = Keychain.read()
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            UserDefaults.standard.set(customMapStyleURL, forKey: "mapStyleURL")
            UserDefaults.standard.set(offlineMapsAllowed, forKey: "offlineMapsAllowed")
            let _: ServerStatus = try await api!.request("/v1/status")
            notice = "Mit dem Pi-Datenspeicher verbunden. Routen berechnet das iPhone."
            await sync()
        } catch { errorMessage = error.localizedDescription }
    }
    func saveBlogPoint(_ point: BlogPoint, at position: Int? = nil, original: BlogPoint? = nil) throws {
        let points = try store.blogPoints(rideID: point.rideID)
        try store.saveBlogPoint(point, at: position ?? points.count, original: original)
        reload()
        Task { await sync() }
    }

    func generateBlog(rideID: UUID) async throws -> BlogDraft {
        if let existing = blogGenerationTasks[rideID] { return try await existing.value }
        guard let api else { throw APIError(status: 0, message: "Verbinde den Pi in den Einstellungen, um einen Blog zu erstellen.") }
        let generationID = UUID()
        let now = Date().timeIntervalSince1970
        blogGeneration[rideID] = BlogGenerationProgress(generationID: generationID, rideID: rideID,
            phase: "synchronizing", startedAt: now, updatedAt: now)
        let task = Task { [self] in
            defer { blogGenerationTasks[rideID] = nil }
            do {
                while synchronizing { try await Task.sleep(for: .milliseconds(200)) }
                await sync()
                guard let record = try store.record(id: rideID), !record.deleted, !record.dirty,
                      record.document.recordingState == .finished,
                      try store.blogPoints(rideID: rideID, pendingOnly: true).isEmpty else {
                    throw APIError(status: 0, message: "Bitte die Fahrt beenden und alle Blog-Orte zum Pi übertragen. Der Abgleich ist noch ausstehend.")
                }
                let job: BlogGenerationProgress
                do {
                    job = try await api.request("/v1/rides/\(rideID.uuidString)/blog-jobs?generation_id=\(generationID.uuidString)", method: "POST", timeout: 15)
                } catch {
                    // Recover a lost acceptance response without creating another job.
                    guard let accepted: BlogGenerationProgress = try? await api.request("/v1/rides/\(rideID.uuidString)/blog-jobs/\(generationID.uuidString)", timeout: 10) else { throw error }
                    job = accepted
                }
                return try await followBlogJob(job, api: api)
            } catch {
                failBlogJob(rideID: rideID, error: error)
                throw error
            }
        }
        blogGenerationTasks[rideID] = task
        return try await task.value
    }

    func resumeBlogGeneration(rideID: UUID) async {
        guard blogGenerationTasks[rideID] == nil, let api else { return }
        guard let job: BlogGenerationProgress = (try? await api.request("/v1/rides/\(rideID.uuidString)/blog-jobs", timeout: 10)) ?? nil else { return }
        // Another view may have started following the job while this GET awaited.
        guard blogGenerationTasks[rideID] == nil else { return }
        if job.phase == "failed" { blogGeneration[rideID] = job; return }
        let task = Task { [self] in
            defer { blogGenerationTasks[rideID] = nil }
            do { return try await followBlogJob(job, api: api) }
            catch { failBlogJob(rideID: rideID, error: error); throw error }
        }
        blogGenerationTasks[rideID] = task
        _ = try? await task.value
    }

    private func followBlogJob(_ initial: BlogGenerationProgress, api: APIClient) async throws -> BlogDraft {
        var job = initial
        let rideID = job.rideID
        let deadline = ContinuousClock.now.advanced(by: .seconds(300))
        while true {
            blogGeneration[rideID] = job
            if job.phase == "failed" {
                throw APIError(status: 502, message: job.message ?? "Der Pi konnte den Blog nicht fertigstellen.")
            }
            if job.phase == "completed", let draftID = job.draftID {
                blogGeneration[rideID]?.phase = "downloading"
                let draft: BlogDraft = try await api.request("/v1/rides/\(rideID.uuidString)/blog?draft_id=\(draftID.uuidString)")
                try store.saveBlogDraft(draft)
                blogGeneration[rideID] = job
                return draft
            }
            guard ContinuousClock.now < deadline else {
                throw APIError(status: 0, message: "Der Pi-Auftrag ist noch nicht abgeschlossen oder gerade nicht erreichbar. Öffne den Blogbereich erneut, um den bestehenden Auftrag abzurufen.")
            }
            try await Task.sleep(for: .seconds(2))
            do {
                job = try await api.request("/v1/rides/\(rideID.uuidString)/blog-jobs/\(job.generationID.uuidString)", timeout: 10)
            } catch let error as APIError where [401, 404].contains(error.status) { throw error }
            catch {
                job.connectionInterrupted = true
                blogGeneration[rideID] = job
            }
        }
    }

    private func failBlogJob(rideID: UUID, error: Error) {
        blogGeneration[rideID]?.phase = (error as? APIError)?.status == 0 ? "unreachable" : "failed"
        blogGeneration[rideID]?.message = error.localizedDescription
    }

    /// Reapply after foreground transitions; recording state is the source of
    /// truth across tabs, sheets, pauses and storage-error recovery.
    func updateScreenAwake(sceneActive: Bool? = nil) {
        if let sceneActive { self.sceneActive = sceneActive }
        UIApplication.shared.isIdleTimerDisabled = self.sceneActive && activeRide?.recordingState == .recording
    }

    func startRide() {
        guard activeRide == nil else { tab = 1; return }
        guard !waitingForRideLocation else { return }
        if plan.profile.mode == .sea, let route = plan.route, (route.provider != "Seeweg · OSM-Wasserwege" || route.marineDraft != boatDraft || !MarineNavigation.current(route)) {
            errorMessage = "Berechne den Seeweg mit der aktuellen Gefahrenstellenprüfung und dem eingestellten Tiefgang erneut. EMODnet-Planungen sind nicht zur Navigation geeignet."
            return
        }
        location.request()
        guard !location.denied else {
            errorMessage = "Bitte erlaube BikeNavi den Standortzugriff in den iPhone-Einstellungen."
            return
        }
        guard location.freshCoordinate != nil else {
            waitingForRideLocation = true
            let planID = plan.id, routeID = plan.route?.id
            #if DEBUG
            if ProcessInfo.processInfo.environment["BIKENAVI_START_LOCATION_TEST"] == "delayed" {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(5))
                    let sample = CLLocation(coordinate: .init(latitude: 49.414601, longitude: 8.681496),
                        altitude: 114, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
                    self?.location.locationManager(CLLocationManager(), didUpdateLocations: [sample])
                }
            }
            #endif
            rideStartTask = Task { [weak self] in
                let deadline = ContinuousClock.now.advanced(by: .seconds(15))
                while !Task.isCancelled {
                    guard let self else { return }
                    guard self.plan.id == planID, self.plan.route?.id == routeID, self.activeRide == nil else {
                        self.cancelRideStart(); return
                    }
                    if self.location.denied {
                        self.cancelRideStart()
                        self.errorMessage = "Bitte erlaube BikeNavi den Standortzugriff in den iPhone-Einstellungen."
                        return
                    }
                    if self.location.freshCoordinate != nil {
                        self.cancelRideStart()
                        self.startRide()
                        return
                    }
                    if ContinuousClock.now >= deadline {
                        self.cancelRideStart()
                        self.errorMessage = "Noch kein aktueller Standort verfügbar. Bitte versuche den Fahrtstart erneut."
                        return
                    }
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
            }
            return
        }
        let followsRoute = plan.canCalculateRoute && plan.route != nil && (!isMarinePresentation || plan.profile.mode == .sea)
        var ride = followsRoute ? plan : TourDocument()
        ride.id = UUID()
        ride.kind = .ride
        ride.sourcePlanID = followsRoute ? plan.id : nil
        ride.localNavigation = followsRoute ? LocalNavigationState() : nil
        if followsRoute && ride.profile.mode == .car { ride.localNavigation?.carPendingWaypointOrdinals = Array(ride.waypoints.indices.dropFirst()) }
        if followsRoute && ride.profile.mode == .sea { ride.localNavigation?.marineNextWaypointIndex = 1 }
        if !followsRoute {
            ride.title = isMarinePresentation ? "Fahrt auf See" : plan.profile.mode == .car ? "Freie Autofahrt" : plan.profile.mode == .hiking ? "Freie Wanderung" : "Freie Fahrt"
            ride.profile = plan.profile
            if isMarinePresentation { ride.profile.mode = .sea }
        }
        ride.track = []
        ride.movingDuration = 0
        ride.endedAt = nil
        ride.createdAt = Date().timeIntervalSince1970
        ride.startedAt = ride.createdAt
        ride.recordingState = .recording
        #if DEBUG
        if ProcessInfo.processInfo.environment["BIKENAVI_PREVIEW_SKIP"] == "1", let route = ride.route, route.coordinates.count > 4 {
            let a = route.coordinates.count / 3, b = route.coordinates.count * 2 / 3
            ride.waypoints = [ride.waypoints.first!, Waypoint(name: "Beispiel: Aussichtspunkt", coordinate: route.coordinates[a]),
                Waypoint(name: "Beispiel: Rastplatz", coordinate: route.coordinates[b]), ride.waypoints.last!]
            ride.route?.waypointIndices = [0, a, b, route.coordinates.count - 1]
        }
        #endif
        do {
            try store.save(ride)
            activeRide = ride
            navigationRoute = ride.route
            progress = nil
            rideGraph = followsRoute && localRoutingReady ? preparedGraph : nil
            localRideStatus = !followsRoute || ride.profile.mode == .sea ? nil : ride.profile.mode == .cycling
                ? (rideGraph == nil ? "Lokale Rückführung noch nicht vorbereitet" : nil)
                : ride.profile.mode == .car ? CarNavigation.onlineNotice : "Gespeicherte Wanderroute · keine lokale Rückführung"
            originalTracker = RouteTracker(lastProgress: 0, lastTimestamp: Date().timeIntervalSince1970)
            tracker = RouteTracker(lastProgress: 0, lastTimestamp: Date().timeIntervalSince1970)
            reroutePolicy = ReroutePolicy()
            waypointSkipProposal = []; declinedWaypointSkips = []
            #if DEBUG
            if ProcessInfo.processInfo.environment["BIKENAVI_PREVIEW_SKIP"] == "1" { waypointSkipProposal = [1, 2] }
            #endif
            segment = 0
            lastAnnouncement = nil
            carZoom = CarAutoZoom(); carLookAhead = 450; carVoice = CarVoiceGuidance()
            carRerouteAttempt = -.infinity; carArrivalAnnounced = false
            location.setRiding(true)

            rideActivity.start(tourName: ride.title, route: ride.route)
            if let sample = location.latestSample { receive(sample) }
            tab = 1
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
    /// Opening the driving tab follows the same checks as the start button.
    func openRide() {
        if applicationMode != nil, activeRide != nil { return }
        // The planning tab is the source of truth when it has a ready route.
        // A paused ride from an earlier session must not unexpectedly replace it.
        if plan.canCalculateRoute, plan.route != nil,
           activeRide?.route?.id != plan.route?.id {
            archivePreviousRideIfNeeded()
        }
        guard activeRide == nil else { return }
        startRide()
    }
    private func archivePreviousRideIfNeeded() {
        guard var previous = activeRide else { return }
        cancelRerouting()
        previous.recordingState = .finished
        previous.endedAt = Date().timeIntervalSince1970
        do {
            try store.save(previous)
            activeRide = nil
            if previous.profile.mode == .sea && plan.profile.mode != .sea && selectedMapStyle == .seamap {
                selectedMapStyle = .standard
            }
            navigationRoute = nil
            rideGraph = nil
            localRideStatus = nil
            progress = nil
            cancelNeighborhood(); location.setRiding(false)

            rideActivity.end()
            reload()
            notice = "Die vorherige unterbrochene Fahrt wurde in Touren gespeichert."
        } catch { errorMessage = error.localizedDescription }
    }
    func togglePause() {
        cancelNeighborhood()
        guard var ride = activeRide else { return }
        cancelRerouting()
        ride.recordingState = ride.recordingState == .recording ? .paused : .recording
        segment += 1
        if ride.profile.mode == .car {
            carRerouteAttempt = -.infinity
            reroutePolicy = ReroutePolicy()
        }
        do {
            try store.save(ride)
            activeRide = ride
            location.setRiding(ride.recordingState == .recording)

            if ride.recordingState == .recording { rideActivity.start(tourName: ride.title, route: ride.route) }
            else { rideActivity.update(progress: progress, route: ridingRoute, paused: true, rerouting: false); Task { await sync() } }
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
    private func cancelNeighborhood() {
        neighborhoodTask?.cancel(); neighborhoodTask = nil; neighborhoodRequestID = nil
        neighborhoodRideID = nil; neighborhoodAttempt = 0
    }

    private func cancelRerouting() {
        waypointSkipProposal = []
        speech.stopSpeaking(at: .immediate)
        rerouteTask?.cancel()
        rerouteTask = nil
        rerouteRequestID = nil
        rerouting = false
    }

    func discardRide() {
        guard let ride = activeRide else { return }
        do {
            try store.discardRide(id: ride.id)
            cancelRerouting()
            activeRide = nil
            navigationRoute = nil
            rideGraph = nil
            localRideStatus = nil
            progress = nil
            cancelNeighborhood(); location.setRiding(false)

            rideActivity.end()
            reload()
            tab = 2
            Task { await sync() }
        } catch { errorMessage = error.localizedDescription }
    }

    func finishRide() {
        guard var ride = activeRide else { return }
        cancelRerouting()
        ride.endedAt = Date().timeIntervalSince1970
        ride.recordingState = .finished
        do {
            try store.save(ride)
            activeRide = nil
            navigationRoute = nil
            rideGraph = nil
            localRideStatus = nil
            progress = nil
            cancelNeighborhood(); location.setRiding(false)

            rideActivity.end()
            reload()
            tab = 2
            Task { await sync() }
        } catch { errorMessage = error.localizedDescription }
    }
    private func speakCar(_ text: String) {
        stopVolumePreview()
        speech.stopSpeaking(at: .immediate)
        // Spoken navigation ducks music and uses the current audio route, including Bluetooth.
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try audio.setActive(true)
            navigationSpeechDelegate.ownsAudioSession = true
        } catch { localRideStatus = "Sprachausgabe konnte nicht aktiviert werden · Hinweise auf der Karte beachten" }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        speech.speak(utterance)
    }

    func poiSearch(category: POICategory, duringRide: Bool, origin: String = "location", radius: Int = 10) throws -> POISearchRequest {
        if duringRide {
            if let ride = activeRide, ride.profile.mode != .car {
                guard let coordinate = location.freshCoordinate else {
                    location.request()
                    throw APIError(status: 0, message: "Bitte auf einen aktuellen GPS-Standort warten.")
                }
                return POISearchRequest(category: category, center: coordinate, radius: radius, profile: ride.profile)
            }
            guard let ride = activeRide, ride.profile.mode == .car, carGPSIsFresh,
                  let coordinate = location.freshCoordinate, !rerouting else {
                throw APIError(status: 0, message: "Bitte auf einen aktuellen GPS-Standort und das Ende der Neuberechnung warten.")
            }
            var context: POIRouteContext?
            if let route = ridingRoute {
                guard let progress, progress.distanceFromRoute <= 35 else {
                    throw APIError(status: 0, message: "Bitte auf eine bestätigte Position auf der Route warten.")
                }
                let pending = CarNavigation.pending(ride: ride)
                guard !pending.isEmpty, pending.count <= 47, pending.allSatisfy({ ride.waypoints.indices.contains($0) }) else {
                    throw APIError(status: 0, message: "Zu viele oder keine offenen Ziele für einen weiteren Stopp.")
                }
                context = POIRouteContext(coordinates: route.coordinates, progress: progress.traveled,
                    pending: pending.map { ride.waypoints[$0] }, bearing: carHeading)
            }
            return POISearchRequest(category: category, center: coordinate, radius: radius, profile: ride.profile, context: context)
        }
        let center = origin == "start" ? plan.startPoint?.coordinate : origin == "destination" ? plan.destinationPoint?.coordinate : location.freshCoordinate
        guard let center else {
            location.request()
            throw APIError(status: 0, message: "Standort wird gesucht. Bitte erneut versuchen oder Start/Ziel als Suchort wählen.")
        }
        return POISearchRequest(category: category, center: center, radius: radius, profile: plan.profile)
    }

    func addPOIToRide(_ point: Waypoint) async throws {
        let request = try poiSearch(category: .fuel, duringRide: true)
        guard let api, let ride = activeRide, ride.profile.mode == .car, ride.waypoints.count < 50 else {
            throw APIError(status: 0, message: "Pi verbinden und höchstens 49 vorhandene Wegpunkte verwenden.")
        }
        let previousRouteID = ridingRoute?.id
        let pending = ride.route == nil ? [] : CarNavigation.pending(ride: ride)
        let requestedAt = Date().timeIntervalSince1970
        let response = try await api.routeToPOI(point, search: request)
        try Task.checkCancellation()
        guard var current = activeRide, current.id == ride.id, current.recordingState == ride.recordingState,
              current.waypoints == ride.waypoints, current.profile == ride.profile,
              ridingRoute?.id == previousRouteID, !rerouting,
              (current.route == nil ? [] : CarNavigation.pending(ride: current)) == pending,
              let latest = location.latestSample, carGPSIsFresh,
              let matched = CarNavigation.replacement(response.route, origin: request.center, requestedAt: requestedAt,
                current: Coordinate(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude),
                timestamp: latest.timestamp.timeIntervalSince1970, heading: carHeading, accuracy: latest.horizontalAccuracy,
                now: Date().timeIntervalSince1970),
              let stopIndex = response.route.waypointIndices?.dropFirst().first,
              response.route.coordinates.indices.contains(stopIndex),
              matched.traveled < LocalRouteMetrics.distances(response.route)[stopIndex] - 10 else {
            throw APIError(status: 409, message: "Fahrt oder Standort hat sich geändert. Bitte den Stopp erneut auswählen.")
        }
        var navigation = current.localNavigation ?? LocalNavigationState()
        if current.route == nil {
            current.waypoints = [Waypoint(name: "Start der Zielführung", coordinate: request.center), point]
            current.route = response.route
            navigation.carPendingWaypointOrdinals = [1]
        } else {
            let insertion = pending[0]
            current.waypoints.insert(point, at: insertion)
            navigation.carPendingWaypointOrdinals = [insertion] + pending.map { $0 >= insertion ? $0 + 1 : $0 }
        }
        navigation.carRoute = response.route
        navigation.routeProgress = matched.traveled
        navigation.carPOIStopID = point.id
        current.localNavigation = navigation
        try store.save(current)
        activeRide = current
        navigationRoute = response.route
        tracker = RouteTracker(lastProgress: matched.traveled, lastTimestamp: latest.timestamp.timeIntervalSince1970)
        progress = matched
        carVoice = CarVoiceGuidance(); carArrivalAnnounced = false
        reroutePolicy = ReroutePolicy()
        localRideStatus = "Stopp eingefügt · " + CarNavigation.trafficNotice
        reload()
        rideActivity.update(progress: progress, route: ridingRoute, paused: current.recordingState == .paused, rerouting: false)
    }

    var pendingPOIStop: Waypoint? {
        guard let ride = activeRide, let identifier = ride.localNavigation?.carPOIStopID,
              let index = ride.waypoints.firstIndex(where: { $0.id == identifier }),
              CarNavigation.pending(ride: ride).contains(index) else { return nil }
        return ride.waypoints[index]
    }

    func removePOIStop() async throws {
        guard let ride = activeRide, let stop = pendingPOIStop,
              let index = ride.waypoints.firstIndex(where: { $0.id == stop.id }), !rerouting else { return }
        let pending = CarNavigation.pending(ride: ride)
        let remaining = pending.filter { $0 != index }
        let previousRouteID = ridingRoute?.id
        if remaining.isEmpty {
            var current = ride
            current.route = nil; current.localNavigation = nil; current.waypoints = []
            try store.save(current)
            activeRide = current; navigationRoute = nil; progress = nil; tracker = RouteTracker()
            carVoice = CarVoiceGuidance(); carArrivalAnnounced = false
            localRideStatus = "Freie Autofahrt · Ziel entfernt"
            rideActivity.update(progress: nil, route: nil, paused: current.recordingState == .paused, rerouting: false)
            reload()
            return
        }
        guard let api, carGPSIsFresh, let coordinate = location.freshCoordinate else {
            throw APIError(status: 0, message: "Zum Entfernen des Stopps werden Pi-Verbindung und ein aktueller Standort benötigt.")
        }
        var request = TourDocument(); request.profile = ride.profile
        request.waypoints = [Waypoint(name: "Aktueller Standort", coordinate: coordinate)] + remaining.map { ride.waypoints[$0] }
        let requestedAt = Date().timeIntervalSince1970
        let route = try await api.route(request, timeout: 40, includeContext: false, startBearing: carHeading)
        try Task.checkCancellation()
        guard var current = activeRide, current.id == ride.id, current.waypoints == ride.waypoints,
              current.recordingState == ride.recordingState, current.profile == ride.profile,
              ridingRoute?.id == previousRouteID, !rerouting, CarNavigation.pending(ride: current) == pending,
              let latest = location.latestSample, carGPSIsFresh,
              let matched = CarNavigation.replacement(route, origin: coordinate, requestedAt: requestedAt,
                current: Coordinate(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude),
                timestamp: latest.timestamp.timeIntervalSince1970, heading: carHeading, accuracy: latest.horizontalAccuracy,
                now: Date().timeIntervalSince1970) else {
            throw APIError(status: 409, message: "Fahrt oder Standort hat sich geändert. Bitte erneut versuchen.")
        }
        current.waypoints.remove(at: index)
        current.localNavigation?.carPendingWaypointOrdinals = remaining.map { $0 > index ? $0 - 1 : $0 }
        current.localNavigation?.carRoute = route
        current.localNavigation?.routeProgress = matched.traveled
        current.localNavigation?.carPOIStopID = nil
        try store.save(current)
        activeRide = current; navigationRoute = route; progress = matched
        tracker = RouteTracker(lastProgress: matched.traveled, lastTimestamp: latest.timestamp.timeIntervalSince1970)
        carVoice = CarVoiceGuidance(); carArrivalAnnounced = false; reroutePolicy = ReroutePolicy()
        localRideStatus = "Stopp entfernt · ursprüngliche Ziele bleiben erhalten"
        rideActivity.update(progress: progress, route: ridingRoute, paused: current.recordingState == .paused, rerouting: false)
        reload()
    }

    private func rerouteCar(from position: Coordinate, ride: TourDocument) {
        let now = Date().timeIntervalSince1970
        guard rerouteTask == nil, now - carRerouteAttempt >= 30, let original = ride.route else { return }
        carRerouteAttempt = now
        guard let api else {
            localRideStatus = "Neuberechnung nicht verfügbar · Internet und Pi verbinden"
            return
        }
        let pending = CarNavigation.pending(ride: ride)
        guard !pending.isEmpty else { return }
        var request = TourDocument()
        request.profile = ride.profile
        request.waypoints = [Waypoint(name: "Aktueller Standort", coordinate: position)] + pending.map { ride.waypoints[$0] }
        let id = UUID(), previousRouteID = ridingRoute?.id
        let startBearing = carHeading
        rerouteRequestID = id
        rerouting = true
        speech.stopSpeaking(at: .immediate)
        localRideStatus = "Pkw-Route wird neu berechnet"
        rerouteTask = Task {
            defer {
                if rerouteRequestID == id {
                    rerouteTask = nil; rerouteRequestID = nil; rerouting = false
                    rideActivity.update(progress: progress, route: ridingRoute,
                        paused: activeRide?.recordingState == .paused, rerouting: false)
                }
            }
            do {
                let route = try await api.route(request, timeout: 40, includeContext: false, startBearing: startBearing)
                try Task.checkCancellation()
                guard rerouteRequestID == id, ridingRoute?.id == previousRouteID,
                      var current = activeRide, current.id == ride.id, current.route?.id == original.id,
                      current.recordingState == .recording, CarNavigation.pending(ride: current) == pending,
                      let latest = location.latestSample,
                      route.waypointIndices?.count == pending.count + 1 else { return }
                let positionNow = Coordinate(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude)
                guard let match = CarNavigation.replacement(route, origin: position, requestedAt: now,
                    current: positionNow, timestamp: latest.timestamp.timeIntervalSince1970,
                    heading: latest.speed >= 1 && latest.course >= 0 ? latest.course : nil,
                    accuracy: latest.horizontalAccuracy, now: Date().timeIntervalSince1970) else {
                    localRideStatus = "Neue Route passt nicht mehr zum Standort · erneuter Versuch folgt"
                    return
                }
                var nav = current.localNavigation ?? LocalNavigationState()
                nav.carRoute = route
                nav.carPendingWaypointOrdinals = pending
                nav.routeProgress = match.traveled
                current.localNavigation = nav
                try store.save(current)
                activeRide = current
                navigationRoute = route
                tracker = RouteTracker(lastProgress: match.traveled, lastTimestamp: latest.timestamp.timeIntervalSince1970)
                progress = match
                carVoice = CarVoiceGuidance(); carArrivalAnnounced = false
                reroutePolicy = ReroutePolicy()
                localRideStatus = "Pkw-Route angepasst · Zwischenziele bleiben erhalten"
                reload()
            } catch {
                guard !Task.isCancelled, rerouteRequestID == id else { return }
                localRideStatus = "Neuberechnung nicht verfügbar: " + error.localizedDescription + " · erneuter Versuch folgt"
            }
        }
    }

    private func reroute(from position: Coordinate, heading: Double?, ride: TourDocument) {
        guard ride.profile.mode == .cycling else {
            localRideStatus = "Wanderroute verlassen · gespeicherte Strecke auf der Karte prüfen"
            return
        }
        guard rerouteTask == nil, let original = ride.route else { return }
        guard let graph = rideGraph else {
            localRideStatus = "Lokale Rückführung nicht vorbereitet · gespeicherte Tour auf der Karte"
            return
        }
        let requestID = UUID(), rideID = ride.id
        let routeID = ridingRoute?.id
        let navigation = ride.localNavigation ?? LocalNavigationState()
        rerouteRequestID = requestID
        rerouting = true
        localRideStatus = nil
        rerouteTask = Task {
            defer {
                if rerouteRequestID == requestID {
                    rerouteTask = nil; rerouteRequestID = nil; rerouting = false
                    if activeRide?.id == rideID {
                        rideActivity.update(progress: progress, route: ridingRoute,
                            paused: activeRide?.recordingState == .paused, rerouting: false)
                    }
                }
            }
            do {
                let work = Task.detached(priority: .userInitiated) {
                    try LocalRouter.connect(graph: graph, original: original, waypoints: ride.waypoints, profile: ride.profile,
                        position: position, heading: heading, traveled: navigation.originalProgress, usedUnpaved: navigation.usedUnpaved,
                        skippedWaypoints: navigation.skippedWaypointOrdinals ?? [])
                }
                let connection = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                guard rerouteRequestID == requestID, ridingRoute?.id == routeID,
                      var current = activeRide, current.id == rideID, current.recordingState == .recording,
                      let latest = location.latestSample, abs(latest.timestamp.timeIntervalSinceNow) < 5, latest.horizontalAccuracy <= 25,
                      let connector = LocalRouteMetrics.trim(connection.connector,
                        to: Coordinate(latitude: latest.coordinate.latitude, longitude: latest.coordinate.longitude),
                        heading: latest.speed >= 1 && latest.course >= 0 ? latest.course : nil, profile: current.profile),
                      (progress?.distanceFromRoute ?? .infinity) >= 25 else { return }
                var nav = current.localNavigation ?? LocalNavigationState()
                nav.connector = connector
                nav.rejoinIndex = connection.rejoinIndex
                nav.routeProgress = 0
                // Reserve the whole issued connector, including a prefix already ridden
                // while the calculation ran. Repeated detours never reset the 100 m budget.
                nav.usedUnpaved += connection.unpavedDistance
                current.localNavigation = nav
                try store.save(current)
                activeRide = current
                navigationRoute = LocalRouteMetrics.combined(original: original, state: nav, profile: current.profile)
                tracker = RouteTracker(lastProgress: 0, lastTimestamp: latest.timestamp.timeIntervalSince1970)
                progress = nil
                lastAnnouncement = nil
                localRideStatus = "Lokaler Anschluss zur Tour · \(Format.distance(connector.distance))"
                reload()
            } catch {
                guard !Task.isCancelled, rerouteRequestID == requestID else { return }
                localRideStatus = error.localizedDescription
            }
        }
    }
    func answerWaypointSkip(_ skip: Bool) {
        let proposal = waypointSkipProposal
        guard !proposal.isEmpty, var ride = activeRide, ride.recordingState == .recording else { return }
        if skip {
            var nav = ride.localNavigation ?? LocalNavigationState()
            nav.skippedWaypointOrdinals = Array(Set((nav.skippedWaypointOrdinals ?? []) + proposal)).sorted()
            nav.connector = nil; nav.rejoinIndex = nil
            nav.routeProgress = nav.originalProgress
            ride.localNavigation = nav
            do { try store.save(ride) } catch { errorMessage = error.localizedDescription; return }
            cancelRerouting()
            activeRide = ride
            navigationRoute = ride.route
            tracker = RouteTracker(lastProgress: nav.originalProgress, lastTimestamp: Date().timeIntervalSince1970)
            originalTracker = tracker
            progress = nil
            lastAnnouncement = nil
            reroutePolicy = ReroutePolicy()
        } else {
            declinedWaypointSkips.formUnion(proposal)
            waypointSkipProposal = []
        }
        if let sample = location.latestSample { receive(sample) }
    }

    private func proposeWaypointSkip(ride: TourDocument, position: Coordinate, heading: Double?) {
        guard let original = ride.route else { return }
        let nav = ride.localNavigation ?? LocalNavigationState()
        let pending = LocalRouteMetrics.pendingWaypoints(route: original, waypoints: ride.waypoints,
            traveled: nav.originalProgress, skipped: nav.skippedWaypointOrdinals ?? [])
        guard let next = pending.first else { waypointSkipProposal = []; return }
        var probe = RouteTracker()
        let match = probe.update(position: position, timestamp: Date().timeIntervalSince1970, route: original, heading: heading)
        let indices = LocalRouteMetrics.waypointIndices(route: original, waypoints: ride.waypoints)
        let distances = LocalRouteMetrics.distances(original)
        let passed = pending.filter { distances[indices[$0]] + 3 < (match?.traveled ?? 0) }
        let proposed = match?.snappedPosition != nil && !passed.isEmpty ? passed : [next]
        if !Set(proposed).isSubset(of: declinedWaypointSkips) { waypointSkipProposal = proposed }
    }

    /// Called only for fresh, accurate fixes. Keep the previous window on errors;
    /// retry after 30 seconds and never install data for another or paused ride.
    private func updateNeighborhood(ride: TourDocument, position: Coordinate) {
        guard ride.profile.mode == .cycling else { return }
        guard let route = ride.route, let required = try? OfflineTileID.neighborhood(position) else { return }
        if neighborhoodRideID != ride.id {
            neighborhoodTask?.cancel(); neighborhoodTask = nil; neighborhoodRequestID = nil
            neighborhoodRideID = ride.id; neighborhoodAttempt = 0
        }
        if let graph = rideGraph, (api == nil || graph.hasCurrentAccessRules),
           Set(required).isSubset(of: graph.tiles) { return }
        let now = Date().timeIntervalSince1970
        guard neighborhoodTask == nil, now - neighborhoodAttempt >= 30 else { return }
        neighborhoodAttempt = now
        let requestID = UUID()
        neighborhoodRequestID = requestID
        let api = api
        neighborhoodTask = Task {
            defer {
                if neighborhoodRequestID == requestID { neighborhoodTask = nil; neighborhoodRequestID = nil }
            }
            do {
                let graph = try await offlineRouting.prepareNeighborhood(route: route, center: position, api: api) { _, _ in }
                guard !Task.isCancelled, neighborhoodRequestID == requestID,
                      activeRide?.id == ride.id, activeRide?.recordingState == .recording else { return }
                rideGraph = graph
                localRideStatus = nil
            } catch {
                guard !Task.isCancelled, neighborhoodRequestID == requestID,
                      activeRide?.id == ride.id, activeRide?.recordingState == .recording else { return }
                localRideStatus = "Umfeld konnte nicht nachgeladen werden · Rückführung nur mit gespeicherten Wegedaten"
            }
        }
    }

    private func receive(_ sample: CLLocation) {
        if PlanningLocation.isUsable(timestamp: sample.timestamp.timeIntervalSince1970,
                                     accuracy: sample.horizontalAccuracy, now: Date().timeIntervalSince1970),
           let coordinate = location.freshCoordinate {
            if requestedStartPlanID == plan.id {
                addPoint(Waypoint(name: "Mein Standort", coordinate: coordinate), role: .start)
            } else if plan.completeAutomaticStart(coordinate) {
                invalidateRoute()
                calculateRouteWhenReady()
            }
        }
        guard var ride = activeRide, ride.recordingState == .recording else { return }
        let point = TrackPoint(coordinate: Coordinate(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude,
                                                     altitude: sample.verticalAccuracy >= 0 ? sample.altitude : nil),
                               timestamp: sample.timestamp.timeIntervalSince1970, accuracy: sample.horizontalAccuracy,
                               speed: max(0, sample.speed), segment: segment)
        let accepted = TrackFilter.accepts(point, after: ride.track.last, now: Date().timeIntervalSince1970, mode: ride.profile.mode)
        let previousPending = ride.localNavigation?.carPendingWaypointOrdinals
        if accepted {
            if let last = ride.track.last, last.segment == point.segment { ride.movingDuration += max(0, point.timestamp-last.timestamp) }
            ride.track.append(point)
        }
        let heading = sample.course >= 0 && sample.speed >= 1 ? sample.course : nil
        progress?.snappedPosition = nil
        if !isMarinePresentation, ride.profile.mode != .car, let original = ride.route, let route = ridingRoute, abs(sample.timestamp.timeIntervalSinceNow) < 5,
           sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 25 {
            updateNeighborhood(ride: ride, position: point.coordinate)
            var nav = ride.localNavigation ?? LocalNavigationState()
            // After a detour, also inspect distant portions of the original route.
            // Never silently cross an unvisited, unskipped mandatory stop.
            var recovery = RouteTracker()
            if (progress?.distanceFromRoute ?? 0) > 35 || (progress == nil && !(nav.skippedWaypointOrdinals ?? []).isEmpty),
               let match = recovery.update(position: point.coordinate, timestamp: point.timestamp,
                    route: original, heading: heading, accuracy: point.accuracy),
               match.snappedPosition != nil, match.traveled > nav.originalProgress + 25 {
                let mandatory = LocalRouteMetrics.nextWaypointIndex(route: original, waypoints: ride.waypoints,
                    traveled: nav.originalProgress, skipped: nav.skippedWaypointOrdinals ?? [])
                if match.traveled <= LocalRouteMetrics.distances(original)[mandatory] + 3 {
                    nav.originalProgress = match.traveled
                    nav.connector = nil; nav.rejoinIndex = nil
                    navigationRoute = original; tracker = recovery; originalTracker = recovery
                    cancelRerouting(); localRideStatus = nil
                }
            }
            progress = tracker.update(position: point.coordinate, timestamp: point.timestamp, route: ridingRoute ?? route, heading: heading, accuracy: point.accuracy)
            if nav.connector != nil, let join = nav.rejoinIndex {
                let connectorDistance = nav.connector.map { LocalRouteMetrics.distances($0).last ?? 0 } ?? 0
                if let p = progress, p.distanceFromRoute < 25, p.traveled >= connectorDistance {
                    let originalDistances = LocalRouteMetrics.distances(original)
                    if originalDistances.indices.contains(join) {
                        nav.originalProgress = originalDistances[join] + max(0,p.traveled-connectorDistance)
                        nav.usedUnpaved += LocalRouteMetrics.unpaved(original, from: originalDistances[join], to: nav.originalProgress)
                        originalTracker = RouteTracker(lastProgress: nav.originalProgress, lastTimestamp: point.timestamp)
                        nav.connector = nil; nav.rejoinIndex = nil
                        navigationRoute = original
                        tracker = originalTracker
                        progress = tracker.update(position: point.coordinate, timestamp: point.timestamp, route: original, heading: heading, accuracy: point.accuracy)
                        cancelRerouting(); localRideStatus = nil
                    }
                } else if let p = originalTracker.update(position: point.coordinate, timestamp: point.timestamp, route: original, heading: heading, accuracy: point.accuracy),
                          p.distanceFromRoute < 15, p.traveled >= nav.originalProgress-10 {
                    // A genuine return before the selected join also ends the detour.
                    let d = LocalRouteMetrics.distances(original)
                    let i = max(0, min(original.coordinates.count-2, (d.firstIndex(where: { $0 > p.traveled }) ?? 1)-1))
                    let mandatory = LocalRouteMetrics.nextWaypointIndex(route: original, waypoints: ride.waypoints, traveled: nav.originalProgress, skipped: nav.skippedWaypointOrdinals ?? [])
                    if p.traveled <= d[mandatory] + 3,
                       (heading.map({ LocalGeometry.angle($0, LocalGeometry.bearing(original.coordinates[i], original.coordinates[i+1])) <= 60 }) ?? true) {
                        nav.originalProgress = max(nav.originalProgress,p.traveled)
                        nav.connector = nil; nav.rejoinIndex = nil
                        navigationRoute = original; tracker = originalTracker; progress = p
                        cancelRerouting(); localRideStatus = nil
                    }
                }
            } else if let p = progress, p.distanceFromRoute < 25 {
                nav.usedUnpaved += LocalRouteMetrics.unpaved(original, from: nav.originalProgress, to: max(nav.originalProgress,p.traveled))
                nav.originalProgress = max(nav.originalProgress,p.traveled)
                originalTracker = tracker
                localRideStatus = nil
                if rerouting { cancelRerouting() }
            }
            nav.routeProgress = progress?.traveled ?? nav.routeProgress
            ride.localNavigation = nav
        }
        if ride.profile.mode == .car, carGPSIsFresh {
            rideActivity.carGPSDate = sample.timestamp
            if let route = ridingRoute {
                progress = tracker.update(position: point.coordinate, timestamp: point.timestamp, route: route,
                    heading: heading, accuracy: point.accuracy, carNavigation: true)
                if let current = progress {
                    progress = CarNavigation.requiringUnvisitedStop(ride: ride, route: route, progress: current, position: point.coordinate)
                }
                if let progress {
                    var nav = ride.localNavigation ?? LocalNavigationState()
                    nav.carPendingWaypointOrdinals = CarNavigation.remaining(ride: ride, route: route, progress: progress, position: point.coordinate)
                    nav.routeProgress = progress.traveled
                    ride.localNavigation = nav
                    if progress.snappedPosition != nil && progress.distanceFromRoute <= 25 {
                        if rerouting { cancelRerouting() }
                        localRideStatus = CarNavigation.onlineNotice
                    }
                    if CarNavigation.arrived(route: route, progress: progress, pending: CarNavigation.pending(ride: ride), position: point.coordinate) {
                        localRideStatus = route.destinationAccessDistance == nil ? "Ziel erreicht" : "Pkw-Zufahrt erreicht · Zugang zum Ziel prüfen"
                        if !carArrivalAnnounced {
                            carArrivalAnnounced = true
                            if voice { speakCar(localRideStatus!) }
                        }
                    }
                }
            }
            carLookAhead = carZoom.update(speed: point.speed, timestamp: point.timestamp, progress: progress,
                followingGap: ridingRoute.flatMap { CarNavigation.following(route: $0, next: progress?.nextManeuver)?.gap }, rerouting: rerouting)
        }
        if accepted, ride.profile.mode == .sea, ride.route != nil {
            var navigation = ride.localNavigation ?? LocalNavigationState()
            navigation.marineNextWaypointIndex = MarineNavigation.nextWaypoint(current: navigation.marineNextWaypointIndex ?? 1,
                points: MarineNavigation.navigationPoints(ride), position: point.coordinate, accuracy: point.accuracy,
                timestamp: point.timestamp, now: Date().timeIntervalSince1970)
            ride.localNavigation = navigation
        }
        if accepted || previousPending != ride.localNavigation?.carPendingWaypointOrdinals {
            do { try store.save(ride) } catch {
                cancelNeighborhood(); location.setRiding(false); ride.recordingState = .paused
                cancelRerouting()
                errorMessage = "Aufzeichnung pausiert: \(error.localizedDescription)"
            }
        }
        activeRide = ride
        if !isMarinePresentation, !waypointSkipProposal.isEmpty, point.accuracy >= 0, point.accuracy <= 25,
           abs(sample.timestamp.timeIntervalSinceNow) < 5 {
            proposeWaypointSkip(ride: ride, position: point.coordinate, heading: heading)
        }
        guard ride.recordingState == .recording else { return }
        rideActivity.carLookAhead = carLookAhead
        rideActivity.update(progress: progress, route: ridingRoute, headingDegrees: heading, paused: false, rerouting: rerouting)
        if !isMarinePresentation, ride.profile.mode == .cycling, let progress, !rerouting,
           reroutePolicy.observe(distanceFromRoute: progress.distanceFromRoute, timestamp: point.timestamp,
                accuracy: point.accuracy, now: Date().timeIntervalSince1970) {
            proposeWaypointSkip(ride: ride, position: point.coordinate, heading: heading)
            reroute(from: point.coordinate, heading: heading, ride: ride)
        }
        if ride.profile.mode == .car, carGPSIsFresh, let progress, !rerouting, !carArrivalAnnounced {
            if reroutePolicy.observe(distanceFromRoute: progress.distanceFromRoute, timestamp: point.timestamp,
                accuracy: point.accuracy, now: Date().timeIntervalSince1970) {
                rerouteCar(from: point.coordinate, ride: ride)
            }
            if voice, let text = carVoice.announcement(progress: progress, speed: point.speed,
                following: ridingRoute.flatMap { CarNavigation.following(route: $0, next: progress.nextManeuver) }) {
                speakCar(text)
            }
        }
        if !isMarinePresentation, ride.profile.mode != .car, voice, let progress, progress.distanceFromRoute < 35,
           progress.distanceToManeuver < 120, let next = progress.nextManeuver,
           lastAnnouncement != next.coordinateIndex {
            lastAnnouncement = next.coordinateIndex
            let utterance = AVSpeechUtterance(string: "In \(Int(progress.distanceToManeuver / 10) * 10) Metern. \(next.instruction)")
            utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
            utterance.volume = 1
            stopVolumePreview()
            speech.speak(utterance)
        }
    }
}

enum PointRole: String, CaseIterable, Identifiable {
    case start, via, destination
    var id: String { rawValue }
    var title: String {
        switch self { case .start: "Start"; case .via: "Zwischenziel"; case .destination: "Ziel" }
    }
}
