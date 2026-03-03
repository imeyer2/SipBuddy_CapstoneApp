//
//  AuthStateManager.swift
//  SipBuddy
//
//  Firebase Authentication State Manager
//

import Foundation
import FirebaseAuth
import Combine

final class AuthStateManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var userProfile: UserProfile?
    
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    
    struct UserProfile: Codable {
        let uid: String
        let email: String
        let firstName: String?
        let lastName: String?
        var createdAt: Date = Date()  // Track when user was created
        
        var fullName: String {
            if let first = firstName, let last = lastName {
                return "\(first) \(last)"
            }
            return email
        }
    }
    
    init() {
        registerAuthStateHandler()
        loadUserProfile()
    }
    
    deinit {
        if let handle = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
    
    // MARK: - Auth State Listener
    
    private func registerAuthStateHandler() {
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.currentUser = user
            self?.isAuthenticated = user != nil
            if user != nil {
                self?.loadUserProfile()
            } else {
                self?.userProfile = nil
            }
        }
    }
    
    // MARK: - Sign Up
    
    func signUp(email: String, password: String, firstName: String, lastName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        
        // Save user profile to UserDefaults (or Firestore in production)
        let profile = UserProfile(uid: result.user.uid, email: email, firstName: firstName, lastName: lastName)
        saveUserProfile(profile)
        
        Log.d("[AUTH] User signed up: \(email)")
    }
    
    // MARK: - Sign In
    
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        Log.d("[AUTH] User signed in: \(email)")
        
        // Load profile after sign in
        loadUserProfile()
    }
    
    // MARK: - Sign Out
    
    func signOut() throws {
        try Auth.auth().signOut()
        userProfile = nil
        Log.d("[AUTH] User signed out")
    }
    
    // MARK: - Password Reset
    
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
        Log.d("[AUTH] Password reset email sent to: \(email)")
    }
    
    // MARK: - Profile Management
    
    private func saveUserProfile(_ profile: UserProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "SB.userProfile")
        }
        self.userProfile = profile
    }
    
    private func loadUserProfile() {
        guard let user = Auth.auth().currentUser else { return }
        
        if let data = UserDefaults.standard.data(forKey: "SB.userProfile"),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            self.userProfile = profile
        } else {
            // Create basic profile from Firebase user
            let profile = UserProfile(uid: user.uid, email: user.email ?? "", firstName: nil, lastName: nil)
            self.userProfile = profile
        }
    }
    
    func updateProfile(firstName: String, lastName: String) {
        guard let user = currentUser else { return }
        
        let profile = UserProfile(
            uid: user.uid,
            email: user.email ?? "",
            firstName: firstName,
            lastName: lastName
        )
        saveUserProfile(profile)
    }
    
    // MARK: - Account Deletion
    enum DeleteAccountError: LocalizedError {
        case notAuthenticated
        case reauthenticationRequired
        case missingEmail
        case missingPassword

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "You must be signed in to delete your account."
            case .reauthenticationRequired: return "Please re-enter your password to confirm account deletion."
            case .missingEmail: return "Your account has no email address associated."
            case .missingPassword: return "Please enter your password."
            }
        }
    }

    /// Deletes the currently signed-in Firebase user. If Firebase requires recent login, this method
    /// will attempt password reauthentication when a password is provided.
    /// - Parameter password: The user's current password (for email/password accounts). Optional; if omitted and reauth is required, an error is thrown.
    @MainActor
    func deleteAccount(password: String?) async throws {
        guard let user = Auth.auth().currentUser else { throw DeleteAccountError.notAuthenticated }

        func performDelete() async throws {
            try await user.delete()
            // Clear local profile data
            UserDefaults.standard.removeObject(forKey: "SB.userProfile")
            self.userProfile = nil
            self.currentUser = nil
            self.isAuthenticated = false
            Log.d("[AUTH] Account deleted and local profile cleared")
        }

        do {
            try await performDelete()
            return
        } catch {
            let nserr = error as NSError
            // Check Firebase Auth error domain and map raw code to AuthErrorCode
            if nserr.domain == "FIRAuthErrorDomain",
               let code = AuthErrorCode(rawValue: nserr.code), code == .requiresRecentLogin {
                // Reauth needed
                guard let email = user.email else { throw DeleteAccountError.missingEmail }
                guard let pwd = password, !pwd.isEmpty else { throw DeleteAccountError.reauthenticationRequired }
                let credential = EmailAuthProvider.credential(withEmail: email, password: pwd)
                try await user.reauthenticate(with: credential)
                try await performDelete()
            } else {
                throw error
            }
        }
    }
}
