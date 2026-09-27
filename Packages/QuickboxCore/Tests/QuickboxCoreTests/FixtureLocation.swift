import Foundation

/// Resolves files in the repository-level `fixtures/` folder shared with non-Swift implementations.
enum FixtureLocation {
    static func url(named name: String) -> URL {
        // Packages/QuickboxCore/Tests/QuickboxCoreTests/<this file> -> repository root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("fixtures")
            .appendingPathComponent(name)
    }
}
