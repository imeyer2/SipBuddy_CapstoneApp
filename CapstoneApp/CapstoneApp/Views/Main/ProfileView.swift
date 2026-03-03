//
//  ProfileView.swift
//  SipBuddy
//
//  User Profile Management Screen
//

import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @EnvironmentObject var authManager: AuthStateManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingLogoutAlert = false
    @State private var isEditingProfile = false
    @State private var editFirstName = ""
    @State private var editLastName = ""
    @State private var showDeleteSheet = false
    @State private var deletePassword = ""
    @State private var isDeleting = false
    @State private var deleteError: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
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

                    Button(role: .destructive) {
                        showDeleteSheet = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
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
            .scrollContentBackground(.hidden)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                PostHogService.shared.screen("Profile")
            }
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
            .sheet(isPresented: $showDeleteSheet) {
                DeleteAccountSheet(
                    email: authManager.currentUser?.email ?? "",
                    isDeleting: $isDeleting,
                    password: $deletePassword,
                    errorMessage: $deleteError,
                    onDelete: deleteAccount,
                    onCancel: { showDeleteSheet = false; deleteError = nil; deletePassword = "" }
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

    private func deleteAccount() {
        deleteError = nil
        isDeleting = true
        Task {
            do {
                try await authManager.deleteAccount(password: deletePassword)
                isDeleting = false
                showDeleteSheet = false
                dismiss() // leave profile screen
            } catch {
                isDeleting = false
                deleteError = error.localizedDescription
            }
        }
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

// MARK: - Delete Account Sheet
struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    let email: String
    @Binding var isDeleting: Bool
    @Binding var password: String
    @Binding var errorMessage: String?
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("Deleting your account permanently removes your profile and data associated with this app. This action cannot be undone.")) {
                    HStack {
                        Text("Account")
                        Spacer()
                        Text(email.isEmpty ? "Email account" : email)
                            .foregroundStyle(.secondary)
                    }
                    SecureField("Confirm Password", text: $password)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Can’t delete in-app?") {
                    Link("Delete via Web Portal", destination: URL(string: "https://sipbuddy.co")!)
                    Text("If required, you can complete deletion on the website.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        if isDeleting { ProgressView() } else { Text("Delete") }
                    }
                    .disabled(isDeleting)
                }
            }
        }
    }
}
