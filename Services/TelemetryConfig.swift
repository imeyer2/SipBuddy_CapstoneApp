//
//  TelemetryConfig.swift
//  SipBuddy
//
//


// Telemetry.swift
// SipBuddy — client-side telemetry
import Foundation
import Combine
import CoreLocation
import UIKit

// MARK: - Config
enum TelemetryConfig {
    // TODO: set to your Azure URL (no trailing slash), e.g. "https://sipbuddy-api-12345.azurewebsites.net"
    static let baseURL = URL(string: "https://sipbuddy-telemetry.azurewebsites.net")!
    // If you turned on API key on the server, set it here
    static let apiKeyHeader = "x-api-key"
    static let apiKeyValue = "1234567890"

    // Heartbeat cadence (seconds)
    static let heartbeatSeconds: TimeInterval = 180
}

// MARK: - Wire enums
enum ModeWire: String, Codable { case sleep, detect, idle, stream, other }

// Map your AppState.Mode to wire enum
func mapAppMode(_ m: String) -> ModeWire {
    switch m {
    case "sleeping": return .sleep
    case "detecting": return .detect
    case "idle":     return .idle
    default:         return .other
    }
}

// MARK: - Requests
struct RegisterUserReq: Codable {
    let user_uuid: String
    let first_name: String
    let last_name: String
    let email: String?  // Optional for backward compatibility
    let client_ts_utc: Date
}

struct ConnectionEventReq: Codable {
    enum Kind: String, Codable { case connect, disconnect }
    let user_uuid: String
    let connection_session_uuid: String
    let event_type: Kind
    let sipbuddy_metadata: [String: String]?
    let client_ts_utc: Date
}

struct ModeChangeReq: Codable {
    let user_uuid: String
    let connection_session_uuid: String
    let mode_session_uuid: String
    let new_mode_type: ModeWire
    let client_ts_utc: Date
}

struct LocationJSON: Codable {
    let lat: Double
    let lon: Double
    let accuracy_m: Double?
}

struct IncidentReq: Codable {
    let user_uuid: String
    let connection_session_uuid: String
    let mode_session_uuid: String
    let image_uuid: String
    let client_ts_utc: Date
    let location: LocationJSON?
    let media_url: String?
    let extra_metadata: [String: String]?
}

struct HeartbeatReq: Codable {
    let user_uuid: String
    let connection_session_uuid: String
    let mode_session_uuid: String
    let current_mode_type: ModeWire
    let client_ts_utc: Date
}

// MARK: - Client
final class TelemetryClient {
    private let enc: JSONEncoder
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
    }

    
    
    private func postWithStatus<T: Encodable>(_ path: String, _ body: T,
                                              completion: @escaping (Int, Data?) -> Void) {
        
        
        
        // Usage
//        print("[DEBUG] Sending POST request to \(path) with \(jsonDebugString(body))")
        Log.d("[DEBUG] Sending POST request to \(path) with \(jsonDebugString(body))")
        
        
        
        let url = TelemetryConfig.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !TelemetryConfig.apiKeyValue.isEmpty {
            req.setValue(TelemetryConfig.apiKeyValue, forHTTPHeaderField: TelemetryConfig.apiKeyHeader)
        }
        req.httpBody = try? enc.encode(body)
        session.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            completion(code, data)
        }.resume()
    }
    
    
    
    
    
    // Idempotent "ensure user exists" using existing register endpoint
    func ensureUserRegistered(_ body: RegisterUserReq, completion: ((Bool) -> Void)? = nil) {
        postWithStatus("/v1/users/register", body) { code, data in
            // Treat create (201), ok (200), or conflict/duplicate (409/422) as "user is present"
            let ok = (200...299).contains(code) || code == 409 || code == 422
            if !ok {
                if let data, let s = String(data: data, encoding: .utf8) {
//                    print("[Telemetry] ensureUserRegistered failed (\(code)): \(s)")
                    Log.d("[Telemetry] ensureUserRegistered failed (\(code)): \(s)")
                } else {
//                    print("[Telemetry] ensureUserRegistered failed (\(code))")
                    Log.d("[Telemetry] ensureUserRegistered failed (\(code))")
                }
            }
            completion?(ok)
        }
    }
    
    
    
    private func jsonDebugString<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(value)
            return String(data: data, encoding: .utf8) ?? "<non-UTF8 JSON>"
        } catch {
            return "<encode error: \(error)>"
        }
    }
    
