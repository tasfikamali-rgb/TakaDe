import Foundation

/// Storage for the device owner's profile and payment details, and the whole-ledger
/// export and erase paths.
public protocol ProfileRepository: Sendable {
    func profile() async throws -> LocalProfile?
    /// Saves the profile and links every "me" member to it.
    func save(_ profile: LocalProfile) async throws

    /// The sign-in methods linked to the TakaDe account, as last read from the service.
    func accountIdentities() async throws -> [AccountIdentity]
    /// Replaces the stored list, after signing in, linking or unlinking.
    func replaceAccountIdentities(_ identities: [AccountIdentity]) async throws

    func paymentHandles(for member: MemberID) async throws -> [PaymentHandle]
    func save(_ handle: PaymentHandle) async throws
    func deletePaymentHandle(_ id: UUID) async throws

    /// Everything stored on this device, for "Export my data".
    func export() async throws -> LedgerExport
    /// Removes every row, history included, and compacts the file so deleted data
    /// doesn't linger in free pages. For "Delete all my data".
    func eraseEverything() async throws
}

/// A full copy of the device's data, written to a file the user chooses where to send.
public struct LedgerExport: Codable, Sendable {
    public struct GroupData: Codable, Sendable {
        public let group: ExpenseGroup
        public let expenses: [Expense]
        public let settlements: [Settlement]
        public let history: [AuditEvent]
        public let paymentHandles: [PaymentHandle]

        public init(group: ExpenseGroup, expenses: [Expense], settlements: [Settlement], history: [AuditEvent], paymentHandles: [PaymentHandle]) {
            self.group = group
            self.expenses = expenses
            self.settlements = settlements
            self.history = history
            self.paymentHandles = paymentHandles
        }
    }

    public let formatVersion: Int
    public let exportedAt: Date
    public let profile: LocalProfile?
    /// Sign-in methods linked to the account. Never tokens.
    public let accountIdentities: [AccountIdentity]?
    public let groups: [GroupData]
    /// Friends from the Social tab and the messages with them, as kept on this phone.
    public let friends: [FriendData]?

    public struct FriendData: Codable, Sendable {
        public let friend: Friend
        public let messages: [FriendMessage]

        public init(friend: Friend, messages: [FriendMessage]) {
            self.friend = friend
            self.messages = messages
        }
    }

    public init(exportedAt: Date = Date(), profile: LocalProfile?, accountIdentities: [AccountIdentity]? = nil, groups: [GroupData],
                friends: [FriendData]? = nil) {
        formatVersion = 1
        self.exportedAt = exportedAt
        self.profile = profile
        self.accountIdentities = accountIdentities
        self.groups = groups
        self.friends = friends
    }
}
