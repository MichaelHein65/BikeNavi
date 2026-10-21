import SwiftUI

enum MapStyle: String, CaseIterable, Identifiable {
    case standard, light, detailed, dark, satellite, topographic, seamap, custom, regional
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Standard · Deutsch"
        case .light: "Hell"
        case .detailed: "Detailreich"
        case .dark: "Dunkel"
        case .satellite: "Satellit"
        case .topographic: "Topografisch"
        case .seamap: "Seekarte · OpenSeaMap"
        case .regional: "Offline-Wegenetz"
        case .custom: "Eigener Kartenstil"
        }
    }
    func url(customURL: String) -> String {
        switch self {
        case .standard: "https://raw.githubusercontent.com/kalwinskidawid/openfreemap-translations/main/styles/liberty_de.json"
        case .light: "https://tiles.openfreemap.org/styles/positron"
        case .detailed: "https://tiles.openfreemap.org/styles/bright"
        case .dark: "https://tiles.openfreemap.org/styles/dark"
        case .satellite, .topographic, .seamap: Bundle.main.url(forResource: rawValue, withExtension: "json")!.absoluteString
        case .regional: customURL
        case .custom: customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct MapStyleMenu: View {
    @EnvironmentObject var state: AppState
    private var mode: TravelMode { state.tab == 1 ? (state.activeRide?.profile.mode ?? state.plan.profile.mode) : state.plan.profile.mode }
    var body: some View {
        Menu {
            Picker("Kartenansicht", selection: $state.selectedMapStyle) {
                ForEach(MapStyle.allCases.filter { ($0 != .regional || state.offlineRegionStyle != nil) && ($0 != .custom || !state.customMapStyleURL.isEmpty) && (mode == .sea || $0 != .seamap) }) { style in
                    Text(style.title).tag(style)
                }
            }
            if mode == .sea {
            Toggle("EMODnet-Wassertiefen", isOn: $state.showWaterDepths).accessibilityIdentifier("mapWaterDepthToggle")
            Text("EMODnet · nicht zur Navigation geeignet")
            if state.showWaterDepths {
                Link("Tiefenlegende (Meter)", destination: URL(string: "https://ows.emodnet-bathymetry.eu/wms?SERVICE=WMS&VERSION=1.1.1&REQUEST=GetLegendGraphic&LAYER=emodnet:mean_multicolour&FORMAT=image/png")!)
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
