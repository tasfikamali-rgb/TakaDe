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
}

/// Turns recognized text lines (from on-device OCR) into a suggestion.
public enum ReceiptParser {
    static let totalKeywords = ["grand total", "net total", "total payable", "amount payable", "net payable", "total", "মোট", "সর্বমোট"]
    static let excludeKeywords = ["subtotal", "sub total", "sub-total", "vat", "tax", "discount", "change", "cash", "tendered", "service charge", "ভ্যাট"]

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

        let candidates = Array(Set(all)).sorted { $0.minorUnits > $1.minorUnits }
        let total = labelledTotal ?? candidates.first
        return ReceiptSuggestion(
            merchant: merchant(in: lines),
            total: total,
            date: date(in: lines),
            candidateAmounts: candidates,
            confidence: labelledTotal != nil ? 0.8 : (total != nil ? 0.3 : 0)
        )
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
