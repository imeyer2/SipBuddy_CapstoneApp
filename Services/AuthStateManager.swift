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
}
