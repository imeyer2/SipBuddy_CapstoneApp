//
//  BLEManager.swift
//  SipBuddy
//
//


import Foundation
import CoreBluetooth
import Combine
import UIKit
import CoreLocation   // 👈 add this for CLLocation

final class BLEManager: NSObject, ObservableObject {
    static let shared = BLEManager()

    // Public state
    @Published private(set) var isPoweredOn = false
    @Published private(set) var isConnected = false
    @Published private(set) var deviceName: String?
    @Published private(set) var discovered: [CBPeripheral] = []
    @Published var advertisedName: [UUID: String] = [:]
    @Published var lastRSSI: [UUID: Int] = [:]
    

    
    // Weak reference to telemetry manager
    weak var telemetry: TelemetryManager?

    // Incident handling
    @Published var incidentStore = IncidentStore()
    
    
    
    // MARK: - Battery percentage
    @Published var batteryPercent: Int? = nil {
        didSet {
            guard let pct = batteryPercent else { return }
            onBatteryPercentUpdated(pct)
        }
    }
    @Published var isCharging: Bool? = nil

    // Varaibles related to battery percentage notifications
    private let batteryLowThreshold = 25
    private var batteryLowNotified = false
    

    
    // MARK: - Internal variables
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    
    
    // internal variables for battery percentage mechanism (polling from app to SipBuddy)
    private var pctTimer: DispatchSourceTimer?
    private var pctLineBuffer = Data()
    private var lastPCTAskAt: TimeInterval = 0
    private let pctReplyWindow: TimeInterval = 5.0 // seconds after asking that we accept a bare-int reply
    
    
    
    // NEW: use a dedicated CoreBluetooth queue (not main)
    private let cbQueue = DispatchQueue(label: "ble.central.queue")

