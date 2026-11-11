import SwiftUI

struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(AppFont.label)
            .foregroundStyle(Color.owe)
            .padding(Spacing.s)
            .frame(maxWidth: .infinity)
            .background(Color.oweTint)
    }
}
