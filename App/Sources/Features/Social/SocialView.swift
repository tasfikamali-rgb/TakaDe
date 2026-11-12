import SwiftUI
import TakaDeCore

/// The Social tab: people you've added by TakaDe ID, and your chats with them. Someone who
/// adds you or writes first shows under Requests until you accept.
struct SocialView: View {
    @Environment(SocialModel.self) private var social
    @Environment(AccountModel.self) private var account
    @Environment(AppChrome.self) private var chrome
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path: [UUID] = []
    @State private var adding = false
    @State private var removing: Friend?
    @State private var error: String?
    @State private var refresh = LogoRefreshState()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .texturedBackground()
                .readableWidth()
                .navigationTitle("Social")
                // Inline, like Account: the ৳ refresh sits just under the bar.
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if social.isAvailable {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Add a friend", systemImage: "person.badge.plus") { adding = true }
                        }
                    }
                }
                .navigationDestination(for: UUID.self) { id in
                    ChatView(friendID: id)
                }
        }
        .sheet(isPresented: $adding) {
            AddFriendSheet { id in path = [id] }
                .rebuildsOnDynamicType()
        }
        .alert(Text("Remove from Social?"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
               presenting: removing) { friend in
            Button("Yes", role: .destructive) { Task { await social.remove(friend) } }
            Button("No", role: .cancel) {}
        }
        // Signing in or out changes whose friends these are.
        .task(id: account.profile?.accountID) { await social.start() }
        .onChange(of: path, initial: true) { updateChrome() }
        .onChange(of: horizontalSizeClass) { updateChrome() }
    }

    /// Inside a chat on a phone, the message field takes the bottom edge.
    private func updateChrome() {
        chrome.hidesTabBar = horizontalSizeClass != .regular && !path.isEmpty
    }

    @ViewBuilder private var content: some View {
        if !social.isAvailable {
            ContentUnavailableView {
                Label("Message your friends", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Sign in to your TakaDe account in the Account tab. Then add friends by their TakaDe ID or QR code.")
            }
        } else {
            List {
                if let error {
                    Text(verbatim: error).foregroundStyle(Color.owe)
                        .listRowBackground(Color.surface)
                }
                if !social.requests.isEmpty {
                    Section {
                        ForEach(social.requests) { friend in
                            RequestRow(friend: friend, onError: { error = $0 })
                        }
                        .listRowBackground(Color.surface)
                    } header: {
                        Text("Requests")
                    } footer: {
                        Text("They added you by your TakaDe ID. Accept to keep chatting, or block to stop their messages.")
                    }
                }
                if !social.chats.isEmpty {
                    Section {
                        ForEach(social.chats) { friend in
                            NavigationLink(value: friend.id) {
                                FriendRow(friend: friend, isTyping: social.typing.contains(friend.id))
                            }
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) { removing = friend }
                            }
                        }
                        .listRowBackground(Color.surface)
                    } header: {
                        Text("Friends")
                    } footer: {
                        Text("Messages are encrypted on your phone so only your friend's phone can read them. TakaDe's server sees who writes to whom and when, not what.")
                    }
                }
                if !social.blocked.isEmpty {
                    Section {
                        DisclosureGroup {
                            ForEach(social.blocked) { friend in
                                HStack {
                                    Text(verbatim: friend.displayName)
                                    Spacer()
                                    Button("Unblock") { unblock(friend) }
                                        .buttonStyle(.borderless)
                                }
                            }
                        } label: {
                            Text("Blocked (\(social.blocked.count))")
                        }
                    }
                    .listRowBackground(Color.surface)
                }
            }
            .overlay {
                if social.chats.isEmpty && social.requests.isEmpty {
                    ContentUnavailableView {
                        Label("No friends yet", systemImage: "person.2")
                    } description: {
                        Text("Add a friend with their TakaDe ID or QR code. They'll find yours in their Account tab.")
                    } actions: {
                        Button("Add a friend") { adding = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.lime)
                            .foregroundStyle(Color.onLime)
                    }
                }
            }
            .logoRefreshableList(state: refresh) { await social.fetchInbox() }
        }
    }

    private func unblock(_ friend: Friend) {
        Task {
            do {
                try await social.unblock(friend)
                error = nil
            } catch {
                self.error = Friends.Failure.message(for: error)
            }
        }
    }
}

/// A friend in the list: their name as you typed it, the last message, and how many are new.
private struct FriendRow: View {
    @Environment(SocialModel.self) private var social
    let friend: Friend
    let isTyping: Bool

    var body: some View {
        HStack(spacing: Spacing.s) {
            Avatar(name: friend.name, size: 44, photo: social.photo(for: friend.id))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: friend.displayName)
                        .font(AppFont.bodyEmphasis)
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: Spacing.xs)
                    if let at = friend.lastMessageAt {
                        Text(at, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                            .font(AppFont.caption)
                            .foregroundStyle(Color.inkMuted)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Group {
                        if isTyping {
                            Text("typing…")
                        } else if let preview = friend.lastMessagePreview {
                            Text(verbatim: preview)
                        } else {
                            Text(verbatim: friend.code.description).monospaced()
                        }
                    }
                    .font(AppFont.label)
                    .foregroundStyle(Color.inkMuted)
                    .lineLimit(2)
                    Spacer(minLength: Spacing.xs)
                    if friend.unread > 0 {
                        Text(friend.unread, format: .number)
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(Color.onLime)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.lime))
                    }
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityValue(friend.unread > 0 ? Text("\(friend.unread) unread") : Text(verbatim: ""))
    }
}

/// Someone who added you or wrote first.
private struct RequestRow: View {
    @Environment(SocialModel.self) private var social
    let friend: Friend
    let onError: (String) -> Void
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Avatar(name: friend.name, size: 44, photo: social.photo(for: friend.id))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: friend.displayName)
                        .font(AppFont.bodyEmphasis)
                    Group {
                        if let preview = friend.lastMessagePreview {
                            Text(verbatim: preview)
                        } else {
                            Text("Added you on TakaDe")
                        }
                    }
                        .font(AppFont.label)
                        .foregroundStyle(Color.inkMuted)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Spacing.s) {
                Button("Accept") { Task { await social.accept(friend) } }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.lime)
                    .foregroundStyle(Color.onLime)
                Button("Block", role: .destructive, action: block)
                    .buttonStyle(.bordered)
                    .disabled(working)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }

    private func block() {
        working = true
        Task {
            defer { working = false }
            do {
                try await social.block(friend)
            } catch {
                onError(Friends.Failure.message(for: error))
            }
        }
    }
}
