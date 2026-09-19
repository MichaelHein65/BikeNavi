import SwiftUI
import MapLibre

struct OfflineContext: Codable {
    var routeID: UUID
    var styleURL: String
}

struct OfflineDownloadView: View {
    @EnvironmentObject var state: AppState
    let route: CalculatedRoute
    @State private var progressText = "Noch nicht heruntergeladen"
    @State private var complete = false
    @State private var busy = false
    @State private var failure: String?
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var matchingPack: MLNOfflinePack? {
        MLNOfflineStorage.shared.packs?.first {
            guard let context = try? JSONDecoder().decode(OfflineContext.self, from: $0.context) else { return false }
            return context.routeID == route.id && context.styleURL == state.mapStyleURL
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(complete ? "Offline bereit" : "Karte für unterwegs", systemImage: complete ? "checkmark.circle.fill" : "arrow.down.circle")
                .font(.headline).foregroundStyle(Theme.accent)
            Text(progressText).font(.caption).foregroundStyle(.secondary)
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            if !state.offlineMapsAllowed {
                Text("Die Route ist lokal gespeichert. Für ein vollständiges Offline-Paket muss zuerst unser Kartenserver eingerichtet werden.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if !complete {
                Button(busy ? "Download pausieren" : "Offline-Karte herunterladen") {
                    if busy { matchingPack?.suspend(); busy = false } else { download() }
                }.buttonStyle(.bordered)
            }
        }.padding(.vertical, 8)
            .onAppear { refresh() }
            .onReceive(timer) { _ in refresh() }
            .onReceive(NotificationCenter.default.publisher(for: .MLNOfflinePackError)) { notification in
                if let pack = notification.object as? MLNOfflinePack, pack === matchingPack {
                    failure = "Ein Teil der Karte konnte nicht geladen werden. Prüfe die Verbindung und setze den Download fort."
                }
            }
    }
    private func refresh() {
        guard let pack = matchingPack else { complete = false; return }
        pack.requestProgress()
        complete = pack.state == .complete
        busy = pack.state == .active
        let p = pack.progress
        if complete { progressText = "Karte, Darstellung und Route auf diesem iPhone gespeichert." }
        else { progressText = "\(p.countOfResourcesCompleted) von ca. \(p.countOfResourcesExpected) Kartenteilen geladen" }
    }
    private func download() {
        guard state.offlineMapsAllowed, let styleURL = URL(string: state.mapStyleURL), styleURL.scheme == "https",
              styleURL.host != "tile.openstreetmap.org" else { return }
        failure = nil
        if let pack = matchingPack { pack.resume(); busy = true; return }
        let latitudes = route.coordinates.map(\.latitude), longitudes = route.coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else { return }
        guard maxLat - minLat < 2, maxLon - minLon < 2 else {
            failure = "Diese Tour umfasst einen zu großen Kartenbereich für den ersten Offline-Download. Bitte kürzere Etappen planen."
            return
        }
        let marginLat = 0.01
        let marginLon = 0.01 / max(0.2, cos((minLat + maxLat) / 2 * .pi / 180))
        let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: max(-85, minLat - marginLat), longitude: max(-180, minLon - marginLon)),
                                         ne: CLLocationCoordinate2D(latitude: min(85, maxLat + marginLat), longitude: min(180, maxLon + marginLon)))
        let region = MLNTilePyramidOfflineRegion(styleURL: styleURL, bounds: bounds, fromZoomLevel: 8, toZoomLevel: 15)
        guard let data = try? JSONEncoder().encode(OfflineContext(routeID: route.id, styleURL: state.mapStyleURL)) else { return }
        busy = true
        MLNOfflineStorage.shared.addPack(for: region, withContext: data) { pack, error in
            DispatchQueue.main.async {
                if error != nil { failure = "Der Offline-Download konnte nicht angelegt werden."; busy = false }
                else { pack?.resume() }
            }
        }
    }
}