//    
//    private func post<T: Encodable>(_ path: String, _ body: T) {
//        
//
//        // Usage
//        print("[DEBUG] Sending POST request to \(path) with \(jsonDebugString(body))")
//        
//        
//        
//        let url = TelemetryConfig.baseURL.appendingPathComponent(path)
//        var req = URLRequest(url: url)
//        req.httpMethod = "POST"
//        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
//        if !TelemetryConfig.apiKeyValue.isEmpty {
//            req.setValue(TelemetryConfig.apiKeyValue, forHTTPHeaderField: TelemetryConfig.apiKeyHeader)
//        }
//        req.httpBody = try? enc.encode(body)
//        session.dataTask(with: req) { _,_,_ in }.resume()
//    }

    // Endpoints
    func register(_ body: RegisterUserReq)        { /* optional now */ }
    func bleEvent(_ body: ConnectionEventReq)     { postWithStatus("/v1/ble/event", body) {_,_ in} }
    func modeChange(_ body: ModeChangeReq)        { postWithStatus("/v1/mode/change", body) {_,_ in} }
    func incident(_ body: IncidentReq)            { postWithStatus("/v1/incident", body) {_,_ in} }
    func heartbeat(_ body: HeartbeatReq)          { postWithStatus("/v1/heartbeat", body) {_,_ in} }
}

// MARK: - Identity
final class UserIdentityStore: ObservableObject {
    @Published private(set) var userUUID: String?
    @Published private(set) var email: String?
    @Published private(set) var firstName: String?
    @Published private(set) var lastName: String?

    private let K_uuid = "SB.user_uuid"
    private let K_email = "SB.user_email"
    private let K_first = "SB.first_name"
    private let K_last  = "SB.last_name"

    init() {
        let ud = UserDefaults.standard
        userUUID  = ud.string(forKey: K_uuid)
        email     = ud.string(forKey: K_email)
        firstName = ud.string(forKey: K_first)
        lastName  = ud.string(forKey: K_last)
    }

    var hasProfile: Bool {
        if let u = userUUID, let f = firstName, let l = lastName,
           !u.isEmpty, !f.isEmpty, !l.isEmpty { return true }
        return false
    }

    /// Set profile from legacy first/last name entry (kept for backwards compatibility)
    func setProfile(first: String, last: String) {
        let ud = UserDefaults.standard
        if userUUID == nil { userUUID = UUID().uuidString; ud.set(userUUID!, forKey: K_uuid) }
        firstName = first; ud.set(first, forKey: K_first)
        lastName  = last;  ud.set(last,  forKey: K_last)
        ud.synchronize()
    }
    
    /// Set profile from Firebase Auth user (NEW - email-based)
    func setProfileFromFirebase(uid: String, email: String, firstName: String?, lastName: String?) {
        let ud = UserDefaults.standard
        
        // Use Firebase UID as the user identifier
        userUUID = uid
        ud.set(uid, forKey: K_uuid)
        
        // Store email
        self.email = email
        ud.set(email, forKey: K_email)
        
        // Store name if provided
        if let first = firstName {
            self.firstName = first
            ud.set(first, forKey: K_first)
        }
        if let last = lastName {
            self.lastName = last
            ud.set(last, forKey: K_last)
        }
        
        ud.synchronize()
        Log.d("[Identity] Profile set from Firebase: \(email)")
    }
    
    /// Get user identifier for telemetry (email-based hash or Firebase UID)
    var telemetryIdentifier: String {
        // Priority: Firebase UID > Email hash > Legacy UUID
        if let uuid = userUUID, !uuid.isEmpty {
            return uuid
        }
        if let email = email, !email.isEmpty {
            return email.data(using: .utf8)?.base64EncodedString() ?? UUID().uuidString
        }
        return UUID().uuidString
    }
}

// MARK: - Telemetry Orchestrator
final class TelemetryManager: ObservableObject {
    @Published private(set) var currentConnectionSessionUUID: String?
    @Published private(set) var currentModeSessionUUID: String?

    let identity: UserIdentityStore
    private let client = TelemetryClient()

    private var heartbeatTimer: Timer?
    
    // NEW: persistence keys
    private let K_conn = "SB.telemetry.conn_uuid"
    private let K_mode = "SB.telemetry.mode_uuid"

    init(identity: UserIdentityStore) {
        self.identity = identity
        // NEW: rehydrate from disk
        let ud = UserDefaults.standard
        currentConnectionSessionUUID = ud.string(forKey: K_conn)
        currentModeSessionUUID       = ud.string(forKey: K_mode)
    }

    // Call after user has provided names
    func registerUserIfReady() {
        guard identity.hasProfile,
              let u = identity.userUUID,
              let f = identity.firstName,
              let l = identity.lastName else { return }
        let req = RegisterUserReq(user_uuid: u, first_name: f, last_name: l, email: identity.email, client_ts_utc: Date())
        client.ensureUserRegistered(req, completion: { ok in
            if ok { Log.d("[DEBUG] user verified/registered with email") }
        })
    }

