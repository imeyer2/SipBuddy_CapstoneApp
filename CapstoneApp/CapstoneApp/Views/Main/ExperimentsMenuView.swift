//
//  ExperimentsMenuView.swift
//  SipBuddy
//
//


// ExperimentsMenuView.swift
import SwiftUI

struct ExperimentsMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthStateManager
    @EnvironmentObject var app: AppState
    @State private var toggles: [Bool] = Array(repeating: false, count: 6)
    @State private var showingLogoutAlert = false

    var body: some View {
        NavigationView {
            ZStack {
                GradientBackground()
                
                List {
                // MARK: - Profile Section
                Section {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if let profile = authManager.userProfile {
                                    Text(profile.fullName)
                                        .font(.headline)
                                    Text(profile.email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Not logged in")
                                        .font(.headline)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    Button(role: .destructive) {
                        showingLogoutAlert = true
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }
                } header: {
                    Text("Profile")
                }
                
                Section("Features") {
                    
                    
                    // MARK: - Experimental Feature: SipMap
                    NavigationLink {
                        SipMapView()
                    } label: {
                        Label("SipMap", systemImage: "map")
                    }
                    
                    // MARK: - Experimental Feature: Buddy System
                    NavigationLink {
                        BuddySystemView()
                    } label: {
                        Label("Buddy System", systemImage: "person.2.fill")
                    }
                    
//                    // MARK: - Replay Tutorial
//                    Button {
//                        app.showTutorial = true
//                        dismiss()
//                    } label: {
//                        Label("Replay Tutorial", systemImage: "play.circle")
//                    }
                    

//                    // MARK: - Placeholder Features
//                    ForEach(0..<toggles.count, id: \.self) { i in
//                        Toggle("Feature Placeholder \(i+1)", isOn: $toggles[i])
//                    }
                }

                Section {
                    Button("Close") { dismiss() }
                }
            }
            .scrollContentBackground(.hidden)
            }
            .navigationTitle("Help")
            .alert("Sign Out", isPresented: $showingLogoutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    do {
                        try authManager.signOut()
                        dismiss()
                    } catch {
                        print("Error signing out: \(error.localizedDescription)")
                    }
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
        }
    }
}

