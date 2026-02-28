import Foundation

final class NoopCrashReporter: CrashReporting {
    func setConsent(_ enabled: Bool) {
        _ = enabled
    }

    func record(nonFatal error: Error, errorContext: [String: String]) {
        _ = error
        _ = errorContext
    }
}
