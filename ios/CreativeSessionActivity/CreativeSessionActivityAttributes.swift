import ActivityKit
import Foundation

// This struct must exactly match LiveActivitiesAppAttributes in the live_activities pod
// (same module: live_activities, same top-level name)
// The extension links live_activities pod so both use live_activities.LiveActivitiesAppAttributes
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        var appGroupId: String
    }

    var id: UUID = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}

let sharedDefault = UserDefaults(suiteName: "group.com.arnav.align")!
