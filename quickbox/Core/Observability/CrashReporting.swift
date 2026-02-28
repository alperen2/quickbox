import Foundation

protocol CrashReporting {
    func setConsent(_ enabled: Bool)
    func record(nonFatal error: Error, errorContext: [String: String])
}
