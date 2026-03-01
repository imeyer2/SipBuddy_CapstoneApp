 
import Foundation
import CoreLocation
import SwiftUI


// MARK: - Incident Object
struct Incident: Identifiable, Hashable {
    let id: UUID // unique identifier for each incident
    var startedAt: Date // when the incident started (first frame received)
    var location: CLLocation? // optional GPS location of the incident (can be nil if unavailable)
    var width: Int // width of the video frames (will be given to us from SipBuddy device, this is a sponsor requirement)
    var height: Int // height of the video frames (will be given to us from SipBuddy device, this is a sponsor requirement)
    var expectedFrames: Int
    // friendly location name (business/park)
    var placeName: String? = nil
    
    
    // Progressive payload
    var framesPNG: [Data] = [] // append in order; animated on demand
    var isComplete: Bool { framesPNG.count >= expectedFrames && expectedFrames > 0 } // computed property. Will be re-evaluated at each time you access isComplete

    // Derived preview
    var previewImage: UIImage? {
        guard let first = framesPNG.first, let img = UIImage(data: first) else { return nil }
        return img
    }
}


// MARK: - Incident Store to hold all Incidents
final class IncidentStore: ObservableObject {
    @Published private(set) var incidents: [Incident] = []

    // MARK: - Persistence (binary Property List)
    private var archiveURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        // e.g. .../Application Support/incidents.plist ??
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("incidents.plist")
    }

    // Convert incident to disk savable to persist
    private struct DiskIncident: Codable {
        var id: UUID
        var startedAt: Date
        var width: Int
        var height: Int
        var expectedFrames: Int
        var placeName: String?
        var locLat: Double?
        var locLon: Double?
        var framesPNG: [Data]   // stored directly; easy + robust MVP
    }

    // MARK: - Initilize the parent classes
    init() { loadFromDisk() }

    // MARK: - Public API (unchanged behavior, now auto-saves)
    func startIncident(width: Int, height: Int, expected: Int, location: CLLocation?) -> Incident {
        var inc = Incident(
            id: UUID(),
            startedAt: Date(),
            location: location,
            width: width,
            height: height,
            expectedFrames: expected
        )
        // When reloading later, gating should treat old items as openable
        inc.lastFrameAt = inc.startedAt
        incidents.insert(inc, at: 0)
        saveToDisk()
        return inc
    }
    
    
    // Appends a frame to the most recent Incident
    // by adding a PNG to the Incident object's `framesPNG` attriute
    //    Parameters
    //    -------------------
    //      id : UUID - UUID of the incident to add data to
    //      jpeg : Data - a frame of data to add
    func appendFrame(to id: UUID, png: Data) {
        // Find the index in the `incidents` attribute of this class (which is an array)
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        var inc = incidents[idx] // fetch the incident corresponding to the provided id
        
        let wasComplete = inc.isComplete // Compute if the incident is complete or not
        
        inc.framesPNG.append(png) // Add new frame
        
        inc.lastFrameAt = Date() // Update the incident's last update time
        incidents[idx] = inc // Update the incident in the incidents list
        saveToDisk()

        // Since frame count and last update time are updated, check if Incident is done
        if !wasComplete && inc.isComplete {
            NotificationCenter.default.post(name: .incidentCompleted, object: nil, userInfo: ["id": inc.id])
        }
    }
    
    

    func delete(at offsets: IndexSet) {
        incidents.remove(atOffsets: offsets)
        saveToDisk()
    }

    func delete(ids: Set<UUID>) {
        incidents.removeAll { ids.contains($0.id) }
        saveToDisk()
    }

    func deleteAll() {
        incidents.removeAll()
        saveToDisk()
    }

    func setPlaceName(for id: UUID, name: String?) {
        guard let idx = incidents.firstIndex(where: { $0.id == id }) else { return }
        var inc = incidents[idx]
        inc.placeName = name
        incidents[idx] = inc
        saveToDisk()
    }

    // MARK: - Encode/Decode
    
    // Hopefully this works? 
    private func saveToDisk() {
        let disk: [DiskIncident] = incidents.map { inc in
            DiskIncident(
                id: inc.id,
                startedAt: inc.startedAt,
                width: inc.width,
                height: inc.height,
                expectedFrames: inc.expectedFrames,
                placeName: inc.placeName,
                locLat: inc.location?.coordinate.latitude,
                locLon: inc.location?.coordinate.longitude,
                framesPNG: inc.framesPNG
            )
        }
        do {
            let enc = PropertyListEncoder()
            enc.outputFormat = .binary
            let data = try enc.encode(disk)
            try data.write(to: archiveURL, options: .atomic)
        } catch {
//            print("[IncidentStore] save error:", error)
            Log.e("[ERROR]: Save error \(error)")
        }
    }

    
    
    // When called, pull incidents from iOS's disk
    // and display them in the application
    private func loadFromDisk() {
        do {
            let data = try Data(contentsOf: archiveURL)
            let dec = PropertyListDecoder()
            let disk = try dec.decode([DiskIncident].self, from: data)
            let restored: [Incident] = disk.map { d in
                var loc: CLLocation? = nil
                if let lat = d.locLat, let lon = d.locLon {
                    loc = CLLocation(latitude: lat, longitude: lon)
                }
                var inc = Incident(
                    id: d.id,
                    startedAt: d.startedAt,
                    location: loc,
                    width: d.width,
                    height: d.height,
                    expectedFrames: d.expectedFrames,
                    placeName: d.placeName,
                    framesPNG: d.framesPNG
                )
                // Reasonable default so gating treats reloaded clips as openable
                inc.lastFrameAt = max(d.startedAt, d.startedAt.addingTimeInterval(1))
                return inc
            }
            incidents = restored
        } catch {
            // First run or no file yet is fine
            incidents = []
        }
    }
}






