import SwiftUI

struct MarineRideView: View {
    @EnvironmentObject private var state: AppState
    @State private var finish = false
    @State private var journal = false
    @State private var details = false
    @State private var mapError: String?
    private let navy = Color(red: 0.04, green: 0.18, blue: 0.27)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let ride = state.activeRide
            let sample = state.location.latestSample
            let fresh = sample.map { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 && context.date.timeIntervalSince($0.timestamp) <= 5 && context.date.timeIntervalSince($0.timestamp) >= -1 } ?? false
            let cog = MarineNavigation.cog(course: sample?.course, speed: sample?.speed,
                timestamp: sample?.timestamp.timeIntervalSince1970, accuracy: sample?.horizontalAccuracy,
                now: context.date.timeIntervalSince1970)
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    compass(cog).frame(width: 76, height: 76).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(ride?.recordingState == .paused ? "Auf See · Pause" : "Auf See").font(.caption.bold())
                        #if DEBUG
                        if ProcessInfo.processInfo.environment["BIKENAVI_MARINE_PREVIEW"] == "1" {
                            Text("GPS-Beispiel · Tribunj–Šibenik").font(.caption2).lineLimit(2)
                        }
                        #endif
                        Text(cog.map(MarineNavigation.course) ?? "—")
                            .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                            .accessibilityIdentifier("marineCourse")
                        Text("Kurs über Grund · rechtweisend").font(.caption2)
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(fresh && (sample?.speed ?? -1) >= 0 ? MarineNavigation.speed(sample!.speed) : "—")
                            .font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                            .accessibilityIdentifier("marineSpeed")
                        Text("Fahrt über Grund").font(.caption2)
                    }
                }.padding(14).foregroundStyle(.white).background(navy)
                if let ride, ride.profile.mode == .sea, MarineNavigation.current(ride.route) {
                    let index = state.marineTargetIndex
                    let points = MarineNavigation.navigationPoints(ride)
                    if points.indices.contains(index) {
                        let target = points[index]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(index + 1)/\(points.count) · \(target.name)").font(.subheadline.bold()).lineLimit(1)
                                Text("Peilung zum nächsten Wegpunkt").font(.caption)
                            }
                            Spacer()
                            if fresh, let coordinate = state.location.coordinate {
                                let leg = MarineNavigation.leg(from: Waypoint(name: "Position", coordinate: coordinate), to: target)
                                VStack(alignment: .trailing) {
                                    Text(MarineNavigation.course(leg.course)).bold().monospacedDigit()
                                    Text(MarineNavigation.distance(leg.distance)).font(.caption)
                                }.accessibilityElement(children: .combine).accessibilityIdentifier("marineTargetBearing")
                            } else { Text("—") }
                        }.padding(12).background(navy.opacity(0.08))
                    } else {
                        Label("Letzter Wegpunkt erreicht", systemImage: "flag.checkered").font(.subheadline.bold()).padding(10)
                    }
                }
                if let ride, ride.route != nil, !MarineNavigation.current(ride.route) {
                    Text(MarineNavigation.outdatedRouteWarning).font(.caption).foregroundStyle(.orange).padding(10)
                        .accessibilityIdentifier("marineRouteOutdated")
                }
                RouteMap(styleURL: state.mapStyleURL, route: ride?.profile.mode == .sea && MarineNavigation.current(ride?.route) ? ride?.route : nil,
                    waypoints: ride?.profile.mode == .sea ? ride?.waypoints ?? [] : [], track: ride?.track ?? [],
                    focus: ride == nil ? state.location.coordinate ?? state.mapFocus : nil, follow: ride?.recordingState != .paused,
                    marineNavigation: true, showWaterDepths: state.showWaterDepths, navigationPosition: state.location.coordinate,
                    navigationHeading: cog, topOverlayInset: 40, onError: { mapError = $0 })
                    .accessibilityIdentifier("rideMap")
                    .overlay(alignment: .topLeading) { MapStyleMenu().background(.regularMaterial, in: Circle()).padding(8) }
                    .overlay(alignment: .topTrailing) {
                        Label("Norden oben", systemImage: "location.north.fill").font(.caption.bold())
                            .padding(8).background(.regularMaterial, in: Capsule()).padding(8)
                    }
                    .overlay(alignment: .bottom) {
                        if let mapError { Text(mapError).font(.caption).padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)).padding(8) }
                    }
                VStack(spacing: 10) {
                    if let ride, let route = ride.route, ride.profile.mode == .sea, MarineNavigation.current(route) {
                        let points = MarineNavigation.navigationPoints(ride)
                        let remaining = fresh ? state.location.coordinate.flatMap { MarineNavigation.remainingDistance(points: points, target: state.marineTargetIndex, position: $0) } : nil
                        let duration = remaining.flatMap { MarineNavigation.travelTime(distance: $0, speedKnots: state.boatSpeedKnots) }
                        HStack {
                            Metric(label: "Gesamtstrecke", value: MarineNavigation.distance(route.distance)).accessibilityIdentifier("marineTotalDistance")
                            Metric(label: "Verbleibend", value: remaining.map(MarineNavigation.distance) ?? "—")
                            VStack(alignment: .leading) {
                                Text(ride.recordingState == .paused || duration == nil ? "—" : context.date.addingTimeInterval(duration!).formatted(date: Calendar.current.isDate(context.date.addingTimeInterval(duration ?? 0), inSameDayAs: context.date) ? .omitted : .abbreviated, time: .shortened))
                                    .font(.subheadline.bold()).monospacedDigit().accessibilityIdentifier("marineETA")
                                Text("ETA · geschätzt").font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let ride {
                        HStack {
                            Metric(label: "Auf See", value: MarineNavigation.distance(ride.recordedDistance))
                            Metric(label: "Fahrzeit", value: Format.duration(ride.movingDuration))
                            Image(systemName: "sailboat.fill").font(.title2).foregroundStyle(navy)
                        }
                    }
                    Text(fresh && state.location.coordinate != nil ? MarineNavigation.position(state.location.coordinate!) : "GPS-Position wird ermittelt …")
                        .font(.caption.monospaced()).lineLimit(2).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("marinePosition")
                    if cog == nil { Text("Kurs bei Stillstand oder fehlendem GPS nicht verfügbar").font(.caption2).foregroundStyle(.secondary) }
                    if let ride {
                        HStack(spacing: 8) {
                            Button { state.togglePause() } label: {
                                Label(ride.recordingState == .paused ? "Fortsetzen" : "Pause", systemImage: ride.recordingState == .paused ? "play.fill" : "pause.fill")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.borderedProminent).tint(navy)
                            if !ride.waypoints.isEmpty && MarineNavigation.current(ride.route) {
                                Button { details = true } label: { Image(systemName: "list.number").frame(width: 36, height: 36) }
                                    .accessibilityLabel("Wegpunkte und Kurse")
                            }
                            Button { journal = true } label: { Image(systemName: "camera.fill").frame(width: 36, height: 36) }
                                .accessibilityLabel("Blog-Ort festhalten")
                            Button { finish = true } label: { Image(systemName: "stop.fill").frame(width: 36, height: 36) }
                                .accessibilityLabel("Tour beenden")
                        }
                    } else if state.waitingForRideLocation {
                        ProgressView("Standort wird ermittelt …")
                        Button("Standortsuche abbrechen") { state.cancelRideStart() }
                    } else {
                        Button("Aufzeichnung auf See starten") { state.startRide() }.buttonStyle(.borderedProminent).tint(navy)
                    }
                    if MarineNavigation.current(ride?.route) { Text("ETA mit Ø " + state.boatSpeedKnots.formatted(.number.precision(.fractionLength(1))) + " kn · ohne spätere Pausen").font(.caption2).foregroundStyle(.secondary) }
                    Text("EMODnet · nicht zur Navigation geeignet").font(.caption2).foregroundStyle(.secondary)
                }.padding(14).background(Color(uiColor: .systemBackground))
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: state.mapStyleURL) { _, _ in mapError = nil }
        .confirmationDialog("Fahrt auf See beenden?", isPresented: $finish, titleVisibility: .visible) {
            Button("Speichern und beenden") { state.finishRide() }
            Button("Nicht speichern und beenden", role: .destructive) { state.discardRide() }
            Button("Weiterfahren", role: .cancel) {}
        }
        .sheet(isPresented: $journal) { if let ride = state.activeRide { BlogPointEditor(rideID: ride.id) } }
        .sheet(isPresented: $details) { MarinePlanDetailsView(points: state.activeRide?.waypoints ?? [], route: state.activeRide?.route) }
    }
    private func compass(_ course: Double?) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.45), lineWidth: 1)
            Text("N").offset(y: -28)
            Text("S").offset(y: 28)
            Text("W").offset(x: -28)
            Text("O").offset(x: 28)
            if let course {
                Image(systemName: "location.north.fill").font(.system(size: 28)).foregroundStyle(.cyan).rotationEffect(.degrees(course))
            } else { Image(systemName: "sailboat.fill").font(.title3) }
        }.font(.system(size: 10, weight: .bold))
    }
}

