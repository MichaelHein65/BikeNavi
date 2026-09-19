import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BikeNaviWidgetBundle: WidgetBundle {
    var body: some Widget { BikeNaviRideActivityWidget() }
}

struct BikeNaviRideActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            HStack(spacing: 12) {
                RoutePreviewView(state: context.state)
                    .frame(width: 162, height: 132)
                    .layoutPriority(1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.status).font(.caption).foregroundStyle(.white.opacity(0.7))
                    if context.state.distanceMeters > 0 {
                        Text("In \(RideActivityFormat.distance(context.state.distanceMeters))")
                            .font(.system(size: 27, weight: .heavy, design: .rounded)).monospacedDigit()
                    }
                    Text(context.state.instruction).font(.subheadline.bold()).lineLimit(3)
                    Spacer(minLength: 2)
                    if context.state.remainingMeters > 0 {
                        HStack(spacing: 5) {
                            Image(systemName: "flag.checkered").font(.caption2)
                            Text("\(RideActivityFormat.distance(context.state.remainingMeters)) bis Ziel")
                                .font(.caption.bold()).monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 132, alignment: .leading)
            }
            .padding(12)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.05, green: 0.12, blue: 0.09))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol).font(.title2.bold()).foregroundStyle(.green)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.instruction).font(.subheadline).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.distanceMeters > 0 {
                        Text(RideActivityFormat.distance(context.state.distanceMeters)).font(.headline).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        RoutePreviewView(state: context.state)
                            .frame(width: 152, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.attributes.tourName).font(.caption).lineLimit(1)
                            if context.state.remainingMeters > 0 {
                                Text("Noch \(RideActivityFormat.distance(context.state.remainingMeters))")
                                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.distanceMeters > 0 ? RideActivityFormat.distance(context.state.distanceMeters) : "Bike")
                    .font(.caption2).monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }
}

private struct RoutePreviewView: View {
    let state: RideActivityAttributes.ContentState
    private var points: [RideActivityPoint] { state.routePoints ?? [] }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.065))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1))
                if points.count > 1 {
                    Canvas { context, size in
                        var outline = Path()
                        outline.move(to: position(points[0], in: size))
                        for point in points.dropFirst() { outline.addLine(to: position(point, in: size)) }
                        context.stroke(outline, with: .color(.black.opacity(0.52)),
                                       style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                        for index in 1..<points.count {
                            var segment = Path()
                            segment.move(to: position(points[index - 1], in: size))
                            segment.addLine(to: position(points[index], in: size))
                            let traveled = index <= (state.currentPointIndex ?? 0)
                            context.stroke(segment,
                                           with: .color(surfaceColor(points[index].surface).opacity(traveled ? 0.32 : 1)),
                                           style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
                        }
                    }
                    if let index = state.maneuverPointIndex, points.indices.contains(index) {
                        ZStack {
                            Circle().fill(.white)
                            Circle().stroke(Color.black.opacity(0.18), lineWidth: 1)
                            Image(systemName: state.symbol)
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Color(red: 0.04, green: 0.34, blue: 0.23))
                        }
                        .frame(width: 31, height: 31)
                        .position(position(points[index], in: proxy.size))
                    }
                    if let index = state.currentPointIndex, points.indices.contains(index) {
                        ZStack {
                            Circle().fill(Color(red: 0.05, green: 0.43, blue: 0.29))
                            Circle().stroke(.white, lineWidth: 2.5)
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 16, weight: .black)).foregroundStyle(.white)
                        }
                        .frame(width: 34, height: 34)
                        .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                        .position(position(points[index], in: proxy.size))
                    }
                    Text("ROUTE VORAUS")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.8).foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 7).padding(.vertical, 5)
                } else {
                    Image(systemName: state.symbol)
                        .font(.system(size: 43, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func position(_ point: RideActivityPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(point.x) / 1_000 * size.width,
                y: CGFloat(point.y) / 1_000 * size.height)
    }

    private func surfaceColor(_ code: Int) -> Color {
        switch code {
        case 1, 3, 4: Color(red: 0.08, green: 0.42, blue: 0.76)
        case 5, 14, 18: Color(red: 0.50, green: 0.30, blue: 0.71)
        case 8, 9, 10: Color(red: 0.82, green: 0.56, blue: 0.05)
        case 2, 11, 12, 15, 16, 17: Color(red: 0.67, green: 0.36, blue: 0.20)
        case 6, 7, 13: Color(red: 0.00, green: 0.60, blue: 0.60)
        default: Color(red: 0.62, green: 0.66, blue: 0.69)
        }
    }
}
