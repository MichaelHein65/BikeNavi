import SwiftUI

struct RideView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmFinish = false
    @State private var showElevation = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        NavigationStack {
            if let ride = state.activeRide {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: state.progress?.nextManeuver?.symbol ?? "location.north.fill")
                            .font(.system(size: 30, weight: .bold)).frame(width: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            if ride.recordingState == .paused {
                                Text("Deine Pause").font(.headline)
                                Text("Fortsetzen, wenn du bereit bist").font(.subheadline)
                            } else if state.rerouting {
                                Text("Route wird angepasst").font(.headline)
                                Text("Das iPhone sucht einen kurzen Anschluss zur Tour.").font(.subheadline).lineLimit(2)
                            } else if let progress = state.progress {
                                if progress.distanceFromRoute > 35 {
                                    Text("Route verlassen").font(.headline)
                                    Text(state.localRideStatus ?? "\(Format.distance(progress.distanceFromRoute)) entfernt · gespeicherte Tour auf der Karte").font(.subheadline)
                                } else {
                                    Text(progress.nextManeuver == nil ? "Dem Ziel entgegen" : "Abbiegen in \(Format.distance(progress.distanceToManeuver))").font(.headline)
                                    Text(progress.nextManeuver?.instruction ?? "Folge der Route bis zum Ziel").font(.subheadline).lineLimit(3)
                                }
                            } else {
                                Text("Gute Fahrt!").font(.headline)
                                Text("Position auf der Route wird ermittelt").font(.subheadline)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 14).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.forest).foregroundStyle(.white)
                    RouteMap(styleURL: state.mapStyleURL, route: state.ridingRoute, waypoints: ride.waypoints,
                             track: ride.track, follow: ride.recordingState == .recording,
                             followHeading: ride.recordingState == .recording,
                             navigationPosition: state.progress?.snappedPosition ?? state.location.coordinate,
                             navigationHeading: state.location.navigationHeading,
                             colorBySurface: true, topOverlayInset: 40)
                    VStack(spacing: 8) {
                        if let status = state.localRideStatus, state.progress?.distanceFromRoute ?? 0 <= 35 {
                            Text(status).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading, spacing: 6) {
                            rideMetric("Reststrecke", Format.distance(state.progress?.remaining ?? state.ridingRoute?.distance ?? 0))
                            rideMetric("Gefahren", Format.distance(ride.recordedDistance))
                            rideMetric("Tempo", "\(Int((ride.track.last?.speed ?? 0) * 3.6)) km/h")
                            rideMetric("Fahrzeit", Format.duration(ride.movingDuration))
                        }
                        Divider()
                        BikeTelemetryView(compact: true)
                        HStack(spacing: 8) {
                            Button { state.togglePause() } label: {
                                Label(ride.recordingState == .paused ? "Fortsetzen" : "Pause", systemImage: ride.recordingState == .paused ? "play.fill" : "pause.fill")
                                    .font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(Theme.forest, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                            }.buttonStyle(.plain)
                            Button { showElevation = true } label: { controlIcon("chart.xyaxis.line") }
                                .accessibilityLabel("Höhenprofil")
                            Button { state.voice.toggle() } label: { controlIcon(state.voice ? "speaker.wave.2" : "speaker.slash") }
                                .accessibilityLabel(state.voice ? "Sprachausgabe ausschalten" : "Sprachausgabe einschalten")
                            Button { confirmFinish = true } label: { controlIcon("stop.fill") }
                                .accessibilityLabel("Tour beenden")
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 14).padding(.vertical, 8).background(Theme.paper)
                }
                .toolbar(.hidden, for: .navigationBar)
                .confirmationDialog("Tour beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button("Speichern und beenden") { state.finishRide() }
                    Button("Nicht speichern und beenden", role: .destructive) { state.discardRide() }
                    Button("Weiterfahren", role: .cancel) { }
                }
                .sheet(isPresented: $showElevation) { if let route = ride.route { RouteDetailsView(route: route) } }
            } else {
                ScrollView {
                  VStack(spacing: 22) {
                    Image(systemName: "bicycle").font(.system(size: 76, weight: .light)).foregroundStyle(Theme.accent)
                    Text("Bereit für draußen?").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Plane deine Strecke und starte deine Tour.\nDein Weg wird unterwegs gespeichert.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Zur Routenplanung") { state.tab = 0 }.buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white).controlSize(.large)
                    BikeTelemetryView().padding(.top, 12)
                  }.padding(26).frame(maxWidth: .infinity)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
                    .navigationTitle("Fahren")
            }
        }
    }

    private func rideMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded, weight: .bold)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(Theme.ink)
            Text(title).font(.caption).foregroundStyle(Theme.secondaryInk)
        }.accessibilityElement(children: .combine)
    }

    private func controlIcon(_ name: String) -> some View {
        Image(systemName: name).font(.body.weight(.semibold))
            .frame(width: 44, height: 44)
            .foregroundStyle(Theme.accent)
            .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
    }
}