import CoreBluetooth

// Approximate distance estimate from RSSI using a simple path-loss model.
// txPower1m defaults to -59 dBm (typical beacon), pathLossExp=2 (indoor).
func estimatedMeters(fromRSSI rssi: Int, txPower1m: Int = -59, pathLossExp: Double = 2.0) -> Double {
    let ratio = Double(txPower1m - rssi) / (10.0 * pathLossExp)
    return pow(10.0, ratio)
}

enum ProximityBand: String, CaseIterable {
    case immediate, near, far
    static func from(meters d: Double) -> ProximityBand {
        if d < 1.5 { return .immediate }     // ~0–1.5 m
        if d < 5.0 { return .near }          // ~1.5–5 m
        return .far                           // 5 m+
    }
}

struct SipNearby: Identifiable {
    let id = UUID()
    let name: String
    let rssi: Int
    var meters: Double {
        estimatedMeters(fromRSSI: rssi)
    }
    var band: ProximityBand {
        .from(meters: meters)
    }
}










import Foundation
import CoreLocation
import SwiftUI

// MARK: - Helpers for display + gating
extension Incident {
/// Last time a frame arrived (updated by IncidentStore.appendFrame)
    var lastFrameAt: Date? {
        get { _lastFrameAt }
        set { _lastFrameAt = newValue }
    }

    /// Estimated seconds remaining based on average inter‑arrival time so far.
    /// If no frames yet, returns nil (UI will show “Estimating…”).
    func estimatedRemainingSeconds(now: Date = .now) -> Int? {
        guard expectedFrames > 0 else { return nil }
        let received = framesPNG.count
        let remaining = max(0, expectedFrames - received)
        guard remaining > 0 else { return 0 }

        // Average frame time = (lastFrameAt - startedAt) / received
        guard received > 0, let last = lastFrameAt else { return nil }
        let avg = last.timeIntervalSince(startedAt) / Double(received)
        return Int((avg * Double(remaining)).rounded())
    }

    /// True when the clip is complete OR no new frames have arrived in 10s
    func isReadyToOpen(now: Date = .now) -> Bool {
        if isComplete { return true }
        guard let last = lastFrameAt else { return false }
        return now.timeIntervalSince(last) >= 10
    }

    /// Human readable mm:ss for the remaining estimate
    func mmss(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var formattedDateTime: String {
        let df = DateFormatter()
        df.locale = .current
        df.dateFormat = "h:mm a, d MMM yyyy"
        return df.string(from: startedAt)
    }

    /// One‑liner for location if available
    var formattedLocation: String {
        if let name = placeName, !name.isEmpty { return name }
        if let loc = location {
            return String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude)
        }
        
        return "Unknown location"
    }
}

// Backing storage for lastFrameAt without changing your public API elsewhere.
private enum _IncidentLastFrameKey { static var key = "_lastFrameAt" }
private extension Incident {
    // Stored property shim via associated object‑like pattern using Mirror fallback
    // In your real project, prefer adding `var lastFrameAt: Date?` directly to the struct.
    var _lastFrameAt: Date? {
        get { _lastFrameMap[id] }
        set { _lastFrameMap[id] = newValue }
    }
}

private var _lastFrameMap: [UUID: Date] = [:]

// MARK: - Store hooks
extension IncidentStore {
    /// Call this from your existing appendFrame to also update lastFrameAt.
    func appendFrameUpdatingTimestamp(to id: UUID, png: Data) {
        appendFrame(to: id, png: png) // your existing behavior
        if let idx = incidents.firstIndex(where: { $0.id == id }) {
            var inc = incidents[idx]
            inc.lastFrameAt = Date()
            incidents[idx] = inc
        }
    }
}
