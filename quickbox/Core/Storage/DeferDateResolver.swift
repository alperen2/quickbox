import Foundation

struct DeferDateResolver {
    func resolve(deferDateString: String, from refDate: Date = Date()) -> Date? {
        // Reuse DueDateResolver logic
        return DueDateResolver().resolve(dueDateString: deferDateString, from: refDate)
    }
}
