//
//  HomeView.swift
//  SipBuddy
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var ble: BLEManager

    @EnvironmentObject var telemetry: TelemetryManager

    @State private var showConnectSheet = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider()

            // Content Window
            ZStack {
                if !ble.isConnected {
                    VStack(spacing: 16) {
                        Image(systemName: "bolt.horizontal.circle").font(.system(size: 64))
                        Text("Please Connect Device").font(.title2).bold()
                        Text("Tap Connect to choose your SipBuddy device.")
                        Button { showConnectSheet = true } label: {
                            Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .sheet(isPresented: $showConnectSheet) { DevicePickerView() }
                } else {
                    switch app.mode {
                    case .idle:
                        VStack(spacing: 12) {
                            Text("Connected!").font(.title2).bold()
                            Text("Click any button to begin.")
                        }
                    case .sleeping:
                        VStack(spacing: 12) {
                            Image(systemName: "zzz").font(.system(size: 52))
                            Text("Sleeping").font(.title2).bold()
                        }
                    case .detecting:
                        VStack(spacing: 12) {
                            PulsingDot()
                            Text("Protecting Drink").font(.title2).bold().foregroundColor(.green)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))

            // Buttons (selected = blue + borderedProminent, unselected = gray + bordered)
            HStack(spacing: 16) {
                let sleepSelected = app.mode == .sleeping
                let detectSelected = app.mode == .detecting
                let isConnected = ble.isConnected // Check BLE connection

                // SLEEP
                if sleepSelected {
                    Button {
                        app.mode = .sleeping
                        ble.sendSleep()
//                      //  telemetry.startModeSession(newMode: .sleep)// You clicked the SLEEP button while in detect.. this is not a mode **change**
                    } label: {
                        Label("Sleep", systemImage: "moon")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!isConnected) // Disable if not connected
                } else {
                    Button {
                        guard ble.isConnected else { return } // Safety check
                        app.mode = .sleeping
                        ble.sendSleep() // Signal SipBuddy to sleep mode (.sendSleep method automatically uses the mode TX)
                        telemetry.startModeSession(newMode: .sleep)

                    } label: {
                        Label("Sleep", systemImage: "moon")
                    }
                    .buttonStyle(.bordered)
                    .tint(isConnected ? .gray : .gray.opacity(0.3)) // Dim when disconnected
                    .disabled(!isConnected) // Disable if not connected
                }

                // DETECT
                if detectSelected {
                    Button {
                        app.mode = .detecting
                        
                        // Send telemetry on mode change
//                        //telemetry.startModeSession(newMode: .detect) // You clicked the DETECT button while in detect.. this is not a mode **change**

                        // Show a bottom toast once BUF header comes in (as you had)
                        NotificationCenter.default.addObserver(
                            forName: .didStartIncident, object: nil, queue: .main
                        ) { _ in
                            withAnimation {
                                app.bottomNotice = AppState.BottomNotice(
                                    title: "Incident detected",
                                    message: "Frames are arriving… View in Incidents.",
                                    actionTitle: "View"
                                ) {
                                    app.tab = .incidents
                                    app.bottomNotice = nil
                                }
                            }
                        }
                        ble.sendDetect() // Signal SipBuddy to detect mode (.sendDetect method automatically uses the mode TX)
                    } label: {
                        Label("Detect", systemImage: "shield.checkerboard")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!isConnected) // Disable if not connected
                } else {
                    Button {
                        guard ble.isConnected else { return } // Safety check
                        app.mode = .detecting
                        // Send telemetry on mode change
                        telemetry.startModeSession(newMode: .detect)
                        NotificationCenter.default.addObserver(
                            forName: .didStartIncident, object: nil, queue: .main
                        ) { _ in
                            withAnimation {
                                app.bottomNotice = AppState.BottomNotice(
                                    title: "Incident detected",
                                    message: "Frames are arriving… View in Incidents.",
                                    actionTitle: "View"
                                ) {
                                    app.tab = .incidents
                                    app.bottomNotice = nil
                                }
                            }
                        }
                        ble.sendDetect()
                    } label: {
                        Label("Detect", systemImage: "shield.checkerboard")
                    }
                    .buttonStyle(.bordered)
                    .tint(isConnected ? .gray : .gray.opacity(0.3)) // Dim when disconnected
                    .disabled(!isConnected) // Disable if not connected
                }
            }
            .padding()
        }
        .onAppear {
            // Initialize ML system and log capabilities
            _ = MLInferenceManager.shared
        }
    }
}

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
