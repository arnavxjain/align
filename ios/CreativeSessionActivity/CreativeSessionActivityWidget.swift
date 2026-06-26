import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct CreativeSessionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            let title = sharedDefault.string(forKey: context.attributes.prefixedKey("title")) ?? "Creative Session"
            let subtitle = sharedDefault.string(forKey: context.attributes.prefixedKey("subtitle")) ?? ""

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
            }
            .padding()
            .activityBackgroundTint(.black)
        } dynamicIsland: { context in
            let title = sharedDefault.string(forKey: context.attributes.prefixedKey("title")) ?? "Creative Session"
            let subtitle = sharedDefault.string(forKey: context.attributes.prefixedKey("subtitle")) ?? ""

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.75))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    EmptyView()
                }
            } compactLeading: {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white)
            } compactTrailing: {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.75))
            } minimal: {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.white)
            }
        }
    }
}
