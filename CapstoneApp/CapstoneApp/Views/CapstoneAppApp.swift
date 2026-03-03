//
//  CapstoneAppApp.swift
//  CapstoneApp
//
//

import SwiftUI
import FirebaseCore

// @main removed — SipBuddyApp in CapstoneApp.swift is the active entry point
struct CapstoneAppApp: App {

    // Create shared state objects once at the top level
    @StateObject private var authManager = AuthStateManager()
    @StateObject private var app = AppState()
    @StateObject private var ble = BLEManager()
    @StateObject private var identity = UserIdentityStore()
    @StateObject private var store = IncidentStore()
    @StateObject private var buddies = BuddyStore()

    // TelemetryManager depends on identity, so we create it lazily
    @StateObject private var telemetry: TelemetryManager

    init() {
        FirebaseApp.configure()
        PostHogService.shared.configure()

        // Create identity + telemetry with shared reference
        let id = UserIdentityStore()
        _identity = StateObject(wrappedValue: id)
        _telemetry = StateObject(wrappedValue: TelemetryManager(identity: id))
    }

    var body: some Scene {
        WindowGroup {
            AuthWrapperView()
                .environmentObject(authManager)
                .environmentObject(app)
                .environmentObject(ble)
                .environmentObject(telemetry)
                .environmentObject(store)
                .environmentObject(buddies)
        }
    }
}
