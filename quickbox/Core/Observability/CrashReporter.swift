import Foundation
import OSLog

final class CrashReporter: CrashReporting {
    private let logger = Logger(subsystem: "quickbox", category: "diagnostics")
    private let fileManager: FileManager
    private let nowProvider: () -> Date

    private var consentEnabled: Bool

    init(
        consentEnabled: Bool,
        fileManager: FileManager = .default,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.consentEnabled = consentEnabled
        self.fileManager = fileManager
        self.nowProvider = nowProvider
    }

    func setConsent(_ enabled: Bool) {
        consentEnabled = enabled
    }

    func record(nonFatal error: Error, errorContext: [String: String]) {
        guard consentEnabled else {
            return
        }

        let sanitizedContext = sanitize(context: errorContext)
        logger.error("Non-fatal error: \(String(describing: error), privacy: .public) context=\(sanitizedContext, privacy: .public)")

        do {
            let logURL = try diagnosticsLogURL()
            let entry = CrashLogEntry(
                timestampISO8601: ISO8601DateFormatter().string(from: nowProvider()),
                errorDescription: String(describing: error),
                context: sanitizedContext
            )
            let data = try JSONEncoder().encode(entry)
            try appendLine(data, to: logURL)
        } catch {
            logger.error("Failed to write diagnostics log: \(String(describing: error), privacy: .public)")
        }
    }

    private func diagnosticsLogURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport.appendingPathComponent("quickbox", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("diagnostics.log")
    }

    private func appendLine(_ lineData: Data, to fileURL: URL) throws {
        var payload = lineData
        payload.append(0x0A)

        if !fileManager.fileExists(atPath: fileURL.path) {
            try payload.write(to: fileURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: payload)
    }

    private func sanitize(context: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for (key, value) in context {
            // Never keep free-text task content in diagnostics.
            if key.localizedCaseInsensitiveContains("text") || key.localizedCaseInsensitiveContains("draft") {
                continue
            }
            sanitized[key] = String(value.prefix(120))
        }
        return sanitized
    }
}

private struct CrashLogEntry: Codable {
    let timestampISO8601: String
    let errorDescription: String
    let context: [String: String]
}
