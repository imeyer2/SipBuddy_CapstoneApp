//  HomeView.swift
//  SipBuddy
//
//

import SwiftUI

#if DEBUG
private let TINT_LOGS_ENABLED = true   // flip to false to silence tint logs in debug
#else
private let TINT_LOGS_ENABLED = false
#endif

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var ble: BLEManager
    @EnvironmentObject var auth: AuthStateManager
    @EnvironmentObject var telemetry: TelemetryManager

    @State private var showConnectSheet = false
    @State private var connectionPulse = false
    @State private var appearAnimation = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar()
                Divider()

                // Content Window
                ZStack {
                    if !ble.isConnected {
                        // Disconnected state with animated entrance
                        VStack(spacing: 20) {
                            // Animated connection icon
                            ZStack {
                                // Outer pulse rings
                                ForEach(0..<3, id: \.self) { i in
                                    Circle()
                                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                                        .frame(width: 80 + CGFloat(i) * 30, height: 80 + CGFloat(i) * 30)
                                        .scaleEffect(connectionPulse ? 1.2 : 0.8)
                                        .opacity(connectionPulse ? 0 : 0.6)
                                        .animation(
                                            .easeInOut(duration: 1.5)
                                            .repeatForever(autoreverses: false)
                                            .delay(Double(i) * 0.3),
                                            value: connectionPulse
                                        )
                                }
                                
                                // Center icon
                                Image(systemName: "bolt.horizontal.circle.fill")
                                    .font(.system(size: 64))
                                    .foregroundStyle(.linearGradient(
                                        colors: [.accentColor, .accentColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .symbolEffect(.pulse, options: .repeating)
                            }
                            .padding(.bottom, 8)
                            
                            Text("Connect Your SipBuddy")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .opacity(appearAnimation ? 1 : 0)
                                .offset(y: appearAnimation ? 0 : 10)
                            
                            Text("Tap below to pair your device")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .opacity(appearAnimation ? 1 : 0)
                                .offset(y: appearAnimation ? 0 : 10)
                            
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                showConnectSheet = true
                            } label: {
                                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.headline)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .clipShape(Capsule())
                            .shadow(color: .accentColor.opacity(0.3), radius: 8, y: 4)
                            .scaleEffect(appearAnimation ? 1 : 0.9)
                            .opacity(appearAnimation ? 1 : 0)
                            .accessibilityLabel("connect")
                            .accessibilityIdentifier("connect")
                        }
                        .padding()
                        .sheet(isPresented: $showConnectSheet) { DevicePickerView() }
                        .onAppear {
                            connectionPulse = true
                            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                                appearAnimation = true
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        // Connected state with mode display
                        switch app.mode {
                        case .idle, .detecting:
                            ProtectingView(firstName: auth.userProfile?.firstName)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        case .sleeping:
                            SleepingView()
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ble.isConnected)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: app.mode)
            }
            .padding(.horizontal)
        }
        .onAppear {
            _ = MLInferenceManager.shared
            PostHogService.shared.screen("Home")
        }
        .onChange(of: ble.isConnected) { _, newValue in
            if newValue {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

// MARK: - Protection Messages
private struct ProtectionMessage {
    let title: String
    let subtitle: String
    
    /// Creates a message, substituting {firstName} placeholder if name is provided
    static func resolve(_ template: ProtectionMessage, firstName: String?) -> ProtectionMessage {
        let name = firstName ?? "friend"
        return ProtectionMessage(
            title: template.title.replacingOccurrences(of: "{firstName}", with: name),
            subtitle: template.subtitle.replacingOccurrences(of: "{firstName}", with: name)
        )
    }
}

private let protectionMessages: [ProtectionMessage] = [
    ProtectionMessage(
        title: "Protecting Drink",
        subtitle: "SipBuddy is monitoring for tampering"
    ),
    ProtectionMessage(
        title: "Keeping an eye on your drink, {firstName} 😉",
        subtitle: "SipBuddy has you covered"
    ),
    // Add more messages here as needed:
    // ProtectionMessage(
    //     title: "Your drink is safe, {firstName}",
    //     subtitle: "Relax and enjoy your night"
    // ),
]

// MARK: - Protecting Drink View
private struct ProtectingView: View {
    let firstName: String?
    
    @State private var ringScale: CGFloat = 0.8
    @State private var shimmer = false
    @State private var currentMessage: ProtectionMessage?
    
    var body: some View {
        let message = currentMessage ?? protectionMessages[0]
        
        VStack(spacing: 16) {
            ZStack {
                // Outer glow rings
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.green.opacity(0.1 - Double(i) * 0.03))
                        .frame(width: 120 + CGFloat(i) * 40, height: 120 + CGFloat(i) * 40)
                        .scaleEffect(ringScale)
                }
                
                // Shield icon with gradient
                Image(systemName: "shield.checkered")
                    .font(.system(size: 56, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                    .shadow(color: .green.opacity(0.4), radius: 12)
                
                // Shimmer overlay
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.2), .clear],
                            startPoint: shimmer ? .topLeading : .bottomTrailing,
                            endPoint: shimmer ? .bottomTrailing : .topLeading
                        )
                    )
                    .frame(width: 100, height: 100)
            }
            
            Text(message.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.green)
                .multilineTextAlignment(.center)
            
            Text(message.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear {
            // Randomly select a protection message
            if let randomTemplate = protectionMessages.randomElement() {
                currentMessage = ProtectionMessage.resolve(randomTemplate, firstName: firstName)
            }
            
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                ringScale = 1.1
            }
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                shimmer.toggle()
            }
        }
    }
}

// MARK: - Sleeping View
private struct SleepingView: View {
    @State private var bounce = false
    
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "zzz")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(y: bounce ? -4 : 4)
            }
            
            Text("Sleeping")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            
            Text("Detection paused")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                bounce = true
            }
        }
    }
}

// MARK: - Legacy Pulsing Dot (kept for compatibility)
private struct PulsingDot: View {
    @State private var scale: CGFloat = 0.8
    var body: some View {
        Circle().fill(Color.green.opacity(0.8))
            .frame(width: 28, height: 28)
            .scaleEffect(scale)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: scale)
            .onAppear { scale = 1.2 }
    }
}

