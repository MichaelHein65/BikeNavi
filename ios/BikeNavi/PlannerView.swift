import SwiftUI
import Charts

struct PlannerView: View {
    @EnvironmentObject var state: AppState
    @State private var showSearch = false
    @State private var showProfile = false
    @State private var showDetails = false
    @State private var showWaypoints = false
    @State private var showSavedPlaces = false
    @State private var choosingPoint = false
    @State private var saveCandidate: Waypoint?
    @State private var selectedMapPlace: SavedPlace?
    @State private var choosingSavedPlace = false
    @State private var mapError: String?
    @AppStorage("planningDetailsExpanded") private var detailsExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editingTourName: Bool
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                RouteMap(styleURL: state.mapStyleURL, route: state.plan.route, waypoints: state.plan.waypoints, savedPlaces: state.savedPlaces,
                         focus: state.mapFocus, fitRevision: state.mapRevision, colorBySurface: true, topOverlayInset: 170, hasStart: !state.plan.isAwaitingStart,
                         onTap: {
                             if editingTourName { finishEditingName() }
                             else { state.selectedPoint = $0; choosingPoint = true }
                         }, onSavedPlaceTap: {
                             selectedMapPlace = $0
                             choosingSavedPlace = true
                         }, onError: { mapError = $0 })
                    .accessibilityIdentifier("planningMap")
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("BikeNavi").font(.system(.title, design: .rounded, weight: .heavy))
                            Text("DEIN WEG NACH DRAUSSEN").font(.system(size: 9, weight: .semibold)).tracking(2)
                        }.foregroundStyle(Theme.ink)
                            .padding(10).background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))
                        Spacer()
                        HStack(spacing: 8) {
                            Button { state.resetPlan() } label: { Image(systemName: "minus").font(.title3.bold()).frame(width: 44, height: 44) }
                                .background(Theme.paper, in: Circle()).accessibilityLabel("Planung zurücksetzen")
                            Button { state.newPlan() } label: { Image(systemName: "plus").font(.title3.bold()).frame(width: 44, height: 44) }
                                .background(Theme.paper, in: Circle()).accessibilityLabel("Neue Tour")
                        }
                    }
                    HStack(spacing: 10) {
                        Button { showSearch = true } label: {
                            HStack { Image(systemName: "magnifyingglass"); Text("Wohin zieht es dich?"); Spacer() }
                                .font(.subheadline).foregroundStyle(Theme.ink).padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 18))
                        }.accessibilityIdentifier("placeSearch")
                        Button { state.useCurrentLocation() } label: {
                            Image(systemName: "location.fill").frame(width: 48, height: 48)
                        }.background(Theme.paper, in: RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Standort als Start verwenden")
                        Button { showSavedPlaces = true } label: {
                            Image(systemName: "bookmark.fill").frame(width: 48, height: 48)
                        }.background(Theme.paper, in: RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Meine gespeicherten Orte")
                    }
                    if !detailsExpanded, let error = state.planningError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("planningError")
                    }
                    if !detailsExpanded, let message = state.automaticStartMessage ?? (state.calculating ? state.localRoutingStatus : nil) {
                        HStack(spacing: 10) {
                            if !state.location.denied { ProgressView() }
                            Text(message).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("compactPlanningStatus")
                    }
                    if let mapError { Text(mapError).font(.caption).foregroundStyle(Theme.ink).padding(10).background(Theme.paper, in: RoundedRectangle(cornerRadius: 12)) }
                }.padding(18)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { planningCard }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if editingTourName {
                        Spacer()
                        Button("Fertig", action: finishEditingName)
                    }
                }
            }
            .sheet(isPresented: $showSearch) { SearchView() }
            .sheet(isPresented: $showProfile) { ProfileView() }
            .sheet(isPresented: $showDetails) { if let route = state.plan.route { RouteDetailsView(route: route) } }
            .sheet(isPresented: $showWaypoints) { WaypointsView() }
            .sheet(isPresented: $showSavedPlaces) { SavedPlacesView() }
            .confirmationDialog("Punkt auf der Karte verwenden", isPresented: $choosingPoint, titleVisibility: .visible) {
                ForEach(PointRole.allCases, id: \.self) { role in
                    if role != .via || state.plan.destinationPoint != nil {
                        Button("Als \(role.title) verwenden") {
                            if let coordinate = state.selectedPoint {
                                state.addPoint(Waypoint(name: "Kartenpunkt", coordinate: coordinate), role: role)
                            }
                        }
                    }
                }
                Button("Ort speichern") {
                    if let coordinate = state.selectedPoint {
                        saveCandidate = Waypoint(name: "", coordinate: coordinate)
                    }
                }
            }
            .sheet(item: $saveCandidate) { SavedPlaceEditor(candidate: $0) }
            .confirmationDialog(selectedMapPlace?.name ?? "Gespeicherten Ort verwenden", isPresented: $choosingSavedPlace, titleVisibility: .visible) {
                ForEach(PointRole.allCases, id: \.self) { role in
                    if role != .via || state.plan.destinationPoint != nil {
                        Button("Als \(role.title) verwenden") {
                            if let place = selectedMapPlace { state.addPoint(place.waypoint, role: role) }
                        }
                    }
                }
            }
        }
        .onDisappear { editingTourName = false }
        .onChange(of: state.plan.id) { _, _ in editingTourName = false }
    }
    private var planningCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(Theme.secondaryInk.opacity(0.5)).frame(width: 38, height: 5)
                .frame(maxWidth: .infinity).accessibilityHidden(true)
            HStack {
                TextField("Name deiner Tour", text: Binding(get: { state.plan.title }, set: { state.renamePlan(to: $0) }))
                    .font(.title3.bold()).foregroundStyle(Theme.ink)
                    .focused($editingTourName)
                    .accessibilityIdentifier("tourName")
                    .submitLabel(.done)
                    .onSubmit(finishEditingName)
                if editingTourName {
                    Button("Fertig", action: finishEditingName)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize()
                        .accessibilityLabel("Tourname übernehmen und Tastatur schließen")
                }
                if detailsExpanded {
                    Image(systemName: state.currentRecord?.dirty == false ? "checkmark.icloud" : "internaldrive")
                        .foregroundStyle(Theme.accent).accessibilityLabel(state.currentRecord?.dirty == false ? "Synchronisiert" : "Lokal gespeichert")
                }
                Button { setDetailsExpanded(!detailsExpanded) } label: {
                    Image(systemName: detailsExpanded ? "chevron.down" : "chevron.up")
                        .font(.subheadline.bold()).frame(width: 32, height: 36).contentShape(Rectangle())
                }
                .accessibilityLabel(detailsExpanded ? "Tourdetails ausblenden" : "Tourdetails einblenden")
                .accessibilityIdentifier("togglePlanningDetails")
            }
            if detailsExpanded {
                HStack {
                    Button { showProfile = true } label: {
                        Label(state.plan.profile.title, systemImage: "bicycle").font(.subheadline.weight(.semibold))
                    }.buttonStyle(.bordered)
                    Button { showSavedPlaces = true } label: {
                        Label("Meine Orte", systemImage: "bookmark.fill").font(.subheadline.weight(.semibold))
                    }.buttonStyle(.bordered)
                    Text(state.plan.profile.surface == .any ? "Schotter erlaubt" : "Befestigte Wege")
                        .font(.caption).foregroundStyle(Theme.secondaryInk)
                    Spacer(minLength: 0)
                }
                Button { showWaypoints = true } label: {
                    HStack(alignment: .center) {
                        VStack(spacing: 4) {
                            Circle().stroke(Theme.accent, lineWidth: 2).frame(width: 9, height: 9)
                            Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 12)
                            Image(systemName: "mappin.circle.fill").font(.system(size: 13))
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            Text(state.plan.startPoint?.name ?? (state.plan.isAwaitingStart ? "Start: aktueller Standort" : "Start auf der Karte wählen"))
                            Text(state.plan.destinationPoint?.name ?? "Ziel hinzufügen")
                        }.font(.subheadline).lineLimit(1)
                        Spacer()
                        if state.plan.waypoints.count > 2 { Text("+\(state.plan.waypoints.count - 2)").font(.caption.bold()) }
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }.foregroundStyle(Theme.ink)
                }.accessibilityIdentifier("waypoints")
                if let message = state.automaticStartMessage {
                    Text(message).font(.caption).foregroundStyle(Theme.secondaryInk)
                        .accessibilityIdentifier("automaticStartStatus")
                }
                if let route = state.plan.route {
                    HStack {
                        Metric(label: "Strecke", value: Format.distance(route.distance))
                        Metric(label: "Fahrzeit ca.", value: Format.duration(route.duration))
                        Metric(label: "Anstieg", value: route.provider.hasPrefix("BikeNavi iPhone") ? "–" : "\(Int(route.ascent)) m")
                    }
                    SurfaceLegend()
                    if route.surfaceSections == nil {
                        Button { Task { await state.calculateRoute() } } label: {
                            Text(state.calculating ? "Beläge werden geladen …" : "Belagsfarben fehlen · Route neu berechnen")
                                .font(.caption).multilineTextAlignment(.leading)
                        }.disabled(state.calculating)
                    }
                    if route.intersectionContexts == nil {
                        Button { Task { await state.calculateRoute() } } label: {
                            Text(state.calculating ? "Kreuzungen werden geladen …" : "Kreuzungsdetails fehlen · Route neu berechnen")
                                .font(.caption).multilineTextAlignment(.leading)
                        }.disabled(state.calculating)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.localRoutingStatus).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("localRoutingStatus")
                        if !state.preparingLocalRouting {
                            Button(state.localRoutingReady ? "Wegenetz aktualisieren" : "Lokale Rückführung vorbereiten") {
                                state.prepareLocalRouting(refresh: state.localRoutingReady)
                            }.font(.caption)
                        }
                    }
                    HStack {
                        Button { showDetails = true } label: { Image(systemName: "chart.xyaxis.line").frame(width: 44, height: 44) }
                            .buttonStyle(.bordered).accessibilityLabel("Höhenprofil und Wegbeläge")
                        Button { state.startRide() } label: { Label("Tour starten", systemImage: "location.north.fill").frame(maxWidth: .infinity).padding(.vertical, 8) }
                            .buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white)
                    }
                } else {
                    Button { Task { await state.calculateRoute() } } label: {
                        HStack {
                            if state.calculating { ProgressView().tint(.white) }
                            Text(state.calculating ? "Deine Route entsteht …" : "Route berechnen")
                        }.frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white)
                        .disabled(!state.plan.canCalculateRoute || state.calculating)
                        .accessibilityIdentifier("calculateRoute")
                    if state.calculating {
                        Text(state.localRoutingStatus).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = state.planningError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("planningError")
                    }
                    if state.plan.waypoints.count < 2 && !state.plan.isAwaitingStart {
                        Text(state.plan.startPoint == nil ? "Wähle Start und Ziel auf der Karte oder über die Suche." : "Wähle jetzt dein Ziel. Die Route wird automatisch berechnet.")
                            .font(.caption).foregroundStyle(Theme.secondaryInk)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, detailsExpanded ? 20 : 10)
        .background(Theme.paper, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.07), radius: 15, y: -5)
        .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { gesture in
            let delta = gesture.translation
            guard abs(delta.height) > abs(delta.width) * 1.3, abs(delta.height) > 40 else { return }
            setDetailsExpanded(delta.height < 0)
        })
        .accessibilityAction(named: "Tourdetails ausblenden") { setDetailsExpanded(false) }
        .accessibilityAction(named: "Tourdetails einblenden") { setDetailsExpanded(true) }
    }

    private func setDetailsExpanded(_ expanded: Bool) {
        if editingTourName { finishEditingName() }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { detailsExpanded = expanded }
    }

    private func finishEditingName() {
        editingTourName = false
        state.finishRenamingPlan()
    }
}

