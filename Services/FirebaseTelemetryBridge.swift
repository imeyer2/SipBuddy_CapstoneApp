//
//  FirebaseTelemetryBridge.swift
//  SipBuddy
//
//  Bridge between Firebase Auth and Telemetry System
//  Syncs Firebase user data (email, UID) with telemetry
//

import Foundation

extension AuthStateManager {
    /// Updates the UserIdentityStore with Firebase user data
    /// Call this after successful authentication
    /// Now uses email and Firebase UID for telemetry tracking
    func syncWithTelemetry(identityStore: UserIdentityStore) {
        guard let currentUser = currentUser,
              let profile = userProfile else {
            Log.d("[Telemetry] Cannot sync - no user profile available")
            return
        }
        
        // Use Firebase UID and email for telemetry
        identityStore.setProfileFromFirebase(
            uid: currentUser.uid,
            email: profile.email,
            firstName: profile.firstName,
            lastName: profile.lastName
        )
        
        Log.d("[Telemetry] Synced Firebase user: \(profile.email)")
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

// MARK: - Automatic Sync Helper

extension TelemetryManager {
    /// Sync telemetry with Firebase auth state
    /// Call this when auth state changes
    func syncWithFirebaseAuth(_ authManager: AuthStateManager) {
        guard authManager.isAuthenticated else {
            Log.d("[Telemetry] User not authenticated, skipping sync")
            return
        }
        
        authManager.syncWithTelemetry(identityStore: identity)
        registerUserIfReady()
    }
}

// MARK: - Usage in SipBuddy_PilotApp.swift
/*
 
 Add this to your app's body to auto-sync on auth changes:
 
 .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
     if isAuthenticated {
         // Sync Firebase user with telemetry
         telemetry.syncWithFirebaseAuth(authManager)
     }
 }
 
 Or in onAppear:
 
 .onAppear {
     // Sync if already authenticated
     if authManager.isAuthenticated {
         telemetry.syncWithFirebaseAuth(authManager)
     }
 }
 
*/
