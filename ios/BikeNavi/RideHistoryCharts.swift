import SwiftUI
import Charts

struct RecordedElevationChart: View {
    let points: [RideElevationPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gefahrenes Höhenprofil").font(.headline)
            if points.isEmpty {
                Text("Für diese Fahrt wurden keine Höhen aufgezeichnet.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Strecke", point.distanceKM), y: .value("Höhe", point.altitude),
                             series: .value("Abschnitt", point.run))
                        .foregroundStyle(Theme.accent)
                    PointMark(x: .value("Strecke", point.distanceKM), y: .value("Höhe", point.altitude))
                        .symbolSize(5).foregroundStyle(Theme.accent)
                }
                .chartYAxisLabel("m").chartXAxisLabel("km")
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
                .modifier(ScrollableRideChart(domain: 0...max(points.last?.distanceKM ?? 0, 0.001)))
                Text("Aufgezeichnete GPS-Höhen · Lücken und Pausen bleiben ausgespart")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct RidePowerChart: View {
    let points: [RidePowerPoint]
    let distanceKM: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Leistungsverlauf").font(.headline)
            if points.isEmpty {
                Text("Für diese Fahrt sind keine Leistungswerte mit Streckenzuordnung verfügbar.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(points) { point in
                    LineMark(x: .value("Strecke", point.distanceKM), y: .value("Leistung", point.watts),
                             series: .value("Abschnitt", "\(point.source)-\(point.run)"))
                        .foregroundStyle(by: .value("Leistung", point.source))
                    PointMark(x: .value("Strecke", point.distanceKM), y: .value("Leistung", point.watts))
                        .symbolSize(3).foregroundStyle(by: .value("Leistung", point.source))
                }
                .chartForegroundStyleScale(["Fahrer": Color.blue, "Motor": Color.orange])
                .chartYAxisLabel("W").chartXAxisLabel("km")
                .frame(height: 190)
                .modifier(ScrollableRideChart(domain: 0...max(distanceKM, 0.001)))
            }
        }
    }
}

struct RideModeLegend: View {
    let modes: [Int]
    let hasUnknown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fahrmodus auf der Strecke").font(.caption.bold())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { labels }
                VStack(alignment: .leading, spacing: 6) { labels }
            }
        }
    }

    @ViewBuilder private var labels: some View {
        ForEach(modes, id: \.self) { mode in
            Label {
                Text(BikeTelemetryDisplay.modeName(mode))
            } icon: {
                Circle().fill(BikeTelemetryView.modeColor(mode) ?? .gray).frame(width: 9, height: 9)
            }.font(.caption)
        }
        if hasUnknown {
            Label { Text("Ohne Messung") } icon: { Circle().fill(.gray).frame(width: 9, height: 9) }.font(.caption)
        }
    }
}

/// Keeps the native chart's horizontal scrolling and the page's vertical scrolling independent.
private struct ScrollableRideChart: ViewModifier {
    let domain: ClosedRange<Double>
    @State private var zoom = 1.0
    @State private var position = 0.0
    @State private var pinchStart: (zoom: Double, center: Double)?

    private var fullLength: Double { max(domain.upperBound - domain.lowerBound, 0.001) }
    private var visibleLength: Double { fullLength / zoom }

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content
                .chartXScale(domain: domain)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: visibleLength)
                .chartScrollPosition(x: $position)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            if pinchStart == nil {
                                pinchStart = (zoom, clampedPosition + visibleLength / 2)
                            }
                            guard let start = pinchStart else { return }
                            setZoom(start.zoom * value.magnification, center: start.center)
                        }
                        .onEnded { _ in pinchStart = nil }
                )
            HStack(spacing: 14) {
                Button { setZoom(zoom / 2) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(zoom <= 1)
                .accessibilityLabel("Kurve verkleinern")
                Text(zoom, format: .number.precision(.fractionLength(0...1)))
                    .monospacedDigit()
                    .accessibilityLabel("Zoomfaktor")
                Button { setZoom(zoom * 2) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(zoom >= 32)
                .accessibilityLabel("Kurve vergrößern")
                Spacer()
                Button("Gesamt") {
                    zoom = 1
                    position = domain.lowerBound
                }
                .disabled(zoom == 1)
                .accessibilityLabel("Gesamte Kurve anzeigen")
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
            .tint(Theme.forest)
            Text("Mit zwei Fingern zoomen · seitlich wischen zum Verschieben")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of: domain) { _, _ in
            zoom = 1
            position = domain.lowerBound
            pinchStart = nil
        }
    }

    private var clampedPosition: Double {
        min(max(position, domain.lowerBound), max(domain.lowerBound, domain.upperBound - visibleLength))
    }

    private func setZoom(_ value: Double, center: Double? = nil) {
        let anchor = center ?? (clampedPosition + visibleLength / 2)
        zoom = min(max(value, 1), 32)
        position = min(max(anchor - visibleLength / 2, domain.lowerBound),
                       max(domain.lowerBound, domain.upperBound - visibleLength))
    }
}
