import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var settings = false
    @State private var library = false
    private let ink = Color(red: 0.15, green: 0.20, blue: 0.22)

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            let veryCompact = geometry.size.height < 640
            let padding: CGFloat = veryCompact ? 12 : compact ? 14 : 20
            let gap: CGFloat = veryCompact ? 8 : compact ? 10 : 14
            let headerHeight: CGFloat = veryCompact ? 48 : compact ? 56 : 66
            let showQuestion = !veryCompact && !(compact && state.activeRide != nil)
            let questionHeight: CGFloat = showQuestion ? 26 : 0
            let resumeHeight: CGFloat = state.activeRide == nil ? 0 : veryCompact ? 44 : compact ? 48 : 56
            let seaHeight: CGFloat = veryCompact ? 76 : compact ? 92 : 112
            let footerHeight: CGFloat = 44
            let sectionCount = 4 + (showQuestion ? 1 : 0) + (state.activeRide == nil ? 0 : 1)
            let fixedHeight = padding * 2 + headerHeight + questionHeight + resumeHeight + seaHeight + footerHeight + gap * CGFloat(sectionCount)
            let tileHeight = max(94, (geometry.size.height - fixedHeight) / 2)

            VStack(alignment: .leading, spacing: gap) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BikeNavi").font(.system(size: compact ? 28 : 34, weight: .heavy, design: .rounded))
                        if !veryCompact {
                            Text("Dein Weg. Dein Abenteuer.").font(.system(size: compact ? 12 : 15, weight: .medium))
                                .foregroundStyle(ink.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.85)
                        }
                    }
                    Spacer()
                    Button { settings = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 20, weight: .semibold))
                            .frame(width: 48, height: 48).background(.white.opacity(0.8), in: Circle())
                    }.accessibilityLabel("Einstellungen").accessibilityIdentifier("homeSettings")
                }.frame(height: headerHeight)
                if showQuestion {
                    Text("Womit geht’s los?").font(.system(size: 22, weight: .bold, design: .rounded))
                        .frame(height: questionHeight).lineLimit(1).minimumScaleFactor(0.85)
                }
                if let ride = state.activeRide {
                    Button { state.resumeApplicationRide() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: ride.profile.mode.symbol).font(.system(size: 22))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fahrt fortsetzen").font(.system(size: 16, weight: .semibold))
                                Text(ride.title).font(.system(size: 12)).lineLimit(1)
                            }
                            Spacer(); Image(systemName: "arrow.right")
                        }.padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: resumeHeight)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20))
                    }.accessibilityIdentifier("homeResumeRide").frame(height: resumeHeight)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap), count: 2), spacing: gap) {
                    ForEach(Array(TravelMode.homeModes.prefix(4)), id: \.self) { mode in
                        tile(mode, height: tileHeight)
                    }
                }.frame(height: tileHeight * 2 + gap)
                tile(.sea, height: seaHeight, wide: true)
                HStack(spacing: 8) {
                    if state.plan.canCalculateRoute || state.plan.isAwaitingStart {
                        Button { state.chooseApplication(state.plan.profile.mode) } label: {
                            Label("Letzte Planung", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity, minHeight: footerHeight)
                        }.accessibilityIdentifier("homeContinuePlan")
                    }
                    Button { library = true } label: {
                        Label("Alle Touren", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity, minHeight: footerHeight)
                    }.accessibilityIdentifier("homeLibrary")
                }.frame(height: footerHeight).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
            }.padding(padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background {
            LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.90), Color(red: 0.98, green: 0.91, blue: 0.86), Color(red: 0.90, green: 0.96, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
        .foregroundStyle(ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $library) { LibraryView() }
    }

    private func tile(_ mode: TravelMode, height: CGFloat, wide: Bool = false) -> some View {
        let subtitle = height >= 152
        let imageHeight = max(30, min(112, height - (subtitle ? 88 : 70)))
        return Button { state.chooseApplication(mode) } label: {
            Group {
                if wide {
                    HStack(spacing: 14) {
                        Image(mode.homeAsset).resizable().scaledToFit()
                            .frame(width: height - 24, height: height - 24)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.homeTitle).font(.system(size: 22, weight: .bold, design: .rounded))
                            if height >= 90 {
                                Text(mode.homeSubtitle).font(.system(size: 13)).foregroundStyle(ink.opacity(0.65)).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.system(size: 17, weight: .semibold))
                    }.padding(12)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(mode.homeAsset).resizable().scaledToFit().frame(height: imageHeight).frame(maxWidth: .infinity)
                        Text(mode.homeTitle).font(.system(size: height < 150 ? 16 : 18, weight: .bold, design: .rounded))
                            .lineLimit(2).minimumScaleFactor(0.85).frame(height: 40, alignment: .leading)
                        if subtitle {
                            Text(mode.homeSubtitle).font(.system(size: 12)).foregroundStyle(ink.opacity(0.65))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
            }.frame(maxWidth: .infinity).frame(height: height)
                .background(tileColor(mode), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.8), lineWidth: 2))
                .shadow(color: tileColor(mode).opacity(0.45), radius: 7, x: 0, y: 5)
                .shadow(color: .white.opacity(0.7), radius: 3, x: -3, y: -3)
        }.buttonStyle(ClayTileButtonStyle())
            .accessibilityLabel(mode.homeTitle)
            .accessibilityHint("Öffnet die passende Routenplanung")
            .accessibilityIdentifier("homeMode_" + mode.rawValue)
    }
    private func tileColor(_ mode: TravelMode) -> Color {
        switch mode {
        case .cycling: Color(red: 0.82, green: 0.94, blue: 0.70)
        case .car: Color(red: 0.74, green: 0.88, blue: 1)
        case .hiking: Color(red: 1, green: 0.83, blue: 0.65)
        case .bikeAndHike: Color(red: 0.89, green: 0.81, blue: 0.98)
        case .sea: Color(red: 0.70, green: 0.91, blue: 0.91)
        }
    }
}

struct ClayTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
