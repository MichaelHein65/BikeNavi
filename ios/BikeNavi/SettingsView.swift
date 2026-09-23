import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "bicycle").font(.largeTitle).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading) { Text("BikeNavi").font(.title2.bold()); Text("Deine Tour. Deine Wege. Deine Daten.").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 12)
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
                    TextField("HTTPS-Adresse des Kartenstils", text: $state.mapStyleURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Eigener Kartenserver für Offline-Pakete", isOn: $state.offlineMapsAllowed)
                } header: { Text("Karten") } footer: {
                    Text("Zum Einstieg werden Online-Karten von OpenFreeMap verwendet. Offline-Downloads erst aktivieren, wenn unser eigener Kartenserver samt Stil und Ressourcen bereitsteht.")
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
                    Link("Deutsche Kartenbeschriftungen", destination: URL(string: "https://github.com/kalwinskidawid/openfreemap-translations")!)
                    Link("Routing: openrouteservice / HeiGIT", destination: URL(string: "https://openrouteservice.org")!)
                    LabeledContent("Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"))")
                }
            }.navigationTitle("Einstellungen")
        }
    }
}
