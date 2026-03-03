//
//  PostHogService.swift
//  SipBuddy
//
//  PostHog Analytics Integration
//  Replaces custom telemetry with PostHog while keeping blob storage for media
//

import Foundation
import PostHog
import CoreLocation
import UIKit

// MARK: - PostHog Configuration
enum PostHogKeys {
    static let apiKey = SecretsManager.postHogAPIKey
    static let host = SecretsManager.postHogHost
    
    // Azure Blob Storage for media (clips/images)
    static let blobBaseURL = SecretsManager.telemetryBaseURL
    static let apiKeyHeader = "x-api-key"
    static let apiKeyValue = SecretsManager.telemetryAPIKey
}

// MARK: - Event Names (standardized for PostHog)
enum PostHogEvents {
    // Core Events
    static let userRegistered = "user_registered"
    static let bleConnected = "ble_connected"
    static let bleDisconnected = "ble_disconnected"
    static let modeChanged = "mode_changed"
    static let incidentStarted = "incident_started"
    static let incidentMediaUploaded = "incident_media_uploaded"
    static let incidentCompleted = "incident_completed"
    static let incidentStalled = "incident_stalled"
    static let modeEnded = "mode_ended"
    static let feedbackSubmitted = "feedback_submitted"
    static let appHeartbeat = "app_heartbeat"
    static let appOpened = "app_opened"
    static let appBackgrounded = "app_backgrounded"
    
    // Onboarding
    static let onboardingCompleted = "onboarding_completed"
    
    // Device Connection Flow
    static let connectionScreenOpened = "connection_screen_opened"
    static let deviceScanStarted = "device_scan_started"
    static let deviceDiscovered = "device_discovered"
    static let connectionAttempted = "connection_attempted"
    static let connectionFailed = "connection_failed"
    static let autoConnectTriggered = "auto_connect_triggered"
    
    // Feature Usage
    static let mapViewed = "map_viewed"
    static let incidentsListViewed = "incidents_list_viewed"
    static let incidentDetailViewed = "incident_detail_viewed"
    static let incidentShared = "incident_shared"
    static let profileViewed = "profile_viewed"
    static let settingsChanged = "settings_changed"
    
    // Buddy System
    static let buddyAdded = "buddy_added"
    static let buddyRemoved = "buddy_removed"
    static let buddyAlertSent = "buddy_alert_sent"
    
    // Errors & Issues
    static let errorOccurred = "error_occurred"
    static let bleConnectionLost = "ble_connection_lost"
    static let uploadFailed = "upload_failed"
    
    // Engagement
    static let sessionStarted = "session_started"
    static let sessionEnded = "session_ended"
    static let notificationReceived = "notification_received"
    static let notificationTapped = "notification_tapped"
}

// MARK: - Mode Types
enum ModeType: String, Codable {
    case sleep, detect, idle, stream, other
}

func mapAppModeToPostHog(_ m: String) -> ModeType {
    switch m {
    case "sleeping": return .sleep
    case "detecting": return .detect
    case "idle": return .idle
    default: return .other
    }
}

// MARK: - PostHog Service (Singleton)
final class PostHogService {
    static let shared = PostHogService()
    
    private init() {}
    
    /// Initialize PostHog SDK - call this in AppDelegate
    func configure() {
        let config = PostHogConfig(apiKey: PostHogKeys.apiKey, host: PostHogKeys.host)
        
        // Enable session recording
        config.sessionReplay = true
        
        // IMPORTANT: Use screenshot mode for SwiftUI apps
        // Wireframe mode (default) doesn't work with SwiftUI and shows gray/blank screens
        config.sessionReplayConfig.screenshotMode = true
        
        // Privacy settings - minimize masking to see actual app content
        config.sessionReplayConfig.maskAllTextInputs = false
        config.sessionReplayConfig.maskAllImages = false
        config.sessionReplayConfig.maskAllSandboxedViews = false
        
        // Capture network requests for debugging (optional)
        config.sessionReplayConfig.captureNetworkTelemetry = true
        
        // Disable automatic screen capture - it shows generic UIHostingController names
        // We use manual PostHogService.shared.screen() calls with descriptive names instead
        config.captureScreenViews = false
        config.captureApplicationLifecycleEvents = true
        
        PostHogSDK.shared.setup(config)
        Log.d("[PostHog] SDK initialized with screenshot mode for session replay")
    }
    
