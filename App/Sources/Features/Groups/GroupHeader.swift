import SwiftUI
import TakaDeCore

/// The header for a group (DESIGN.md section 2, optional group tint): lilac, or a soft
/// tint of the main colour in the group's photo.
struct GroupHeader<Status: View>: View {
    @Environment(AppModel.self) private var app
    let group: ExpenseGroup
    /// Nil while loading, so the header doesn't flash "Settled up".
    let myNet: Money?
    let onAddExpense: () -> Void
    /// For a shared group, whether everything has reached the other phones.
    @ViewBuilder var status: () -> Status

    @State private var photo: UIImage?
    @State private var photoError: String?

    private var tint: Color { GroupTint.color(for: group) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            GroupPhotoPicker(hasPhoto: photo != nil, onPick: setPhoto, onRemove: removePhoto) {
                HStack(spacing: Spacing.s) {
                    GroupPhotoBadge(group: group, photo: photo, size: photo == nil ? 32 : 64, ring: tint)
                    if photo == nil {
                        Label("Add photo", systemImage: "camera")
                            .font(AppFont.label)
                            .foregroundStyle(Color.ink)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(photo == nil ? Text("Add a group photo") : Text("Group photo"))
            if let photoError {
                Text(verbatim: photoError).font(AppFont.caption).foregroundStyle(Color.owe)
            }
            Text(verbatim: group.name)
                .font(AppFont.title)
                .tracking(-0.005 * 28)
                .foregroundStyle(Color.ink)
            status()
            if let myNet {
                let state = BalanceState(myNet)
                Text(state.label)
                    .font(AppFont.label)
                    .foregroundStyle(Color.ink.opacity(0.72))
                    .padding(.top, Spacing.xs)
                if state != .settled {
                    AmountText(money: myNet.magnitude, size: .balance, color: .ink, minorColor: .ink.opacity(0.6))
                }
            }
            Button("Add expense", systemImage: "plus", action: onAddExpense)
                .buttonStyle(HeaderPillButtonStyle(filled: true, fill: .ink, text: tint))
                .padding(.top, Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.m)
        .padding(.bottom, Spacing.huge + Radius.sheet)
        .background(tint)
        .task(id: app.revision) { photo = GroupPhotoFile.load(group.id) }
    }

    private func setPhoto(_ data: Data) {
        Task {
            do {
                try await app.setGroupPhoto(data, for: group)
                photoError = nil
            } catch {
                photoError = String(localized: "That photo couldn't be used. Try another one.", bundle: .appLanguage)
            }
        }
    }

    private func removePhoto() {
        Task { try? await app.removeGroupPhoto(for: group) }
    }
}