// Explicit button styles keep List from treating all actions as one row action.
// Both lists share this row so selecting or renaming can never invoke deletion.
private struct SavedPlaceRow: View {
    @EnvironmentObject private var state: AppState
    let place: SavedPlace
    let onSelect: () -> Void
    let onRename: () -> Void
    @State private var confirmingDeletion = false

    var body: some View {
        HStack {
            Button(action: onSelect) {
                Label(place.name, systemImage: "bookmark.fill")
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Button(action: onRename) {
                Image(systemName: "pencil").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Gespeicherten Ort umbenennen")
            Button { confirmingDeletion = true } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Gespeicherten Ort löschen")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
        .confirmationDialog("Ort löschen?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("Ort löschen", role: .destructive) { state.deletePlace(place) }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Möchtest du „\(place.name)“ aus deinen gespeicherten Orten löschen?")
        }
    }
}

struct SavedPlacesView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editingPlace: SavedPlace?

    var body: some View {
        NavigationStack {
            List {
                if state.savedPlaces.isEmpty {
                    ContentUnavailableView("Noch keine gespeicherten Orte", systemImage: "bookmark",
                                           description: Text("Tippe auf einen Kartenpunkt und wähle „Ort speichern“. Alternativ kannst du einen Suchtreffer über das Lesezeichen speichern."))
                        .listRowBackground(Color.clear)
                } else {
                    Section("Meine Orte") {
                        ForEach(state.savedPlaces) { place in
                            SavedPlaceRow(place: place, onSelect: {
                                state.addPlaceToTour(place.waypoint)
                                dismiss()
                            }, onRename: { editingPlace = place })
                        }
                    }
                }
            }
            .navigationTitle("Meine Orte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sheet(item: $editingPlace) { place in
                SavedPlaceEditor(candidate: Waypoint(name: place.name, coordinate: place.coordinate), existing: place)
            }
        }
    }
}

struct SearchView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var results: [Waypoint] = []
    @State private var searching = false
    @State private var error: String?
    @State private var saveCandidate: Waypoint?
    @State private var editingPlace: SavedPlace?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Ort, Adresse oder Sehenswürdigkeit", text: $query).submitLabel(.search).onSubmit { Task { await search() } }
                        Button { Task { await search() } } label: { Image(systemName: "magnifyingglass") }.disabled(query.count < 3 || searching)
                    }
                }
                if !state.savedPlaces.isEmpty {
                    Section("Gespeicherte Orte") {
                        ForEach(state.savedPlaces) { place in
                            SavedPlaceRow(place: place, onSelect: {
                                state.addPlaceToTour(place.waypoint)
                                dismiss()
                            }, onRename: { editingPlace = place })
                        }
                    }
                }
                if searching { ProgressView("Suche läuft …") }
                if let error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                ForEach(results) { point in
                    HStack {
                        Button { state.addPlaceToTour(point); dismiss() } label: {
                            Label(point.name, systemImage: "mappin.and.ellipse").foregroundStyle(.primary).padding(.vertical, 5)
                        }
                        Spacer()
                        Button { saveCandidate = point } label: { Image(systemName: "bookmark") }
                            .accessibilityLabel("Ort speichern")
                    }
                    .buttonStyle(.borderless)
                }
                if results.isEmpty && !searching && error == nil {
                    Text("Suche beispielsweise nach einer Burg, einem Café oder einer Adresse.").foregroundStyle(.secondary)
                }
            }.navigationTitle("Ort wählen").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
                .sheet(item: $saveCandidate) { SavedPlaceEditor(candidate: $0) }
                .sheet(item: $editingPlace) { place in
                    SavedPlaceEditor(candidate: Waypoint(name: place.name, coordinate: place.coordinate), existing: place)
                }
        }
    }
    func search() async {
        guard query.count >= 3 else { return }
        guard let api = state.api else { error = "Verbinde zuerst deinen Pi in den Einstellungen. Orte kannst du bereits auf der Karte auswählen."; return }
        searching = true; error = nil
        defer { searching = false }
        do { results = try await api.search(query, near: state.location.coordinate); if results.isEmpty { error = "Keine passenden Orte gefunden." } }
        catch { self.error = error.localizedDescription }
    }
}