    /// Identify user with PostHog
    func identify(userId: String, properties: [String: Any]? = nil) {
        var props = properties ?? [:]
        props["identified_at"] = ISO8601DateFormatter().string(from: Date())
        
        PostHogSDK.shared.identify(userId, userProperties: props)
        Log.d("[PostHog] User identified: \(userId)")
    }
    
    /// Reset user (on logout)
    func reset() {
        PostHogSDK.shared.reset()
        Log.d("[PostHog] User reset")
    }
    
    /// Capture a custom event
    func capture(_ event: String, properties: [String: Any]? = nil) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
    
    /// Track screen view with a meaningful name
    func screen(_ screenName: String, properties: [String: Any]? = nil) {
        var props = properties ?? [:]
        props["screen_name"] = screenName
        PostHogSDK.shared.screen(screenName, properties: props)
        Log.d("[PostHog] Screen viewed: \(screenName)")
    }
    
    /// Flush events immediately
    func flush() {
        PostHogSDK.shared.flush()
    }
    
    // MARK: - Session Tracking
    private var sessionStartTime: Date?
    private var connectionStartDate: Date?
    private var modeStartDate: Date?
    private var currentModeType: ModeType?
    
    func startSession() {
        sessionStartTime = Date()
        capture(PostHogEvents.sessionStarted, properties: [
            "session_start": ISO8601DateFormatter().string(from: Date())
        ])
    }
    
    func endSession() {
        var properties: [String: Any] = [
            "session_end": ISO8601DateFormatter().string(from: Date())
        ]
        if let start = sessionStartTime {
            let duration = Date().timeIntervalSince(start)
            properties["session_duration_seconds"] = Int(duration)
        }
        capture(PostHogEvents.sessionEnded, properties: properties)
        sessionStartTime = nil
    }
    
    // MARK: - Connection Flow Tracking
    func trackConnectionScreenOpened() {
        capture(PostHogEvents.connectionScreenOpened)
    }
    
    func trackDeviceDiscovered(deviceName: String, rssi: Int, isKnownDevice: Bool) {
        capture(PostHogEvents.deviceDiscovered, properties: [
            "device_name": deviceName,
            "rssi": rssi,
            "is_known_device": isKnownDevice
        ])
    }
    
    func trackConnectionAttempted(deviceName: String, isAutoConnect: Bool) {
        capture(PostHogEvents.connectionAttempted, properties: [
            "device_name": deviceName,
            "is_auto_connect": isAutoConnect
        ])
    }
    
    func trackConnectionFailed(deviceName: String, errorMessage: String?) {
        capture(PostHogEvents.connectionFailed, properties: [
            "device_name": deviceName,
            "error": errorMessage ?? "unknown"
        ])
    }
    
    // MARK: - Feature Usage Tracking
    func trackScreenView(screenName: String) {
        capture("screen_viewed", properties: [
            "screen_name": screenName
        ])
    }
    
    func trackIncidentViewed(incidentId: String, hasMedia: Bool) {
        capture(PostHogEvents.incidentDetailViewed, properties: [
            "incident_id": incidentId,
            "has_media": hasMedia
        ])
    }
    
    func trackIncidentShared(incidentId: String, shareMethod: String) {
        capture(PostHogEvents.incidentShared, properties: [
            "incident_id": incidentId,
            "share_method": shareMethod
        ])
    }
    
    // MARK: - Buddy System Tracking
    func trackBuddyAdded(buddyCount: Int) {
        capture(PostHogEvents.buddyAdded, properties: [
            "total_buddies": buddyCount
        ])
    }
    
    func trackBuddyRemoved(buddyCount: Int) {
        capture(PostHogEvents.buddyRemoved, properties: [
            "total_buddies": buddyCount
        ])
    }
    
    func trackBuddyAlertSent(buddyCount: Int, incidentId: String?) {
        capture(PostHogEvents.buddyAlertSent, properties: [
            "buddies_notified": buddyCount,
            "incident_id": incidentId ?? "manual"
        ])
    }
    
    // MARK: - Error Tracking
    func trackError(category: String, message: String, context: [String: Any]? = nil) {
        var properties: [String: Any] = [
            "error_category": category,
            "error_message": message
        ]
        if let ctx = context {
            for (key, value) in ctx {
                properties["context_\(key)"] = value
            }
        }
        capture(PostHogEvents.errorOccurred, properties: properties)
    }
    
    // MARK: - Notification Tracking
    func trackNotificationReceived(type: String) {
        capture(PostHogEvents.notificationReceived, properties: [
            "notification_type": type
        ])
    }
    
