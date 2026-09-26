import Foundation

/// Stable, human-typeable task identifiers persisted as an `id:` token on each task line.
///
/// Unlike line indexes, an `id:` survives edits, reordering and concurrent writers
/// (another device or an agent appending to the same file), so mutations can target
/// the right line even after the file has changed.
nonisolated enum TaskIdentifier {
    static let metadataKey = "id"
    static let length = 8

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")

    static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(using: &generator)
    }

    static func generate<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func isValid(_ value: String) -> Bool {
        value.wholeMatch(of: /^[A-Za-z0-9_\-]+$/) != nil
    }
}
