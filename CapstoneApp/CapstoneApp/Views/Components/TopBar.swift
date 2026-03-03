

////
////  TopBar.swift
////  SipBuddy
////
////

import SwiftUI

struct TopBar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var ble: BLEManager

    var body: some View {
        HStack {
            // Hamburger → Experiments menu
            Button { app.showExperiments.toggle() } label: {
                Image(systemName: "line.3.horizontal")
                    .imageScale(.large)
            }
            .padding(.trailing, 8)
            .sheet(isPresented: $app.showExperiments) { ExperimentsMenuView() }

            Spacer()
            Text("SipBuddy")
                .font(.headline)
            Spacer()

            // Status pill (tap → Connection menu)
            Button { app.showDevicePicker = true } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(ble.isConnected ? Color.green : Color.red)
                        .frame(width: 12, height: 12)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .imageScale(.medium)
                }
                .contentShape(Rectangle()) // easier tap target
            }
            .sheet(isPresented: $app.showDevicePicker) { DevicePickerView() }

            // DISABLED: Battery indicator temporarily hidden
            // if let pct = ble.batteryPercent {
            //     HStack(spacing: 4) {
            //         ZStack(alignment: .topTrailing) {
            //             BatteryIcon(percent: Double(pct) / 100.0)
            //                 .frame(width: 30, height: 14)
            //
            //             if ble.isCharging == true {
            //                 Image(systemName: "bolt.fill")
            //                     .font(.system(size: 14, weight: .bold))
            //                     .symbolRenderingMode(.palette)
            //                     .foregroundStyle(.yellow, .clear)
            //                     .offset(x: -10, y: -2)
            //             }
            //         }
            //
            //         Text("\(pct)%")
            //             .font(.system(.callout, design: .monospaced))
            //             .foregroundStyle(.secondary)
            //     }
            //     .transition(.opacity.combined(with: .move(edge: .trailing)))
            // }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
}

// MARK: - Dynamic Battery Icon
struct BatteryIcon: View {
    var percent: Double   // 0.0 → 1.0

    var body: some View {
        ZStack(alignment: .leading) {
            // Outline
            Image(systemName: "battery.100")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)

            // Dynamic fill
            GeometryReader { geo in
                Rectangle()
                    .fill(fillColor)
                    .frame(width: geo.size.width * CGFloat(percent),
                           height: geo.size.height)
            }
        }
        .mask(
            Image(systemName: "battery.100")
                .resizable()
                .scaledToFit()
        )
    }

    private var fillColor: Color {
        switch percent {
        case 0.0..<0.2: return .red
        case 0.2..<0.5: return .yellow
        default: return .green
        }
    }
}



