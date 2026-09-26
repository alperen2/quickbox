import Foundation

/// Moves entries from the legacy flat `<Project>.md` layout into the
/// `<Project>/<date>.md` layout described by `StorageLayout`.
///
/// Legacy lines carry a `date:<daily file name>` tag which becomes the target
/// file name. Lines that don't belong to the project or have no usable tag are
/// left in place; the legacy file is removed once nothing remains in it.
/// Running the migration repeatedly is safe: already migrated lines are skipped.
struct LegacyProjectMigrator {
    private static let projectNamePattern = /^[a-zA-Z0-9_\-]+$/
    private static let dateTagPattern = /\s+date:(?<value>[^\s\/\\]+)/

    private let fileManager: FileManager
    private let parser = InboxParser()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func migrate(in folderURL: URL) throws {
        for legacyURL in try legacyProjectFiles(in: folderURL) {
            try migrateFile(at: legacyURL, in: folderURL)
        }
    }

    private func legacyProjectFiles(in folderURL: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { url in
                url.pathExtension == "md"
                    && url.deletingPathExtension().lastPathComponent.wholeMatch(of: Self.projectNamePattern) != nil
            }
    }

    private func migrateFile(at legacyURL: URL, in folderURL: URL) throws {
        let project = legacyURL.deletingPathExtension().lastPathComponent
        var remainingLines = try readLines(at: legacyURL)
        var migratedLines: [(targetFileName: String, line: String)] = []

        let projectItems = parser.parse(lines: remainingLines, sourceID: legacyURL.lastPathComponent)
            .filter { $0.projectName == project }

        for item in projectItems.reversed() {
            guard let migration = migratedLine(from: item.rawLine) else { continue }
            migratedLines.insert(migration, at: 0)
            remainingLines.remove(at: item.lineIndex)
        }

        guard !migratedLines.isEmpty else { return }

        let projectURL = folderURL.appendingPathComponent(project, isDirectory: true)
        try fileManager.createDirectory(at: projectURL, withIntermediateDirectories: true, attributes: nil)

        // Write targets before shrinking the legacy file so an interruption never loses entries
        for (targetFileName, lines) in Dictionary(grouping: migratedLines, by: \.targetFileName) {
            try append(lines.map(\.line), to: projectURL.appendingPathComponent(targetFileName))
        }

        if remainingLines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            try fileManager.removeItem(at: legacyURL)
        } else {
            try write(remainingLines, to: legacyURL)
        }
    }

    /// Returns the target file name and the line without its routing tag.
    private func migratedLine(from rawLine: String) -> (targetFileName: String, line: String)? {
        guard let match = rawLine.firstMatch(of: Self.dateTagPattern),
              !match.output.value.hasPrefix(".")
        else {
            return nil
        }

        var line = rawLine
        line.removeSubrange(match.range)
        return ("\(match.output.value).md", line)
    }

    private func append(_ newLines: [String], to fileURL: URL) throws {
        let existingLines = try readLines(at: fileURL)
        let linesToAdd = newLines.filter { !existingLines.contains($0) }
        guard !linesToAdd.isEmpty else { return }
        try write(existingLines + linesToAdd, to: fileURL)
    }

    private func readLines(at fileURL: URL) throws -> [String] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        var lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    private func write(_ lines: [String], to fileURL: URL) throws {
        let content = lines.joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: fileURL, options: .atomic)
    }
}
