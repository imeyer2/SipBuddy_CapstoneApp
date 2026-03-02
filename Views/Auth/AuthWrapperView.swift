//
//  AuthWrapperView.swift
//  SipBuddy
//
//  Wrapper to show Login or Main App based on auth state
//

import SwiftUI

struct AuthWrapperView: View {
    @EnvironmentObject var authManager: AuthStateManager
    @State private var showWelcome = false
    @State private var welcomeOpacity: Double = 0
    @State private var hasAppearedOnce = false
    
    var body: some View {
        ZStack {
            if authManager.isAuthenticated {
                if showWelcome {
                    // Welcome screen
                    WelcomeScreen()
                        .opacity(welcomeOpacity)
                        .transition(.opacity)
                } else {
                    // Main app
                    RootView()
                        .transition(.opacity)
                }
            } else {
                // Login screen
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: authManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: showWelcome)
        .animation(.easeInOut(duration: 0.5), value: welcomeOpacity)
        .onAppear {
            hasAppearedOnce = true
        }
        .onChange(of: authManager.isAuthenticated) { oldValue, newValue in
            // Only show welcome if:
            // 1. User just logged in (newValue=true, oldValue=false)
            // 2. The view has appeared at least once (not initial load)
            if newValue && !oldValue && hasAppearedOnce {
                // Just logged in - show welcome animation
                showWelcomeAnimation()
            }
        }
    }
    
    private func showWelcomeAnimation() {
        showWelcome = true
        
        // Fade in welcome screen
        withAnimation(.easeIn(duration: 0.5)) {
            welcomeOpacity = 1.0
        }
        
        // After 2 seconds, fade out and show main app
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                welcomeOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 500_000_000) // Wait for fade out
            showWelcome = false
        }
    }
}

// MARK: - Welcome Screen

struct WelcomeScreen: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Welcome content
            VStack(spacing: 20) {
                Image(systemName: "wineglass.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text("Welcome to")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
                
                Text("SipBuddy")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }
}
