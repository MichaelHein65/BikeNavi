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
    var onLocation: ((CLLocation) -> Void)?
    var onAuthorizationChange: (() -> Void)?
    private var lastTimestamp: Double?
    var freshCoordinate: Coordinate? {
        guard !denied, let timestamp = lastTimestamp, let accuracy,
              PlanningLocation.isUsable(timestamp: timestamp, accuracy: accuracy, now: Date().timeIntervalSince1970) else { return nil }
        return coordinate
    }
    private let manager = CLLocationManager()
    private var activeRide = false

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
    }
    func request() {
        manager.requestWhenInUseAuthorization()
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    func setRiding(_ active: Bool) {
        activeRide = active
        manager.allowsBackgroundLocationUpdates = active
        manager.showsBackgroundLocationIndicator = active
        if active { request() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        denied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        onAuthorizationChange?()
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where location.horizontalAccuracy >= 0 && abs(location.timestamp.timeIntervalSinceNow) < 15 {
            coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                    altitude: location.verticalAccuracy >= 0 ? location.altitude : nil)
            accuracy = location.horizontalAccuracy
            lastTimestamp = location.timestamp.timeIntervalSince1970
            onLocation?(location)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var plan = TourDocument()
    @Published var records: [SavedRecord] = []
    @Published var savedPlaces: [SavedPlace] = []
    @Published var activeRide: TourDocument?
    @Published var progress: RouteProgress?
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var calculating = false
    @Published var rerouting = false
    @Published var synchronizing = false
    @Published var tab = 0
    @Published var mapFocus: Coordinate?
    @Published var mapRevision = UUID()
    @Published var selectedPoint: Coordinate?
    @Published var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? ""
    @Published var token = Keychain.read()
    @Published var mapStyleURL = UserDefaults.standard.string(forKey: "mapStyleURL") ?? "https://tiles.openfreemap.org/styles/liberty"
    @Published var offlineMapsAllowed = UserDefaults.standard.bool(forKey: "offlineMapsAllowed")
    @Published var voice = true
    let location = LocationService()
    let store: LocalStore
    private var routeTask: Task<Void, Never>?
    private var rerouteTask: Task<Void, Never>?
    private var nameTask: Task<Void, Never>?
    private var requestedStartPlanID: UUID?
    private var tracker = RouteTracker()
    private var reroutePolicy = ReroutePolicy()
    private var lastAnnouncement: Int?
    private var segment = 0
    private let speech = AVSpeechSynthesizer()

    init(store: LocalStore) {
        self.store = store
        records = (try? store.all()) ?? []
        savedPlaces = (try? store.places()) ?? []
        if let idString = UserDefaults.standard.string(forKey: "currentPlan"),
           let id = UUID(uuidString: idString), let saved = records.first(where: { $0.id == id && !$0.deleted }) {
            plan = saved.document
        }
        if var unfinished = records.first(where: { $0.document.kind == .ride && [.recording, .paused].contains($0.document.recordingState) })?.document {
            unfinished.recordingState = .paused
            activeRide = unfinished
            segment = (unfinished.track.last?.segment ?? 0) + 1
            try? store.save(unfinished)
            notice = "Deine letzte Fahrt ist gespeichert. Du kannst sie fortsetzen oder beenden."
        }
        location.onLocation = { [weak self] sample in self?.receive(sample) }
        location.onAuthorizationChange = { [weak self] in self?.objectWillChange.send() }
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
        if ProcessInfo.processInfo.environment["BIKENAVI_CONFIGURE"] == "1" {
            Task { await saveSettings() }
        }
        #endif
        if plan.isAwaitingStart { Task { requestAutomaticStart() } }
        else if plan.waypoints.count >= 2 { Task { refreshPlanName() } }
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
            : "Dein Ziel ist gespeichert. Dein aktueller Standort wird als Start ermittelt. Du kannst den Start auch auf der Karte wählen."
    }

    func reload() {
        do {
            records = try store.all()
            savedPlaces = try store.places()
        } catch { errorMessage = error.localizedDescription }
    }
    func savePlace(name: String, coordinate: Coordinate) {
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !cleaned.isEmpty else { errorMessage = "Gib dem gespeicherten Ort einen Namen."; return }
        guard !savedPlaces.contains(where: { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame && $0.coordinate.distance(to: coordinate) < 10 }) else { return }
        do {
            try store.save(SavedPlace(name: cleaned, coordinate: coordinate))
            reload()
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
        } catch { errorMessage = error.localizedDescription }
    }
    func deletePlace(_ place: SavedPlace) {
        do { try store.delete(place); reload() } catch { errorMessage = error.localizedDescription }
    }
    func savePlan() {
        do {
            plan.updateAutomaticTitle()
            var snapshot = plan
            if snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { snapshot.title = "Meine nächste Tour" }
            try store.save(snapshot)
            UserDefaults.standard.set(plan.id.uuidString, forKey: "currentPlan")
            reload()
        } catch { errorMessage = error.localizedDescription }
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
        let reservedCount = plan.waypoints.count + (plan.isAwaitingStart ? 1 : 0)
        guard reservedCount < 50 || role != .via else { errorMessage = "Eine Tour kann höchstens 50 Punkte enthalten."; return }
        switch role {
        case .start:
            requestedStartPlanID = nil
            plan.setStart(point)
        case .destination:
            plan.setDestination(point, currentPosition: location.freshCoordinate)
        case .via:
            plan.waypoints.insert(point, at: max(0, plan.waypoints.count - 1))
        }
        mapFocus = point.coordinate
        invalidateRoute()
        if plan.isAwaitingStart { requestAutomaticStart() }
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
    private func requestAutomaticStart() {
        guard plan.isAwaitingStart else { return }
        location.request()
        if let coordinate = location.freshCoordinate, plan.completeAutomaticStart(coordinate) {
            invalidateRoute()
        }
    }
    func invalidateRoute() {
        routeTask?.cancel()
        plan.route = nil
        if plan.waypoints.isEmpty { plan.awaitingStart = nil }
        refreshPlanName()
        guard plan.canCalculateRoute, api != nil else { calculating = false; return }
        routeTask = Task {
            do { try await Task.sleep(for: .milliseconds(650)); await calculateRoute() } catch { }
        }
    }
    func calculateRoute() async {
        guard let api else { errorMessage = "Verbinde zuerst deinen Pi in den Einstellungen. Deine Planung ist lokal gespeichert."; return }
        guard plan.canCalculateRoute else { return }
        let snapshot = plan
        calculating = true
        do {
            let route = try await api.route(snapshot)
            guard !Task.isCancelled, snapshot.id == plan.id,
                  snapshot.waypoints.map(\.coordinate) == plan.waypoints.map(\.coordinate),
                  snapshot.profile == plan.profile else { return }
            plan.route = route
            mapRevision = UUID()
            savePlan()
            calculating = false
            await sync()
        } catch {
            if !Task.isCancelled { errorMessage = error.localizedDescription; calculating = false }
        }
    }
    func newPlan() {
        savePlan()
        routeTask?.cancel()
        nameTask?.cancel()
        requestedStartPlanID = nil
        calculating = false
        plan = TourDocument()
        savePlan()
    }
    func open(_ document: TourDocument) {
        savePlan()
        routeTask?.cancel()
        calculating = false
        requestedStartPlanID = nil
        plan = document.kind == .ride ? document.asNewPlan() : document
        mapRevision = UUID()
        refreshPlanName()
        if plan.isAwaitingStart { requestAutomaticStart() }
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
            if plan.id == record.id {
                routeTask?.cancel()
                nameTask?.cancel()
                calculating = false
                plan = TourDocument()
                UserDefaults.standard.removeObject(forKey: "currentPlan")
            }
            reload()
            Task { await sync() }
        } catch { errorMessage = error.localizedDescription }
    }

    func sync() async {
        guard !synchronizing, let api else { return }
        let planAtStart = plan
        synchronizing = true
        defer { synchronizing = false; reload() }
        do {
            for record in try store.all() where record.dirty && record.document.recordingState != .recording {
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
            var hasMore = true
            while hasMore {
                let page: ChangePage = try await api.request("/v1/changes?after=\(store.cursor)")
                for remote in page.records { try store.merge(remote) }
                try store.setCursor(page.cursor)
                hasMore = page.hasMore
            }
            if plan == planAtStart,
               let latest = try store.all().first(where: { $0.id == plan.id && !$0.dirty && !$0.deleted }) {
                plan = latest.document
            }
        } catch { notice = "Lokal gespeichert · Abgleich ausstehend: \(error.localizedDescription)" }
    }
    func saveSettings() async {
        do {
            guard api != nil else { throw APIError(status: 0, message: "Bitte eine HTTPS-Serveradresse und den BikeNavi-Zugangsschlüssel eintragen.") }
            if UserDefaults.standard.string(forKey: "serverURL") != serverURL {
                try store.setCursor(0)
                // A different server has its own revision history. Preserve all local documents.
                for var record in try store.all() { record.revision = 0; record.dirty = true; record.mutationID = UUID(); try store.put(record) }
            }
            try Keychain.save(token.trimmingCharacters(in: .whitespacesAndNewlines))
            token = Keychain.read()
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            UserDefaults.standard.set(mapStyleURL, forKey: "mapStyleURL")
            UserDefaults.standard.set(offlineMapsAllowed, forKey: "offlineMapsAllowed")
            let status: ServerStatus = try await api!.request("/v1/status")
            notice = status.routingAvailable ? "Mit dem Pi verbunden. Routenberechnung ist bereit." : "Mit dem Pi verbunden. Dort fehlt noch der Routing-Schlüssel."
            await sync()
        } catch { errorMessage = error.localizedDescription }
    }
    func startRide() {
        guard activeRide == nil else { tab = 1; return }
        guard plan.canCalculateRoute, plan.route != nil else { errorMessage = "Bitte zuerst eine Route berechnen."; return }
        guard location.coordinate != nil && !location.denied else { location.request(); errorMessage = "Zum Starten der Fahrt wird dein Standort benötigt."; return }
        var ride = plan
        ride.id = UUID()
        ride.kind = .ride
        ride.createdAt = Date().timeIntervalSince1970
        ride.startedAt = ride.createdAt
        ride.recordingState = .recording
        do {
            try store.save(ride)
            activeRide = ride
            tracker = RouteTracker()
            reroutePolicy = ReroutePolicy()
            segment = 0
            lastAnnouncement = nil
            location.setRiding(true)
            UIApplication.shared.isIdleTimerDisabled = true
            tab = 1
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
    /// Opening the driving tab follows the same checks as the start button.
    func openRide() {
        guard activeRide == nil else { return }
        startRide()
    }
    func togglePause() {
        guard var ride = activeRide else { return }
        ride.recordingState = ride.recordingState == .recording ? .paused : .recording
        segment += 1
        do {
            try store.save(ride)
            activeRide = ride
            location.setRiding(ride.recordingState == .recording)
            UIApplication.shared.isIdleTimerDisabled = ride.recordingState == .recording
            reload()
        } catch { errorMessage = error.localizedDescription }
    }
    func finishRide() {
        guard var ride = activeRide else { return }
        ride.endedAt = Date().timeIntervalSince1970
        ride.recordingState = .finished
        do {
            try store.save(ride)
            activeRide = nil
            progress = nil
            location.setRiding(false)
            UIApplication.shared.isIdleTimerDisabled = false
            reload()
            tab = 2
            Task { await sync() }
        } catch { errorMessage = error.localizedDescription }
    }
    private func remainingWaypoints(for ride: TourDocument, after traveled: Double) -> [Waypoint] {
        guard let route = ride.route, route.coordinates.count > 1 else {
            return Array(ride.waypoints.dropFirst())
        }
        var cumulative = [0.0]
        for index in 1..<route.coordinates.count {
            cumulative.append(cumulative[index - 1] + route.coordinates[index - 1].distance(to: route.coordinates[index]))
        }
        return ride.waypoints.dropFirst().filter { waypoint in
            let nearest = route.coordinates.indices.min {
                route.coordinates[$0].distance(to: waypoint.coordinate) < route.coordinates[$1].distance(to: waypoint.coordinate)
            } ?? 0
            return cumulative[nearest] > traveled + 25
        }
    }
    private func reroute(from position: Coordinate, ride: TourDocument, traveled: Double) {
        guard rerouteTask == nil, let api, let destination = ride.destinationPoint else { return }
        rerouting = true
        let rideID = ride.id
        var request = ride
        var remaining = remainingWaypoints(for: ride, after: traveled)
        if !remaining.contains(where: { $0.id == destination.id }) { remaining.append(destination) }
        request.waypoints = [Waypoint(name: "Aktueller Standort", coordinate: position)] + remaining
        rerouteTask = Task {
            defer { rerouteTask = nil }
            do {
                let route = try await api.route(request)
                guard var current = activeRide, current.id == rideID,
                      current.recordingState == .recording else { return }
                current.route = route
                try store.save(current)
                activeRide = current
                tracker = RouteTracker()
                progress = nil
                rerouting = false
                notice = "Route ab deinem aktuellen Standort angepasst."
                reload()
                await sync()
            } catch {
                rerouting = false
                notice = "Route konnte gerade nicht angepasst werden. Wir versuchen es bei weiterer deutlicher Abweichung erneut."
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
            }
        }
        guard var ride = activeRide, ride.recordingState == .recording else { return }
        let point = TrackPoint(coordinate: Coordinate(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude,
                                                     altitude: sample.verticalAccuracy >= 0 ? sample.altitude : nil),
                               timestamp: sample.timestamp.timeIntervalSince1970, accuracy: sample.horizontalAccuracy,
                               speed: max(0, sample.speed), segment: segment)
        if TrackFilter.accepts(point, after: ride.track.last, now: Date().timeIntervalSince1970) {
            if let last = ride.track.last, last.segment == point.segment {
                ride.movingDuration += max(0, point.timestamp - last.timestamp)
            }
            ride.track.append(point)
            do { try store.save(ride); activeRide = ride } catch {
                location.setRiding(false)
                ride.recordingState = .paused
                activeRide = ride
                errorMessage = "Aufzeichnung pausiert: \(error.localizedDescription)"
            }
        }
        if let route = ride.route, sample.horizontalAccuracy >= 0, sample.horizontalAccuracy <= 50 {
            progress = tracker.update(position: point.coordinate, timestamp: point.timestamp, route: route)
            if let progress, let activeRide, api != nil,
               reroutePolicy.observe(distanceFromRoute: progress.distanceFromRoute, timestamp: point.timestamp) {
                reroute(from: point.coordinate, ride: activeRide, traveled: progress.traveled)
            }
            if voice, let progress, progress.distanceFromRoute < 60,
               progress.distanceToManeuver < 120, let next = progress.nextManeuver,
               lastAnnouncement != next.coordinateIndex {
                lastAnnouncement = next.coordinateIndex
                let utterance = AVSpeechUtterance(string: "In \(Int(progress.distanceToManeuver / 10) * 10) Metern. \(next.instruction)")
                utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
                speech.speak(utterance)
            }
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
