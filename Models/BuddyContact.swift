//
//  BuddyContact.swift
//  SipBuddy
//
//


import Foundation

struct BuddyContact: Identifiable, Codable, Equatable {
    enum DeliveryMode: String, Codable, CaseIterable {
        case autoSend    // send via server without prompting the user
        case askFirst    // show a toast; user taps to send via Messages
    }

    let id: UUID
    var name: String
    var phone: String
    var mode: DeliveryMode = .askFirst   // NEW: default for existing entries

    init(id: UUID = UUID(), name: String, phone: String, mode: DeliveryMode = .askFirst) {
        self.id = id
        self.name = name
        self.phone = phone
        self.mode = mode
    }
}



final class BuddyStore: ObservableObject {
    @Published var contacts: [BuddyContact] = [] { didSet { save() } }
    @Published var autoSendViaServer: Bool = false { didSet { save() } }
    @Published var webhookURL: String = "" { didSet { save() } }

    private let key = "SB.buddyStore.v1"
    
    
    
    init() { load() }


    private struct Snapshot: Codable {
        var contacts: [BuddyContact]
        var autoSendViaServer: Bool
        var webhookURL: String
    }
    


    private func save() {
        let snap = Snapshot(contacts: contacts, autoSendViaServer: autoSendViaServer, webhookURL: webhookURL)
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        contacts = snap.contacts
        autoSendViaServer = snap.autoSendViaServer
        webhookURL = snap.webhookURL
    }
}
