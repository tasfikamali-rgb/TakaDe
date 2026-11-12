import SwiftUI
import TakaDeCore

/// The header for a group (DESIGN.md section 2, optional group tint): lilac, or a soft
/// tint of the main colour in the group's cover photo. The cover, when there is one, runs
/// across the top; the round icon comes from the group's name and can't be changed by hand.
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
        VStack(alignment: .leading, spacing: 0) {
            if let photo {
                // Facebook-style: the cover runs edge to edge, the icon overlaps its bottom edge.
                GroupPhotoPicker(hasPhoto: true, onPick: setPhoto, onRemove: removePhoto) {
                    GroupCoverImage(photo: photo)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Cover photo"))
                .accessibilityHint(Text("Change or remove the cover photo"))
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                HStack(alignment: .bottom, spacing: Spacing.s) {
                    GroupIconBadge(name: group.name, size: 64, fill: .surface, ring: tint)
                    Spacer(minLength: Spacing.xs)
                    if photo == nil {
                        GroupPhotoPicker(hasPhoto: false, onPick: setPhoto, onRemove: removePhoto) {
                            Label("Add cover photo", systemImage: "photo")
                        }
                        .buttonStyle(HeaderPillButtonStyle(filled: false, fill: .ink, text: tint))
                    }
                }
                .padding(.top, photo == nil ? 0 : -32)
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
                        AmountText(money: myNet.magnitude, size: .balance, color: .ink, minorColor: .inkMuted)
                    }
                }
                Button("Add expense", systemImage: "plus", action: onAddExpense)
                    .buttonStyle(HeaderPillButtonStyle(filled: true, fill: .ink, text: tint))
                    .padding(.top, Spacing.xs)
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, photo == nil ? Spacing.m : 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
