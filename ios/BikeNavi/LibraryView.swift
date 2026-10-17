import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var state: AppState
    @State private var kind: DocumentKind = .plan
    var visible: [SavedRecord] { state.records.filter { !$0.deleted && $0.document.kind == kind && (state.applicationMode == nil || $0.document.profile.mode == state.applicationMode) } }
    var body: some View {
        NavigationStack {
            List {
                Picker("Touren", selection: $kind) { Text("Geplant").tag(DocumentKind.plan); Text("Gefahren").tag(DocumentKind.ride) }
                    .pickerStyle(.segmented).listRowBackground(Color.clear).listRowSeparator(.hidden)
                if let notice = state.notice {
                    HStack(alignment: .top) { Text(notice).font(.caption); Spacer(); Button { state.notice = nil } label: { Image(systemName: "xmark") } }
                        .foregroundStyle(.secondary)
                }
                if visible.isEmpty {
                    ContentUnavailableView(kind == .plan ? "Deine nächste Tour wartet" : "Dein Tourenbuch beginnt hier",
                        systemImage: kind == .plan ? "map" : (state.applicationMode?.symbol ?? "location.fill"),
                        description: Text(kind == .plan ? "Deine Planungen werden automatisch gespeichert." : "Nach der ersten Fahrt findest du hier deinen Weg, Zeiten und Höhenprofil."))
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { record in
                    NavigationLink {
                        TourDetailView(document: record.document)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: record.document.profile.mode.symbol).foregroundStyle(Theme.accent)
                                Text(record.document.title).font(.headline).lineLimit(2)
                            }
                            HStack(spacing: 15) {
                                Text(record.document.profile.mode == .sea ? MarineNavigation.distance(kind == .ride ? record.document.recordedDistance : record.document.route?.distance ?? 0) : Format.distance(kind == .ride ? record.document.recordedDistance : record.document.route?.distance ?? 0))
                                if let route = record.document.route, record.document.profile.mode != .car { Label(route.hasElevation ? "\(Int(route.ascent.rounded())) m" : "–", systemImage: "arrow.up.right") }
                                Spacer()
                                Image(systemName: record.dirty || ((try? state.store.bikeSampleCounts(rideID: record.id).pending) ?? 0) > 0 ? "internaldrive" : "checkmark.icloud")
                            }.font(.caption).foregroundStyle(.secondary)
                            Text(Date(timeIntervalSince1970: record.document.createdAt), format: .dateTime.day().month(.wide).year().hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    .swipeActions { Button("Löschen", role: .destructive) { state.delete(record) } }
                }
            }.scrollContentBackground(.hidden).background(Theme.paper)
                .navigationTitle("Deine Touren")
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await state.sync() } } label: {
                        if state.synchronizing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }.disabled(state.synchronizing).accessibilityLabel("Mit dem Pi synchronisieren")
                } }
                .refreshable { await state.sync() }
        }
    }
}