    // NEW: brief “keep alive” during transitions
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    // helper to publish on main
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }

    
    // Private BLE variables
    //CBCharacteristic and its subclass CBMutableCharacteristic represent further information about a peripheral’s service. In particular, CBCharacteristic objects represent the characteristics of a remote peripheral’s service. A characteristic contains a single value and any number of descriptors describing that value. The properties of a characteristic determine how you can use a characteristic’s value, and how you access the descriptors.
    private var txText: CBCharacteristic? // CoreBluetoothCharacteristics
    private var txFrame: CBCharacteristic?
    private var rxBasic: CBCharacteristic?
    private var rxCam: CBCharacteristic?
    private var rxMode: CBCharacteristic?
    
    // Camera config to send on connect
    private let cameraConfig = "RGB565,QVGA,60"
    private var camCfgSent = false

    // Streaming parsers for detect-dump pipeline
    private var bufParser = BUFHeaderParser()
    private var fr2 = FR2Assembler()
    private var currentIncidentID: UUID? = nil
    private var expectedCount = 0
    
    
    // Provide current location without coupling BLE to CoreLocation
    var getLocation: (() -> CLLocation?)?
    var resolvePlaceName: ((CLLocation, @escaping (String?) -> Void) -> Void)?   // NEW


    // Backpressure guard for writes
    private var writeQueue = DispatchQueue(label: "ble.write.queue")

    private var nameFilter: String? = nil


    override init() {
        super.init()
        // NEW: restoration + power alert, on cbQueue
        central = CBCentralManager(
            delegate: self,
            queue: cbQueue,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.sipbuddy.central",
                CBCentralManagerOptionShowPowerAlertKey: true
            ]
        )
    }


    // MARK: - Scan/Connect
    func startScanning(filter: String? = nil) {
        nameFilter = filter
        guard isPoweredOn else { return }
        onMain { self.discovered.removeAll() } // ← run on main
        central.scanForPeripherals(
            withServices: [BLEUUIDs.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    func stopScanning() {
        central.stopScan()
    }

    func connect(_ p: CBPeripheral) {
        stopScanning()
        peripheral = p
        p.delegate = self
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    
    // MARK: - Commands (mirror unit test channels)
    func sendSleep() { sendLine("SLEEP") }     // was "SLEEP\n" (double newline bug)
    func sendDetect() {
        // Cancel any pending “default to sleep” if the user explicitly chose Detect
        defaultSleepWorkItem?.cancel()
        sendLine("DETECT")
    }
    func sendStart() { sendLine("START") }
    func sendPing() { sendRaw("PING\n") }

    private func sendLine(_ s: String) { sendRaw(s + "\n") }

    // Timer handle to default to sleep post-connect
    private var defaultSleepWorkItem: DispatchWorkItem?
    
    
    private func sendRaw(_ s: String) {
        guard let data = s.data(using: .utf8) else { return }
        guard let p = peripheral else { return }
        // Prefer RX_MODE (without response), else RX_BASIC (with response)
        if let c = rxMode, c.properties.contains(.writeWithoutResponse) {
            p.writeValue(data, for: c, type: .withoutResponse)
        } else if let c = rxBasic {
            let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(data, for: c, type: type)
        }
    }
    
    // Send a raw string to the basic rtx on the SipBuddy
    private func sendBasicRaw(_ s: String) {
        guard let data = s.data(using: .utf8), let p = peripheral else { return }
        if let c = rxBasic {
            let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(data, for: c, type: type)
        } else if let c = rxMode {
            let type: CBCharacteristicWriteType = c.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            p.writeValue(data, for: c, type: type) // fallback if rxBasic missing
        }
    }
    private func sendBasicLine(_ s: String) { sendBasicRaw(s + "\n") }
    
    
    
    // MARK: - Polling for battery percentages
    private func startPctPolling() {
        stopPctPolling() // idempotent
        let timer = DispatchSource.makeTimerSource(queue: cbQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(3)) // fire now, then every 3s
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.isConnected else { return }
            self.lastPCTAskAt = CFAbsoluteTimeGetCurrent()
            self.sendBasicLine("PCTCHG")
        }
        pctTimer = timer
        timer.resume()
    }

    private func stopPctPolling() {
        pctTimer?.cancel()
        pctTimer = nil
    }
    

    // MARK: - iOS Notification for low SipBuddy battery
    private func onBatteryPercentUpdated(_ pct: Int) {
        // fire once when crossing under 25; reset when back above 30 (hysteresis)
        if !batteryLowNotified && pct < batteryLowThreshold {
            batteryLowNotified = true
            NotificationManager.shared.notifyBatteryLow(percent: pct)
        } else if batteryLowNotified && pct >= 30 {
            batteryLowNotified = false
        }
    }
        
    
    // MARK: - Detect start hook
    private func beginIncident(width: Int, height: Int, count: Int) {
        let loc = getLocation?()
        expectedCount = count

        // Publish on main to update SwiftUI safely
        onMain {
            let inc = self.incidentStore.startIncident(width: width, height: height, expected: count, location: loc)
            self.currentIncidentID = inc.id
            
//            self.telemetry?.recordIncidentStart(
//                imageUUID: inc.id.uuidString,
//                location: loc,
//                placeName: inc.placeName
//            )
            
            
            // NEW: Schedule a local iOS notification only if user is outside the app
            if UIApplication.shared.applicationState != .active {
                NotificationManager.shared.notifyIncidentStarted(id: inc.id, placeName: inc.placeName)
            }
            
            
            if let loc {
                self.resolvePlaceName?(loc) { [weak self] name in
                    self?.incidentStore.setPlaceName(for: inc.id, name: name)
                }
            }

            NotificationCenter.default.post(name: .didStartIncident, object: nil, userInfo: [
                "width": width, "height": height, "count": count
                ]
            )
            
            
        }
    }
    
    

    // MARK: - Frame notify handler
    private func handleFrameChunk(_ data: Data) {
        // First, see if we need to parse BUF header (tolerant)
        if !bufParser.haveHeader {
            let used = bufParser.consume(data)
            if bufParser.haveHeader {
                beginIncident(width: bufParser.width, height: bufParser.height, count: bufParser.count)
            }
            // any trailing bytes (data[used...]) may already contain FR2 bytes
            if used < data.count {
                let rest = data[used...]
                _consumeFR2(Data(rest))
            }
            return
        }
        // Already have BUF header → feed FR2 assembler repeatedly
        _consumeFR2(data)
    }

    private func _consumeFR2(_ data: Data) {
        var offset = 0
        let local = data
        while offset < local.count {
            let used = fr2.consume(local[offset...])
            offset += used
            
            
            // Recieve JPEG and convert to PNG to store
            if fr2.done, let jpegData = fr2.takeJPEG(), let id = currentIncidentID {
                if let img = UIImage(data: jpegData),
                   let pngData = img.pngData() {
                    
                    // Publish converted PNG on main
                    onMain { self.incidentStore.appendFrameUpdatingTimestamp(to: id, png: pngData) }

                    if expectedCount > 0 {
                        onMain {
                            let now = self.incidentStore.incidents.first { $0.id == id }
                            if now?.framesPNG.count == self.expectedCount {
                                // All frames received! Run ML inference
                                Log.d("[BLE] All \(self.expectedCount) frames received for incident \(id)")
                                
                                if let incident = now {
                                    // Run ML model on complete frame sequence
                                    DispatchQueue.global(qos: .userInitiated).async {
                                        MLInferenceManager.shared.analyzeIncident(incident)
                                    }
                                }
                                
                                self.bufParser.reset(); self.fr2.reset()
                                self.currentIncidentID = nil; self.expectedCount = 0
                            }
                        }
                    }
                } else {
                    
//                    print("[DEBUG] Failed to convert JPEG → PNG for incident \(String(describing: currentIncidentID))")
                    Log.d("[DEBUG] Failed to convert JPEG → PNG for incident \(String(describing: currentIncidentID))")
                }
            } else {
                break
            }

        }
    }
    
    // MARK: - Background bridging (optional but helpful)
    func appDidEnterBackground() {
//        print("Entered background")
        Log.d("[DEBUG] App entered background")
        if bgTask == .invalid {
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "BLEStreaming") {
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
        }
        stopPctPolling()       //when app is inactive, stop polling

    }
    func appDidBecomeActive() {
//        print("Entered foreground")
        Log.d("[DEBUG] Entered foreground")
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        startPctPolling()       // when app is active, begin polling

    }
    
    
    
    // MARK: - Send initial camera configuration
    private func sendCameraConfig() {
        guard let p = peripheral else { return }
        guard let data = (cameraConfig + "\n").data(using: .utf8) else { return }

        if let c = rxCam {
            let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
            p.writeValue(data, for: c, type: type)
        } else if let c = rxBasic {
            let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
            p.writeValue(data, for: c, type: type)
        }
    }
    
    
    
}


// MARK: - CBCentralManagerDelegate, CBPeripheralDelegate
extension BLEManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onMain { self.isPoweredOn = (central.state == .poweredOn) }
        if isPoweredOn { startScanning(filter: nameFilter) }
    }

//    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
//        // iOS woke us in the background with prior state
//        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
//            for p in peripherals {
//                self.peripheral = p
//                p.delegate = self
//                if let services = p.services, !services.isEmpty {
//                    for s in services where s.uuid == BLEUUIDs.service {
//                        p.discoverCharacteristics([BLEUUIDs.txText, BLEUUIDs.txFrame, BLEUUIDs.rxBasic, BLEUUIDs.rxCam, BLEUUIDs.rxMode], for: s)
//                    }
//                } else {
//                    p.discoverServices([BLEUUIDs.service])
//                }
//            }
//            let connected = peripherals.contains { $0.state == .connected }
//            onMain { self.isConnected = connected; self.deviceName = peripherals.first?.name }
//            
//            
//            let meta: [String:String] = [
//                "device_name": peripherals.first?.name ?? "SipBuddy",
//                "peripheral_id": peripherals.first?.identifier.uuidString ?? ""
//            ]
//            telemetry?.ensureConnectionSession(meta: meta)
//
//        }
//        
//        
//    }

    
    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
        // iOS woke us with prior state (runs on cbQueue)
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            for p in peripherals {
                self.peripheral = p
                p.delegate = self
                if let services = p.services, !services.isEmpty {
                    for s in services where s.uuid == BLEUUIDs.service {
                        p.discoverCharacteristics([BLEUUIDs.txText, BLEUUIDs.txFrame, BLEUUIDs.rxBasic, BLEUUIDs.rxCam, BLEUUIDs.rxMode], for: s)
                    }
                } else {
                    p.discoverServices([BLEUUIDs.service])
                }
            }
            
            let connected = peripherals.contains { $0.state == .connected }
            onMain {
                self.isConnected = connected
                self.deviceName = peripherals.first?.name
            }
            
            // ✅ Self-heal telemetry session(s) after state restoration
            if connected {
                let first = peripherals.first!
                let meta: [String:String] = [
                    "device_name": first.name ?? "SipBuddy",
                    "peripheral_id": first.identifier.uuidString
                ]
                telemetry?.ensureConnectionSession(meta: meta)
                
                // If you added the provider in the App, this recreates a mode session too:
                if let name = telemetry?.currentModeNameProvider?() {
                    telemetry?.ensureModeSessionIfMissing(newMode: mapAppMode(name))
                }
            }
        }
    }
    
    
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        // Prefer the current advertising local name over peripheral.name (cached)
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let nameForFilter = advName ?? peripheral.name

        if let f = nameFilter,
           let n = nameForFilter,
           !n.lowercased().contains(f.lowercased()) { return }

        onMain {
            // keep freshest name + RSSI
            self.advertisedName[peripheral.identifier] = advName ?? self.advertisedName[peripheral.identifier] ?? peripheral.name
            self.lastRSSI[peripheral.identifier] = RSSI.intValue

            // ensure it’s in the discovered list exactly once
            if !self.discovered.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discovered.append(peripheral)
            }
        }
    }
    
    
    
    
    
    

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onMain {
            self.deviceName = peripheral.name
            self.isConnected = true
            
            // On connect setup metadata and send telemetry
            let meta: [String: String] = [
                "device_name": peripheral.name ?? "SipBuddy",
                "peripheral_id": peripheral.identifier.uuidString
            ]
            self.telemetry?.startConnectionSession(meta: meta)

        }
        startPctPolling()   // <--- add

        peripheral.discoverServices([BLEUUIDs.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        onMain { self.isConnected = false }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onMain {
            self.isConnected = false
            
             
            self.telemetry?.endConnectionSession() // End the connection session

            self.deviceName = nil
            self.batteryPercent = nil   // <--- clear UI state

        }
        stopPctPolling()                // <--- stop

        txText = nil; txFrame = nil; rxBasic = nil; rxCam = nil; rxMode = nil
        bufParser.reset(); fr2.reset(); currentIncidentID = nil; expectedCount = 0
        camCfgSent = false
        startScanning(filter: nameFilter)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let svcs = peripheral.services else { return }
        for s in svcs where s.uuid == BLEUUIDs.service {
            peripheral.discoverCharacteristics([BLEUUIDs.txText, BLEUUIDs.txFrame, BLEUUIDs.rxBasic, BLEUUIDs.rxCam, BLEUUIDs.rxMode], for: s)
        }
    }
    
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let chars = service.characteristics else { return }
        for c in chars {
            switch c.uuid {
            case BLEUUIDs.txText: txText = c; peripheral.setNotifyValue(true, for: c)
            case BLEUUIDs.txFrame: txFrame = c; peripheral.setNotifyValue(true, for: c)
            case BLEUUIDs.rxBasic: rxBasic = c
            case BLEUUIDs.rxCam:   rxCam   = c
            case BLEUUIDs.rxMode:  rxMode  = c
            default: break
            }
        }
        sendPing()
        if !camCfgSent { camCfgSent = true; sendCameraConfig() }

        // ---- NEW: default to Sleep 2s after a fresh connect ----
        defaultSleepWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sendSleep()
            NotificationCenter.default.post(name: .forceDefaultSleep, object: nil)
        }
        defaultSleepWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    
    

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
//        if characteristic.uuid == BLEUUIDs.txText {
//            if let s = String(data: data, encoding: .utf8) { print("[TX_TEXT] \(s.trimmingCharacters(in: .whitespacesAndNewlines))") }
//        }
        if characteristic.uuid == BLEUUIDs.txText {
            if let chunk = characteristic.value {
                
//                print("Received percentage from SipBuddy")
                Log.d("[DEBUG] Received percentage from SipBuddy")
                // Accumulate to line buffer
                pctLineBuffer.append(chunk)
                while let nlRange = pctLineBuffer.firstRange(of: Data([0x0A])) { // '\n'
                    let lineData = pctLineBuffer[..<nlRange.lowerBound]
                    pctLineBuffer.removeSubrange(..<nlRange.upperBound) // drop line + newline
                    if let s = String(data: lineData, encoding: .utf8) {
                        
                        
//                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
//                        // Only accept shortly after PCTCHG? to avoid mis-parsing other messages
//                        let now = CFAbsoluteTimeGetCurrent()
//                        if now - lastPCTAskAt <= pctReplyWindow,
//                           let val = Int(trimmed),
//                           (-10...110).contains(val) {
//                                let clamped = min(100, max(0, val))
//                                onMain { self.batteryPercent = clamped }
//                        }
                        
                        
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        let now = CFAbsoluteTimeGetCurrent()
                        guard now - lastPCTAskAt <= pctReplyWindow else { continue }

                        // New format: "BAT <pct> <chg>"
                        if trimmed.hasPrefix("BAT ") {
                            let parts = trimmed.split(separator: " ")
                            if parts.count >= 3,
                               let pct = Int(parts[1]),
                               let chgInt = Int(parts[2]) {
                                let clamped = min(100, max(0, pct))
                                onMain {
                                    self.batteryPercent = clamped
                                    self.isCharging = (chgInt != 0)
                                }
                                continue
                            }
                        }

                        
                        
                    }
                }
            }
        }
        
        
        else if characteristic.uuid == BLEUUIDs.txFrame {
            handleFrameChunk(data) // stays on cbQueue
        }
    }
}



extension Notification.Name {
    static let didStartIncident = Notification.Name("SB.didStartIncident")
    static let forceDefaultSleep = Notification.Name("SB.forceDefaultSleep")   // NEW
}
