//
//  BuddySystemView.swift
//  SipBuddy
//
//


import SwiftUI
import ContactsUI

struct BuddySystemView: View {
    @EnvironmentObject var buddies: BuddyStore
    @State private var showPicker = false
    @State private var showingURLHelp = false

    var body: some View {
        List {
            Section(header: Text("Your Buddy System")) {
                if buddies.contacts.isEmpty {
                    Text("No buddies yet. Tap “Add from Contacts”.")
                        .foregroundStyle(.secondary)
                } else {
//                    ForEach(buddies.contacts) { b in
//                        HStack {
//                            Image(systemName: "person.fill")
//                            VStack(alignment: .leading) {
//                                Text(b.name).bold()
//                                Text(b.phone).font(.caption).foregroundStyle(.secondary)
//                            }
//                        }
//                    }
//                    .onDelete { idx in
//                        buddies.contacts.remove(atOffsets: idx)
//                    }
                    
                    ForEach($buddies.contacts) { b in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "person.fill")
                                VStack(alignment: .leading) {
                                    Text(b.name.wrappedValue).bold()
                                    Text(b.phone.wrappedValue).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            Picker("Delivery", selection: b.mode) {
                                Text("Auto-send").tag(BuddyContact.DeliveryMode.autoSend)
                                Text("Ask first").tag(BuddyContact.DeliveryMode.askFirst)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .onDelete { idx in
                        buddies.contacts.remove(atOffsets: idx)
                    }
                    
                    
                }

                Button {
                    showPicker = true
                } label: {
                    Label("Add from Contacts", systemImage: "person.crop.circle.badge.plus")
                }
            }

            Section(header: Text("Delivery")) {
                Toggle(isOn: $buddies.autoSendViaServer) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-send via server")
                        Text("Requires a webhook (e.g., Twilio) to send texts automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                // buddies.autoSendViaServer is a boolean which is the toggle in "Buddy System" menu
                if buddies.autoSendViaServer {
                    TextField("Webhook URL (POST)", text: $buddies.webhookURL) // any text put in will be put into webhookURL
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)
                    Button("What should the webhook accept?") { showingURLHelp = true }
                        .font(.caption)
                } else {
                    Text("When an incident completes, the app will open the Messages composer pre-filled with your Buddy contacts and the clip; you just tap Send.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle("Buddy System")
        .sheet(isPresented: $showPicker) {
            ContactPickerView { picked in
                // Merge (avoid duplicates by phone)
                let existing = Set(buddies.contacts.map { $0.phone })
                let merged = picked.filter { !existing.contains($0.phone) }
                if !merged.isEmpty { buddies.contacts.append(contentsOf: merged) }
            }
        }
        .alert("Webhook format", isPresented: $showingURLHelp, actions: { Button("OK", role: .cancel) {} }, message: {
            Text("POST JSON: { \"to\":[\"+1408...\"], \"text\":\"message body\", \"media_base64\":\"...\", \"media_type\":\"image/gif\" }")
        })
    }
}

// MARK: - Contacts picker
struct ContactPickerView: View {
    var onPicked: ([BuddyContact]) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var allContacts: [CNContact] = []
    @State private var searchText = ""
    @State private var selectedContacts: Set<String> = []
    @State private var isLoading = true
    
    var filteredContacts: [CNContact] {
        if searchText.isEmpty {
            return allContacts
        }
        return allContacts.filter { contact in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            return name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading contacts...")
                } else if allContacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.slash",
                        description: Text("No contacts available")
                    )
                } else {
                    List(filteredContacts, id: \.identifier, selection: $selectedContacts) { contact in
                        ContactRow(contact: contact, isSelected: selectedContacts.contains(contact.identifier))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleSelection(contact.identifier)
                            }
                    }
                    .searchable(text: $searchText, prompt: "Search contacts")
                }
            }
            .navigationTitle("Add Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedContacts.count))") {
                        addSelectedContacts()
                    }
                    .disabled(selectedContacts.isEmpty)
                }
            }
            .onAppear {
                loadContacts()
            }
        }
    }
    
    private func toggleSelection(_ id: String) {
        if selectedContacts.contains(id) {
            selectedContacts.remove(id)
        } else {
            selectedContacts.insert(id)
        }
    }
    
    private func loadContacts() {
        let store = CNContactStore()
        var keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        keysToFetch.append(CNContactFormatter.descriptorForRequiredKeys(for: .fullName))
        
        store.requestAccess(for: .contacts) { granted, error in
            guard granted else {
                DispatchQueue.main.async {
                    isLoading = false
                }
                return
            }
            
            let request = CNContactFetchRequest(keysToFetch: keysToFetch)
            var contacts: [CNContact] = []
            
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    if !contact.phoneNumbers.isEmpty {
                        contacts.append(contact)
                    }
                }
                DispatchQueue.main.async {
                    allContacts = contacts.sorted { c1, c2 in
                        let name1 = CNContactFormatter.string(from: c1, style: .fullName) ?? ""
                        let name2 = CNContactFormatter.string(from: c2, style: .fullName) ?? ""
                        return name1 < name2
                    }
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
        }
    }
    
    private func addSelectedContacts() {
        let selected = allContacts.filter { selectedContacts.contains($0.identifier) }
        let buddyContacts: [BuddyContact] = selected.compactMap { c in
            let name = CNContactFormatter.string(from: c, style: .fullName) ?? "Unknown"
            let mobile = c.phoneNumbers.first(where: { ($0.label ?? "").lowercased().contains("mobile") }) ?? c.phoneNumbers.first
            guard let phone = mobile?.value.stringValue else { return nil }
            let digits = phone.filter("0123456789+".contains)
            return BuddyContact(name: name, phone: digits)
        }
        onPicked(buddyContacts)
        dismiss()
    }
}

struct ContactRow: View {
    let contact: CNContact
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .gray)
                .imageScale(.large)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(CNContactFormatter.string(from: contact, style: .fullName) ?? "Unknown")
                    .font(.body)
                
                if let phoneNumber = contact.phoneNumbers.first {
                    Text(phoneNumber.value.stringValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
