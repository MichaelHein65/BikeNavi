import SwiftUI

struct OfflineRegionsView: View {
    @EnvironmentObject var state: AppState
    var center: Coordinate?
    @State private var regions: [OfflineRegion] = []
    @State private var name = "Meine Radregion"
    @State private var radius = 1
    @State private var status = ""
    @State private var task: Task<Void, Never>?
    @State private var deleting: OfflineRegion?
    @State private var pending = 0
    @State private var discardPending = false
    var body: some View {
        List {
            Section("Region vorbereiten") {
                TextField("Name", text: $name)
                Picker("Ausdehnung", selection: $radius) {
                    Text("3 × 3 Bereiche · etwa 10–17 km").tag(1)
                    Text("5 × 5 Bereiche · etwa 18–28 km").tag(2)
                }
                Text("Mittelpunkt ist der Routenstart, sonst dein aktueller Standort. Download mit Pi-Verbindung, danach auf diesem iPhone verfügbar.").font(.caption)
                if task == nil {
                    Button("Region laden / fortsetzen") { start() }.disabled(center == nil || state.api == nil)
                        .accessibilityIdentifier("downloadRegion")
                } else {
                    ProgressView(); Button("Download pausieren") { task?.cancel() }
                }
                if pending > 0, task == nil {
                    Button("Unvollständige Downloads verwerfen", role: .destructive) { discardPending = true }
                }
                if !status.isEmpty { Text(status).font(.subheadline).accessibilityIdentifier("regionStatus") }
            }
            Section("Gespeicherte Regionen") {
                if regions.isEmpty { Text("Noch keine Region gespeichert") }
                ForEach(regions) { region in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(region.name).font(.headline)
                        Text("\(region.tiles.count) Bereiche · \(ByteCountFormatter.string(fromByteCount: Int64(region.bytes), countStyle: .file))").font(.caption)
                        Text("Ältester Abruf: \(Date(timeIntervalSince1970: region.oldestSource).formatted(date: .abbreviated, time: .shortened))").font(.caption)
                        Text("Routing und einfache Wegenetzkarte gespeichert. OSM kann vor Ort veraltet oder unvollständig sein.").font(.caption)
                        Button("Wegenetzkarte verwenden") {
                            Task { do { try await state.useRegion(region); status = "Lokale Wegenetzkarte ausgewählt" } catch { status = error.localizedDescription } }
                        }.accessibilityIdentifier("useRegion")
                        NavigationLink("Offline-Orte") { OfflinePOIView(region: region, center: center) }
                        HStack {
                            Button("Aktualisieren") { start(region) }.disabled(task != nil || state.api == nil)
                            Spacer()
                            Button("Löschen", role: .destructive) { deleting = region }.disabled(task != nil)
                        }
                    }.padding(.vertical, 6)
                }
            }
            Section("Karteninhalt") {
                Text("Die lokale Wegenetzkarte zeigt die im Fahrradgraph erfassten Wege. Gebäude, Gelände, Beschriftung und Höhenlinien fehlen. Ausführliche Offline-Karten des eigenen Kartenservers können zusätzlich in den Streckendetails geladen werden.")
                Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
        }.buttonStyle(.borderless).navigationTitle("Offline-Regionen").task { await reload() }
            .confirmationDialog("Offline-Region löschen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Region und ihre Offline-Orte löschen", role: .destructive) {
                    guard let region = deleting else { return }; deleting = nil
                    Task {
                        do { try await OfflineRegionStore.shared.delete(region); state.regionDeleted(region); await reload() }
                        catch { status = error.localizedDescription }
                    }
                }
            }
            .confirmationDialog("Unvollständige Downloads verwerfen? Fertige Regionen bleiben erhalten.", isPresented: $discardPending) {
                Button("Download-Arbeitsstände löschen", role: .destructive) {
                    Task { do { try await OfflineRegionStore.shared.discardPendingDownloads(); await reload() } catch { status = error.localizedDescription } }
                }
            }
            .onDisappear { task?.cancel() }
    }
    private func reload() async {
        do { regions = try await OfflineRegionStore.shared.list(); pending = try await OfflineRegionStore.shared.pendingDownloads() } catch { status = error.localizedDescription }
    }
    private func start(_ region: OfflineRegion? = nil) {
        guard let api = state.api else { return }
        task = Task {
            defer { task = nil }
            do {
                let tiles = try region?.tiles ?? OfflineRegion.tiles(center: center!, radius: radius)
                let result = try await OfflineRegionStore.shared.download(name: region?.name ?? name, tiles: tiles, refresh: region != nil,
                    fetch: { try await api.regionTile($0, refresh: $1) }, progress: { done, total in
                        await MainActor.run { status = "\(done) von \(total) Bereichen geprüft" }
                    })
                try await state.useRegion(result)
                status = "Region geprüft und gespeichert · lokale Wegenetzkarte aktiv"
                state.prepareLocalRouting(refresh: true)
                await reload()
            } catch is CancellationError { status = "Pausiert. Erneutes Laden setzt an geprüften Bereichen fort." }
            catch { status = error.localizedDescription }
            await reload()
        }
    }
}

struct OfflinePOIView: View {
    @EnvironmentObject var state: AppState
    let region: OfflineRegion
    var center: Coordinate?
    @State private var places: [OfflinePOI] = []
    @State private var category: OfflinePOICategory = .water
    @State private var query = ""
    @State private var notice: String?
    var filtered: [OfflinePOI] {
        places.filter { $0.category == category && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query)) }
            .sorted { a, b in
                guard let center else { return a.title < b.title }
                return a.coordinate.distance(to: center) < b.coordinate.distance(to: center)
            }
    }
    var body: some View {
        List {
            Section {
                Picker("Kategorie", selection: $category) { ForEach(OfflinePOICategory.allCases, id: \.self) { Text($0.title).tag($0) } }
                TextField("Im Paket suchen", text: $query)
                Text("\(region.name) · Offline-Katalog · Abruf \(Date(timeIntervalSince1970: region.oldestSource).formatted(date: .abbreviated, time: .omitted))").font(.caption)
                Text("Öffnung und Trinkwasserqualität vor Ort prüfen. Entfernungen sind Luftlinie. Keine Internetabfrage.").font(.caption)
                if let notice { Text(notice).font(.subheadline) }
            }
            if filtered.isEmpty { Text("Keine passenden Orte im Paket erfasst") }
            ForEach(filtered) { place in
                VStack(alignment: .leading, spacing: 8) {
                    Text(place.title).font(.headline)
                    if let center { Text(Format.distance(center.distance(to: place.coordinate)) + " Luftlinie").font(.caption) }
                    if let hours = place.openingHours { Text(hours).font(.caption) }
                    Text(place.source + " · " + place.id).font(.caption).foregroundStyle(.secondary)
                    Button("Ort merken") { state.savePlace(place.waypoint); notice = "Ort gespeichert" }.frame(minHeight: 44)
                    Button("Zur Planung hinzufügen") {
                        state.addPlaceToTour(place.waypoint)
                        notice = state.plan.route?.isGPXTrack == true ? "GPX-Originalspur bleibt unverändert. Ort kann separat gemerkt werden." : "Ort zur Planung hinzugefügt; eine laufende Fahrt bleibt unverändert."
                    }.frame(minHeight: 44).disabled(state.plan.route?.isGPXTrack == true || state.plan.profile.mode == .sea)
                }.padding(.vertical, 4)
            }
        }.buttonStyle(.borderless).navigationTitle("Offline-Orte")
            .task { do { places = try await OfflineRegionStore.shared.pois(region) } catch { notice = error.localizedDescription } }
    }
}
