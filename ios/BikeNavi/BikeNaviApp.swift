import SwiftUI

@main
struct BikeNaviApp: App {
    private let storeResult: Result<LocalStore, Error>
    init() {
        storeResult = Result {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return try LocalStore(url: directory.appendingPathComponent("BikeNavi/tours.sqlite"))
        }
    }
    var body: some Scene {
        WindowGroup {
            switch storeResult {
            case .success(let store): AppRoot(store: store)
            case .failure(let error):
                ContentUnavailableView("Speicher nicht verfügbar", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(error.localizedDescription))
            }
        }
    }
}

struct AppRoot: View {
    @StateObject private var state: AppState
    @Environment(\.scenePhase) private var phase
    init(store: LocalStore) { _state = StateObject(wrappedValue: AppState(store: store)) }
    var body: some View {
        TabView(selection: $state.tab) {
            PlannerView().tabItem { Label("Planen", systemImage: "map") }.tag(0)
            RideView().tabItem { Label("Fahren", systemImage: "location.north.line") }.tag(1)
            LibraryView().tabItem { Label("Touren", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.tag(2)
            SettingsView().tabItem { Label("Einstellungen", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .environmentObject(state)
        .tint(Theme.accent)
        .alert("BikeNavi", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("Verstanden", role: .cancel) { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
        .task { await state.sync() }
        .onChange(of: phase) { _, value in if value == .active { Task { await state.sync() } } }
        .onChange(of: state.tab) { _, tab in
            if tab == 1 { state.openRide() }
        }
    }
}

enum Theme {
    // Keep map lines and filled action buttons dark against their light content.
    static let forest = Color(red: 0.10, green: 0.35, blue: 0.27)
    static let ink = adaptive(light: (0.09, 0.18, 0.16), dark: (0.94, 0.97, 0.94))
    static let secondaryInk = adaptive(light: (0.32, 0.40, 0.36), dark: (0.70, 0.76, 0.72))
    static let paper = adaptive(light: (0.96, 0.97, 0.93), dark: (0.08, 0.12, 0.10))
    static let accent = adaptive(light: (0.10, 0.35, 0.27), dark: (0.56, 0.86, 0.69))
    static let lime = Color(red: 0.82, green: 0.94, blue: 0.42)

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

struct Metric: View {
    var label: String
    var value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(label).font(.caption).foregroundStyle(Theme.secondaryInk)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
