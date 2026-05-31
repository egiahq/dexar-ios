import ActivityKit
import Foundation

struct DexarAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endDate: Date
        var isWork: Bool
        var loopNumber: Int
        var isOvertime: Bool = false
    }

    var goal: String
    var shortGoal: String
    var totalLoops: Int
}
