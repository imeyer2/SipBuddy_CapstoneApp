//
//  SecretsManager.swift
//  SipBuddy
//
//  Loads sensitive keys from Secrets.plist (which is git-ignored).
//  Never commit Secrets.plist to source control.
//

import Foundation

enum SecretsManager {
    
    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            fatalError("⚠️ Secrets.plist not found. Copy Secrets.example.plist → Secrets.plist and fill in your keys.")
        }
        return dict
    }()
    
    static func value(forKey key: String) -> String {
        guard let value = secrets[key] as? String, !value.isEmpty else {
            fatalError("⚠️ Missing or empty key '\(key)' in Secrets.plist")
        }
        return value
    }
    
    // MARK: - Convenience accessors
    
    static var postHogAPIKey: String { value(forKey: "POSTHOG_API_KEY") }
    static var postHogHost: String   { value(forKey: "POSTHOG_HOST") }
    static var telemetryBaseURL: URL {
        guard let url = URL(string: value(forKey: "TELEMETRY_BASE_URL")) else {
            fatalError("⚠️ Invalid TELEMETRY_BASE_URL in Secrets.plist")
        }
        return url
    }
    static var telemetryAPIKey: String { value(forKey: "TELEMETRY_API_KEY") }
}
