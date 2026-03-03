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
    
    // Track incidents that have already been notified (don't send duplicate notifications)
    private var notifiedIncidents: Set<UUID> = []

    func configure(appState: AppState?) {
        self.appState = appState
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Ask once; iOS remembers the choice.
        // Note: .criticalAlert requires special Apple entitlement - using .timeSensitive instead
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                Log.e("[NotificationManager] Authorization error: \(error)")
            }
            Log.d("[NotificationManager] Authorization granted: \(granted)")
            self.registerCategories()
            
            // Check current settings for debugging
            center.getNotificationSettings { settings in
                Log.d("[NotificationManager] Notification settings:")
                Log.d("  - Authorization status: \(settings.authorizationStatus.rawValue)")
                Log.d("  - Alert setting: \(settings.alertSetting.rawValue)")
                Log.d("  - Sound setting: \(settings.soundSetting.rawValue)")
                Log.d("  - Badge setting: \(settings.badgeSetting.rawValue)")
                Log.d("  - Notification center: \(settings.notificationCenterSetting.rawValue)")
                Log.d("  - Lock screen: \(settings.lockScreenSetting.rawValue)")
            }
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
        
        // Disconnect category
        let disconnected = UNNotificationCategory(
            identifier: "DEVICE_DISCONNECTED",
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([cat, batteryLow, disconnected])
    }
    
    
    // 3) Add this new method anywhere in the class:
    func notifyBatteryLow(percent: Int) {
        let content = UNMutableNotificationContent()
        content.title = "SipBuddy battery low"
        content.body  = "Your device is at \(percent)%. Please charge."
        // Note: .critical and criticalSound require special Apple entitlement
        // Using .timeSensitive which is available without special approval
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        content.sound = .default
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
    
    /// Notify user when device disconnects unexpectedly (not by user action)
    func notifyUnexpectedDisconnect(deviceName: String?) {
        Log.d("[NotificationManager] Sending unexpected disconnect notification")
        
        // Haptic feedback on main thread
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.error)
        }
        
        let content = UNMutableNotificationContent()
        content.title = "SipBuddy Disconnected"
        content.body = deviceName.map { "\($0) lost connection. We'll try to reconnect automatically." } 
            ?? "Your device lost connection. We'll try to reconnect automatically."
        content.sound = .default
        content.categoryIdentifier = "DEVICE_DISCONNECTED"
        
        // High priority - time sensitive
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        
        // Immediate delivery
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        let req = UNNotificationRequest(
            identifier: "SB.disconnect.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                Log.e("[NotificationManager] Failed to send disconnect notification: \(error)")
            } else {
                Log.d("[NotificationManager] Disconnect notification scheduled successfully")
            }
        }
    }
    
    
    
    

    /// Schedules a local notification with an attached GIF/image preview.
    /// Called after 2+ frames have arrived for a more engaging notification.
    func notifyIncidentWithFrames(id: UUID, placeName: String?, frames: [Data]) {
        Log.d("[NotificationManager] notifyIncidentWithFrames called for incident \(id.uuidString) with \(frames.count) frames")
        
        // Prevent duplicate notifications for the same incident
        guard !notifiedIncidents.contains(id) else {
            Log.d("[NotificationManager] Skipping duplicate notification for \(id.uuidString)")
            return
        }
        notifiedIncidents.insert(id)
        
        // Trigger haptic feedback immediately on main thread
        DispatchQueue.main.async {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(.warning)
        }
        
        // Prepare notification content on background thread (GIF encoding is CPU-intensive)
        ThreadingManager.shared.notificationPrep.async { [weak self] in
            guard let self = self else { return }
            
            let content = UNMutableNotificationContent()
            content.title = "Possible tampering detected"
            content.body = placeName.map { "Near \($0). Tap to review." } ?? "Tap to review the incident."
            content.sound = .default
            content.categoryIdentifier = "INCIDENT_DETECTED"
            content.userInfo = ["incidentID": id.uuidString]
            
            // High priority for incident alerts
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }
            
            // Create attachment on background thread
            if let attachment = self.createImageAttachment(from: frames, incidentID: id) {
                content.attachments = [attachment]
                Log.d("[NotificationManager] Created attachment for incident notification")
            }
            
            // Schedule notification (must update badge on main)
            ThreadingManager.onMain {
                content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
                
                // Small delay helps avoid race conditions when transitioning to background.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.3, repeats: false)
                let req = UNNotificationRequest(identifier: "incident-\(id.uuidString)", content: content, trigger: trigger)
                
                Log.d("[NotificationManager] Scheduling incident notification...")
                UNUserNotificationCenter.current().add(req) { error in
                    if let error = error {
                        Log.e("[NotificationManager] Failed to schedule incident notification: \(error)")
                    } else {
                        Log.d("[NotificationManager] Incident notification scheduled successfully for \(id.uuidString)")
                    }
                }
            }
        }
    }
    
    /// Check if an incident has already been notified
    func hasNotified(incident id: UUID) -> Bool {
        notifiedIncidents.contains(id)
    }
    
    /// Clear notification tracking for an incident (e.g., when incident is deleted)
    func clearNotificationTracking(for id: UUID) {
        notifiedIncidents.remove(id)
    }
    
    /// Creates a GIF or image attachment for the notification
    /// NOTE: This should be called from a background thread (CPU-intensive)
    private func createImageAttachment(from frames: [Data], incidentID: UUID) -> UNNotificationAttachment? {
        guard !frames.isEmpty else { return nil }
        
        let token = PerformanceLogger.shared.startTiming("NotificationManager.createImageAttachment (\(frames.count) frames)")
        
        // Convert PNG data to UIImages
        let images = frames.compactMap { UIImage(data: $0) }
        guard !images.isEmpty else {
            PerformanceLogger.shared.endTiming(token)
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        
        // If we have 2+ frames, create a GIF
        if images.count >= 2 {
            let gifToken = PerformanceLogger.shared.startTiming("GIFEncoder.makeGIF (\(images.count) frames)")
            let gifData = GIFEncoder.makeGIF(from: images, fps: 4)
            PerformanceLogger.shared.endTiming(gifToken)
            
            if let gifData = gifData {
                let gifURL = tempDir.appendingPathComponent("incident-\(incidentID.uuidString).gif")
                do {
                    try gifData.write(to: gifURL)
                    let attachment = try UNNotificationAttachment(
                        identifier: "incident-gif-\(incidentID.uuidString)",
                        url: gifURL,
                        options: [UNNotificationAttachmentOptionsTypeHintKey: "public.gif"]
                    )
                    PerformanceLogger.shared.endTiming(token)
                    return attachment
                } catch {
                    Log.e("[NotificationManager] Failed to create GIF attachment: \(error)")
                }
            }
        }
        
        // Fallback: use the first frame as a static image
        if let firstImage = images.first, let jpegData = firstImage.jpegData(compressionQuality: 0.8) {
            let imageURL = tempDir.appendingPathComponent("incident-\(incidentID.uuidString).jpg")
            do {
                try jpegData.write(to: imageURL)
                let attachment = try UNNotificationAttachment(
                    identifier: "incident-image-\(incidentID.uuidString)",
                    url: imageURL,
                    options: nil
                )
                PerformanceLogger.shared.endTiming(token)
                return attachment
            } catch {
                Log.e("[NotificationManager] Failed to create image attachment: \(error)")
            }
        }
        
        PerformanceLogger.shared.endTiming(token)
        return nil
    }

    /// Legacy method - schedules a notification immediately without frames.
    /// Kept for backward compatibility but prefer notifyIncidentWithFrames.
    func notifyIncidentStarted(id: UUID, placeName: String?) {
        // Use the new method with empty frames
        notifyIncidentWithFrames(id: id, placeName: placeName, frames: [])
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
        let categoryId = response.notification.request.content.categoryIdentifier
        let actionId = response.actionIdentifier
        
        // Track notification tap in PostHog
        PostHogService.shared.trackNotificationTapped(
            type: categoryId.isEmpty ? "unknown" : categoryId,
            action: actionId == UNNotificationDefaultActionIdentifier ? "open" : actionId
        )
        
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
