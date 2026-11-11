import Foundation

/// A suggestion extracted from receipt text. Untrusted: the user must review it before
/// anything is saved (CLAUDE.md, OCR boundary).
public struct ReceiptSuggestion: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public var merchant: String?
    public var total: Money?
    public var date: Date?
    /// Every amount found, largest first, so the user can pick another if the total is wrong.
    public var candidateAmounts: [Money]
    /// 0...1. Low when no line was clearly labelled as the total.
    public var confidence: Double
    /// Priced lines above the subtotal, in receipt order.
    public var items: [ReceiptLine] = []
    /// Subtotal, VAT or tax, service charge and discount lines, in receipt order.
    public var charges: [ReceiptLine] = []

    /// The lines' own sum: the subtotal (or the items when there's none) plus tax and
    /// service charge, minus discounts. Nil when the receipt had no priced lines.
    public var computedTotal: Money? {
        var sum: Int64
        if let subtotal = charges.first(where: { $0.kind == .subtotal }) {
            sum = subtotal.amount.minorUnits
        } else if !items.isEmpty {
            sum = items.reduce(Int64(0)) { $0 + $1.amount.minorUnits }
        } else {
            return nil
        }
        for line in charges {
            switch line.kind {
            case .tax, .serviceCharge: sum += line.amount.minorUnits
            case .discount: sum -= line.amount.minorUnits
            case .item, .subtotal: break
            }
        }
        return Money(minorUnits: sum, currency: currencyOfLines)
    }

    private var currencyOfLines: Currency { (items.first ?? charges.first)?.amount.currency ?? .bdt }
}

/// One priced line read from a receipt. Discounts are stored as positive amounts.
public struct ReceiptLine: Equatable, Sendable, Identifiable {
    public enum Kind: Sendable, Equatable { case item, subtotal, tax, serviceCharge, discount }
    public let id = UUID()
    public var label: String
    public var amount: Money
    public var kind: Kind

    public init(label: String, amount: Money, kind: Kind) {
        self.label = label
        self.amount = amount
        self.kind = kind
    }

    public static func == (lhs: ReceiptLine, rhs: ReceiptLine) -> Bool {
        lhs.label == rhs.label && lhs.amount == rhs.amount && lhs.kind == rhs.kind
    }
}

/// Turns recognized text lines (from on-device OCR) into a suggestion.
public enum ReceiptParser {
    static let totalKeywords = ["grand total", "net total", "total payable", "amount payable", "net payable", "total", "মোট", "সর্বমোট"]
    static let excludeKeywords = ["subtotal", "sub total", "sub-total", "vat", "tax", "discount", "change", "cash", "tendered", "service charge", "ভ্যাট"]
    static let subtotalKeywords = ["subtotal", "sub total", "sub-total", "উপমোট"]
    static let taxKeywords = ["vat", "tax", "ভ্যাট", "sd "]
    static let serviceKeywords = ["service charge", "svc", "service", "সার্ভিস চার্জ"]
    static let discountKeywords = ["discount", "disc.", "less", "ছাড়"]
    /// Lines that carry numbers but aren't something bought.
    static let notItemKeywords = ["date", "time", "tel", "phone", "mobile", "invoice", "bill no", "order", "token", "table", "bin", "vat reg", "mushak", "qty", "rate", "price", "amount", "paid", "cash", "card", "bkash", "nagad", "change", "tendered", "due", "balance", "round", "total", "মোট"]

