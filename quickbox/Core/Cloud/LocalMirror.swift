import CryptoKit
import Foundation

/// The storage folder as seen by sync: `.md` files at the root and one folder deep (project
/// folders and `_notes/`), except `_conflicts/`. Every access goes through the storage queue and
/// the security-scoped folder, like the rest of the storage layer.
struct LocalMirror {
    /// System folders start with "_" so they never collide with project folders (see `StorageLayout`).
    static let conflictsFolder = "_conflicts"

    private let storageResolver: StorageResolving

    init(storageResolver: StorageResolving) {
        self.storageResolver = storageResolver
    }

    /// Paths relative to the storage folder, e.g. `2026-09-28.md`, `Marketing/2026-09-28.md` or `_notes/k3f9x2ab.md`.
    func markdownFiles() throws -> [String: String] {
        try withFolder { folder in
            let fileManager = FileManager.default
            let subfolders = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { $0.lastPathComponent != Self.conflictsFolder }

            var files: [String: String] = [:]
            for (directory, prefix) in [(folder, "")] + subfolders.map({ ($0, "\($0.lastPathComponent)/") }) {
                let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                for url in urls where url.pathExtension == "md" {
                    files[prefix + url.lastPathComponent] = try String(contentsOf: url, encoding: .utf8)
                }
            }
            return files
        }
    }

    func read(_ path: String) throws -> String? {
        try withFolder { folder in
            let url = try Self.url(for: path, in: folder)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    func write(_ path: String, content: String) throws {
        try withFolder { folder in
            let url = try Self.url(for: path, in: folder)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url, options: .atomic)
        }
    }

    /// Keeps a copy of local content that is about to be replaced, in a folder quickbox never reads.
    func saveConflictCopy(of path: String, content: String, at date: Date = Date()) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = (path as NSString).deletingPathExtension.replacingOccurrences(of: "/", with: "-")
        try write("\(Self.conflictsFolder)/\(name) \(formatter.string(from: date)).md", content: content)
    }

    nonisolated static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        try InboxStorageQueue.shared.sync {
            let folder = try storageResolver.resolvedBaseURL()
            defer { storageResolver.stopAccess(for: folder) }
            return try body(folder)
        }
    }

    /// Refuses paths that would leave the storage folder (they come from the server).
    private static func url(for path: String, in folder: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        return folder.appendingPathComponent(path)
    }
}
