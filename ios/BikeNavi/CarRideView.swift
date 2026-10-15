import SwiftUI

struct CarRideView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmFinish = false
    @State private var showPOIs = false
    @State private var confirmRemovePOI = false
    @State private var removingPOI = false
    @State private var poiError: String?
    @State private var showBlogPoint = false
    @State private var mapError: String?
    @State private var cameraSuspended = false
    @State private var cameraResumeID = 0

    var body: some View {
        if let ride = state.activeRide {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let fresh = state.carGPSIsFresh
                let driving = ride.recordingState == .recording
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Image(systemName: state.progress?.nextManeuver?.symbol ?? "car.fill")
                            .font(.system(size: 36, weight: .bold)).frame(width: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ride.title).font(.caption).lineLimit(1)
                            Text(header(ride: ride, fresh: fresh)).font(.title3.bold())
                                .accessibilityIdentifier("carManeuverTitle")
                            Text(instruction(ride: ride, fresh: fresh)).font(.headline).lineLimit(3)
                            if driving, fresh, !state.rerouting, let route = state.ridingRoute,
                               let following = CarNavigation.following(route: route, next: state.progress?.nextManeuver),
                               following.gap <= max(100, (state.location.latestSample?.speed ?? 0) * 8) {
                                Text("Danach: " + following.maneuver.carInstruction).font(.caption).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.forest).foregroundStyle(.white)
                    RouteMap(styleURL: state.carMapStyleURL(dark: colorScheme == .dark), route: state.ridingRoute,
                        waypoints: Array(ride.waypoints.dropFirst()), track: ride.track,
                        follow: driving && fresh, followHeading: true, carNavigation: true,
                        navigationPosition: fresh ? (state.progress?.snappedPosition ?? state.location.coordinate) : nil,
                        navigationHeading: state.carHeading, navigationLookAhead: state.carLookAhead,
                        navigationProgress: state.progress?.traveled, navigationResumeID: cameraResumeID, topOverlayInset: 40, hasStart: false,
                        onNavigationSuspended: { cameraSuspended = $0 }, onError: { mapError = $0 })
                        .accessibilityIdentifier("carRideMap")
                        .overlay(alignment: .topLeading) {
                            MapStyleMenu().background(Theme.paper, in: Circle()).padding(8)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button("Orte", systemImage: "square.grid.2x2.fill") { showPOIs = true }
                                .font(.headline).padding(12).background(Theme.paper, in: Capsule()).padding(8)
                                .accessibilityLabel("Orte entdecken").accessibilityIdentifier("ridePOIs")
                        }
                        .overlay(alignment: .bottomLeading) {
                            Text("Auto-Zoom · \(Int(state.carLookAhead.rounded())) m voraus")
                                .font(.caption2).padding(6).background(Theme.paper, in: RoundedRectangle(cornerRadius: 6)).padding(.leading, 8).padding(.bottom, 30)
                                .accessibilityIdentifier("carAutoZoom")
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if cameraSuspended {
                                Button { cameraResumeID += 1; cameraSuspended = false } label: {
                                    Label("Fahransicht", systemImage: "location.fill").frame(minHeight: 48)
                                }.buttonStyle(.borderedProminent).tint(Theme.forest)
                                    .padding(.trailing, 12).padding(.bottom, 42)
                                    .accessibilityIdentifier("resumeAutoCamera")
                            }
                        }
                        .overlay(alignment: .top) {
                            if let mapError { Text(mapError).font(.caption).padding(8).background(Theme.paper, in: RoundedRectangle(cornerRadius: 8)).padding(.top, 50) }
                        }
                        .onChange(of: state.mapStyleURL) { _, _ in mapError = nil }
                    VStack(spacing: 10) {
                        if let stop = state.pendingPOIStop {
                            HStack {
                                Text("Stopp: " + stop.name).font(.caption).lineLimit(1)
                                Spacer()
                                Button(removingPOI ? "Berechnen …" : "Entfernen") { confirmRemovePOI = true }
                                    .font(.caption.bold()).frame(minHeight: 44).disabled(removingPOI)
                                    .accessibilityIdentifier("removePOIStop")
                            }
                        }
                        if ride.route != nil {
                            HStack {
                                metric("Ankunft", arrival(ride: ride, now: context.date))
                                metric("Restzeit", remaining(ride: ride).map { Format.duration($0) } ?? "—")
                                metric("Reststrecke", Format.distance(state.progress?.remaining ?? state.ridingRoute?.distance ?? 0))
                            }
                            Text(CarNavigation.trafficNotice).font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack {
                            metric("Tempo", fresh ? "\(Int(max(0, state.location.latestSample?.speed ?? 0) * 3.6)) km/h" : "—")
                            metric("Gefahren", Format.distance(ride.recordedDistance))
                            metric("Fahrzeit", Format.duration(ride.movingDuration))
                        }
                        if let status = state.localRideStatus, status != CarNavigation.onlineNotice {
                            Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                                .accessibilityIdentifier("carNavigationStatus")
                        }
                        HStack(spacing: 10) {
                            Button { state.togglePause() } label: {
                                Label(driving ? "Pause" : "Fortsetzen", systemImage: driving ? "pause.fill" : "play.fill")
                                    .frame(maxWidth: .infinity, minHeight: 48)
                            }.buttonStyle(.borderedProminent).tint(Theme.forest).accessibilityIdentifier("carPause")
                            if ride.route != nil {
                                Button { state.voice.toggle() } label: {
                                    Image(systemName: state.voice ? "speaker.wave.2.fill" : "speaker.slash.fill").frame(width: 48, height: 48)
                                }.buttonStyle(.bordered)
                                    .accessibilityLabel(state.voice ? "Sprachausgabe ausschalten" : "Sprachausgabe einschalten")
                            }
                            Button { confirmFinish = true } label: { Image(systemName: "stop.fill").frame(width: 48, height: 48) }
                                .buttonStyle(.bordered).accessibilityLabel("Autofahrt beenden")
                        }
                        if !driving {
                            Button("Blog-Ort festhalten", systemImage: "camera.fill") { showBlogPoint = true }
                        }
                    }.padding(14).background(Theme.paper)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Autofahrt beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Speichern und beenden") { state.finishRide() }
                Button("Nicht speichern und beenden", role: .destructive) { state.discardRide() }
                Button("Weiterfahren", role: .cancel) { }
            }
            .sheet(isPresented: $showBlogPoint) { BlogPointEditor(rideID: ride.id) }
            .sheet(isPresented: $showPOIs) { POIView(duringRide: true) }
            .confirmationDialog("Letzten hinzugefügten Stopp entfernen?", isPresented: $confirmRemovePOI, titleVisibility: .visible) {
                Button("Stopp entfernen") {
                    removingPOI = true
                    Task { @MainActor in
                        defer { removingPOI = false }
                        do { try await state.removePOIStop() } catch { poiError = error.localizedDescription }
                    }
                }
            }
            .alert("Stopp bleibt erhalten", isPresented: Binding(get: { poiError != nil }, set: { if !$0 { poiError = nil } })) {
                Button("Verstanden") { poiError = nil }
            } message: { Text(poiError ?? "") }
        }
    }

    private func header(ride: TourDocument, fresh: Bool) -> String {
        if ride.recordingState == .paused { return "Autofahrt pausiert" }
        if !fresh { return "GPS-Signal fehlt" }
        if state.rerouting { return "Route wird neu berechnet" }
        if ride.route == nil { return "Freie Autofahrt" }
        if state.progress?.distanceFromRoute ?? 0 > 35 { return "Route verlassen" }
        if state.localRideStatus?.contains("erreicht") == true { return "Pkw-Ziel erreicht" }
        guard let progress = state.progress else { return "Position wird ermittelt" }
        return progress.nextManeuver == nil ? "Dem Ziel folgen" : "In " + Format.distance(progress.distanceToManeuver)
    }

    private func instruction(ride: TourDocument, fresh: Bool) -> String {
        if ride.recordingState == .paused { return "Fortsetzen, wenn du bereit bist" }
        if !fresh { return "Letzte Karte bleibt sichtbar · auf aktuellen Standort warten" }
        if state.rerouting { return "Weiter zu deinen verbleibenden Zielen" }
        if ride.route == nil { return "Dein Weg wird aufgezeichnet" }
        if state.progress?.distanceFromRoute ?? 0 > 35 { return state.localRideStatus ?? "Neue Pkw-Route wird angefordert" }
        if state.localRideStatus?.contains("erreicht") == true { return state.localRideStatus! }
        return state.progress?.nextManeuver?.carInstruction ?? "Folge der Route"
    }

    private func remaining(ride: TourDocument) -> Double? {
        guard ride.recordingState == .recording, state.carGPSIsFresh, !state.rerouting,
              let route = state.ridingRoute, let progress = state.progress, progress.distanceFromRoute <= 35 else { return nil }
        return RouteTravelTime(route: route, profile: ride.profile).remaining(after: progress.traveled)
    }
    private func arrival(ride: TourDocument, now: Date) -> String {
        guard let seconds = remaining(ride: ride) else { return "—" }
        let date = now.addingTimeInterval(seconds)
        return Calendar.current.isDate(date, inSameDayAs: now) ? date.formatted(.dateTime.hour().minute()) : date.formatted(.dateTime.day().month().hour().minute())
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.headline).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
