import SwiftUI

struct NotchTabButton: View {
    let tab: AppTab
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            Label(tab.title, systemImage: tab.systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(isSelected ? Color.onLime : Color.onHeader.opacity(0.7))
                .offset(y: isSelected ? -18 : 0)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
