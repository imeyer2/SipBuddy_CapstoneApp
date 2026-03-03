//
//  DevicePickerView.swift
//  SipBuddy
//
//


import SwiftUI
import CoreBluetooth

struct DevicePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        NavigationView {
            ZStack {
                GradientBackground()
                
                List {

                Section("Connection") {
                    if ble.isConnected {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Connected to").font(.subheadline).foregroundColor(.secondary)
                                Text(ble.deviceName ?? "SipBuddy").font(.headline)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                ble.disconnect()   // iPhone side only
                                dismiss()
                            } label: {
                                Label("Disconnect", systemImage: "bolt.horizontal.circle")
                            }
                        }
                    } else {
                        Text("Not connected").foregroundColor(.secondary)
                    }
                    
                    // Auto-connect toggle
                    Toggle("Auto-connect to last known device", isOn: $ble.autoConnectEnabled)
                }
                

                
                // Known SipBuddies section - shows previously connected devices that are currently discovered
                Section("Known SipBuddies") {
                    let knownAndDiscovered = ble.discovered.filter { p in
                        let n = ble.advertisedName[p.identifier] ?? p.name ?? ""
                        return n.localizedCaseInsensitiveContains("sip") && ble.isKnownDevice(p.identifier)
                    }
                    
                    if knownAndDiscovered.isEmpty {
                        Text("No known devices nearby.")
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(knownAndDiscovered, id: \.identifier) { p in
                        let displayName = ble.advertisedName[p.identifier] ?? p.name ?? "Unknown"
                        let rssi = ble.lastRSSI[p.identifier]
                        Button { ble.connect(p); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack {
                                        Text(displayName).font(.headline)
                                        Image(systemName: "star.fill")
                                            .font(.caption)
                                            .foregroundColor(.yellow)
                                    }
                                    Text(p.identifier.uuidString).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let rssi = rssi {
                                    Text("\(rssi) dBm")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                        }
                    }
                }
                
                Section("Other Devices") {
                    // Use the freshest advertising name, exclude known devices
                    let sipOnly = ble.discovered.filter {
                        let n = ble.advertisedName[$0.identifier] ?? $0.name ?? ""
                        return n.localizedCaseInsensitiveContains("sip") && !ble.isKnownDevice($0.identifier)
                    }

                    if sipOnly.isEmpty {
                        Text("No new Sip* devices found yet.")
                            .foregroundColor(.secondary)
                    }

                    ForEach(sipOnly, id: \.identifier) { p in
                        let displayName = ble.advertisedName[p.identifier] ?? p.name ?? "Unknown"
                        let rssi = ble.lastRSSI[p.identifier]
                        Button { ble.connect(p); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(displayName).font(.headline)
                                    Text(p.identifier.uuidString).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if let rssi = rssi {
                                    Text("\(rssi) dBm")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                        }
                    }
                }
                
                Section("Testing") {
                    Button {
                        ble.simulateDummyConnection()
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text("SipBuddy (Demo)").font(.headline)
                                    Image(systemName: "wrench.and.screwdriver")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                Text("Simulated device for testing").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            }
            .navigationTitle("Connect SipBuddy")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                ble.startScanning(filter: "Sip")
                PostHogService.shared.screen("Device Picker")
            }
            .onDisappear {
                if ble.autoConnectEnabled {
                    ble.startBackgroundScanning()
                } else {
                    ble.stopScanning()
                }
            }
        }
    }
}

