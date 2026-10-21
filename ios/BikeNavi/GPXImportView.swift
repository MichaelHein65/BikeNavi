import SwiftUI

struct GPXImportView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let file: GPXFile
    @State private var part = 0
    @State private var start = 1
    @State private var end = 2
    @State private var reversed = false
    @State private var preview: TourDocument?
    @State private var failure: String?
    private var selection: String { "\(part):\(start):\(end):\(reversed)" }
    private var pointCount: Int { file.parts.indices.contains(part) ? file.parts[part].points.count : 0 }
    private var boundedStart: Int { min(max(1, start), max(1, pointCount - 1)) }
    private var boundedEnd: Int { min(max(2, end), max(2, pointCount)) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Datei") {
                    Text(file.name).font(.headline)
                    Text("\(file.parts.count) Abschnitte · \(file.waypoints.count) Wegpunkte")
                    Text("Ein Abschnitt pro Tour. Getrennte Abschnitte werden nicht verbunden. Andere Abschnitte kannst du danach separat importieren.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !file.parts.isEmpty {
                    Section("Strecke auswählen") {
                        Picker("Abschnitt", selection: $part) {
                            ForEach(file.parts.indices, id: \.self) { index in
                                Text("\(index + 1). \(file.parts[index].name) (\(file.parts[index].points.count) Punkte)").tag(index)
                            }
                        }.accessibilityIdentifier("gpxPart")
                        if pointCount >= 2 {
                            HStack {
                                Text("Von Punkt").fixedSize()
                                TextField("Start", value: $start, format: .number.grouping(.never))
                                    .keyboardType(.numberPad).accessibilityIdentifier("gpxStartNumber")
                                Text("bis")
                                TextField("Ziel", value: $end, format: .number.grouping(.never))
                                    .keyboardType(.numberPad).accessibilityIdentifier("gpxEndNumber")
                            }
                            Stepper("Start: Punkt \(start)", value: $start, in: 1...(boundedEnd - 1))
                                .accessibilityIdentifier("gpxStart")
                            Stepper("Ziel: Punkt \(end)", value: $end, in: (boundedStart + 1)...pointCount)
                                .accessibilityIdentifier("gpxEnd")
                            Toggle("Richtung umkehren", isOn: $reversed).accessibilityIdentifier("gpxReverse")
                        }
                    }
                }
                if let preview, let route = preview.route {
                    Section("Ausgewählte Originalspur") {
                        RouteMap(styleURL: state.mapStyleURL, route: route, waypoints: preview.waypoints, fitRevision: route.id)
                            .frame(height: 210).listRowInsets(EdgeInsets())
                        Text("\(route.coordinates.count) Punkte · \(Format.distance(route.distance)) · Fahrrad")
                        Text("Geometrie und Höhen bleiben erhalten. Keine Straßenanpassung, keine Abbiegehinweise und keine automatische Rückführung. Die Hintergrundkarte benötigt ein separat vorbereitetes Offline-Paket.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Als neue Tour importieren") { state.importGPX(preview) }
                            .accessibilityIdentifier("gpxConfirm")
                    }
                }
                if let failure { Section { Text(failure).foregroundStyle(.red).accessibilityIdentifier("gpxFailure") } }
                if file.parts.isEmpty { Text("Diese Datei enthält nur Wegpunkte. Ohne Track oder Route ist keine Streckenverfolgung möglich.") }
                if !file.waypoints.isEmpty {
                    Section("Wegpunkte · bleiben vollständig erhalten") {
                        ForEach(file.waypoints.indices, id: \.self) { index in
                            let point = file.waypoints[index]
                            VStack(alignment: .leading) {
                                Text(point.details.name ?? "Wegpunkt \(index + 1)")
                                Text(String(format: "%.6f, %.6f", point.coordinate.latitude, point.coordinate.longitude)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Datenerhalt") {
                    Text("Alle Wegpunkte bleiben in ihrer Reihenfolge erhalten. Der Export dieser Tour enthält den ausgewählten Abschnitt und Punktbereich. Erweiterungen, Kommentare und sonstige GPX-Metadaten werden nicht übernommen.")
                        .font(.caption)
                    if file.ignoredExtensions { Text("Die Datei enthält Erweiterungen; diese werden ausgelassen.").font(.caption).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("GPX importieren").navigationBarTitleDisplayMode(.inline)
            .tint(Theme.accent)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onAppear { selectPart() }
            .onChange(of: part) { _, _ in selectPart() }
            .task(id: selection) {
                preview = nil; failure = nil
                guard !file.parts.isEmpty else { return }
                guard start >= 1, start < end, end <= pointCount else {
                    failure = "Wähle mindestens zwei aufeinanderfolgende Punkte zwischen 1 und \(pointCount)."
                    return
                }
                let index = part, first = start - 1, last = end - 1, reverse = reversed
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try file.document(part: index, start: first, end: last, reversed: reverse)
                    }.value
                    guard !Task.isCancelled else { return }
                    preview = result
                } catch { if !Task.isCancelled { failure = error.localizedDescription } }
            }
        }
    }
    private func selectPart() { preview = nil; start = 1; end = max(2, pointCount) }
}

struct GPXPlanCard: View {
    @EnvironmentObject var state: AppState
    @State private var exportURL: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.plan.title).font(.headline).lineLimit(2)
            Text("GPX-Originalspur · \(Format.distance(state.plan.route?.distance ?? 0))")
                .font(.subheadline.bold()).accessibilityIdentifier("gpxOriginalTrack")
            Text("Keine automatische Rückführung oder Abbiegehinweise. Beläge und Zugänglichkeit unbekannt.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Umkehren", systemImage: "arrow.left.arrow.right") { state.reversePlan() }
                    .accessibilityIdentifier("gpxReversePlan")
                Spacer()
                if let exportURL { ShareLink(item: exportURL) { Label("GPX", systemImage: "square.and.arrow.up") } }
            }.buttonStyle(.bordered)
            Button("Track bearbeiten / Wegpunkte") {
                guard let route = state.plan.route, let metadata = route.gpxTrack else { return }
                let points = zip(route.coordinates, metadata.points).map { GPXPoint(coordinate: $0.0, details: $0.1) }
                state.gpxImport = GPXFile(name: state.plan.title,
                    parts: [GPXPart(name: state.plan.title, kind: metadata.kind, points: points)], waypoints: metadata.waypoints)
            }.font(.subheadline).accessibilityIdentifier("gpxEdit")
            if state.waitingForRideLocation { Text("Standort wird ermittelt …").font(.caption) }
            Button {
                if state.activeRide != nil { state.resumeApplicationRide() }
                else if state.waitingForRideLocation { state.cancelRideStart() }
                else { state.startRide() }
            } label: {
                Label(state.activeRide != nil ? "Fahrt fortsetzen" : state.waitingForRideLocation ? "Standortsuche abbrechen" : "Track folgen", systemImage: "location.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
                .buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white).accessibilityIdentifier("gpxFollow")
        }.padding(18).background(Theme.paper)
            .task(id: state.plan.route?.id) { exportURL = try? GPX.write(state.plan) }
    }
}
