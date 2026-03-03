//
//  ProfileView.swift
//  SipBuddy
//
//  User Profile Management Screen
//

import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthStateManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingLogoutAlert = false
    @State private var isEditingProfile = false
    @State private var editFirstName = ""
    @State private var editLastName = ""
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Profile Info Section
                Section {
                    if let profile = authManager.userProfile {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text(profile.fullName)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text(profile.email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                                if let uid = authManager.currentUser?.uid {
                                    Text("UID: \(uid.prefix(8))...")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        
                        Button {
                            editFirstName = profile.firstName ?? ""
                            editLastName = profile.lastName ?? ""
                            isEditingProfile = true
                        } label: {
                            Label("Edit Profile", systemImage: "pencil")
                        }
                    }
                } header: {
                    Text("Account")
                }
                
                // MARK: - Account Actions
                Section {
                    Button(role: .destructive) {
                        showingLogoutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }
                } header: {
                    Text("Actions")
                }
                
                // MARK: - App Info
                Section {
                    HStack {
                        Text("App Version")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Sign Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .sheet(isPresented: $isEditingProfile) {
                EditProfileSheet(
                    firstName: $editFirstName,
                    lastName: $editLastName,
                    onSave: updateProfile
                )
            }
        }
    }
    
    private func signOut() {
        do {
            try authManager.signOut()
            dismiss()
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    private func updateProfile() {
        authManager.updateProfile(firstName: editFirstName, lastName: editLastName)
        isEditingProfile = false
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var firstName: String
    @Binding var lastName: String
    let onSave: () -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("First Name", text: $firstName)
                        .textContentType(.givenName)
                        .autocapitalization(.words)
                    
                    TextField("Last Name", text: $lastName)
                        .textContentType(.familyName)
                        .autocapitalization(.words)
                } header: {
                    Text("Personal Information")
                } footer: {
                    Text("This information is stored locally on your device.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(firstName.isEmpty || lastName.isEmpty)
                }
            }
        }
    }
}
