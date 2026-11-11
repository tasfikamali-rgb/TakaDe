import Foundation
import TakaDeCore

struct ActivityItem: Identifiable, Hashable {
    let group: ExpenseGroup
    let expense: Expense
    var id: ExpenseID { expense.id }
}
