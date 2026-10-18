import SwiftUI
import MediaPlayer
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var installedVoices = NavigationVoice.available
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("iPhone-Medienlautstärke")
                        .accessibilityIdentifier("systemVolumeLabel")
                    #if targetEnvironment(simulator)
                    Text("Systemregler nur auf dem iPhone verfügbar")
                        .font(.footnote).foregroundStyle(.secondary)
                    #else
                    SystemVolumeSlider()
                        .frame(height: 44)
                    #endif
                    Button("Kinderreim anhören") { state.previewSystemVolume() }
                        .accessibilityIdentifier("volumePreview")
                    if let status = state.speechStatus {
                        Text(status).font(.footnote)
                            .accessibilityIdentifier("speechStatus")
                    }
                } header: { Text("Lautstärke") } footer: {
                    Text("Dieser Regler und die Lautstärketasten am iPhone steuern die Medienlautstärke. Beim Verstellen hörst du einen kurzen Kinderreim. Bei Auto-Ansagen über die Freisprechanlage die Telefonlautstärke während der Ansage am Auto einstellen.")
                }
                if state.applicationMode == .car {
                    Section {
                        Toggle("Überraschungscharakter", isOn: $state.carCharacterEnabled)
                            .accessibilityIdentifier("carCharacterEnabled")
                        Button("Charakter wechseln") { state.prepareCarCharacter() }
                            .disabled(!state.carCharacterEnabled || state.carCharacterLoading)
                            .accessibilityIdentifier("carCharacterChange")
                        if state.carCharacterLoading { ProgressView() }
                        Text(state.carCharacterStatus).font(.footnote).foregroundStyle(.secondary)
                    } header: { Text("Dein Auto-Beifahrer") } footer: {
                        Text("Bei der Routenplanung wählt der Pi heimlich einen Charakter. Kurze Kommentare begleiten Navigation, Tempo und Umwege. Ausschalten behält sachliche Ansagen und Tempohinweise bei. Die gewählte Navigationsstimme bleibt erhalten.")
                    }
                }
                Section {
                    Picker("Stimme", selection: $state.navigationVoiceID) {
                        Text("Automatisch · Anna bevorzugt").tag("")
                            .accessibilityIdentifier("navigationVoiceAutomatic")
                        ForEach(installedVoices, id: \.identifier) { voice in
                            Text(NavigationVoice.label(voice)).tag(voice.identifier)
                                .accessibilityIdentifier("navigationVoiceChoice_" + voice.identifier)
                        }
                        if !state.navigationVoiceID.isEmpty, !installedVoices.contains(where: { $0.identifier == state.navigationVoiceID }) {
                            Text("Nicht verfügbar · automatische Auswahl").tag(state.navigationVoiceID)
                        }
                    }.pickerStyle(.navigationLink)
                        .accessibilityIdentifier("navigationVoicePicker")
                    if let voice = NavigationVoice.selected(state.navigationVoiceID) {
                        Text("Aktuell: " + NavigationVoice.label(voice)).font(.footnote)
                    }
                    Button("Navigationsstimme anhören") { state.previewSystemVolume(navigation: true) }
                        .disabled(installedVoices.isEmpty)
                        .accessibilityIdentifier("navigationVoicePreview")
                    if installedVoices.isEmpty {
                        Text("Noch keine Premium- oder Siri-Stimme für BikeNavi verfügbar. Bitte Anna oder Petra in Premium laden und hierher zurückkehren.").font(.footnote)
                    }
                    Link("Hochwertige Stimmen auf dem iPhone laden", destination: URL(string: "https://support.apple.com/de-de/guide/iphone/iph96b214f0/ios")!)
                } header: { Text("Navigationsstimme") } footer: {
                    Text("Nur Premium- und verfügbare Siri-Stimmen. Automatisch bevorzugt Anna Premium; Petra lässt sich direkt wählen. Laden: iPhone-Einstellungen → Bedienungshilfen → Lesen & Sprechen → Stimmen → Deutsch. Danach hier auswählen. Siri erscheint nur, wenn iOS die Stimme für Apps bereitstellt.")
                }
                Section {
                    TextField("https://pi5…ts.net:10443", text: $state.serverURL).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("BikeNavi-Zugangsschlüssel", text: $state.token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Speichern und Verbindung prüfen") { Task { await state.saveSettings() } }
                } header: { Text("Dein Pi-Server") } footer: {
                    Text("Verbinde dein iPhone mit Tailscale. Hier gehört BIKENAVI_TOKEN hinein. Der openrouteservice-Schlüssel bleibt auf dem Server.")
                }
                if let notice = state.notice { Section("Status") { Text(notice).font(.subheadline) } }
                if state.applicationMode == .sea {
                BoatSettingsSection(draft: $state.boatDraft, speed: $state.boatSpeedKnots)
                }
                Section {
                    Picker("Kartenansicht", selection: $state.selectedMapStyle) {
                        ForEach(state.applicationMapStyles) { style in Text(style.title).tag(style) }
                    }.accessibilityIdentifier("settingsMapStyle")
                    Text("Passende Grundkarte für " + (state.applicationMode ?? state.plan.profile.mode).homeTitle).font(.footnote).foregroundStyle(.secondary)
                    if state.selectedMapStyle == .custom {
                        TextField("HTTPS-Adresse des Kartenstils", text: $state.customMapStyleURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if state.applicationMode == .sea {
                    Toggle("EMODnet-Wassertiefen", isOn: $state.showWaterDepths).accessibilityIdentifier("waterDepthToggle")
                    Text("Nicht zur Navigation geeignet · grobe Tiefenübersicht für verfügbare Meeresgebiete").font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("Eigener Kartenserver für Offline-Pakete", isOn: $state.offlineMapsAllowed)
                } header: { Text("Karten") } footer: {
                    if state.applicationMode == .sea { Text("Seekarte zeigt OpenSeaMap-Seezeichen und öffnet die maritime Fahrtansicht ohne Fahrradverbindung. Das Profil Seeweg berechnet Wasserwege über den Pi und bevorzugt erfasste Seewege. EMODnet-Rastertiefen werden bei der Planung berücksichtigt; Wasserstand und Hindernisse werden nicht geprüft. Öffentliche Kartenansichten benötigen Internet. Offline-Downloads sind nur mit eigenem Kartenstil und Kartenserver verfügbar.") }
                    else { Text("Öffentliche Kartenansichten benötigen Internet. Für vollständige Offline-Pakete einen eigenen Kartenstil und Kartenserver einrichten.") }
                }
                if state.applicationMode?.supportsBike == true { Section("Dein Bike") {
                    NavigationLink { BikeBluetoothTestView() } label: {
                        Label("Bosch Kiox 500 · Verbindung testen", systemImage: "bicycle")
                    }
                } }
                Section("Deine Daten") {
                    LabeledContent("Lokal gespeicherte Touren", value: "\(state.records.filter { !$0.deleted }.count)")
                    LabeledContent("Abgleich ausstehend", value: "\(state.records.filter(\.dirty).count)")
                    Text("Planungen und Aufzeichnungen werden zuerst auf diesem iPhone gespeichert und anschließend mit deinem Pi abgeglichen.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Kartengrundlagen") {
                    Link("© OpenStreetMap-Mitwirkende · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("OpenFreeMap / OpenMapTiles", destination: URL(string: "https://openfreemap.org")!)
                    Link("Satellitenbilder: Esri World Imagery", destination: URL(string: "https://www.arcgis.com/home/item.html?id=10df2279f9684e4a9f6a7f08febac2a9")!)
                    Link("Topografisch: OpenTopoMap · CC-BY-SA", destination: URL(string: "https://opentopomap.org/about")!)
                    Link("Tiefen: EMODnet · CC BY 4.0", destination: URL(string: "https://emodnet.ec.europa.eu/en/bathymetry")!)
                    Link("Seekarte: OpenSeaMap", destination: URL(string: "https://www.openseamap.org")!)
                    Link("Deutsche Kartenbeschriftungen", destination: URL(string: "https://github.com/kalwinskidawid/openfreemap-translations")!)
                    Link("Auto-Routing und Verkehr: TomTom", destination: URL(string: "https://www.tomtom.com/")!)
                    Link("Routing: openrouteservice / HeiGIT", destination: URL(string: "https://openrouteservice.org")!)
                    LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"))")
                }
            }.navigationTitle("Einstellungen")
                .onAppear { refreshVoices(); state.observeSystemVolume() }
                .onDisappear { state.stopObservingSystemVolume() }
                .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
                    refreshVoices()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { refreshVoices(); state.observeSystemVolume() }
                    else { state.stopObservingSystemVolume() }
                }
        }
    }

    private func refreshVoices() {
        installedVoices = NavigationVoice.available
        if !state.navigationVoiceID.isEmpty, !installedVoices.contains(where: { $0.identifier == state.navigationVoiceID }) {
            state.navigationVoiceID = ""
        }
    }
}


