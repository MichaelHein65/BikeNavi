import SwiftUI

struct RideView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmFinish = false
    @State private var showElevation = false
    var body: some View {
        NavigationStack {
            if let ride = state.activeRide {
                VStack(spacing: 0) {
                    HStack(spacing: 18) {
                        Image(systemName: state.progress?.nextManeuver?.symbol ?? "location.north.fill")
                            .font(.system(size: 38, weight: .bold)).frame(width: 55)
                        VStack(alignment: .leading, spacing: 5) {
                            if ride.recordingState == .paused {
                                Text("Deine Pause").font(.title2.bold())
                                Text("Fortsetzen, wenn du bereit bist").font(.subheadline)
                            } else if state.rerouting {
                                Text("Route wird angepasst").font(.title2.bold())
                                Text("Ab deinem aktuellen Standort wird eine neue Verbindung berechnet.").font(.subheadline).lineLimit(2)
                            } else if let progress = state.progress {
                                if progress.distanceFromRoute > 60 {
                                    Text("Route verlassen").font(.title2.bold())
                                    Text("\(Format.distance(progress.distanceFromRoute)) entfernt · gespeicherte Route auf der Karte").font(.subheadline)
                                } else {
                                    Text(progress.nextManeuver == nil ? "Dem Ziel entgegen" : "Nächster Abbieger in \(Format.distance(progress.distanceToManeuver))").font(.title2.bold())
                                    Text(progress.nextManeuver?.instruction ?? "Folge der Route bis zum Ziel").font(.subheadline).lineLimit(3)
                                }
                            } else {
                                Text("Gute Fahrt!").font(.title2.bold())
                                Text("Position auf der Route wird ermittelt").font(.subheadline)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.forest).foregroundStyle(.white)
                    RouteMap(styleURL: state.mapStyleURL, route: ride.route, waypoints: ride.waypoints,
                             track: ride.track, follow: ride.recordingState == .recording,
                             followHeading: ride.recordingState == .recording,
                             colorBySurface: true, topOverlayInset: 118)
                    VStack(spacing: 18) {
                        HStack {
                            Metric(label: "Noch vor dir", value: Format.distance(state.progress?.remaining ?? ride.route?.distance ?? 0))
                            Metric(label: "Gefahren", value: Format.distance(ride.recordedDistance))
                            Metric(label: "Tempo", value: "\(Int((ride.track.last?.speed ?? 0) * 3.6)) km/h")
                        }
                        HStack {
                            Label(Format.duration(ride.movingDuration), systemImage: "clock")
                            Spacer()
                            Button { showElevation = true } label: { Label("Höhenprofil", systemImage: "chart.xyaxis.line") }
                            Button { state.voice.toggle() } label: { Image(systemName: state.voice ? "speaker.wave.2" : "speaker.slash") }
                                .accessibilityLabel(state.voice ? "Sprachausgabe ausschalten" : "Sprachausgabe einschalten")
                        }.font(.subheadline)
                        HStack {
                            Button { state.togglePause() } label: {
                                Label(ride.recordingState == .paused ? "Fortsetzen" : "Pause", systemImage: ride.recordingState == .paused ? "play.fill" : "pause.fill")
                                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                            }.buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white)
                            Button { confirmFinish = true } label: { Image(systemName: "stop.fill").padding(10) }
                                .buttonStyle(.bordered).accessibilityLabel("Tour beenden")
                        }
                    }.padding(20).background(Theme.paper)
                }
                .toolbar(.hidden, for: .navigationBar)
                .confirmationDialog("Tour beenden und speichern?", isPresented: $confirmFinish, titleVisibility: .visible) {
                    Button("Tour speichern und beenden") { state.finishRide() }
                }
                .sheet(isPresented: $showElevation) { if let route = ride.route { RouteDetailsView(route: route) } }
            } else {
                VStack(spacing: 22) {
                    Image(systemName: "bicycle").font(.system(size: 76, weight: .light)).foregroundStyle(Theme.accent)
                    Text("Bereit für draußen?").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Plane deine Strecke und starte deine Tour.\nDein Weg wird unterwegs gespeichert.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Zur Routenplanung") { state.tab = 0 }.buttonStyle(.borderedProminent).tint(Theme.forest).foregroundStyle(.white).controlSize(.large)
                }.padding(26).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
            }
        }
    }
}