    public static func parse(lines rawLines: [String], currency: Currency = .bdt) -> ReceiptSuggestion {
        let lines = rawLines.map { Digits.toLatin($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        var labelledTotal: Money?
        var labelledRank = Int.max
        var all: [Money] = []

        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            let amounts = amountsIn(line, currency: currency)
            all.append(contentsOf: amounts)

            guard !excludeKeywords.contains(where: { lower.contains($0) }) else { continue }
            if let rank = totalKeywords.firstIndex(where: { lower.contains($0) }) {
                // The amount may be on the same line or the next one.
                let amount = amounts.last ?? (index + 1 < lines.count ? amountsIn(lines[index + 1], currency: currency).last : nil)
                if let amount, rank <= labelledRank {
                    labelledTotal = amount
                    labelledRank = rank
                }
            }
        }

        let (items, charges) = lineBreakdown(lines, currency: currency)
        var suggestion = ReceiptSuggestion(
            merchant: merchant(in: lines),
            total: nil,
            date: date(in: lines),
            candidateAmounts: [],
            confidence: 0,
            items: items,
            charges: charges
        )
        // With no labelled total, the priced lines' sum beats the largest number.
        let computed = labelledTotal == nil && items.count >= 2 ? suggestion.computedTotal : nil
        if let computed, computed.minorUnits > 0 { all.append(computed) }
        let candidates = Array(Set(all)).sorted { $0.minorUnits > $1.minorUnits }
        suggestion.candidateAmounts = candidates
        if let labelledTotal {
            suggestion.total = labelledTotal
            suggestion.confidence = 0.8
        } else if let computed, computed.minorUnits > 0 {
            suggestion.total = computed
            suggestion.confidence = 0.5
        } else {
            suggestion.total = candidates.first
            suggestion.confidence = candidates.isEmpty ? 0 : 0.3
        }
        return suggestion
    }

    /// Items are priced lines before the first subtotal, tax or total line. Charges are
    /// the subtotal, tax, service and discount lines. Payment lines (cash, change) are left out.
    static func lineBreakdown(_ lines: [String], currency: Currency) -> (items: [ReceiptLine], charges: [ReceiptLine]) {
        var items: [ReceiptLine] = []
        var charges: [ReceiptLine] = []
        var pastItems = false
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if let kind = chargeKind(lower) {
                // A discount may be written "-50.00"; read it as 50.
                let text = kind == .discount ? line.replacingOccurrences(of: "-", with: " ") : line
                // A heading like "Tax Invoice" has no amount and doesn't end the items.
                guard let amount = amountsIn(text, currency: currency).last, !amount.isZero else { continue }
                pastItems = true
                charges.append(ReceiptLine(label: label(of: line), amount: amount, kind: kind))
                continue
            }
            if totalKeywords.contains(where: { lower.contains($0) }) { pastItems = true }
            // The first line is the shop's name.
            guard !pastItems, index >= 1,
                  !notItemKeywords.contains(where: { startsWord(lower, $0) }),
                  let amount = amountsIn(line, currency: currency).last, !amount.isZero
            else { continue }
            let name = label(of: line)
            guard name.contains(where: { $0.isLetter }) else { continue }
            items.append(ReceiptLine(label: name, amount: amount, kind: .item))
        }
        return (items, charges)
    }

    static func chargeKind(_ lower: String) -> ReceiptLine.Kind? {
        if subtotalKeywords.contains(where: { lower.contains($0) }) { return .subtotal }
        if serviceKeywords.contains(where: { startsWord(lower, $0) }) { return .serviceCharge }
        if taxKeywords.contains(where: { startsWord(lower, $0) }), !lower.contains("vat reg"), !lower.contains("incl") { return .tax }
        if discountKeywords.contains(where: { startsWord(lower, $0) }) { return .discount }
        return nil
    }

    /// True when a word in the line starts with the keyword, so "table" matches
    /// "Table 4" but not "Vegetable".
    static func startsWord(_ lower: String, _ keyword: String) -> Bool {
        lower.hasPrefix(keyword) || lower.contains(" " + keyword)
    }

    /// The words of a line without its numbers, quantity marks or currency signs.
    static func label(of line: String) -> String {
        let noise: Set<String> = ["x", "@", "tk", "tk.", "bdt", "৳", "-", ":", "="]
        let words = line.split(whereSeparator: \.isWhitespace).filter { word in
            let w = word.lowercased()
            if noise.contains(w) { return false }
            // Numbers, prices and quantities like 2x, 5%, 640.00, 1,250.
            return !w.allSatisfy { $0.isNumber || ".,%x@:৳-".contains($0) }
        }
        return words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " :-="))
    }

    /// Amounts like 1,250.00 / 1250 / Tk 450.5 / ৳450. Ignores things that look like
    /// phone numbers, dates or long ids.
    static func amountsIn(_ line: String, currency: Currency) -> [Money] {
        let pattern = #"(?<![\d/:\-])(\d{1,3}(?:,\d{2,3})+|\d{1,7})(?:\.(\d{1,2}))?(?![\d/:\-%])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range, in: line) else { return nil }
            let text = String(line[r])
            // Plain integers under 10 are usually quantities, not prices.
            if !text.contains("."), !text.contains(","), let v = Int(text), v < 10 { return nil }
            return try? Money.parse(text, currency: currency)
        }
    }

    static func merchant(in lines: [String]) -> String? {
        // First line with letters that isn't a header like "invoice" or a phone/address line.
        let skip = ["invoice", "receipt", "bill", "tel", "phone", "mobile", "vat reg", "bin", "date", "www", "http"]
        return lines.prefix(5).first { line in
            let lower = line.lowercased()
            return line.contains(where: \.isLetter) && line.count >= 3 && !skip.contains(where: { lower.hasPrefix($0) || lower.contains($0 + ":") })
        }
    }

    static func date(in lines: [String]) -> Date? {
        let pattern = #"(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let m = regex.firstMatch(in: line, range: range),
                  let d = Range(m.range(at: 1), in: line).flatMap({ Int(line[$0]) }),
                  let mo = Range(m.range(at: 2), in: line).flatMap({ Int(line[$0]) }),
                  var y = Range(m.range(at: 3), in: line).flatMap({ Int(line[$0]) })
            else { continue }
            if y < 100 { y += 2000 }
            // Bangladesh writes dates day first.
            var components = DateComponents()
            components.day = d; components.month = mo; components.year = y
            guard (1...12).contains(mo), (1...31).contains(d) else { continue }
            if let date = Calendar(identifier: .gregorian).date(from: components) { return date }
        }
        return nil
    }
}
