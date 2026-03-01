//
//  NotificationManager.swift
//  SipBuddy
//
//


import Foundation
import UserNotifications
import UIKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    weak var appState: AppState?

    func configure(appState: AppState?) {
        self.appState = appState
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Ask once; iOS remembers the choice.
        center.requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert]) { _, _ in
            self.registerCategories()
        }

    }

    
    
    private func registerCategories() {
        let open = UNNotificationAction(
            identifier: "OPEN_INCIDENTS",
            title: "Open Incidents",
            options: [.foreground]
        )
        let cat = UNNotificationCategory(
            identifier: "INCIDENT_DETECTED",
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        
        // New: battery low category (no actions needed, but you can add “Open App” if you like)
        let batteryLow = UNNotificationCategory(
            identifier: "BATTERY_LOW",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([cat])
    }
    
    
    // 3) Add this new method anywhere in the class:
    func notifyBatteryLow(percent: Int) {
        let content = UNMutableNotificationContent()
        content.title = "SipBuddy battery low"
        content.body  = "Your device is at \(percent)%. Please charge."
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .critical   // requires entitlement
        }
        if #available(iOS 12.0, *) {
            content.sound = .defaultCriticalSound(withAudioVolume: 1.0) // requires entitlement
        } else {
            content.sound = .default
        }
        content.categoryIdentifier = "BATTERY_LOW"
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let req = UNNotificationRequest(
            identifier: "SB.battery.low.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
    
    
    
    

    /// Schedules a local notification immediately.
    func notifyIncidentStarted(id: UUID, placeName: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Possible tampering detected"
        content.body = placeName.map { "Near \($0). Tap to review." } ?? "Tap to review the incident."
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        content.categoryIdentifier = "INCIDENT_DETECTED"
        content.userInfo = ["incidentID": id.uuidString]

        // 0.5s delay helps avoid race conditions when transitioning to background.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let req = UNNotificationRequest(identifier: "incident-\(id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // Show banner even if the app is foregrounded (optional; remove if you prefer only the in-app toast)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list, .sound])
    }

    // Tapping the notification jumps to Incidents.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.appState?.tab = .incidents
            NotificationCenter.default.post(name: .openIncidentsTab, object: nil)
        }
        completion()
    }
}



// Required for Buddy System
// Notification.Name is originally from the "Foundation" iOS package
// but we are adding new Notifications
extension Notification.Name {
    static let openIncidentsTab : Notification.Name = Notification.Name("SB.openIncidentsTab")
    static let incidentCompleted : Notification.Name = Notification.Name("SB.incidentCompleted")
}