struct MarinePlanDetailsView: View {
    let points: [Waypoint]
    var route: CalculatedRoute?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(MarineNavigation.warning).font(.footnote)
                    Text(MarineNavigation.depthWarning).font(.footnote)
                    if route?.marineDepthUncertain == true { Label("Tiefen teilweise unbekannt", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    if let draft = route?.marineDraft { LabeledContent("Tiefgang bei Planung", value: draft.formatted(.number.precision(.fractionLength(1))) + " m") }
                    Text("Kurse sind rechtweisende Loxodromkurse. Wind und Strömung können den tatsächlich zu steuernden Kurs verändern.").font(.footnote)
                }
                Section("Deine Wegpunkte") {
                    ForEach(points) { point in
                        VStack(alignment: .leading) {
                            Text(point.name).font(.headline)
                            Text(MarineNavigation.position(point.coordinate)).font(.caption.monospaced())
                        }
                    }
                }
                ForEach(MarineNavigation.legs(MarineNavigation.navigationPoints(waypoints: points, route: route))) { leg in
                    Section("Abschnitt \(leg.id)") {
                        Text(leg.start.name + " → " + leg.end.name).font(.headline)
                        LabeledContent("Kurs rechtweisend", value: MarineNavigation.course(leg.course))
                        LabeledContent("Entfernung", value: MarineNavigation.distance(leg.distance))
                        Text(MarineNavigation.position(leg.end.coordinate)).font(.caption.monospaced())
                    }
                }
            }.navigationTitle("Wegpunkte und Kurse").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