/// Apple's control changes the actual output volume and follows the hardware buttons.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.accessibilityIdentifier = "systemVolume"
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Keep incomplete decimal input local; only finished, valid numbers reach AppState.
struct BoatSettingsSection: View {
    @Binding var draft: Double
    @Binding var speed: Double
    var profile = false
    @State private var draftText = ""
    @State private var speedText = ""
    @FocusState private var field: Field?
    private enum Field: Hashable { case draft, speed }

    private var parsedDraft: Double? { MarineNavigation.settingInput(draftText, range: 0.1...20) }
    private var parsedSpeed: Double? { MarineNavigation.settingInput(speedText, range: 0.5...50) }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tiefgang (m)").font(.subheadline)
                TextField("Meter", text: $draftText)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .focused($field, equals: .draft).accessibilityLabel("Tiefgang in Metern")
                    .accessibilityIdentifier(profile ? "profileBoatDraft" : "boatDraft")
            }
            if parsedDraft == nil {
                Text("Bitte einen Tiefgang von 0,1 bis 20 m eingeben.")
                    .font(.footnote).foregroundStyle(.red).accessibilityIdentifier("boatDraftError")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Durchschnittstempo (kn)").font(.subheadline)
                TextField("Knoten", text: $speedText)
                    .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                    .focused($field, equals: .speed).accessibilityLabel("Durchschnittstempo in Knoten")
                    .accessibilityIdentifier(profile ? "profileBoatSpeed" : "boatSpeedKnots")
            }
            if parsedSpeed == nil {
                Text("Bitte ein Tempo von 0,5 bis 50 kn eingeben.")
                    .font(.footnote).foregroundStyle(.red)
            }
            Button("Bootswerte speichern") { save(); field = nil }
                .disabled(parsedDraft == nil || parsedSpeed == nil)
                .accessibilityIdentifier("saveBoatSettings")
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if field != nil {
                            Spacer()
                            Button("Fertig") { save(); field = nil }.accessibilityIdentifier("finishBoatEditing")
                        }
                    }
                }
        } header: { Text("Dein Boot") } footer: {
            Text("Bleibt auf diesem iPhone gespeichert. Komma oder Punkt sind möglich. Der tatsächliche Tiefgang gilt für neue Seewegplanungen; das Tempo für Fahrzeit und ETA. EMODnet-Rasterdaten sind keine Navigationsfreigabe. Standard: 2 m und 4 kn.")
        }
        .onAppear {
            draftText = formatted(draft)
            speedText = formatted(speed)
        }
        .onChange(of: field) { old, _ in
            if old == .draft, let value = parsedDraft { draft = value }
            if old == .speed, let value = parsedSpeed { speed = value }
        }
        .onDisappear { save() }
    }

    private func save() {
        if let value = parsedDraft { draft = value }
        if let value = parsedSpeed { speed = value }
    }
    private func formatted(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(1...6)))
    }
}
