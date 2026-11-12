import SwiftUI
import TakaDeCore

/// A chat with one friend. Messages show the moment they're typed and are sent in the
/// background; one that couldn't be sent says so and can be tried again. While the friend
/// types, "typing…" shows under the last message.
struct ChatView: View {
    @Environment(SocialModel.self) private var social
    @Environment(AccountModel.self) private var account
    @Environment(\.dismiss) private var dismiss
    let friendID: UUID

    @State private var messages: [FriendMessage] = []
    @State private var draft = ""
    @State private var confirmingBlock = false
    @State private var confirmingRemove = false
    @State private var error: String?
    @FocusState private var composing: Bool

    private var friend: Friend? { social.people.first { $0.id == friendID } }
    private var myName: String { account.profile?.displayName ?? "" }
    private static let bottom = "bottom"

    var body: some View {
        Group {
            if let friend {
                chat(with: friend)
            } else {
                ContentUnavailableView("This chat was removed", systemImage: "bubble.left.and.bubble.right")
            }
        }
        .texturedBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: social.revision) {
            messages = await social.messages(with: friendID)
            await social.markRead(friendID)
        }
        .onAppear {
            social.openChat = friendID
            if let friend { social.openTyping(with: friend) }
        }
        .onDisappear {
            if social.openChat == friendID { social.openChat = nil }
            if let friend { social.closeTyping(with: friend) }
        }
    }

    private func chat(with friend: Friend) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.xxs) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if startsNewDay(at: index) {
                            Text(message.at, format: .dateTime.weekday(.wide).day().month())
                                .font(AppFont.caption)
                                .foregroundStyle(Color.inkMuted)
                                .padding(.top, Spacing.m)
                                .padding(.bottom, Spacing.xxs)
                        }
                        MessageBubble(message: message, friendName: friend.displayName, showsTime: showsTime(at: index)) {
                            Task { await social.retry(message, to: friend, myName: myName) }
                        }
                    }
                    if social.typing.contains(friend.id) {
                        TypingBubble(name: friend.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id(Self.bottom)
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.s)
                .readableWidth()
                .animation(Motion.standard, value: social.typing.contains(friend.id))
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: social.typing.contains(friend.id)) { proxy.scrollTo(Self.bottom, anchor: .bottom) }
            .onChange(of: composing) {
                if composing { withAnimation(Motion.standard) { proxy.scrollTo(Self.bottom, anchor: .bottom) } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if friend.status == .request { requestBar(for: friend) }
                    if let error = error ?? (messages.last?.state == .failed ? social.sendProblem : nil) {
                        Text(verbatim: error)
                            .font(AppFont.label)
                            .foregroundStyle(Color.owe)
                            .padding(.horizontal, Spacing.screenMargin)
                            .padding(.top, Spacing.xs)
                    }
                    if friend.status != .blocked { composer(for: friend) }
                }
                .background(Color.canvas.ignoresSafeArea())
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: Spacing.xs) {
                    Avatar(name: friend.name, size: 30, photo: FriendPhotos.image(for: friend.id))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: friend.displayName)
                            .font(AppFont.bodyEmphasis)
                            .lineLimit(1)
                        Group {
                            if social.typing.contains(friend.id) {
                                Text("typing…")
                            } else {
                                Text(verbatim: friend.code.description).monospaced()
                            }
                        }
                        .font(AppFont.caption)
                        .foregroundStyle(Color.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("Copy TakaDe ID", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = friend.code.description
                    }
                    Button("Block", systemImage: "hand.raised", role: .destructive) { confirmingBlock = true }
                    Button("Remove from Social", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                }
            }
        }
        .confirmationDialog(Text("Block \(friend.displayName)?"), isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) { block(friend) }
        } message: {
            Text("Their messages stop reaching you. They aren't told. You can unblock them in Social.")
        }
        .confirmationDialog(Text("Remove from Social?"), isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task {
                    await social.remove(friend)
                    dismiss()
                }
            }
        } message: {
            Text("\(friend.displayName) and your chat are removed from this phone. If they write again, it shows as a request.")
        }
    }

    private func requestBar(for friend: Friend) -> some View {
        HStack(spacing: Spacing.s) {
            Text("\(friend.displayName) isn't in your friends yet.")
                .font(AppFont.label)
                .foregroundStyle(Color.inkMuted)
            Spacer(minLength: Spacing.xs)
            Button("Accept") { Task { await social.accept(friend) } }
                .buttonStyle(.borderedProminent)
                .tint(Color.lime)
                .foregroundStyle(Color.onLime)
            Button("Block", role: .destructive) { confirmingBlock = true }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.s)
        .readableWidth()
    }

    private func composer(for friend: Friend) -> some View {
        HStack(alignment: .bottom, spacing: Spacing.xs) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(AppFont.body)
                .focused($composing)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, 10)
                .background(Capsule(style: .continuous).fill(Color.surface))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.ink.opacity(0.08), lineWidth: 1))
                .onChange(of: draft) {
                    if draft.isEmpty { social.stoppedTyping(in: friend) } else { social.userTyped(in: friend) }
                }
                .onSubmit { send(to: friend) }
            Button {
                send(to: friend)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.onLime)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.lime))
            }
            .buttonStyle(PressScaleButtonStyle())
            .disabled(FriendMessage.cleaned(draft) == nil)
            .opacity(FriendMessage.cleaned(draft) == nil ? 0.4 : 1)
            .accessibilityLabel(Text("Send"))
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.xs)
        .readableWidth()
    }

    private func send(to friend: Friend) {
        guard FriendMessage.cleaned(draft) != nil else { return }
        let text = draft
        draft = ""
        Task {
            // Writing back to someone who wrote first accepts them.
            if friend.status == .request { await social.accept(friend) }
            await social.send(text, to: friend, myName: myName)
        }
    }

    private func block(_ friend: Friend) {
        Task {
            do {
                try await social.block(friend)
                error = nil
                dismiss()
            } catch {
                self.error = Friends.Failure.message(for: error)
            }
        }
    }

    private func startsNewDay(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].at, inSameDayAs: messages[index - 1].at)
    }

    /// The time shows under the last message of a run: before a gap of 5 minutes, a change
    /// of who's writing, or the end.
    private func showsTime(at index: Int) -> Bool {
        guard index + 1 < messages.count else { return true }
        let next = messages[index + 1]
        return next.direction != messages[index].direction || next.at.timeIntervalSince(messages[index].at) > 300
    }
}

