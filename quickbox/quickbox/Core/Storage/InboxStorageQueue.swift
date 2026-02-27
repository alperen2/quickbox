import Foundation

enum InboxStorageQueue {
    static let shared = DispatchQueue(label: "quickbox.inbox-storage")
}
