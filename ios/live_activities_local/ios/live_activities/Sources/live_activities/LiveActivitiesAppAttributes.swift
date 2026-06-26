import ActivityKit
import Foundation

public struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        public var appGroupId: String
        public init(appGroupId: String) {
            self.appGroupId = appGroupId
        }
    }

    public var id: UUID
    public init(id: UUID = UUID()) {
        self.id = id
    }
}

public extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}
