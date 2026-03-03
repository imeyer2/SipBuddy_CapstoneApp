import SwiftUI

// Tutorial removed: placeholder view to satisfy any legacy references
struct TutorialView: View {
    @Binding var isShowing: Bool
    let targetRects: [String: CGRect]
    let onHighlightChanged: (String?) -> Void

    var body: some View {
        // Immediately dismiss if ever presented
        EmptyView()
            .onAppear {
                isShowing = false
                onHighlightChanged(nil)
            }
    }
}