struct SavedPlaceEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    let candidate: Waypoint
    let existing: SavedPlace?
    @State private var name: String

    init(candidate: Waypoint, existing: SavedPlace? = nil) {
        self.candidate = candidate
        self.existing = existing
        _name = State(initialValue: candidate.name == "Kartenpunkt" ? "" : candidate.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Zum Beispiel: Lieblingscafé", text: $name).submitLabel(.done) }
                Section { Text("Der Ort erscheint anschließend bei der Ortssuche und kann direkt zur Tour hinzugefügt werden.")
                    .font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Ort speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        if let existing { state.renamePlace(existing, to: name) }
                        else { state.savePlace(name: name, coordinate: candidate.coordinate) }
                        dismiss()
                    }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Dein Fahrrad") {
                    Picker("Fahrradtyp", selection: $state.plan.profile.bike) { ForEach(Bike.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Elektrische Unterstützung", isOn: $state.plan.profile.electric)
                }
                Section {
                    ForEach(SurfacePreference.allCases, id: \.self) { choice in
                        Button { state.plan.profile.surface = choice } label: {
                            HStack { Text(choice.title); Spacer(); if state.plan.profile.surface == choice { Image(systemName: "checkmark.circle.fill") } }
                        }.foregroundStyle(.primary)
                    }
                } header: { Text("Deine Wege") } footer: {
                    Text("Befestigt umfasst auch Pflaster. „Nur bekannte befestigte Wege“ erlaubt insgesamt bis zu 100 m unbefestigte oder unbekannte Abschnitte pro Tour, beispielsweise kurze Schotterverbindungen. Eine Garantie für den tatsächlichen Zustand ist damit nicht verbunden.")
                }
                Section { Toggle("Sanfte Steigungen bevorzugen", isOn: $state.plan.profile.gentleHills) }
                Section("Schnellauswahl") {
                    Button("Meine Tour · Schotter erlaubt") { state.plan.profile.surface = .any }
                    Button("Gemeinsam · befestigte Wege bevorzugen") { state.plan.profile.surface = .preferPaved }
                }
            }.navigationTitle("So fährst du gern").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Übernehmen") { dismiss() } } }
                .onDisappear { state.invalidateRoute() }
        }
    }
}