    // BLE connect
    func startConnectionSession(meta: [String: String]) {
        guard let u = identity.userUUID else { return }
        // If we already have one, don't create a new one (app relaunch case).
        if let existing = currentConnectionSessionUUID {
            // Optionally you could send a lightweight "restore" event here, but not required.
            Log.d("[DEBUG] Reusing existing connection session: \(existing)")
            return
        }
        let conn = UUID().uuidString
        currentConnectionSessionUUID = conn
        // NEW: persist
        UserDefaults.standard.set(conn, forKey: K_conn)

        client.bleEvent(.init(user_uuid: u,
                              connection_session_uuid: conn,
                              event_type: .connect,
                              sipbuddy_metadata: meta,
                              client_ts_utc: Date()))
    }
    

    // BLE disconnect
    func endConnectionSession() {
        guard let u = identity.userUUID,
              let conn = currentConnectionSessionUUID else { return }

        client.bleEvent(.init(user_uuid: u,
                              connection_session_uuid: conn,
                              event_type: .disconnect,
                              sipbuddy_metadata: nil,
                              client_ts_utc: Date()))
        currentConnectionSessionUUID = nil
        currentModeSessionUUID = nil
        // NEW: clear persisted IDs
        let ud = UserDefaults.standard
        ud.removeObject(forKey: K_conn)
        ud.removeObject(forKey: K_mode)
    }

    // Mode change
    /// Starts a new mode session. Call this when the user changes the app mode (sleep/detect).
    /// **IMPORTANT**: Only call when connected to BLE device. Callers should check `ble.isConnected` first.
    func startModeSession(newMode: ModeWire) {
        guard let u = identity.userUUID,
              let conn = currentConnectionSessionUUID else { return }
        // If we already have a mode session, end it implicitly by just rotating the UUID.
        let mode = UUID().uuidString
        currentModeSessionUUID = mode
        // NEW: persist
        UserDefaults.standard.set(mode, forKey: K_mode)

        client.modeChange(.init(user_uuid: u,
                                connection_session_uuid: conn,
                                mode_session_uuid: mode,
                                new_mode_type: newMode,
                                client_ts_utc: Date()))
    }
    
    // NEW: convenience for app/restore flows
    func ensureConnectionSession(meta: [String:String]) {
        if currentConnectionSessionUUID == nil { startConnectionSession(meta: meta) }
    }
    func ensureModeSessionIfMissing(newMode: ModeWire) {
        if currentModeSessionUUID == nil { startModeSession(newMode: newMode) }
    }
    
    

    // Incident (on incident start is fine)
    func recordIncidentStart(imageUUID: String, location: CLLocation?, placeName: String?) {
        guard let u = identity.userUUID,
              let conn = currentConnectionSessionUUID,
              let mode = currentModeSessionUUID else { return }

        var locJSON: LocationJSON? = nil
        if let l = location {
            locJSON = .init(lat: l.coordinate.latitude,
                            lon: l.coordinate.longitude,
                            accuracy_m: l.horizontalAccuracy > 0 ? l.horizontalAccuracy : nil)
        }

        var meta: [String: String] = [:]
        if let name = placeName { meta["place_name"] = name }

        client.incident(.init(
            user_uuid: u,
            connection_session_uuid: conn,
            mode_session_uuid: mode,
            image_uuid: imageUUID,
            client_ts_utc: Date(),
            location: locJSON,
            media_url: nil,                 // you can fill this once you upload media
            extra_metadata: meta.isEmpty ? nil : meta
        ))
    }

    // Heartbeat
    func startHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: TelemetryConfig.heartbeatSeconds, repeats: true) { [weak self] _ in
            self?.sendHeartbeat()
        }
        // fire one immediately
        sendHeartbeat()
    }
    func stopHeartbeat() { heartbeatTimer?.invalidate(); heartbeatTimer = nil }

    private func sendHeartbeat() {
        guard let u = identity.userUUID,
              let conn = currentConnectionSessionUUID,
              let mode = currentModeSessionUUID else { return }
        // mode type best-effort — server uses it to self-heal
        let wire: ModeWire = guessCurrentModeWire()
        client.heartbeat(.init(user_uuid: u,
                               connection_session_uuid: conn,
                               mode_session_uuid: mode,
                               current_mode_type: wire,
                               client_ts_utc: Date()))
    }

    // You can inject the real current mode if you prefer; this fallback lets it compile without tight coupling
    var currentModeNameProvider: (() -> String)? = nil
    private func guessCurrentModeWire() -> ModeWire {
        if let name = currentModeNameProvider?() { return mapAppMode(name) }
        return .other
    }
}


struct SasResponse: Codable {
    let sas_url: String
}


