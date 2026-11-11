import CoreTransferable
import Foundation
import TakaDeCore
import UniformTypeIdentifiers

/// A group's expenses and payments as a .csv file, handed to the share sheet so it can go
/// to Files, Excel, Google Sheets or a chat. The file is written to the app's temporary
/// folder only while sharing.
struct SpreadsheetExport: Transferable {
    let fileName: String
    let text: String

    init(group: ExpenseGroup, expenses: [Expense], settlements: [Settlement]) {
        var labels = LedgerCSV.Labels()
        labels.date = String(localized: "Date", bundle: .appLanguage)
        labels.type = String(localized: "Type", bundle: .appLanguage)
        labels.title = String(localized: "Title", bundle: .appLanguage)
        labels.category = String(localized: "Category", bundle: .appLanguage)
        labels.amount = String(localized: "Amount", bundle: .appLanguage)
        labels.currency = String(localized: "Currency", bundle: .appLanguage)
        labels.paidBy = String(localized: "Paid by", bundle: .appLanguage)
        labels.status = String(localized: "Status", bundle: .appLanguage)
        labels.expense = String(localized: "Expense", bundle: .appLanguage)
        labels.payment = String(localized: "Payment", bundle: .appLanguage)
        text = LedgerCSV.make(group: group, expenses: expenses, settlements: settlements, labels: labels,
                              categoryName: { String(localized: $0.csvLabel, bundle: .appLanguage) },
                              statusName: \.explanation)
        // A file name can't hold slashes or colons; the group's name is otherwise kept.
        let safe = group.name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        fileName = "\(safe.isEmpty ? "TakaDe" : safe).csv"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { export in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(export.fileName)
            // The byte-order mark makes Excel read Bengali names as UTF-8.
            var data = Data([0xEF, 0xBB, 0xBF])
            data.append(Data(export.text.utf8))
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return SentTransferredFile(url)
        }
    }
}

private extension ExpenseCategory {
    var csvLabel: String.LocalizationValue {
        switch self {
        case .food: "Food"
        case .groceries: "Bazar"
        case .transport: "Transport"
        case .stay: "Stay"
        case .rent: "Rent"
        case .utilities: "Bills"
        case .shopping: "Shopping"
        case .fun: "Fun"
        case .health: "Health"
        case .other: "Other"
        }
    }
}
