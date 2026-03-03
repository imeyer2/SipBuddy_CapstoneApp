//
//  FirebaseTelemetryBridge.swift
//  SipBuddy
//
//  Bridge between Firebase Auth and Telemetry System
//  Syncs Firebase user data (email, UID) with telemetry (PostHog)
//

import Foundation

extension AuthStateManager {
    /// Updates the UserIdentityStore with Firebase user data
    /// Call this after successful authentication
    /// Now uses email and Firebase UID for telemetry tracking
    func syncWithTelemetry(identityStore: UserIdentityStore) {
        guard let currentUser = currentUser,
              let profile = userProfile else {
            Log.d("[PostHog] Cannot sync - no user profile available")
            return
        }
        
        // Use Firebase UID and email for telemetry
        identityStore.setProfileFromFirebase(
            uid: currentUser.uid,
            email: profile.email,
            firstName: profile.firstName,
            lastName: profile.lastName
        )
        
        Log.d("[PostHog] Synced Firebase user: \(profile.email)")
    }
    
    /// Get user ID for telemetry (Firebase UID)
    var telemetryUserID: String? {
        return currentUser?.uid
    }
    
    /// Get user email for telemetry
    var telemetryEmail: String? {
        return userProfile?.email
    }
    
    /// Get full name for telemetry
    var telemetryFullName: String? {
        return userProfile?.fullName
    }
}

// Note: TelemetryManager.syncWithFirebaseAuth is now defined in PostHogService.swift