    func trackNotificationTapped(type: String, action: String?) {
        capture(PostHogEvents.notificationTapped, properties: [
            "notification_type": type,
            "action": action ?? "open"
        ])
    }
    
    // MARK: - User Properties (for segmentation)
    func setUserProperties(_ properties: [String: Any]) {
        PostHogSDK.shared.capture("$set", properties: ["$set": properties])
    }
    
    func incrementUserProperty(_ property: String, by value: Int = 1) {
        PostHogSDK.shared.capture("$set", properties: [
            "$set_once": ["\(property)_first": Date().timeIntervalSince1970],
            "$set": [property: value]
        ])
    }
    
    // MARK: - User Profile Updates (call these after key events)
    
    /// Update user profile with current stats - call periodically or after key events
    func updateUserProfile(
        totalIncidents: Int,
        totalConnections: Int,
        buddyCount: Int,
        knownDeviceCount: Int,
        primaryMode: String?,
        registrationDate: Date?
    ) {
        var properties: [String: Any] = [
            "total_incidents": totalIncidents,
            "total_connections": totalConnections,
            "has_buddies": buddyCount > 0,
            "buddy_count": buddyCount,
            "device_count": knownDeviceCount,
            "last_seen": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let mode = primaryMode {
            properties["primary_mode"] = mode
        }
        
        if let regDate = registrationDate {
            let daysSinceReg = Calendar.current.dateComponents([.day], from: regDate, to: Date()).day ?? 0
            properties["account_age_days"] = daysSinceReg
        }
        
        setUserProperties(properties)
    }
    
    /// Track when user completes an incident (increments counter)
    func userDidCompleteIncident() {
        PostHogSDK.shared.capture("$set", properties: [
            "$set_once": ["first_incident_at": ISO8601DateFormatter().string(from: Date())],
            "$set": ["last_incident_at": ISO8601DateFormatter().string(from: Date())]
        ])
    }
    
    /// Track when user connects a device
    func userDidConnectDevice(deviceName: String) {
        PostHogSDK.shared.capture("$set", properties: [
            "$set_once": ["first_connection_at": ISO8601DateFormatter().string(from: Date())],
            "$set": [
                "last_connection_at": ISO8601DateFormatter().string(from: Date()),
                "last_device_name": deviceName
            ]
        ])
    }
    
    /// Track user's mode preference
    func userDidChangeMode(to mode: String) {
        // Track mode usage for determining primary mode
        let key = "mode_\(mode)_count"
        PostHogSDK.shared.capture("$set", properties: [
            "$set": ["last_mode": mode, "last_mode_change_at": ISO8601DateFormatter().string(from: Date())]
        ])
    }
    
    /// Track buddy system usage
    func userDidUpdateBuddies(count: Int) {
        var properties: [String: Any] = [
            "buddy_count": count,
            "has_buddies": count > 0
        ]
        if count > 0 {
            properties["buddy_feature_adopted"] = true
        }
        setUserProperties(properties)
    }
    
    /// Set user tier/segment based on usage
    func updateUserSegment(incidentsThisWeek: Int, sessionsThisWeek: Int) {
        var segment = "casual"
        if incidentsThisWeek >= 10 || sessionsThisWeek >= 7 {
            segment = "power_user"
        } else if incidentsThisWeek >= 3 || sessionsThisWeek >= 3 {
            segment = "regular"
        }
        
        setUserProperties([
            "user_segment": segment,
            "incidents_this_week": incidentsThisWeek,
            "sessions_this_week": sessionsThisWeek
        ])
    }
    
    /// Mark user as churned risk (no activity in X days)
    func checkChurnRisk(lastActiveDate: Date?) {
        guard let lastActive = lastActiveDate else { return }
        
        let daysSinceActive = Calendar.current.dateComponents([.day], from: lastActive, to: Date()).day ?? 0
        
        var churnRisk = "none"
        if daysSinceActive >= 30 {
            churnRisk = "high"
        } else if daysSinceActive >= 14 {
            churnRisk = "medium"
        } else if daysSinceActive >= 7 {
            churnRisk = "low"
        }
        
        setUserProperties([
            "churn_risk": churnRisk,
            "days_since_active": daysSinceActive
        ])
    }
}

// MARK: - User Identity Store (updated for PostHog)
final class UserIdentityStore: ObservableObject {
    @Published private(set) var userUUID: String?
    @Published private(set) var email: String?
    @Published private(set) var firstName: String?
    @Published private(set) var lastName: String?

