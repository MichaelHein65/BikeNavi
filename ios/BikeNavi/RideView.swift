import SwiftUI

struct RideView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmFinish = false
    @State private var showBlogPoint = false
    @State private var showElevation = false
    @State private var showPOIs = false
    @State private var showRegions = false
    @AppStorage("ridePresentation") private var presentation = "navigation"
    private var presentationTitle: String { presentation == "bike" ? "E-Bike-Technik" : presentation == "tourism" ? "Touristik" : "Navigation" }
    @State private var mapError: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            if state.hasConflictingApplicationRide {
                VStack(spacing: 18) {
                    Image(systemName: state.activeRide?.profile.mode.symbol ?? "location.fill").font(.system(size: 52)).foregroundStyle(Theme.accent)
                    Text("Eine andere Fahrt ist noch geöffnet").font(.title2.bold()).multilineTextAlignment(.center)
                    Text(state.activeRide?.title ?? "").foregroundStyle(.secondary)
                    Button("Fahrt fortsetzen") { state.resumeApplicationRide() }.buttonStyle(.borderedProminent).tint(Theme.forest)
                        .accessibilityIdentifier("resumeConflictingRide")
                    Text("Beende diese Fahrt, bevor du eine neue Aufzeichnung beginnst.").font(.subheadline).multilineTextAlignment(.center)
                }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
            } else if state.isMarinePresentation {
                MarineRideView()
            } else if state.activeRide?.profile.mode == .car {
                CarRideView()
            } else if let ride = state.activeRide {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: state.progress?.nextManeuver?.symbol ?? "location.north.fill")
                            .font(.system(size: 30, weight: .bold)).frame(width: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            if ride.recordingState == .paused {
                                Text("Deine Pause").font(.headline)
                                Text(ride.title).font(.subheadline).lineLimit(2)
                            } else if ride.route == nil {
                                Text(ride.profile.mode == .hiking ? "Freie Wanderung" : "Freie Fahrt").font(.headline)
                                Text("Dein Weg wird aufgezeichnet").font(.subheadline)
                            } else if state.rerouting {
                                Text("Route wird angepasst").font(.headline)
                                Text("Das iPhone sucht einen kurzen Anschluss zur Tour.").font(.subheadline).lineLimit(2)
                            } else if let progress = state.progress {
                                if progress.distanceFromRoute > 35 {
                                    Text("Route verlassen").font(.headline)
                                    Text(state.localRideStatus ?? "\(Format.distance(progress.distanceFromRoute)) entfernt · gespeicherte Tour auf der Karte").font(.subheadline)
                                } else {
                                    Text(progress.nextManeuver == nil ? "Dem Ziel entgegen" : "Abbiegen in \(Format.distance(progress.distanceToManeuver))").font(.headline)
                                    Text(progress.nextManeuver?.instruction ?? "Folge der Route bis zum Ziel").font(.subheadline).lineLimit(3)
                                }
                            } else {
                                Text(state.isWalkingSection ? "Gute Wanderung!" : "Gute Fahrt!").font(.headline)
                                Text("Position auf der Route wird ermittelt").font(.subheadline)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.forest).foregroundStyle(.white)
                    RouteMap(styleURL: state.mapStyleURL, route: state.ridingRoute, waypoints: ride.waypoints,
                             track: ride.track, follow: ride.recordingState == .recording,
                             followHeading: ride.recordingState == .recording, hikingNavigation: state.isWalkingSection, showWaterDepths: false,
                             navigationPosition: state.progress?.snappedPosition ?? state.location.coordinate,
                             navigationHeading: state.location.navigationHeading,
                             colorBySurface: true, topOverlayInset: 40, onError: { mapError = $0 })
                        .accessibilityIdentifier("rideMap")
                        .overlay(alignment: .topLeading) {
                            MapStyleMenu().background(Theme.paper, in: Circle()).padding(8)
                        }
                        .overlay(alignment: .topTrailing) { poiButton.padding(8) }
                        .overlay(alignment: .bottom) {
                            if let mapError {
                                Text(mapError).font(.caption).padding(8)
                                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8)).padding(8)
                            }
                        }
                        .onChange(of: state.mapStyleURL) { _, _ in mapError = nil }
                    ScrollView {
                    VStack(spacing: 8) {
                        HStack {
                            Menu {
                                Picker("Fahransicht", selection: $presentation) {
                                    Text("Navigation").tag("navigation")
                                    Text("E-Bike-Technik").tag("bike")
                                    Text("Touristik").tag("tourism")
                                }
                            } label: { Label(presentationTitle, systemImage: "rectangle.3.group").font(.subheadline.bold()).frame(minHeight: 44) }
                                .accessibilityIdentifier("ridePresentation")
                            Spacer()
                        }
                        if presentation == "tourism" {
                            Text(ride.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Offline-Orte der Region", systemImage: "map") { showRegions = true }
                                .frame(minHeight: 44).accessibilityIdentifier("rideOfflinePlaces")
                        }
                        if let status = state.localRideStatus, state.progress?.distanceFromRoute ?? 0 <= 35 {
                            Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 2 : (ride.route == nil ? 3 : 5)), alignment: .leading, spacing: 6) {
                            if ride.route != nil {
                                rideMetric("Reststrecke", Format.distance(state.progress?.remaining ?? state.ridingRoute?.distance ?? 0))
                            }
                            rideMetric(state.isWalkingSection ? "Gegangen" : "Gefahren", Format.distance(ride.recordedDistance))
                            rideMetric("Tempo", "\(Int((ride.track.last?.speed ?? 0) * 3.6)) km/h")
                            rideMetric(state.isWalkingSection ? "Gehzeit" : "Fahrzeit", Format.duration(ride.movingDuration))
                            if ride.route != nil {
                                TimelineView(.periodic(from: .now, by: 15)) { context in
                                    rideMetric("ETA", arrivalTime(ride: ride, now: context.date))
                                }.accessibilityIdentifier("rideETA")
                            }
                        }
                        Button { showBlogPoint = true } label: {
                            Label("Blog-Ort festhalten", systemImage: "camera.fill").font(.subheadline.bold())
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }.accessibilityIdentifier("captureBlogPoint")
                        Divider()
                        if ride.profile.mode.supportsBike && !state.isWalkingSection {
                            BikeTelemetryView(compact: presentation != "bike")
                            if presentation == "bike" { EnergyEstimateView() }
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                    }.frame(maxHeight: presentation == "bike" || typeSize.isAccessibilitySize ? 330 : 230).background(Theme.paper).accessibilityIdentifier("rideInformation")
                    rideControls(ride).padding(.horizontal, 14).padding(.vertical, 8).background(Theme.paper)
                }
                .overlay {
                    if !state.waypointSkipProposal.isEmpty {
                        ZStack {
                            Color.black.opacity(0.45).ignoresSafeArea()
                            VStack(spacing: 18) {
                                Text(state.waypointSkipProposal.count == 1 ? "Zwischenziel überspringen?" : "Zwischenziele überspringen?")
                                    .font(.title2.bold())
                                Text(state.waypointSkipNames).font(.title3).multilineTextAlignment(.center)
                                Text("Du bist von der Route abgewichen. Diese Ziele für die laufende Fahrt auslassen?")
                                    .multilineTextAlignment(.center)
                                Button { state.answerWaypointSkip(true) } label: {
                                    Text("Ja, überspringen").font(.title2.bold())
                                        .frame(maxWidth: .infinity, minHeight: 96)
                                        .background(Theme.forest, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
                                }.accessibilityIdentifier("skipWaypointYes")
                                Button { state.answerWaypointSkip(false) } label: {
                                    Text("Nein, anfahren").font(.title2.bold())
                                        .frame(maxWidth: .infinity, minHeight: 96)
                                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))
                                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.forest, lineWidth: 3))
                                }.accessibilityIdentifier("skipWaypointNo")
                            }.buttonStyle(.plain).foregroundStyle(Theme.ink)
                                .padding(24).background(Theme.paper, in: RoundedRectangle(cornerRadius: 24)).padding(16)
                        }
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .confirmationDialog("Tour beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button("Speichern und beenden") { state.finishRide() }
                    Button("Nicht speichern und beenden", role: .destructive) { state.discardRide() }
                    Button("Weiterfahren", role: .cancel) { }
                }
                .sheet(isPresented: $showBlogPoint) { BlogPointEditor(rideID: ride.id) }
                .sheet(isPresented: $showElevation) { if let route = ride.route { RouteDetailsView(route: route) } }
            } else if !state.plan.canCalculateRoute || state.plan.route == nil {
                VStack(spacing: 0) {
                    RouteMap(styleURL: state.mapStyleURL, route: nil, focus: state.location.coordinate ?? state.mapFocus,
                             follow: true, hikingNavigation: state.plan.profile.mode == .hiking, showWaterDepths: false, navigationPosition: state.location.coordinate,
                             onError: { mapError = $0 })
                        .accessibilityIdentifier("rideMap")
                        .overlay(alignment: .topLeading) {
                            MapStyleMenu().background(Theme.paper, in: Circle()).padding(8)
                        }
                        .overlay(alignment: .topTrailing) { poiButton.padding(8) }
                        .overlay(alignment: .bottom) {
                            if let mapError {
                                Text(mapError).font(.caption).padding(8)
                                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 8)).padding(8)
                            }
                        }
                        .onChange(of: state.mapStyleURL) { _, _ in mapError = nil }
                    VStack(spacing: 12) {
                        Text(state.waitingForRideLocation ? "Standort wird ermittelt …" : state.plan.profile.mode == .hiking ? "Freie Wanderung" : "Freie Fahrt")
                            .font(.headline)
                        Text("Dein Weg wird ab der aktuellen GPS-Position aufgezeichnet.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if state.waitingForRideLocation {
                            ProgressView()
                            Button("Standortsuche abbrechen") { state.cancelRideStart() }
                        } else {
                            Button("Aufzeichnung starten") { state.startRide() }
                                .buttonStyle(.borderedProminent).tint(Theme.forest)
                        }
                    }.padding(16).frame(maxWidth: .infinity).background(Theme.paper)
                }.toolbar(.hidden, for: .navigationBar)
            } else {
                ScrollView {
                  VStack(spacing: 22) {
                    Image(systemName: state.plan.profile.mode.symbol).font(.system(size: 76, weight: .light)).foregroundStyle(Theme.accent)
                    Text(state.waitingForRideLocation ? "Standort wird ermittelt …" : "Bereit für draußen?").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Plane deine Strecke und starte deine Tour.\nDein Weg wird unterwegs gespeichert.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    if state.waitingForRideLocation {
                        ProgressView()
                        Button("Standortsuche abbrechen") { state.cancelRideStart() }
                    }
                    Button("Zur Routenplanung") { state.tab = 0 }.buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white).controlSize(.large)
                    poiButton
                    if state.plan.profile.mode.supportsBike { BikeTelemetryView().padding(.top, 12) }
                  }.padding(26).frame(maxWidth: .infinity)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
                    .navigationTitle("Fahren")
            }
        }.sheet(isPresented: $showRegions) {
            NavigationStack { OfflineRegionsView(center: state.location.coordinate ?? state.activeRide?.route?.coordinates.first) }
        }.sheet(isPresented: $showPOIs) { POIView(duringRide: state.activeRide != nil) }
    }

    private func rideControls(_ ride: TourDocument) -> some View {
                        HStack(spacing: 8) {
                            Button { state.togglePause() } label: {
                                Label(ride.recordingState == .paused ? "Fortsetzen" : "Pause", systemImage: ride.recordingState == .paused ? "play.fill" : "pause.fill")
                                    .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Theme.forest, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                            }.buttonStyle(.plain)
                            if ride.route != nil {
                                Button { showElevation = true } label: { controlIcon("chart.xyaxis.line") }
                                    .accessibilityLabel("Höhenprofil")
                                Button { state.voice.toggle() } label: { controlIcon(state.voice ? "speaker.wave.2" : "speaker.slash") }
                                    .accessibilityLabel(state.voice ? "Sprachausgabe ausschalten" : "Sprachausgabe einschalten")
                            }
                            Button { confirmFinish = true } label: { controlIcon("stop.fill") }
                                .accessibilityLabel("Tour beenden")
                        }.buttonStyle(.plain)
    }

    private var poiButton: some View {
        Button("Orte", systemImage: "square.grid.2x2.fill") { showPOIs = true }
            .font(.subheadline.bold()).padding(12)
            .background(Theme.paper, in: Capsule()).accessibilityIdentifier("ridePOIs")
    }

    private func arrivalTime(ride: TourDocument, now: Date) -> String {
        guard ride.recordingState == .recording, !state.rerouting,
              state.location.freshCoordinate != nil,
              let route = state.ridingRoute, let progress = state.progress,
              progress.distanceFromRoute <= 35 else { return "—" }
        let seconds = RouteTravelTime(route: route, profile: ride.profile).remaining(after: progress.traveled)
        let arrival = now.addingTimeInterval(seconds)
        if Calendar.current.isDate(arrival, inSameDayAs: now) {
            return arrival.formatted(.dateTime.hour().minute())
        }
        return arrival.formatted(.dateTime.day().month().hour().minute())
    }

    private func rideMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(Theme.ink)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryInk)
        }.accessibilityElement(children: .combine)
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name).font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }
}