struct WaypointsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var showSearch = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(state.plan.waypoints.enumerated()), id: \.element.id) { index, point in
                        HStack {
                            Text(index == 0 && !state.plan.isAwaitingStart ? "S" : (index == state.plan.waypoints.count - 1 ? "Z" : "\(index + (state.plan.isAwaitingStart ? 1 : 0))"))
                                .font(.caption.bold()).foregroundStyle(Theme.forest).frame(width: 28, height: 28).background(Theme.lime, in: Circle())
                            Text(point.name)
                        }
                    }.onDelete { state.plan.waypoints.remove(atOffsets: $0); state.invalidateRoute() }
                        .onMove { state.plan.waypoints.move(fromOffsets: $0, toOffset: $1); state.invalidateRoute() }
                } header: { Text("Reihenfolge deiner Tour") } footer: { Text("Verschiebe die Punkte, um ihre Reihenfolge zu ändern. Der erste Punkt ist der Start, der letzte das Ziel.") }
                Section {
                    Button("Ort hinzufügen") { showSearch = true }
                    Button { state.reversePlan() } label: {
                        Label("Tour umkehren", systemImage: "arrow.triangle.2.circlepath")
                    }.disabled(!state.plan.canCalculateRoute)
                    Button("Zurück zum Start") {
                        if var first = state.plan.startPoint { first.id = UUID(); state.plan.waypoints.append(first); state.invalidateRoute() }
                    }.disabled(state.plan.startPoint == nil)
                }
            }.navigationTitle("Deine Wegpunkte").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { EditButton() }; ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
                .sheet(isPresented: $showSearch) { SearchView() }
        }
    }
}