    private let K_uuid = "SB.user_uuid"
    private let K_email = "SB.user_email"
    private let K_first = "SB.first_name"
    private let K_last = "SB.last_name"

    init() {
        let ud = UserDefaults.standard
        userUUID = ud.string(forKey: K_uuid)
        email = ud.string(forKey: K_email)
        firstName = ud.string(forKey: K_first)
        lastName = ud.string(forKey: K_last)
        
        // If we have a user, identify with PostHog
        if let uuid = userUUID {
            identifyWithPostHog()
        }
    }

    var hasProfile: Bool {
        if let u = userUUID, let f = firstName, let l = lastName,
           !u.isEmpty, !f.isEmpty, !l.isEmpty { return true }
        return false
    }

    /// Set profile from legacy first/last name entry
    func setProfile(first: String, last: String) {
        let ud = UserDefaults.standard
        if userUUID == nil {
            userUUID = UUID().uuidString
            ud.set(userUUID!, forKey: K_uuid)
        }
        firstName = first
        ud.set(first, forKey: K_first)
        lastName = last
        ud.set(last, forKey: K_last)
        ud.synchronize()
        
        identifyWithPostHog()
    }
    
    /// Set profile from Firebase Auth user
    func setProfileFromFirebase(uid: String, email: String, firstName: String?, lastName: String?) {
        let ud = UserDefaults.standard
        
        userUUID = uid
        ud.set(uid, forKey: K_uuid)
        
        self.email = email
        ud.set(email, forKey: K_email)
        
        if let first = firstName {
            self.firstName = first
            ud.set(first, forKey: K_first)
        }
        if let last = lastName {
            self.lastName = last
            ud.set(last, forKey: K_last)
        }
        
        ud.synchronize()
        Log.d("[Identity] Profile set from Firebase: \(email)")
        
        identifyWithPostHog()
    }
    
    /// Identify user with PostHog
    private func identifyWithPostHog() {
        guard let uuid = userUUID else { return }
        
        var properties: [String: Any] = [:]
        if let email = email { properties["email"] = email }
        if let first = firstName { properties["first_name"] = first }
        if let last = lastName { properties["last_name"] = last }
        if let first = firstName, let last = lastName {
            properties["name"] = "\(first) \(last)"
        }
        
        PostHogService.shared.identify(userId: uuid, properties: properties)
    }
    
    /// Clear identity on logout
    func clearIdentity() {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: K_uuid)
        ud.removeObject(forKey: K_email)
        ud.removeObject(forKey: K_first)
        ud.removeObject(forKey: K_last)
        
        userUUID = nil
        email = nil
        firstName = nil
        lastName = nil
        
        PostHogService.shared.reset()
    }
}

// MARK: - Telemetry Manager (PostHog-based)
final class TelemetryManager: ObservableObject {
    @Published private(set) var currentConnectionSessionUUID: String?
    @Published private(set) var currentModeSessionUUID: String?
    @Published private(set) var currentDeviceID: String?  // SipBuddy BLE peripheral identifier

    let identity: UserIdentityStore
    
    private var heartbeatTimer: Timer?
    
    // Persistence keys
    private let K_conn = "SB.telemetry.conn_uuid"
    private let K_mode = "SB.telemetry.mode_uuid"
    private let K_device = "SB.telemetry.device_id"

    private var connectionStartDate: Date?
    private var modeStartDate: Date?
    private var currentModeType: ModeType?

    init(identity: UserIdentityStore) {
        self.identity = identity
        
        // Rehydrate from disk
        let ud = UserDefaults.standard
        currentConnectionSessionUUID = ud.string(forKey: K_conn)
        currentModeSessionUUID = ud.string(forKey: K_mode)
        currentDeviceID = ud.string(forKey: K_device)
    }

    // MARK: - User Registration
    func registerUserIfReady() {
        guard identity.hasProfile,
              let userId = identity.userUUID,
              let firstName = identity.firstName,
              let lastName = identity.lastName else { return }
        
        PostHogService.shared.capture(PostHogEvents.userRegistered, properties: [
            "user_id": userId,
            "first_name": firstName,
            "last_name": lastName,
            "email": identity.email ?? "",
            "registered_at": ISO8601DateFormatter().string(from: Date())
        ])
    }