private struct MessageBubble: View {
    let message: FriendMessage
    let friendName: String
    let showsTime: Bool
    let retry: () -> Void

    private var isMine: Bool { message.direction == .outgoing }

    var body: some View {
        if message.direction == .notice {
            Label {
                Text(verbatim: message.text)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(AppFont.caption)
            .foregroundStyle(Color.inkMuted)
            .multilineTextAlignment(.center)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
        } else {
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                Text(verbatim: message.text)
                    .font(AppFont.body)
                    .foregroundStyle(isMine ? Color.onLime : Color.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(isMine ? Color.lime : Color.surface)
                    )
                    .opacity(message.state == .sending ? 0.7 : 1)
                if message.state == .failed {
                    Button(action: retry) {
                        Label("Not sent. Tap to try again.", systemImage: "exclamationmark.circle")
                            .font(AppFont.caption)
                            .foregroundStyle(Color.owe)
                    }
                    .buttonStyle(.plain)
                } else if showsTime {
                    HStack(spacing: 4) {
                        Text(message.at, format: .dateTime.hour().minute())
                        if isMine { stateText }
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(Color.inkMuted)
                    .padding(.bottom, Spacing.xs)
                }
            }
            .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
            .padding(isMine ? Edge.Set.leading : Edge.Set.trailing, Spacing.huge)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isMine ? Text("You: \(message.text)") : Text("\(friendName): \(message.text)"))
        }
    }

    @ViewBuilder private var stateText: some View {
        switch message.state {
        case .sending: Text("· Sending…")
        case .sent: Text("· Sent")
        default: EmptyView()
        }
    }
}

/// Three dots that rise in turn while the friend types. With Reduce Motion they stay still.
private struct TypingBubble: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Dot(index: index, animates: !reduceMotion)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.surface))
        .accessibilityElement()
        .accessibilityLabel(Text("\(name) is typing"))
    }

    private struct Dot: View {
        let index: Int
        let animates: Bool

        var body: some View {
            if animates {
                Circle()
                    .fill(Color.inkMuted)
                    .frame(width: 7, height: 7)
                    .phaseAnimator([false, true]) { dot, up in
                        dot.offset(y: up ? -3 : 0).opacity(up ? 1 : 0.45)
                    } animation: { _ in
                        .easeInOut(duration: 0.45).delay(Double(index) * 0.15)
                    }
            } else {
                Circle().fill(Color.inkMuted).frame(width: 7, height: 7)
            }
        }
    }
}