struct RouteDetailsView: View {
    let route: CalculatedRoute
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack { Metric(label: "Strecke", value: Format.distance(route.distance)); Metric(label: "Anstieg", value: route.provider.hasPrefix("BikeNavi iPhone") ? "–" : "\(Int(route.ascent)) m"); Metric(label: "Abstieg", value: route.provider.hasPrefix("BikeNavi iPhone") ? "–" : "\(Int(route.descent)) m") }
                        .padding(.vertical, 8)
                    ElevationChart(coordinates: route.coordinates).frame(height: 170)
                } header: { Text("Höhenprofil") } footer: { Text("Höhen und Fahrzeit sind Schätzwerte aus den verfügbaren Kartendaten.") }
                Section("Wegbeschaffenheit") {
                    SurfaceLegend()
                    Text("Die Farben zeigen den Untergrund in der Planung. Grau bedeutet: Für diesen Abschnitt fehlen Angaben.")
                        .font(.caption).foregroundStyle(.secondary)
                    if route.surfaces.isEmpty { Text("Keine Angaben verfügbar") }
                    ForEach(Array(route.surfaces.enumerated()), id: \.offset) { _, surface in
                        HStack { Text(surface.name); Spacer(); Text("\(Int(surface.percentage.rounded())) %").monospacedDigit().foregroundStyle(.secondary) }
                    }
                }
                if !route.warnings.isEmpty { Section("Zur Route") { ForEach(route.warnings, id: \.self) { Text($0).font(.subheadline) } } }
                Section { OfflineDownloadView(route: route) }
                Section("Abbiegehinweise") {
                    ForEach(Array(route.maneuvers.enumerated()), id: \.offset) { _, maneuver in
                        Label(maneuver.instruction, systemImage: maneuver.symbol).font(.subheadline)
                    }
                }
            }.navigationTitle("Deine Strecke").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

struct ElevationChart: View {
    let coordinates: [Coordinate]
    private var samples: [(distance: Double, altitude: Double)] {
        var distance = 0.0
        var values: [(Double, Double)] = []
        for (i, c) in coordinates.enumerated() {
            if i > 0 { distance += coordinates[i - 1].distance(to: c) }
            if let altitude = c.altitude { values.append((distance / 1000, altitude)) }
        }
        let stride = max(1, values.count / 350)
        return values.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
    }
    var body: some View {
        let points = samples
        let baseline = (points.map(\.altitude).min() ?? 0) - 15
        if points.isEmpty { Text("Keine Höhendaten verfügbar").foregroundStyle(.secondary) }
        else {
            Chart(Array(points.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("km", point.distance), yStart: .value("Basis", baseline), yEnd: .value("m", point.altitude))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.4), Theme.lime.opacity(0.15)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("km", point.distance), y: .value("m", point.altitude)).foregroundStyle(Theme.accent)
            }.chartYAxisLabel("m").chartXAxisLabel("km").chartYScale(domain: .automatic(includesZero: false))
        }
    }
}
