import SwiftUI

struct POIView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    var duringRide = false
    @State private var selected: POICategory?
    @State private var origin = "location"
    @State private var radius = 10
    @State private var result: POISearchResult?
    @State private var error: String?
    @State private var loading = false
    @State private var adding = false
    @State private var detail: POIPlace?
    @State private var savedCandidate: Waypoint?
    @State private var searchTask: Task<Void, Never>?
    @State private var searchID = UUID()
    private let ink = Color(red: 0.15, green: 0.20, blue: 0.22)
    private var mode: TravelMode { duringRide ? state.activeRide?.profile.mode ?? state.plan.profile.mode : state.plan.profile.mode }
    private var usesCarRoutes: Bool { mode == .car }
    private var alongRoute: Bool { usesCarRoutes && duringRide && state.ridingRoute != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let selected {
                        resultHeader(selected)
                        if loading { ProgressView(usesCarRoutes ? "Orte und Pkw-Anfahrt prüfen …" : "Orte in deiner Nähe suchen …").frame(maxWidth: .infinity).padding() }
                        if let error { Label(error, systemImage: "exclamationmark.triangle").font(.subheadline).accessibilityIdentifier("poiError") }
                        if let result {
                            Text(result.scope).font(.subheadline.bold())
                            ForEach(result.items) { place in resultCard(place, category: selected) }
                            if !result.unpriced.isEmpty {
                                Text("Ohne bestätigten Dieselpreis").font(.headline)
                                ForEach(result.unpriced) { place in resultCard(place, category: selected) }
                            }
                            ForEach(result.notices, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                            if usesCarRoutes {
                                Text("Fahrzeiten geschätzt · ohne Live-Verkehr · Aufenthalt nicht enthalten")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        if mode == .cycling || mode == .hiking || mode == .bikeAndHike {
                            offlinePlacesLink
                        }
                        Text("Was brauchst du unterwegs?")
                            .font(.system(.title, design: .rounded, weight: .heavy))
                        Text(alongRoute ? "Entlang deiner Route" : mode == .sea ? "Orte für deinen Landgang entdecken." : "Entdecke passende Orte in deiner Nähe.")
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(POICategory.allCases) { category in
                                Button { selected = category; search() } label: { tile(category) }
                                    .buttonStyle(ClayTileButtonStyle()).accessibilityIdentifier("poiCategory_" + category.rawValue)
                            }
                        }
                        Text("Diesel · Deutschland, Österreich, Slowenien & Kroatien")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }
            .background(LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.91), Color(red: 0.92, green: 0.96, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .foregroundStyle(ink)
            .navigationTitle(selected?.title ?? "Orte entdecken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selected != nil {
                        Button("Kategorien", systemImage: "chevron.left") { cancelSearch(); selected = nil; result = nil; error = nil }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } }
            }
            .sheet(item: $detail) { place in details(place) }
            .onAppear {
                if state.location.freshCoordinate == nil, state.plan.startPoint != nil, !duringRide { origin = "start" }
                state.location.request()
            }
            .onDisappear { cancelSearch() }
        }.preferredColorScheme(.light)
    }

    private var offlinePlacesLink: some View {
        NavigationLink(destination: OfflineRegionsView(center: state.location.coordinate ?? state.plan.startPoint?.coordinate)) {
            Label("Offline-Orte und Regionen", systemImage: "map")
        }.accessibilityIdentifier("offlinePlaces")
    }

    private func color(_ category: POICategory) -> Color {
        switch category {
        case .fuel: Color(red: 1, green: 0.83, blue: 0.65)
        case .supermarket: Color(red: 0.82, green: 0.94, blue: 0.70)
        case .airport: Color(red: 0.74, green: 0.88, blue: 1)
        case .station: Color(red: 0.89, green: 0.81, blue: 0.98)
        case .beach: Color(red: 0.99, green: 0.89, blue: 0.68)
        case .parking: Color(red: 0.70, green: 0.91, blue: 0.91)
        }
    }

    private func tile(_ category: POICategory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image("POI_" + category.rawValue).resizable().scaledToFit()
                .frame(height: 110).frame(maxWidth: .infinity).accessibilityHidden(true)
            Text(category.title).font(.system(.headline, design: .rounded, weight: .bold))
            Text(category.subtitle).font(.caption).foregroundStyle(ink.opacity(0.65))
        }.frame(maxWidth: .infinity, minHeight: 166, alignment: .leading).padding(12)
            .background(color(category), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.85), lineWidth: 2))
            .shadow(color: color(category).opacity(0.45), radius: 7, x: 0, y: 5)
            .shadow(color: .white.opacity(0.7), radius: 3, x: -3, y: -3)
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func resultHeader(_ category: POICategory) -> some View {
        if !duringRide {
            Picker("Suchort", selection: $origin) {
                Text("Standort").tag("location")
                if state.plan.startPoint != nil { Text("Start").tag("start") }
                if state.plan.destinationPoint != nil { Text("Ziel").tag("destination") }
            }.pickerStyle(.segmented).onChange(of: origin) { _, _ in search() }
        }
        if !alongRoute {
            Picker("Umkreis", selection: $radius) { Text("10 km").tag(10); Text("25 km").tag(25) }
                .pickerStyle(.segmented).onChange(of: radius) { _, _ in search() }
        }
        HStack {
            Label(category == .fuel ? "Diesel · bis zu drei Angebote" : "Passende Orte", systemImage: category.symbol).font(.headline)
            Spacer()
            Button { search() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                .accessibilityLabel("Orte aktualisieren")
        }
        Text(usesCarRoutes ? "Fahrzeiten geschätzt · ohne Live-Verkehr" : "Luftlinie · Wege und Erreichbarkeit noch nicht geprüft")
            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("poiDistanceHint")
    }

    private func resultCard(_ place: POIPlace, category: POICategory) -> some View {
        Button { detail = place } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(place.name).font(.headline)
                    Spacer()
                    Text(place.country).font(.caption.bold())
                }
                if category == .fuel {
                    Text(place.priceLabel).font(.system(.title2, design: .rounded, weight: .heavy))
                    Text("Preisstand unbekannt · Abruf " + Date(timeIntervalSince1970: place.fetchedAt).formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if usesCarRoutes {
                    Text("\(Format.distance(place.drivingDistance)) · \(Format.duration(place.drivingSeconds)) Anfahrt")
                        .font(.subheadline)
                    if let extra = place.detourSeconds { Text("+\(Int(ceil(extra / 60))) min Umweg").font(.subheadline.bold()) }
                } else if let distance = place.airDistance {
                    Text("\(Format.distance(distance)) Luftlinie").font(.subheadline)
                }
                Text(place.isOpen == true ? "Laut Quelle geöffnet" : "Öffnungsstatus unbekannt").font(.caption)
                HStack { Text("Karte & Details"); Spacer(); Image(systemName: "arrow.up.right") }.font(.subheadline.bold())
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 22))
        }.buttonStyle(.plain).accessibilityIdentifier("poiResult_" + place.id)
    }

    private func details(_ place: POIPlace) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RouteMap(styleURL: state.mapStyleURL, route: nil, waypoints: [place.waypoint], focus: place.coordinate, pointOverviewZoom: 14, hasStart: false)
                        .frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 20))
                    Text(place.name).font(.title2.bold())
                    Text(place.address)
                    if selected == .fuel { Text("Diesel · " + place.priceLabel).font(.title3.bold()) }
                    if let hours = place.openingHours, !hours.isEmpty { Text("Öffnungszeiten laut Quelle: " + hours).font(.footnote) }
                    Text("Abgerufen: " + Date(timeIntervalSince1970: place.fetchedAt).formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                    if selected == .fuel { Text("Zeitpunkt der Preismeldung unbekannt. Preis vor Ort prüfen.").font(.footnote) }
                    if let url = URL(string: place.sourceURL), url.scheme == "https" { Link(place.source, destination: url).font(.footnote) }
                    if usesCarRoutes && (selected == .beach || selected == .airport || selected == .station) {
                        Text("Anfahrt zum erreichbaren Straßenpunkt. Zugang, Terminal und eventuellen Fußweg vor Ort prüfen.").font(.footnote)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
                    if mode == .sea {
                        Text("Ort an Land: für den Landgang speichern. Keine bestätigte Anlegestelle oder Bootstankstelle; die Wasserroute bleibt unverändert.")
                            .font(.footnote).accessibilityIdentifier("poiLandWarning")
                    } else if duringRide && !usesCarRoutes {
                        Text("Speichere den Ort für deine weitere Planung. Die laufende Tour und Aufzeichnung bleiben unverändert.")
                            .font(.footnote)
                    }
                    Button("Ort speichern", systemImage: "bookmark") { savedCandidate = place.waypoint }
                        .buttonStyle(.bordered).disabled(adding).accessibilityIdentifier("poiSavePlace")
                    if duringRide && usesCarRoutes {
                        Button(adding ? "Anfahrt erneut prüfen …" : state.ridingRoute == nil ? "Dorthin fahren" : "Als nächsten Stopp einfügen") { addToRide(place) }
                            .buttonStyle(.borderedProminent).disabled(adding).accessibilityIdentifier("poiAddToRide")
                    } else if !duringRide && mode != .sea {
                        Button("Als Ziel verwenden") { state.addPoint(place.waypoint, role: .destination); detail = nil; dismiss() }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("poiSetDestination")
                        if state.plan.destinationPoint != nil {
                            Button("Als Zwischenstopp einfügen") { state.addPlaceToTour(place.waypoint); detail = nil; dismiss() }
                                .buttonStyle(.bordered).accessibilityIdentifier("poiAddToPlan")
                        }
                    }
                }.padding(20)
            }.navigationTitle("Ort ansehen").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Zurück") { detail = nil }.disabled(adding) } }
        }.interactiveDismissDisabled(adding)
            .sheet(item: $savedCandidate) { SavedPlaceEditor(candidate: $0) }
    }

    private func cancelSearch() {
        searchID = UUID(); searchTask?.cancel(); searchTask = nil; loading = false
    }

    private func search() {
        cancelSearch(); result = nil; error = nil
        guard let selected else { return }
        let identifier = searchID
        loading = true
        searchTask = Task { @MainActor in
            defer { if searchID == identifier { loading = false } }
            do {
                let request = try await state.preparedPOISearch(category: selected, duringRide: duringRide, origin: origin, radius: radius)
                guard let api = state.api else { throw APIError(status: 0, message: "Für die Ortesuche bitte den Pi in den Einstellungen verbinden.") }
                let response = try await api.searchPOIs(request)
                try Task.checkCancellation()
                guard searchID == identifier else { return }
                result = response
            } catch {
                if !Task.isCancelled, searchID == identifier { self.error = error.localizedDescription }
            }
        }
    }

    private func addToRide(_ place: POIPlace) {
        adding = true; error = nil
        Task { @MainActor in
            defer { adding = false }
            do {
                try await state.addPOIToRide(place.waypoint)
                detail = nil; dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
