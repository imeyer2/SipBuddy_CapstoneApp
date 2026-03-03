//
//  FeedbackView.swift
//  SipBuddy
//

//

import SwiftUI

struct FeedbackView: View {
    // Free-text input
    @State private var message: String = ""

    // Mail / Share
    @EnvironmentObject var telemetry: TelemetryManager
    @EnvironmentObject var authManager: AuthStateManager
    @EnvironmentObject var app: AppState
    @State private var showingSentConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            // (Optional) Thin top divider to match app chrome
            Divider()

            Form {
                Section(header: Text("Tell us anything")) {
                    TextEditorWithPlaceholder(
                        text: $message,
                        placeholder: "Type your feedback, questions, or notes here…"
                    )
                    .frame(minHeight: 200)
                }

                Section {
                    Button {
                        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }

                        // Send to telemetry backend
                        telemetry.sendFeedback(comments: trimmed) { ok in
                            DispatchQueue.main.async {
                                if ok {
                                    // clear message after successful send
                                    message = ""
                                    // show bottom toast via shared AppState
                                    app.bottomNotice = AppState.BottomNotice(
                                        title: "Feedback sent!",
                                        message: "Thanks — we've received your feedback.",
                                        actionTitle: "OK",
                                        action: { app.bottomNotice = nil }
                                    )
                                } else {
                                    // fallback alert if desired — reuse showingSentConfirmation for simplicity
                                    showingSentConfirmation = false
                                }
                            }
                        }
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            PostHogService.shared.screen("Feedback")
        }
        .toolbar {
            // Done button above keyboard
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { dismissKeyboard() }
            }
        }
        // Use AppState.bottomNotice to show transient confirmation (handled in RootView)
    }

    // MARK: - Helper to dismiss keyboard
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    // MARK: - Export (plain text)
    private func exportText() -> URL {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileText = """
        # SipBuddy Feedback
        # Timestamp: \(Date().isoStamp)

        \(trimmed)
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SipBuddy_Feedback_\(Date().isoStamp).txt")
        try? fileText.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }
}

// MARK: - Minimal placeholder TextEditor

private struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    var placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
            }
            TextEditor(text: $text)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
        }
    }
}

// Mail/Share helpers removed — feedback now sends directly to telemetry and shows an in-app toast.

// MARK: - Utilities

private extension Date {
    var isoStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: self)
    }
}
