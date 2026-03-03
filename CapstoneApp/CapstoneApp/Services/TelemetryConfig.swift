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
    static let baseURL = SecretsManager.telemetryBaseURL
    static let apiKeyHeader = "x-api-key"
    static let apiKeyValue = SecretsManager.telemetryAPIKey

    // Heartbeat cadence (seconds)
    static let heartbeatSeconds: TimeInterval = 180
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
