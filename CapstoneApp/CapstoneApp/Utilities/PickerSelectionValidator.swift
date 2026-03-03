// PickerSelectionValidator.swift
// Utility to globally validate Picker selections and auto-correct invalid/nil values

import SwiftUI

/// Protocol for types that can validate their Picker selection
protocol PickerSelectionValidatable {
    mutating func validatePickerSelections()
}

/// Example global validator for AppState or any ObservableObject
extension ObservableObject {
    func validateAllPickerSelections() {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if var validatable = child.value as? PickerSelectionValidatable {
                validatable.validatePickerSelections()
            }
        }
    }
}

/// Example usage in your App's main view:
/// .onAppear { appState.validateAllPickerSelections() }
/// .onChange(of: any relevant state) { _ in appState.validateAllPickerSelections() }

// To use globally, conform your models (e.g., BuddyContact, AppState, etc.) to PickerSelectionValidatable
// and implement the validatePickerSelections() method to ensure all Picker selection properties are valid.