    // MARK: - BLE Connection Events
    func startConnectionSession(meta: [String: String]) {
        guard let userId = identity.userUUID else { return }
        
        let conn = UUID().uuidString
        currentConnectionSessionUUID = conn
        UserDefaults.standard.set(conn, forKey: K_conn)
        connectionStartDate = Date()
        
        // Store the device ID (peripheral UUID) for all subsequent events
        if let deviceId = meta["peripheral_id"] {
            currentDeviceID = deviceId
            UserDefaults.standard.set(deviceId, forKey: K_device)
        }

        var properties: [String: Any] = [
            "connection_session_id": conn,
            "user_id": userId,
            "connected_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Add device metadata
        for (key, value) in meta {
            properties["device_\(key)"] = value
        }
        
        // Add device_id at top level for easy filtering in PostHog
        if let deviceId = currentDeviceID {
            properties["device_id"] = deviceId
        }
        
        PostHogService.shared.capture(PostHogEvents.bleConnected, properties: properties)
        Log.d("[PostHog] BLE connected, session: \(conn), device: \(currentDeviceID ?? "unknown")")
    }

    func endConnectionSession() {
        guard let userId = identity.userUUID,
              let conn = currentConnectionSessionUUID else { return }

        // End any active mode session first
        endModeSession()

        var props: [String: Any] = [
            "connection_session_id": conn,
            "user_id": userId,
            "disconnected_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let start = connectionStartDate {
            let duration = Date().timeIntervalSince(start)
            props["connection_duration_seconds"] = Int(duration)
        }
        if let deviceId = currentDeviceID {
            props["device_id"] = deviceId
        }
        PostHogService.shared.capture(PostHogEvents.bleDisconnected, properties: props)

        currentConnectionSessionUUID = nil
        connectionStartDate = nil
        currentModeSessionUUID = nil
        modeStartDate = nil
        currentModeType = nil
        currentDeviceID = nil

        let ud = UserDefaults.standard
        ud.removeObject(forKey: K_conn)
        ud.removeObject(forKey: K_mode)
        ud.removeObject(forKey: K_device)
    }
    
    func ensureConnectionSession(meta: [String: String]) {
        if currentConnectionSessionUUID == nil {
            startConnectionSession(meta: meta)
        }
    }

    // MARK: - Mode Change Events
    func startModeSession(newMode: ModeType) {
        guard let userId = identity.userUUID,
              let conn = currentConnectionSessionUUID else { return }

        let now = Date()

        // If a mode is already active, end it and record duration
        if let prev = currentModeType,
           let prevStart = modeStartDate,
           let prevModeID = currentModeSessionUUID {

            let duration = now.timeIntervalSince(prevStart)
            var modeEndedProps: [String: Any] = [
                "mode_session_id": prevModeID,
                "connection_session_id": conn,
                "user_id": userId,
                "mode": prev.rawValue,
                "duration_seconds": Int(duration),
                "ended_at": ISO8601DateFormatter().string(from: now)
            ]
            if let deviceId = currentDeviceID {
                modeEndedProps["device_id"] = deviceId
            }
            PostHogService.shared.capture(PostHogEvents.modeEnded, properties: modeEndedProps)
        }

        // Start a new mode session
        let mode = UUID().uuidString
        currentModeSessionUUID = mode
        modeStartDate = now
        currentModeType = newMode
        UserDefaults.standard.set(mode, forKey: K_mode)

        var modeChangedProps: [String: Any] = [
            "mode_session_id": mode,
            "connection_session_id": conn,
            "user_id": userId,
            "new_mode": newMode.rawValue,
            "changed_at": ISO8601DateFormatter().string(from: now),
            "previous_mode": currentModeType == newMode ? newMode.rawValue : (currentModeType?.rawValue ?? "unknown")
        ]
        if let deviceId = currentDeviceID {
            modeChangedProps["device_id"] = deviceId
        }
        PostHogService.shared.capture(PostHogEvents.modeChanged, properties: modeChangedProps)
    }
    
    func endModeSession() {
        guard let userId = identity.userUUID,
              let conn = currentConnectionSessionUUID,
              let modeID = currentModeSessionUUID,
              let start = modeStartDate,
              let mode = currentModeType else {
            // Nothing to end
            currentModeSessionUUID = nil
            modeStartDate = nil
            currentModeType = nil
            UserDefaults.standard.removeObject(forKey: K_mode)
            return
        }

        let now = Date()
        let duration = now.timeIntervalSince(start)
        var modeEndedProps: [String: Any] = [
            "mode_session_id": modeID,
            "connection_session_id": conn,
            "user_id": userId,
            "mode": mode.rawValue,
            "duration_seconds": Int(duration),
            "ended_at": ISO8601DateFormatter().string(from: now)
        ]
        if let deviceId = currentDeviceID {
            modeEndedProps["device_id"] = deviceId
        }
        PostHogService.shared.capture(PostHogEvents.modeEnded, properties: modeEndedProps)

        currentModeSessionUUID = nil
        modeStartDate = nil
        currentModeType = nil
        UserDefaults.standard.removeObject(forKey: K_mode)
    }
    
    // Convenience overload for ModeWire compatibility
    func startModeSession(newMode: ModeWire) {
        let modeType: ModeType
        switch newMode {
        case .sleep: modeType = .sleep
        case .detect: modeType = .detect
        case .idle: modeType = .idle
        case .stream: modeType = .stream
        case .other: modeType = .other
        }
        startModeSession(newMode: modeType)
    }
    
    func ensureModeSessionIfMissing(newMode: ModeWire) {
        if currentModeSessionUUID == nil {
            startModeSession(newMode: newMode)
        }
    }

    // MARK: - Incident Events
    func recordIncidentStart(imageUUID: String, location: CLLocation?, placeName: String?) {
        guard let userId = identity.userUUID,
              let conn = currentConnectionSessionUUID,
              let mode = currentModeSessionUUID else { return }

        var properties: [String: Any] = [
            "incident_id": imageUUID,
            "connection_session_id": conn,
            "mode_session_id": mode,
            "user_id": userId,
            "started_at": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let deviceId = currentDeviceID {
            properties["device_id"] = deviceId
        }
        
        if let location = location {
            properties["latitude"] = location.coordinate.latitude
            properties["longitude"] = location.coordinate.longitude
            if location.horizontalAccuracy > 0 {
                properties["location_accuracy_m"] = location.horizontalAccuracy
            }
        }
        
        if let placeName = placeName {
            properties["place_name"] = placeName
        }

        PostHogService.shared.capture(PostHogEvents.incidentStarted, properties: properties)
    }

    func recordIncidentCompleted(incident: Incident, outcome: String = "complete") {
        guard let userId = identity.userUUID else { return }

        var properties: [String: Any] = [
            "incident_id": incident.id.uuidString,
            "user_id": userId,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
            "frame_count": incident.framesPNG.count,
            "expected_frames": incident.expectedFrames,
            "outcome": outcome
        ]

        if let start = incident.startedAt as Date? {
            properties["started_at"] = ISO8601DateFormatter().string(from: start)
        }
        if let elapsed = incident.totalElapsedTime ?? (incident.lastFrameAt.map { $0.timeIntervalSince(incident.startedAt) }) {
            properties["elapsed_seconds"] = Int(elapsed)
        }
        if let conn = currentConnectionSessionUUID { properties["connection_session_id"] = conn }
        if let mode = currentModeSessionUUID { properties["mode_session_id"] = mode }
        if let deviceId = currentDeviceID { properties["device_id"] = deviceId }
        if let loc = incident.location {
            properties["latitude"] = loc.coordinate.latitude
            properties["longitude"] = loc.coordinate.longitude
        }
        if let place = incident.placeName { properties["place_name"] = place }

        PostHogService.shared.capture(PostHogEvents.incidentCompleted, properties: properties)
    }

    func recordIncidentStalled(incident: Incident, stalledAfter: TimeInterval) {
        guard let userId = identity.userUUID else { return }

        var properties: [String: Any] = [
            "incident_id": incident.id.uuidString,
            "user_id": userId,
            "stalled_after_seconds": Int(stalledAfter),
            "frame_count": incident.framesPNG.count,
            "expected_frames": incident.expectedFrames,
            "started_at": ISO8601DateFormatter().string(from: incident.startedAt)
        ]
        if let conn = currentConnectionSessionUUID { properties["connection_session_id"] = conn }
        if let mode = currentModeSessionUUID { properties["mode_session_id"] = mode }
        if let deviceId = currentDeviceID { properties["device_id"] = deviceId }
        if let last = incident.lastFrameAt { properties["last_frame_at"] = ISO8601DateFormatter().string(from: last) }
        if let loc = incident.location {
            properties["latitude"] = loc.coordinate.latitude
            properties["longitude"] = loc.coordinate.longitude
        }
        if let place = incident.placeName { properties["place_name"] = place }

        PostHogService.shared.capture(PostHogEvents.incidentStalled, properties: properties)
    }
    
    // MARK: - Feedback
    func sendFeedback(comments: String, completion: ((Bool) -> Void)? = nil) {
        guard let userId = identity.userUUID else {
            completion?(false)
            return
        }
        
        PostHogService.shared.capture(PostHogEvents.feedbackSubmitted, properties: [
            "user_id": userId,
            "comments": comments,
            "submitted_at": ISO8601DateFormatter().string(from: Date())
        ])
        
        completion?(true)
    }

    // MARK: - Heartbeat
    var currentModeNameProvider: (() -> String)? = nil
    
    func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        sendHeartbeat()
        
        // Also track app becoming active
        PostHogService.shared.capture(PostHogEvents.appOpened)
    }
    
    func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        // Track app going to background
        PostHogService.shared.capture(PostHogEvents.appBackgrounded)
    }

