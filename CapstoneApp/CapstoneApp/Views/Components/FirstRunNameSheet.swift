//
//  FirstRunNameSheet.swift
//  SipBuddy
//
//


// FirstRunNameSheet.swift
import SwiftUI

struct FirstRunNameSheet: View {
    @ObservedObject var identity: UserIdentityStore
    let onDone: () -> Void        // called after we register

    @State private var first = ""
    @State private var last  = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Tell us who you are") {
                    TextField("First name", text: $first)
                        .textContentType(.givenName)
                        .autocapitalization(.words)
                    TextField("Last name", text: $last)
                        .textContentType(.familyName)
                        .autocapitalization(.words)
                }

                Section {
                    Button {
                        guard !first.trimmingCharacters(in: .whitespaces).isEmpty,
                              !last.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        isSubmitting = true
                        identity.setProfile(first: first, last: last)
                        onDone()
                    } label: {
                        if isSubmitting { ProgressView() } else { Text("Continue") }
                    }
                    .disabled(isSubmitting)
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Welcome to SipBuddy")
        }
    }
}
