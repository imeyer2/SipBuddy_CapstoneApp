//
//  SipMapView.swift
//  SipBuddy
//
//

import SwiftUI
import MapKit
import CoreBluetooth

struct SipMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @EnvironmentObject var ble: BLEManager
    @StateObject private var location = LocationManager()

    // Fixed 200 ft radius ≈ 61 m
    private let radiusMeters: CLLocationDistance = 61.0

    @State private var camera: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var showPrecisionAlert = false

    // Burst-scan state
    @State private var isVisible = false
    @State private var burstTask: Task<Void, Never>? = nil

    // Nearby "Sip*" devices derived from BLEManager.discovered
    private var nearby: [SipNearby] {
        ble.discovered
            .compactMap { item -> SipNearby? in
                // Expecting items that have .name (String?) and .rssi (NSNumber?) — if your BLEManager
                // already normalizes RSSI to Int, this still works by changing the line below.
                let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.localizedCaseInsensitiveContains("sip") else { return nil }

                // NOTE: Using CBPeripheral.rssi (NSNumber?) if your discovered array is [CBPeripheral].
                // This may emit a deprecation warning from Apple’s API. Long-term fix is to store RSSI
                // from didDiscover(_:rssi:) in BLEManager and read it from there.
                let rssiInt = item.rssi?.intValue ?? -100

                return SipNearby(name: name, rssi: rssiInt)
            }
            .sorted { $0.rssi > $1.rssi } // stronger first
    }

    // Count per band
    private var counts: (immediate: Int, near: Int, far: Int) {
        (
            nearby.filter { $0.band == .immediate }.count,
            nearby.filter { $0.band == .near }.count,
            nearby.filter { $0.band == .far }.count
        )
    }

    var body: some View {
        VStack(spacing: 0) {
//            banner

            ZStack {
                mapLayer

                // Ring legend & counts
                VStack {
                    Spacer()
                    legend
                        .padding(8)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.bottom, 8)
                }
            }

            listLayer
        }
        .navigationTitle("SipMap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // If presented over a sheet, let user jump home fast
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    app.tab = .home
                    dismiss()
                } label: {
                    Label("Home", systemImage: "house.fill")
                }
            }
        }
        .onAppear {
            isVisible = true
            // center camera once we have a location
            if let loc = location.lastLocation {
                camera = .region(MKCoordinateRegion(center: loc.coordinate,
                                                    span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)))
            }
            requestPreciseIfNeeded()
            startBurstScan()
        }
        .onDisappear {
            isVisible = false
            burstTask?.cancel()
            burstTask = nil
            ble.stopScanning()
        }
        .alert("Enable Precise Location", isPresented: $showPrecisionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("SipMap works best with precise location enabled in Settings → Privacy & Security → Location Services.")
        }
    }

    private var banner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Features may not work as intended.")
                .font(.footnote)
            Spacer()
        }
        .padding(10)
        .background(.yellow.opacity(0.2))
    }

    @ViewBuilder
    private var mapLayer: some View {
        Map(position: $camera) {
            // User location + 200 ft circle
            UserAnnotation()
            if let coord = location.lastLocation?.coordinate {
                // Big soft area
                MapCircle(center: coord, radius: radiusMeters)
                    .foregroundStyle(.blue.opacity(0.06))  // lighter fill
                    .stroke(.blue.opacity(0.20), lineWidth: 2)

                // Concentric distance rings – ensure NO fill
                MapCircle(center: coord, radius: 1.5)
                    .foregroundStyle(.clear)
                    .stroke(.green.opacity(0.6), lineWidth: 2)

                MapCircle(center: coord, radius: 5.0)
                    .foregroundStyle(.clear)
                    .stroke(.orange.opacity(0.6), lineWidth: 2)

                MapCircle(center: coord, radius: 15.0)
                    .foregroundStyle(.clear)
                    .stroke(.red.opacity(0.6), lineWidth: 2)
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onChange(of: location.lastLocation) { _, newLoc in
            guard let coord = newLoc?.coordinate else { return }
            camera = .region(MKCoordinateRegion(center: coord,
                                                span: MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)))
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().stroke(.green, lineWidth: 2).frame(width: 10, height: 10)
                Text("Immediate (<1.5 m): \(counts.immediate)")
            }
            HStack(spacing: 8) {
                Circle().stroke(.orange, lineWidth: 2).frame(width: 10, height: 10)
                Text("Near (1.5–5 m): \(counts.near)")
            }
            HStack(spacing: 8) {
                Circle().stroke(.red, lineWidth: 2).frame(width: 10, height: 10)
                Text("Far (≥5 m): \(counts.far)")
            }
        }
        .font(.footnote)
    }

    private var listLayer: some View {
        List {
            Section("Nearby Sip devices (RSSI→band)") {
                ForEach(nearby) { dev in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(dev.name).font(.subheadline)
                            Text("\(dev.band.rawValue.capitalized) • ~\(String(format: "%.1f", dev.meters)) m")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(dev.rssi) dBm").font(.caption).foregroundColor(.secondary)
                    }
                }
                if nearby.isEmpty {
                    Text("Scanning…").foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Precision & Burst-scan

    private func requestPreciseIfNeeded() {
        location.ensurePreciseLocation {
            if !location.hasFullAccuracy {
                showPrecisionAlert = true
            }
        }
    }

    private func startBurstScan() {
        burstTask?.cancel()
        burstTask = Task { [weak ble] in
            guard let ble = ble else { return }
            while !Task.isCancelled && isVisible {
                // 1) Scan for "Sip" for 5 seconds (allow duplicates → RSSI refresh)
                ble.startScanning(filter: "Sip")
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                ble.stopScanning()

                // 2) Idle 10 seconds
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
            }
        }
    }
}


























// MARK: - Preview Seeds
extension AppState {
    static var preview: AppState {
        let s = AppState()
        // seed any flags you read in the view
        return s
    }
}

extension BLEManager {
    static var preview: BLEManager {
        let m = BLEManager.shared // or a real instance with scanning disabled
        // seed devices if your map shows them
        // m.discovered = [...]
        return m
    }
}

extension LocationManager {
    static var preview: LocationManager {
        let lm = LocationManager() // provide fixed coords/region
        // lm.region = MKCoordinateRegion( ... )
        return lm
    }
}

// MARK: - A tiny wrapper that injects everything
struct PreviewContainer<Content: View>: View {
    let content: Content
    @StateObject private var appState = AppState.preview
    @StateObject private var ble       = BLEManager.preview
    @StateObject private var loc       = LocationManager.preview

    var body: some View {
        content
            .environmentObject(appState)
            .environmentObject(ble)
            .environmentObject(loc)
    }
}

#Preview("SipMapView") {
    PreviewContainer(content: SipMapView())
}