    private func sendHeartbeat() {
        guard let userId = identity.userUUID,
              let conn = currentConnectionSessionUUID,
              let mode = currentModeSessionUUID else { return }
        
        let currentMode = currentModeNameProvider?() ?? "unknown"
        
        var properties: [String: Any] = [
            "user_id": userId,
            "connection_session_id": conn,
            "mode_session_id": mode,
            "current_mode": mapAppModeToPostHog(currentMode).rawValue,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let deviceId = currentDeviceID {
            properties["device_id"] = deviceId
        }
        PostHogService.shared.capture(PostHogEvents.appHeartbeat, properties: properties)
    }
}

// MARK: - Media Upload (Azure Blob Storage)
// Keep blob storage for media, but link it to PostHog events

struct SasResponse: Codable {
    let sas_url: String
}

extension TelemetryManager {
    /// Upload incident media to Azure Blob Storage and track in PostHog
    func uploadIncidentMedia(incident: Incident) {
        var fileURL: URL? = nil
        var contentType = "application/octet-stream"
        var mediaType = "unknown"

        Log.d("[PostHog] Preparing media upload for incident \(incident.id), frames: \(incident.framesPNG.count)")
        
        if incident.framesPNG.count > 1 {
            let frames = incident.framesPNG.compactMap { UIImage(data: $0) }
            if let gif = GIFEncoder.makeGIF(from: frames, fps: 30) {
                Log.d("[PostHog] GIF created, size: \(gif.count) bytes")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(incident.id).gif")
                try? gif.write(to: url)
                fileURL = url
                contentType = "image/gif"
                mediaType = "gif"
            }
        } else if let first = incident.framesPNG.first {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(incident.id).png")
            try? first.write(to: url)
            fileURL = url
            contentType = "image/png"
            mediaType = "png"
        }

        guard let fileURL = fileURL else { return }

        // Get SAS URL from backend
        let sasURL = PostHogKeys.blobBaseURL.appendingPathComponent("v1/incidents/\(incident.id)/sas")
        
        URLSession.shared.dataTask(with: sasURL) { [weak self] data, _, _ in
            guard let self = self, let data = data else { return }

            guard let resp = try? JSONDecoder().decode(SasResponse.self, from: data),
                  let uploadURL = URL(string: resp.sas_url) else {
                Log.e("[PostHog] Failed to decode SAS response")
                return
            }

            // Upload to Azure Blob
            var req = URLRequest(url: uploadURL)
            req.httpMethod = "PUT"
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")

            if let body = try? Data(contentsOf: fileURL) {
                URLSession.shared.uploadTask(with: req, from: body) { [weak self] _, resp, _ in
                    guard let self = self else { return }
                    
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    guard (200...299).contains(code) else {
                        Log.e("[PostHog] Blob upload failed, status=\(code)")
                        return
                    }
                    
                    Log.d("[PostHog] Blob upload success")
                    
                    // Track media upload in PostHog with blob URL
                    let cleanURL = uploadURL.absoluteString.components(separatedBy: "?").first!
                    
                    var properties: [String: Any] = [
                        "incident_id": incident.id.uuidString,
                        "media_url": cleanURL,
                        "media_type": mediaType,
                        "frame_count": incident.framesPNG.count,
                        "uploaded_at": ISO8601DateFormatter().string(from: Date())
                    ]
                    
                    if let userId = self.identity.userUUID {
                        properties["user_id"] = userId
                    }
                    if let conn = self.currentConnectionSessionUUID {
                        properties["connection_session_id"] = conn
                    }
                    if let mode = self.currentModeSessionUUID {
                        properties["mode_session_id"] = mode
                    }
                    if let deviceId = self.currentDeviceID {
                        properties["device_id"] = deviceId
                    }
                    if let location = incident.location {
                        properties["latitude"] = location.coordinate.latitude
                        properties["longitude"] = location.coordinate.longitude
                    }
                    if let placeName = incident.placeName {
                        properties["place_name"] = placeName
                    }
                    
                    PostHogService.shared.capture(PostHogEvents.incidentMediaUploaded, properties: properties)
                    
                }.resume()
            }
        }.resume()
    }
}

// MARK: - Firebase Auth Sync
extension TelemetryManager {
    func syncWithFirebaseAuth(_ authManager: AuthStateManager) {
        guard authManager.isAuthenticated else {
            Log.d("[PostHog] User not authenticated, skipping sync")
            return
        }
        
        authManager.syncWithTelemetry(identityStore: identity)
        registerUserIfReady()
    }
}

// MARK: - Incident Observer
extension TelemetryManager {
    func observeIncidentCompletion(store: IncidentStore) {
        NotificationCenter.default.addObserver(
            forName: .incidentCompleted,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let id = note.userInfo?["id"] as? UUID,
                  let inc = store.incidents.first(where: { $0.id == id }) else { return }
            
            self.recordIncidentStart(
                imageUUID: inc.id.uuidString,
                location: inc.location,
                placeName: inc.placeName
            )
        }
    }
}

// MARK: - Backward Compatibility
// Keep ModeWire enum for compatibility with existing code
enum ModeWire: String, Codable {
    case sleep, detect, idle, stream, other
}

func mapAppMode(_ m: String) -> ModeWire {
    switch m {
    case "sleeping": return .sleep
    case "detecting": return .detect
    case "idle": return .idle
    default: return .other
    }
}

// MARK: - Auto User Property Updates
extension TelemetryManager {
    /// Call this after BLE connection to update user properties
    func updateUserPropertiesOnConnect(deviceName: String, knownDeviceCount: Int) {
        PostHogService.shared.userDidConnectDevice(deviceName: deviceName)
        
        // Update device count
        PostHogService.shared.setUserProperties([
            "device_count": knownDeviceCount
        ])
    }
    
