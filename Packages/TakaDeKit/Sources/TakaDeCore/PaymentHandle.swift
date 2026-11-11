import Foundation

/// How a member can be paid: a wallet number or bank details shown to their group so others
/// can copy it when settling. Never a PIN, password or OTP.
public struct PaymentHandle: Hashable, Codable, Sendable, Identifiable {
    public enum Rail: String, Codable, Sendable, CaseIterable {
        case bkash, nagad, rocket, upay, bank

        /// Mobile wallets are paid to an 11-digit Bangladeshi mobile number.
        public var isWallet: Bool { self != .bank }
    }

    public let id: UUID
    public let memberID: MemberID
    public var rail: Rail
    /// Wallet number (Latin digits, 01XXXXXXXXX) or bank details as typed.
    public var handle: String
    public var label: String?
    public let createdAt: Date

    /// Validates and normalizes the handle. Wallet numbers accept Bengali digits, spaces,
    /// dashes and a +88 prefix, and are stored as 01XXXXXXXXX.
    public init(id: UUID = UUID(), memberID: MemberID, rail: Rail, handle: String, label: String? = nil, createdAt: Date = Date()) throws {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String
        if rail.isWallet {
            guard let number = Self.walletNumber(from: trimmed) else { throw PaymentHandleError.invalidWalletNumber }
            normalized = number
        } else {
            guard !trimmed.isEmpty, trimmed.count <= 80 else { throw PaymentHandleError.invalidBankDetails }
            normalized = trimmed
        }
        self.id = id
        self.memberID = memberID
        self.rail = rail
        self.handle = normalized
        self.label = label?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
    }

    /// "01712345678" from "+880 1712-345678", "০১৭১২৩৪৫৬৭৮" and similar; nil if it isn't a BD mobile number.
    public static func walletNumber(from text: String) -> String? {
        var digits = Digits.toLatin(text).filter(\.isNumber)
        if digits.hasPrefix("880") { digits.removeFirst(2) }
        guard digits.count == 11, digits.hasPrefix("01"),
              let third = digits.dropFirst(2).first, "3456789".contains(third) else { return nil }
        return digits
    }
}

public enum PaymentHandleError: Error, Equatable, Sendable {
    case invalidWalletNumber
    case invalidBankDetails
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
