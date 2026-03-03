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
            List {

                // DevicePickerView.swift — add this Section above the "Discovered" section
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
                }
                

                
                Section("Discovered") {
                    // Use the freshest advertising name
                    let sipOnly = ble.discovered.filter {
                        let n = ble.advertisedName[$0.identifier] ?? $0.name ?? ""
                        return n.localizedCaseInsensitiveContains("sip")
                    }

                    if sipOnly.isEmpty {
                        Text("No Sip* devices found yet.")
                            .foregroundColor(.secondary)
                    }

                    ForEach(sipOnly, id: \.identifier) { p in
                        let displayName = ble.advertisedName[p.identifier] ?? p.name ?? "Unknown"
                        Button { ble.connect(p); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(displayName).font(.headline)
                                    Text(p.identifier.uuidString).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                        }
                    }
                }
                
                
                
                
                
                
                
                
            }
            .navigationTitle("Connect SipBuddy")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { ble.startScanning(filter: "Sip") }
            .onDisappear { ble.stopScanning() }
        }
    }
}
