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
            case .success(let store):
                #if DEBUG
                if ProcessInfo.processInfo.environment["BIKENAVI_LOCAL_ROUTING_CHECK"] == "1" {
                    LocalRoutingDiagnostics()
                } else { AppRoot(store: store) }
                #else
                AppRoot(store: store)
                #endif
            case .failure(let error):
                ContentUnavailableView("Speicher nicht verfügbar", systemImage: "externaldrive.badge.exclamationmark",
                                       description: Text(error.localizedDescription))
            }
        }
    }
}

struct AppRoot: View {
    @StateObject private var state: AppState
    @StateObject private var bike = BikeBluetoothService()
    #if DEBUG
    @State private var showBikeTest = ProcessInfo.processInfo.environment["BIKENAVI_BIKE_TEST"] == "1"
    #endif
    @Environment(\.scenePhase) private var phase
    init(store: LocalStore) { _state = StateObject(wrappedValue: AppState(store: store)) }
    var body: some View {
        Group {
          if let mode = state.applicationMode {
            VStack(spacing: 0) {
                HStack {
                    Button { state.returnToHome() } label: { Label("Start", systemImage: "house.fill") }
                        .accessibilityIdentifier("returnHome")
                    Spacer()
                    Label(mode.homeTitle, systemImage: mode.symbol).font(.subheadline.bold())
                        .accessibilityIdentifier("applicationTitle")
                }.font(.subheadline.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Theme.paper)
                TabView(selection: $state.tab) {
            PlannerView().tabItem { Label("Planen", systemImage: "map") }.tag(0)
            RideView().tabItem { Label(mode == .hiking ? "Gehen" : mode == .sea ? "Segeln" : "Fahren", systemImage: mode.symbol) }.tag(1)
            LibraryView().tabItem { Label("Touren", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.tag(2)
            SettingsView().tabItem { Label("Einstellungen", systemImage: "slider.horizontal.3") }.tag(3)
                }
            }
          } else { HomeView() }
        }
        .environmentObject(state)
        .environmentObject(bike)
        #if DEBUG
        .sheet(isPresented: $showBikeTest) { NavigationStack { BikeBluetoothTestView() }.environmentObject(bike) }
        #endif
        .tint(Theme.accent)
        .onOpenURL { url in Task { await state.readGPX(url) } }
        .sheet(item: $state.gpxImport) { file in GPXImportView(file: file).environmentObject(state) }
        .alert("BikeNavi", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("Verstanden", role: .cancel) { state.errorMessage = nil }
        } message: { Text(state.errorMessage ?? "") }
        .task {
            state.restoreLocalRouting()
            bike.onMeasurement = { [weak state] measurement in state?.recordBikeMeasurement(measurement) }
            while !Task.isCancelled {
                await state.sync()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
        .onAppear { state.updateScreenAwake(sceneActive: phase == .active) }
        .onChange(of: state.workspaceSupportsBike, initial: true) { _, _ in updateBikeMonitoring() }
        .onChange(of: state.applicationMode) { _, _ in updateBikeMonitoring() }
        .onChange(of: phase) { _, value in
            state.updateScreenAwake(sceneActive: value == .active)
            if value == .active { state.becameActive(); Task { await state.sync() } }
            else { state.cancelRideStart() }
        }
        .onChange(of: state.tab, initial: true) { _, tab in
            state.cancelRideStart()
            updateBikeMonitoring()
            if tab == 1 && state.applicationMode != nil { state.openRide() }
        }
        .onChange(of: state.activeRide?.id, initial: true) { _, id in
            updateBikeMonitoring()
        }
    }
    private func updateBikeMonitoring() {
        let inBikeWorkspace = state.applicationMode?.supportsBike == true
        let bikeRide = state.activeRideSupportsBike
        bike.setSuspended(!inBikeWorkspace && !bikeRide)
        bike.monitor(state.tab == 1 && inBikeWorkspace && !state.hasConflictingApplicationRide, for: .rideScreen)
        bike.monitor(bikeRide, for: .activeRide)
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
