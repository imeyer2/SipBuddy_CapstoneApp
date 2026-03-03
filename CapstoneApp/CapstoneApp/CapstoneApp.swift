//// -----------------------------------------------------------------------------
// FILE: SipBuddyApp.swift
// PURPOSE:
//   App entry point (like your program’s `main`, but declarative).
//   Wires up long-lived state objects (BLE, location, app state),
//   injects them into the SwiftUI environment, and reacts to
//   lifecycle changes (foreground/background) via `scenePhase`.

import SwiftUI
import FirebaseCore
import FirebaseAppCheck

@main
struct SipBuddyApp: App {
    // AppDelegate for PostHog initialization
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var appState = AppState()
    @StateObject private var ble = BLEManager.shared
    @StateObject private var loc = LocationManager()
    @StateObject private var buddies = BuddyStore()

    // Firebase Auth State Manager
    @StateObject private var authManager = AuthStateManager()

    // Keep identity as StateObject (owned by SwiftUI)
    @StateObject private var identity: UserIdentityStore

    // Telemetry (PostHog-based)
    private let telemetry: TelemetryManager

    init() {
        // Configure Firebase
        FirebaseApp.configure()
        
        // Configure App Check for development
        #if DEBUG
        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)
        #endif
        
        // Build one identity instance and share it
        let identityStore = UserIdentityStore()
        _identity = StateObject(wrappedValue: identityStore)
        telemetry = TelemetryManager(identity: identityStore)
        BLEManager.shared.telemetry = telemetry

    }

    @Environment(\.scenePhase) private var scenePhase

    
    var body: some Scene {
        // WindowGroup = top-level window container (iPhone still shows one)
        WindowGroup {
            // Use AuthWrapperView to show Login or Main App
            AuthWrapperView()
                // Inject shared objects so ANY descendant view can `@EnvironmentObject` them.
                .environmentObject(appState)
                .environmentObject(ble)
                .environmentObject(ble.incidentStore) // passes the store by reference
                .environmentObject(loc)
                .environmentObject(buddies)          // passes the Buddy store to root
                .environmentObject(identity)
                .environmentObject(telemetry)
                .environmentObject(authManager)      // Inject Firebase Auth Manager
            
                // onAppear fires when RootView becomes part of the view hierarchy.
                // Caution: can fire more than once across the app’s lifetime if
                // the system rebuilds the view tree; idempotent setup is wise.
                .onAppear {
                    // Provide BLE with a getter instead of a hard reference:
                    // This is like handing a function pointer/lambda so BLE
                    // can lazily pull the latest location without owning `loc`.
                    ble.getLocation = { loc.lastLocation }

                    // Start BLE scanning (likely idempotent internally).
                    // Consider guarding if your implementation isn’t idempotent.
                    ble.startScanning(filter: "Sip")

                    // Configure local notifications (permissions, categories, etc.).
                    NotificationManager.shared.configure(appState: appState)
                    
                    
                    
                    // MARK: - Telemetry Setup
                    // Let Telemetry read current mode name for heartbeats
                    telemetry.currentModeNameProvider = { appState.mode.rawValue }

                    // Sync Firebase auth with telemetry (email-based tracking)
                    if authManager.isAuthenticated {
                        telemetry.syncWithFirebaseAuth(authManager)
                    }

                    // Let BLE talk to telemetry if you add a weak ref (see BLE patch below)
                    BLEManager.shared.telemetry = telemetry
                    
                    // Sync all user properties for PostHog segmentation
                    telemetry.syncAllUserProperties(
                        incidentStore: ble.incidentStore,
                        // TODO: Replace 0 with the real buddy count property from BuddyStore (e.g., buddies.count or buddies.all.count)
                        buddyCount: 0,
                        knownDeviceCount: ble.knownDevices.count,
                        primaryMode: appState.mode.rawValue,
                        registrationDate: authManager.userProfile?.createdAt
                    )

                    
                    if ble.isConnected {
                        let meta: [String:String] = [
                            "device_name": ble.deviceName ?? "SipBuddy"
                            // You can add peripheral id if you surface it from BLEManager
                        ]
                        telemetry.ensureConnectionSession(meta: meta)
                        telemetry.ensureModeSessionIfMissing(newMode: mapAppMode(appState.mode.rawValue))
                    }
                    
                    // MARK: - END Telemetry Setup
                    
                    
                }

                // React to lifecycle transitions from the OS.
                // Swift 5.9+ onChange(of:initial:) gives old/new; we ignore `old`.
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        // App not visible; limited execution time.
                        // Good place to stop high-power work, flush state, schedule
                        // background tasks, etc. BLE background behavior depends on
                        // Info.plist background modes and CoreBluetooth rules.
                        ble.appDidEnterBackground()
                        telemetry.stopHeartbeat()


                        // The commented hacks below were "touches" to keep main alive.
                        // In SwiftUI you should prefer explicit background tasks or
                        // OS-sanctioned background modes — avoid no-op selector tricks.
                        // (left here as historical context)
                        // ble.incidentStore.performSelector(onMainThread: #selector(NSObject.description), with: nil, waitUntilDone: false)
                        // _ = ble.incidentStore.value(forKey: "incidents")

                    case .active:
                        // Foreground + interactive; resume work that feeds the UI.
                        ble.appDidBecomeActive()
                        telemetry.startHeartbeat()
                        
                        // Clear notification badge when app becomes active
                        UIApplication.shared.applicationIconBadgeNumber = 0


                    // .inactive = transient (e.g., system alert overlay).
                    default:
                        break
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .incidentCompleted)) { note in
                    if let id = note.userInfo?["id"] as? UUID,
                       let inc = ble.incidentStore.incidents.first(where: { $0.id == id }) {
                        telemetry.uploadIncidentMedia(incident: inc)
                    }
                }
                // MARK: - Firebase Auth State Changes
                .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        // User logged in - sync Firebase data with telemetry
                        telemetry.syncWithFirebaseAuth(authManager)
                        Log.d("[App] User authenticated, telemetry synced")
                    } else {
                        // User logged out
                        Log.d("[App] User logged out")
                    }
                }
        }
    }
}

//#Preview {
//    RootView()
//        .environmentObject(AppState())
//        .environmentObject(BLEManager())
//        .environmentObject(BLEManager().incidentStore) // passes the store by reference
//        .environmentObject(LocationManager())
//}

