//
//  CapstoneAppTests.swift
//  CapstoneAppTests
//
//

import Foundation
import XCTest
@testable import CapstoneApp

@MainActor
final class CapstoneAppTests: XCTestCase {

    // MARK: - Helpers
    private func clearBLEUserDefaults() {
        let ud = UserDefaults.standard
        if let id = Bundle.main.bundleIdentifier {
            ud.removePersistentDomain(forName: id)
        } else {
            ud.removeObject(forKey: "SipBuddy.knownDevices")
            ud.removeObject(forKey: "SipBuddy.autoConnectEnabled")
            ud.removeObject(forKey: "SipBuddy.lastConnectedDevice")
        }
        ud.synchronize()
    }

    // MARK: - KnownDevice codable round-trip
    func testKnownDeviceCodableRoundTrip() throws {
        let original = KnownDevice(id: UUID(), name: "TestBuddy", lastConnected: Date())
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KnownDevice.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - BLEManager known devices: load + sort
    func testBLEManagerLoadsAndSortsKnownDevices() throws {
        clearBLEUserDefaults()

        // Seed UserDefaults with two devices out of order
        let older = KnownDevice(id: UUID(), name: "OlderBuddy", lastConnected: Date(timeIntervalSinceNow: 9_000_000))
        let newer = KnownDevice(id: UUID(), name: "NewerBuddy", lastConnected: Date(timeIntervalSinceNow: 10_000_000))
        let seeded = [older, newer]
        let data = try JSONEncoder().encode(seeded)
        UserDefaults.standard.set(data, forKey: "SipBuddy.knownDevices")
        UserDefaults.standard.synchronize()

        // Instantiate a fresh manager; it loads known devices in init()
        let manager = BLEManager()

        // Expect our seeded entries to be present and ordered first
        let names = manager.knownDevices.map { $0.name }
        XCTAssertTrue(names.contains("NewerBuddy"))
        XCTAssertTrue(names.contains("OlderBuddy"))
        if names.count >= 2 {
            let firstTwo = Array(names.prefix(2))
            XCTAssertEqual(firstTwo, ["NewerBuddy", "OlderBuddy"])
        }
        clearBLEUserDefaults()
    }

    // MARK: - BLEManager isKnownDevice/removeKnownDevice
    func testBLEManagerKnownDeviceLookupAndRemoval() throws {
        clearBLEUserDefaults()

        // Seed one known device
        let device = KnownDevice(id: UUID(), name: "SeedBuddy", lastConnected: Date())
        let data = try JSONEncoder().encode([device])
        UserDefaults.standard.set(data, forKey: "SipBuddy.knownDevices")

        let manager = BLEManager()
        XCTAssertTrue(manager.isKnownDevice(device.id))

        // Remove it and expect it gone
        manager.removeKnownDevice(device.id)
        XCTAssertFalse(manager.isKnownDevice(device.id))
        clearBLEUserDefaults()
    }

    // MARK: - autoConnectEnabled persistence
    func testAutoConnectEnabledPersists() {
        clearBLEUserDefaults()

        let manager = BLEManager()
        // Default should be true when unset
        XCTAssertEqual(manager.autoConnectEnabled, true)

        // Flip to false and verify it's stored
        manager.autoConnectEnabled = false
        let stored = UserDefaults.standard.object(forKey: "SipBuddy.autoConnectEnabled") as? Bool
        XCTAssertEqual(stored, false)

        // Flip back to true
        manager.autoConnectEnabled = true
        let stored2 = UserDefaults.standard.object(forKey: "SipBuddy.autoConnectEnabled") as? Bool
        XCTAssertEqual(stored2, true)
        clearBLEUserDefaults()
    }

    // MARK: - Notification names exist (light sanity)
    func testNotificationNamesExist() {
        XCTAssertEqual(Notification.Name.didStartIncident.rawValue, "SB.didStartIncident")
        XCTAssertEqual(Notification.Name.forceDefaultDetect.rawValue, "SB.forceDefaultDetect")
    }
}
