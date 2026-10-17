import SwiftUI

struct CarRideView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var metricValueSize = 26
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
                            VStack(spacing: 8) {
                                MapStyleMenu().background(Theme.paper, in: Circle())
                                let limit = state.ridingRoute.flatMap { CarNavigation.speedLimit(route: $0, progress: state.progress, active: driving && fresh && !state.rerouting) }
                                VStack(spacing: 2) {
                                    Text(limit.map { String(Int($0.rounded())) } ?? "—")
                                        .font(.title2.bold()).foregroundStyle(.black)
                                        .frame(width: 54, height: 54).background(.white, in: Circle())
                                        .overlay(Circle().stroke(limit == nil ? Color.gray : Color.red, lineWidth: 4))
                                    Text("km/h").font(.caption2)
                                }.padding(8).background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                                    .accessibilityLabel(limit.map { "Tempolimit \(Int($0)) Kilometer pro Stunde" } ?? "Tempolimit unbekannt")
                                    .accessibilityIdentifier("carSpeedLimit")
                            }.padding(8)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button("Orte", systemImage: "square.grid.2x2.fill") { showPOIs = true }
                                .font(.headline).padding(12).background(Theme.paper, in: Capsule()).padding(8)
                                .accessibilityLabel("Orte entdecken").accessibilityIdentifier("ridePOIs")
                        }
                        .overlay(alignment: .topTrailing) {
                            if let route = state.ridingRoute,
                               let lanes = CarNavigation.lanes(route: route, progress: state.progress, active: driving && fresh && !state.rerouting) {
                                laneOverlay(lanes)
                                    .padding(.leading, 88).padding(.trailing, 8).padding(.top, 64)
                                    .allowsHitTesting(false)
                            }
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
                    VStack(spacing: 4) {
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
                            if let notice = CarNavigation.rideTrafficNotice(route: state.ridingRoute, now: context.date.timeIntervalSince1970) {
                                Text(notice).font(.caption2).foregroundStyle(.secondary).accessibilityIdentifier("carTrafficStatus")
                            }
                            if driving, fresh, !state.rerouting, let route = state.ridingRoute,
                               let incident = CarNavigation.nextTraffic(route: route, progress: state.progress, now: context.date.timeIntervalSince1970) {
                                Text("Voraus: " + incident.title + (incident.delaySeconds > 0 ? " · +\(Int(ceil(incident.delaySeconds / 60))) min" : ""))
                                    .font(.caption).foregroundStyle(.orange).accessibilityIdentifier("carTrafficIncident")
                            }
                            if let error = state.carTrafficError { Text(error).font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
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

    private func laneOverlay(_ section: CarLaneSection) -> some View {
        VStack(spacing: 6) {
            Text("SPUR WÄHLEN").font(.caption.bold()).foregroundStyle(.white)
            HStack(spacing: 6) {
                ForEach(Array(section.lanes.enumerated()), id: \.offset) { index, lane in
                    laneTile(lane, index: index)
                }
            }
        }
        .padding(10).frame(maxWidth: 400)
        .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.yellow, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .accessibilityIdentifier("carLaneGuidance")
    }

    private func laneTile(_ lane: CarLane, index: Int) -> some View {
        let recommended = lane.follow != nil
        let arrows = lane.follow.map(CarLane.arrow) ?? lane.directions.map(CarLane.arrow).joined()
        let label = "Spur \(index + 1), " + (recommended ? "empfohlen: " : "") + arrows
        return VStack(spacing: 2) {
            Text(arrows).font(.system(size: 42, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.4)
            Image(systemName: recommended ? "checkmark.circle.fill" : "minus").font(.caption.bold())
        }
        .frame(maxWidth: .infinity, minHeight: 68)
        .foregroundStyle(recommended ? Color.black : Color.white)
        .background(recommended ? Color.yellow : Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
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
    private func metricText(_ value: String) -> Text {
        value.split(separator: " ").enumerated().reduce(Text("")) { text, part in
            let unit = ["km/h", "km", "m", "min", "h"].contains(String(part.element))
            return text + Text((part.offset == 0 ? "" : " ") + part.element)
                .font(.system(size: unit ? metricValueSize * 0.54 : metricValueSize, weight: .bold, design: .rounded))
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            metricText(value).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("carMetric_" + title)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }
}
