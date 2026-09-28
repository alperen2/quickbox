import Foundation

/// User-facing product names. Keep every visible mention of the product here, so a future
/// rename is a one-line change. Internal identifiers (bundle IDs, defaults keys, log
/// subsystems) intentionally keep the original `quickbox` spelling.
nonisolated enum Brand {
    static let name = "Pigeon"
    static let cloudName = "Pigeon Cloud"
}