    /// Call this after mode change to track preferences
    func updateUserPropertiesOnModeChange(mode: String) {
        PostHogService.shared.userDidChangeMode(to: mode)
    }
    
    /// Call this after incident completes
    func updateUserPropertiesOnIncident(totalIncidents: Int) {
        PostHogService.shared.userDidCompleteIncident()
        PostHogService.shared.setUserProperties([
            "total_incidents": totalIncidents
        ])
    }
    
    /// Call this when buddy list changes
    func updateUserPropertiesOnBuddyChange(buddyCount: Int) {
        PostHogService.shared.userDidUpdateBuddies(count: buddyCount)
    }
    
    /// Comprehensive profile update - call on app launch or periodically
    func syncAllUserProperties(
        incidentStore: IncidentStore,
        buddyCount: Int,
        knownDeviceCount: Int,
        primaryMode: String?,
        registrationDate: Date?
    ) {
        let totalIncidents = incidentStore.incidents.count
        
        // Calculate sessions this week (simplified - you'd track this properly)
        let sessionsKey = "SB.sessions_this_week"
        let lastResetKey = "SB.sessions_week_start"
        let ud = UserDefaults.standard
        
        var sessionsThisWeek = ud.integer(forKey: sessionsKey)
        let lastReset = ud.object(forKey: lastResetKey) as? Date ?? Date.distantPast
        
        // Reset counter if it's a new week
        if !Calendar.current.isDate(lastReset, equalTo: Date(), toGranularity: .weekOfYear) {
            sessionsThisWeek = 0
            ud.set(Date(), forKey: lastResetKey)
        }
        sessionsThisWeek += 1
        ud.set(sessionsThisWeek, forKey: sessionsKey)
        
        // TODO: Replace with real incident date property when available
        let incidentsThisWeek = 0
        
        // Update full profile
        PostHogService.shared.updateUserProfile(
            totalIncidents: totalIncidents,
            totalConnections: ud.integer(forKey: "SB.total_connections"),
            buddyCount: buddyCount,
            knownDeviceCount: knownDeviceCount,
            primaryMode: primaryMode,
            registrationDate: registrationDate
        )
        
        // Update segment
        PostHogService.shared.updateUserSegment(
            incidentsThisWeek: incidentsThisWeek,
            sessionsThisWeek: sessionsThisWeek
        )
        
        // Check churn risk
        let lastActiveKey = "SB.last_active_date"
        let lastActive = ud.object(forKey: lastActiveKey) as? Date
        PostHogService.shared.checkChurnRisk(lastActiveDate: lastActive)
        ud.set(Date(), forKey: lastActiveKey)
    }
}