struct TourDetailView: View {
    @EnvironmentObject var state: AppState
    var document: TourDocument
    @State private var showRoute = false
    @State private var exportURL: URL?
    @State private var modeSections: [RideModeSection] = []
    @State private var powerPoints: [RidePowerPoint] = []
    @State private var elevationPoints: [RideElevationPoint] = []
    @State private var measurementError: String?
    private var blogRideID: UUID? {
        if document.kind == .ride { return document.id }
        let rides = state.records.filter { !$0.deleted && $0.document.kind == .ride && $0.document.sourcePlanID == document.id && $0.document.recordingState == .finished }
        return (rides.first { !$0.document.track.isEmpty || ((try? state.store.blogPointCounts(rideID: $0.id).total) ?? 0) > 0 } ?? rides.first)?.id
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RouteMap(styleURL: state.mapStyleURL, route: document.profile.mode == .sea && !MarineNavigation.current(document.route) ? nil : document.route, waypoints: document.waypoints,
                         track: document.track, modeSections: document.kind == .ride && document.profile.mode.supportsBike ? modeSections : nil, fitRevision: document.id, carNavigation: document.profile.mode == .car, showWaterDepths: state.showWaterDepths && document.profile.mode == .sea, colorBySurface: document.profile.mode != .sea && document.profile.mode != .car,
                         hasStart: !document.isAwaitingStart)
                    .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                if document.kind == .ride && document.profile.mode.supportsBike {
                    RideModeLegend(modes: Array(Set(modeSections.compactMap(\.mode))).sorted(),
                                   hasUnknown: modeSections.contains { $0.mode == nil })
                }
                HStack {
                    Metric(label: document.kind == .ride ? (document.profile.mode == .hiking ? "Gegangen" : "Gefahren") : "Strecke", value: document.profile.mode == .sea ? MarineNavigation.distance(document.kind == .ride ? document.recordedDistance : document.route?.distance ?? 0) : Format.distance(document.kind == .ride ? document.recordedDistance : document.route?.distance ?? 0))
                    if document.profile.mode == .sea && document.kind == .plan {
                        Metric(label: "Abschnitte", value: "\(max(0, (document.route?.coordinates.count ?? 1) - 1))")
                    } else {
                        Metric(label: document.kind == .ride ? "Aufgezeichnet" : (document.profile.mode == .hiking ? "Gehzeit ca." : "Fahrzeit ca."), value: Format.duration(document.kind == .ride ? document.movingDuration : document.route.map { RouteTravelTime(route: $0, profile: document.profile).total } ?? 0))
                    }
                }
                if let blogRideID {
                    VStack(alignment: .leading, spacing: 8) {
                        if document.kind == .plan { Text("Blog der letzten gefahrenen Tour").font(.caption).foregroundStyle(.secondary) }
                        RideBlogActions(rideID: blogRideID)
                    }.padding(16)
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }
                if document.kind == .ride && document.profile.mode.supportsBike, let counts = try? state.store.bikeSampleCounts(rideID: document.id) {
                    Text(counts.total == 0 ? "Noch keine Bike-Messungen aufgezeichnet" :
                        "\(counts.total) Bike-Messungen · " + (counts.pending == 0 ? "auf dem Pi gespeichert" : "\(counts.pending) zur Übertragung vorgemerkt"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if document.profile.mode == .sea { Text(MarineNavigation.current(document.route) ? MarineNavigation.warning : MarineNavigation.outdatedRouteWarning).font(.caption) }
                else if document.profile.mode == .car { Text(CarNavigation.trafficNotice(route: document.route)).font(.caption).foregroundStyle(.secondary) }
                else if document.kind == .ride {
                    RecordedElevationChart(points: elevationPoints)
                    if document.profile.mode.supportsBike { RidePowerChart(points: powerPoints, distanceKM: document.recordedDistance / 1000) }
                    if let measurementError { Text(measurementError).font(.caption).foregroundStyle(.red) }
                } else if let route = document.route {
                    ElevationChart(route: route).frame(height: 140)
                }
                if document.route != nil && (document.profile.mode != .sea || MarineNavigation.current(document.route)) {
                    Button(document.profile.mode == .sea ? "Wegpunkte und Kurse" : document.profile.mode == .car ? "Pkw-Routendetails" : "Wegbeschaffenheit und Routendetails") { showRoute = true }
                }
                Button { state.open(document) } label: {
                    Label(document.kind == .ride ? "Als neue Tour planen" : "Planung öffnen", systemImage: "map")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white)
                if let exportURL { ShareLink(item: exportURL) { Label("GPX exportieren", systemImage: "square.and.arrow.up") } }
                if document.kind == .ride && document.profile.mode.supportsBike { Text("Belagsfarben: geplante Route · Fahrmodusfarben: gefahrene Strecke").font(.caption).foregroundStyle(.secondary) }
            }.padding(20)
        }.background(Theme.paper).navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRoute) {
                if document.profile.mode == .sea { MarinePlanDetailsView(points: document.waypoints, route: document.route) }
                else if let route = document.route { RouteDetailsView(route: route) }
            }
            .task(id: document.id) {
                exportURL = try? GPX.write(document)
                guard document.kind == .ride && document.profile.mode != .sea && document.profile.mode != .car else { return }
                elevationPoints = RideHistory.elevations(document.track)
                guard document.profile.mode.supportsBike else { return }
                do {
                    let samples = try state.store.bikeSamples(rideID: document.id, limit: Int.max)
                    modeSections = RideHistory.modeSections(track: document.track, samples: samples)
                    powerPoints = RideHistory.powers(samples, track: document.track)
                    measurementError = nil
                } catch {
                    modeSections = RideHistory.modeSections(track: document.track, samples: [])
                    powerPoints = []
                    measurementError = "Bike-Messungen konnten nicht geladen werden: " + error.localizedDescription
                }
            }
    }
}