extension TelemetryManager {
    /// Called when an incident is complete to upload clip and update server
    func uploadIncidentMedia(incident: Incident) {
        // Pick GIF if multiple frames, else JPEG
        var fileURL: URL? = nil
        var contentType = "application/octet-stream" // This is required by Azure... we are sending octet-stream?

        
        
        Log.d("[DEBUG] framesPNG count = \(incident.framesPNG.count)")
        if incident.framesPNG.count > 1 {
            if let gif = GIFEncoder.makeGIF(from: incident.framesPNG.compactMap { UIImage(data: $0) }, fps: 30) {
                Log.d("[DEBUG] GIF created successfully with \(incident.framesPNG.count) frames")
            } else {
                Log.e("[DEBUG] GIF creation failed, falling back to PNG")
            }
        } else {
            Log.e("[DEBUG] Only 1 frame, saving PNG")
        }
        
        
        print("[DEBUG] framesPNG count = \(incident.framesPNG.count)")
        if incident.framesPNG.count > 1 {
            let frames = incident.framesPNG.compactMap { UIImage(data: $0) }
            print("[DEBUG] Attempting GIF encode with \(frames.count) frames")
            if let gif = GIFEncoder.makeGIF(from: frames, fps: 30) {
                print("[DEBUG] GIF created successfully, size: \(gif.count) bytes")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(incident.id).gif")
                try? gif.write(to: url)
                fileURL = url
                contentType = "image/gif"
            } else {
                print("[DEBUG] GIF creation failed, falling back to PNG")
            }
        } else if let first = incident.framesPNG.first {
            print("[DEBUG] Only 1 frame, saving as PNG")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("incident_\(incident.id).png")
            try? first.write(to: url)
            fileURL = url
            contentType = "image/png"
        }


        guard let fileURL else { return }

        // 1. Ask backend for SAS URL
        let sasURL = TelemetryConfig.baseURL.appendingPathComponent("v1/incidents/\(incident.id)/sas")
        
        
        URLSession.shared.dataTask(with: sasURL) { data, _, _ in
            guard let data else { return }

            // Decode the JSON into SasResponse
            guard let resp = try? JSONDecoder().decode(SasResponse.self, from: data),
                  let uploadURL = URL(string: resp.sas_url) else {
                print("[DEBUG] Failed to decode SAS response")
                return
            }

            print("[DEBUG] Received SAS token: \(resp.sas_url)")

            

            // 2. Upload to Azure Blob
            var req = URLRequest(url: uploadURL)
            req.httpMethod = "PUT"
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
            req.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")

            if let body = try? Data(contentsOf: fileURL) {
                URLSession.shared.uploadTask(with: req, from: body) { _, resp, _ in
                    let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                    if !(200...299).contains(code) {
                        print("[DEBUG] Blob upload failed, status=\(code)")
                        if let httpResp = resp as? HTTPURLResponse {
                            print("[DEBUG] Headers: \(httpResp.allHeaderFields)")
                        }
                        return
                    }
                    print("[DEBUG] Blob upload success")
                    

                    // 3. Notify backend telemetry with URL
                    if let u = self.identity.userUUID,
                       let conn = self.currentConnectionSessionUUID,
                       let mode = self.currentModeSessionUUID {
                        let cleanURL = uploadURL.absoluteString.components(separatedBy: "?").first!
                        self.client.incident(.init(
                            user_uuid: u,
                            connection_session_uuid: conn,
                            mode_session_uuid: mode,
                            image_uuid: incident.id.uuidString,
                            client_ts_utc: Date(),
                            location: nil,
                            media_url: cleanURL,
                            extra_metadata: nil
                        ))
                    }
                }.resume()
            }
        }.resume()
    }
}



extension TelemetryManager {
    func observeIncidentCompletion(store: IncidentStore) {
        NotificationCenter.default.addObserver(
            forName: .incidentCompleted,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard
                let self,
                let id = note.userInfo?["id"] as? UUID,
                let inc = store.incidents.first(where: { $0.id == id }),
                let u = self.identity.userUUID,
                let conn = self.currentConnectionSessionUUID,
                let mode = self.currentModeSessionUUID
            else { return }

            var locJSON: LocationJSON? = nil
            if let l = inc.location {
                locJSON = .init(lat: l.coordinate.latitude,
                                lon: l.coordinate.longitude,
                                accuracy_m: l.horizontalAccuracy > 0 ? l.horizontalAccuracy : nil)
            }

            var meta: [String: String] = [:]
            if let name = inc.placeName { meta["place_name"] = name }

            self.client.incident(.init(
                user_uuid: u,
                connection_session_uuid: conn,
                mode_session_uuid: mode,
                image_uuid: inc.id.uuidString,
                client_ts_utc: Date(),
                location: locJSON,
                media_url: nil,   // you’ll fill this once blob upload finishes
                extra_metadata: meta.isEmpty ? nil : meta
            ))
        }
    }
}
