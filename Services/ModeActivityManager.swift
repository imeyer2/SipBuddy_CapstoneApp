import ActivityKit
import Foundation

class ModeActivityManager {
    static let shared = ModeActivityManager()
    private var activity: Activity<ModeActivityAttributes>?
    
    private init() {}
    
    func startActivity(mode: ModeActivityAttributes.Mode) {
        let attributes = ModeActivityAttributes(initialMode: mode)
        let contentState = ModeActivityAttributes.ContentState(mode: mode)
        do {
            activity = try Activity<ModeActivityAttributes>.request(attributes: attributes, contentState: contentState, pushType: nil)
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    func updateActivity(mode: ModeActivityAttributes.Mode) {
        guard let activity = activity else { return }
        let contentState = ModeActivityAttributes.ContentState(mode: mode)
        Task {
            await activity.update(using: contentState)
        }
    }
    
    func endActivity() {
        guard let activity = activity else { return }
        Task {
            await activity.end(dismissalPolicy: .immediate)
        }
        self.activity = nil
    }
}