import SwiftUI

enum MapStyle: String, CaseIterable, Identifiable {
    case standard, light, detailed, dark, satellite, topographic, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Standard · Deutsch"
        case .light: "Hell"
        case .detailed: "Detailreich"
        case .dark: "Dunkel"
        case .satellite: "Satellit"
        case .topographic: "Topografisch"
        case .custom: "Eigener Kartenstil"
        }
    }
    func url(customURL: String) -> String {
        switch self {
        case .standard: "https://raw.githubusercontent.com/kalwinskidawid/openfreemap-translations/main/styles/liberty_de.json"
        case .light: "https://tiles.openfreemap.org/styles/positron"
        case .detailed: "https://tiles.openfreemap.org/styles/bright"
        case .dark: "https://tiles.openfreemap.org/styles/dark"
        case .satellite, .topographic: Bundle.main.url(forResource: rawValue, withExtension: "json")!.absoluteString
        case .custom: customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct MapStyleMenu: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Menu {
            Picker("Kartenansicht", selection: $state.selectedMapStyle) {
                ForEach(MapStyle.allCases.filter { $0 != .custom || !state.customMapStyleURL.isEmpty }) { style in
                    Text(style.title).tag(style)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d").font(.title3).frame(width: 44, height: 44)
        }
        .accessibilityLabel("Kartenansicht")
        .accessibilityValue(state.selectedMapStyle.title)
        .accessibilityIdentifier("mapStyleMenu")
    }
}
