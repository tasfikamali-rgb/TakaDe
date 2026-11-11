import SwiftUI

/// The small handle at the top of the content sheet, so it reads as a physical layer.
struct SheetGrabber: View {
    var body: some View {
        Capsule()
            .fill(Color.ink.opacity(0.15))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
