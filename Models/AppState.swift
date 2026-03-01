//// -----------------------------------------------------------------------------
//// FILE: AppState.swift
//// PURPOSE:
////   Central, observable UI state container for the app. Views subscribe to it
////   and re-render when its @Published properties change.
////

import SwiftUI
import Combine

// Consider adding `@MainActor` to guarantee main-thread mutations of @Published props,
// which matches SwiftUI's expectations. Kept as-is for parity with your code.
// @MainActor
final class AppState: ObservableObject {

    // MARK: - App operating modes (simple state machine)
    //
    // Backed by `String` so the value can be persisted in UserDefaults
    // without custom encoding/decoding. Renaming cases will break restore,
    // so prefer adding new cases over renaming existing ones.
    enum Mode: String { case idle, sleeping, detecting }

    // Current mode; persisted to UserDefaults on every change via didSet.
    // NOTE: didSet runs after the new value is set and before the change is published.
    // Keep side effects here small/fast (disk sync is buffered).
    @Published var mode: Mode = .idle {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "SB.mode") }
    }

    // MARK: - UI presentation flags (drive sheets/menus/experiments)
    //
    // Views typically bind these to .sheet(isPresented:) or .confirmationDialog.
    @Published var showDevicePicker = false
    @Published var showExperiments = false

    // A single, optional "bottom notice" (e.g., a toast/sheet) that the UI can present.
    // Setting this non-nil triggers display; setting back to nil dismisses it.
    @Published var bottomNotice: BottomNotice? = nil

    // Drives a badge/dot indicator for new incidents. The tab switcher logic
    // clears this when the user visits the Incidents tab.
    @Published var hasUnseenIncident = false
    // Disable horizontal pager when viewing zoomable incident detail
    @Published var isPagingDisabled = false

    // MARK: - Tab routing
    //
    // The current selected tab. Changing to `.incidents` acts as an acknowledgment
    // and clears the unseen flag. (This is a simple and efficient policy.)
    enum Tab { case home, incidents, feedback }
    @Published var tab: Tab = .home {
        didSet {
            if tab == .incidents { hasUnseenIncident = false }
        }
    }

    // MARK: - Ephemeral "command object" for bottom notices
    //
    // `Identifiable` lets SwiftUI efficiently diff/present/dismiss.
    // The `action` closure is invoked by the UI; be mindful of capture lists
    // (e.g., `[weak self]`) where appropriate to avoid retain cycles beyond the lifetime
    // of the notice.
    struct BottomNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let actionTitle: String
        let action: () -> Void
    }

    // MARK: - Init & persistence restore
    //
    // On startup, restore `mode` from UserDefaults if present. If the stored
    // string no longer maps to a known case, we fall back to `.idle`.
    init() {
        if let raw = UserDefaults.standard.string(forKey: "SB.mode"),
           let m = Mode(rawValue: raw) {
            mode = m
        }
    }
}
