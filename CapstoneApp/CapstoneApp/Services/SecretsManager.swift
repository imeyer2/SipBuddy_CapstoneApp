//
//  SecretsManager.swift
//  SipBuddy
//
//  Loads runtime secrets from Secrets.plist (git-ignored).
//  Never commit real keys — use Secrets.example.plist as the template.
//

import Foundation

enum SecretsManager {

    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            fatalError("⚠️  Secrets.plist not found in app bundle. Copy Secrets.example.plist → Secrets.plist and add it to your target's Copy Bundle Resources.")
        }
        return dict
    }()

    /// PostHog project API key
    static var postHogAPIKey: String {
        secrets["POSTHOG_API_KEY"] as? String ?? ""
    }

    /// PostHog ingestion host
    static var postHogHost: String {
        secrets["POSTHOG_HOST"] as? String ?? "https://us.i.posthog.com"
    }

    /// Azure telemetry backend base URL
    static var telemetryBaseURL: URL {
        let str = secrets["TELEMETRY_BASE_URL"] as? String ?? ""
        return URL(string: str)!
    }

    /// API key sent to the telemetry backend
    static var telemetryAPIKey: String {
        secrets["TELEMETRY_API_KEY"] as? String ?? ""
    }
}
