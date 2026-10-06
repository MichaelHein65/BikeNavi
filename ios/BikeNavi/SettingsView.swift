import SwiftUI
import MediaPlayer

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.scenePhase) private var scenePhase
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
                } header: { Text("Lautstärke") } footer: {
                    Text("Dieser Regler und die Lautstärketasten am iPhone steuern dieselbe Medienlautstärke. Beim Verstellen hörst du einen kurzen Kinderreim. Die Lautstärke gilt auch für Navigationsansagen.")
                }
                Section {
                    TextField("https://pi5…ts.net:10443", text: $state.serverURL).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("BikeNavi-Zugangsschlüssel", text: $state.token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Speichern und Verbindung prüfen") { Task { await state.saveSettings() } }
                } header: { Text("Dein Pi-Server") } footer: {
                    Text("Verbinde dein iPhone mit Tailscale. Hier gehört BIKENAVI_TOKEN hinein. Der openrouteservice-Schlüssel bleibt auf dem Server.")
                }
                if let notice = state.notice { Section("Status") { Text(notice).font(.subheadline) } }
                Section {
                    Picker("Kartenansicht", selection: $state.selectedMapStyle) {
                        ForEach(MapStyle.allCases) { style in Text(style.title).tag(style) }
                    }.accessibilityIdentifier("settingsMapStyle")
                    Text("Beim App-Start immer Standard · Deutsch").font(.footnote).foregroundStyle(.secondary)
                    if state.selectedMapStyle == .custom {
                        TextField("HTTPS-Adresse des Kartenstils", text: $state.customMapStyleURL)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Toggle("Eigener Kartenserver für Offline-Pakete", isOn: $state.offlineMapsAllowed)
                } header: { Text("Karten") } footer: {
                    Text("Die Auswahl gilt bis zum nächsten App-Start für alle Karten. Satellit zeigt Luftbilder ohne Ortsbeschriftungen; Topografisch zeigt Gelände und Höhenlinien. Öffentliche Karten sind Online-Ansichten. Offline-Downloads sind nur mit eigenem Kartenstil und Kartenserver verfügbar.")
                }
                Section("Dein Bike") {
                    NavigationLink { BikeBluetoothTestView() } label: {
                        Label("Bosch Kiox 500 · Verbindung testen", systemImage: "bicycle")
                    }
                }
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
                    Link("Deutsche Kartenbeschriftungen", destination: URL(string: "https://github.com/kalwinskidawid/openfreemap-translations")!)
                    Link("Routing: openrouteservice / HeiGIT", destination: URL(string: "https://openrouteservice.org")!)
                    LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"))")
                }
            }.navigationTitle("Einstellungen")
                .onAppear { state.observeSystemVolume() }
                .onDisappear { state.stopObservingSystemVolume() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { state.observeSystemVolume() }
                    else { state.stopObservingSystemVolume() }
                }
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
