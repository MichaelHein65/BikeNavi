import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var state: AppState
    @State private var kind: DocumentKind = .plan
    var visible: [SavedRecord] { state.records.filter { !$0.deleted && $0.document.kind == kind } }
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
                        systemImage: kind == .plan ? "map" : "bicycle",
                        description: Text(kind == .plan ? "Deine Planungen werden automatisch gespeichert." : "Nach der ersten Fahrt findest du hier deinen Weg, Zeiten und Höhenprofil."))
                        .listRowBackground(Color.clear)
                }
                ForEach(visible) { record in
                    NavigationLink {
                        TourDetailView(document: record.document)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: kind == .plan ? "map.fill" : "flag.checkered").foregroundStyle(Theme.accent)
                                Text(record.document.title).font(.headline).lineLimit(2)
                            }
                            HStack(spacing: 15) {
                                Text(Format.distance(kind == .ride ? record.document.recordedDistance : record.document.route?.distance ?? 0))
                                if let route = record.document.route { Label("\(Int(route.ascent)) m", systemImage: "arrow.up.right") }
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
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RouteMap(styleURL: state.mapStyleURL, route: document.route, waypoints: document.waypoints,
                         track: document.track, modeSections: document.kind == .ride ? modeSections : nil, fitRevision: document.id, colorBySurface: true,
                         hasStart: !document.isAwaitingStart)
                    .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 24))
                if document.kind == .ride {
                    RideModeLegend(modes: Array(Set(modeSections.compactMap(\.mode))).sorted(),
                                   hasUnknown: modeSections.contains { $0.mode == nil })
                }
                HStack {
                    Metric(label: document.kind == .ride ? "Gefahren" : "Strecke", value: Format.distance(document.kind == .ride ? document.recordedDistance : document.route?.distance ?? 0))
                    Metric(label: document.kind == .ride ? "Aufgezeichnet" : "Fahrzeit ca.", value: Format.duration(document.kind == .ride ? document.movingDuration : document.route?.duration ?? 0))
                }
                if document.kind == .ride, let counts = try? state.store.bikeSampleCounts(rideID: document.id) {
                    Text(counts.total == 0 ? "Noch keine Bike-Messungen aufgezeichnet" :
                        "\(counts.total) Bike-Messungen · " + (counts.pending == 0 ? "auf dem Pi gespeichert" : "\(counts.pending) zur Übertragung vorgemerkt"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if document.kind == .ride {
                    RecordedElevationChart(points: elevationPoints)
                    RidePowerChart(points: powerPoints, distanceKM: document.recordedDistance / 1000)
                    if let measurementError { Text(measurementError).font(.caption).foregroundStyle(.red) }
                } else if let route = document.route {
                    ElevationChart(coordinates: route.coordinates).frame(height: 140)
                }
                if document.route != nil {
                    Button("Wegbeschaffenheit und Routendetails") { showRoute = true }
                }
                Button { state.open(document) } label: {
                    Label(document.kind == .ride ? "Als neue Tour planen" : "Planung öffnen", systemImage: "map")
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }.buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white)
                if let exportURL { ShareLink(item: exportURL) { Label("GPX exportieren", systemImage: "square.and.arrow.up") } }
                if document.kind == .ride { Text("Belagsfarben: geplante Route · Fahrmodusfarben: gefahrene Strecke").font(.caption).foregroundStyle(.secondary) }
            }.padding(20)
        }.background(Theme.paper).navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRoute) { if let route = document.route { RouteDetailsView(route: route) } }
            .task(id: document.id) {
                exportURL = try? GPX.write(document)
                guard document.kind == .ride else { return }
                elevationPoints = RideHistory.elevations(document.track)
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
