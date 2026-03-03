import Foundation
import ActivityKit

struct ModeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var mode: Mode
    }
    
    enum Mode: String, Codable, Hashable {
        case detect = "Detect"
        case sleep = "Sleep"
    }
    
    var initialMode: Mode
}