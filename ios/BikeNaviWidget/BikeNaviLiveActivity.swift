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
            HStack(spacing: 14) {
                Image(systemName: context.state.symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.status).font(.caption).foregroundStyle(.white.opacity(0.7))
                    if context.state.distanceMeters > 0 {
                        Text("In \(RideActivityFormat.distance(context.state.distanceMeters))")
                            .font(.title3.bold()).monospacedDigit()
                    }
                    Text(context.state.instruction).font(.subheadline).lineLimit(2)
                }
                Spacer(minLength: 4)
                if context.state.remainingMeters > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(RideActivityFormat.distance(context.state.remainingMeters)).font(.subheadline.bold()).monospacedDigit()
                        Text("bis Ziel").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(16)
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
                    Text(context.attributes.tourName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
